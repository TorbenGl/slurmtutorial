"""Web layer: FastAPI routes around the functions in segment.py, plus the CLI.

    uv run seg-demo                         # http://127.0.0.1:8000, data in ./data
    uv run seg-demo --port 8642 --data-dir /path/on/the/cluster

Everything the app reads or writes lives under --data-dir:

    <data-dir>/inputs/    put your own images here (scp/rsync) -> pick them in the UI
    <data-dir>/uploads/   originals uploaded through the browser
    <data-dir>/results/   <id>_input.png, <id>_overlay.png, <id>_labels.png, <id>.json
"""

from __future__ import annotations

import argparse
import io
import json
import os
import socket
import threading
import time
import uuid
from datetime import datetime
from importlib.resources import files
from pathlib import Path
from typing import Annotated

import torch
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from seg_demo import __version__
from seg_demo.segment import MAX_K, describe_device, kmeans_segment, load_image, overlay, pick_device

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp"}
MAX_UPLOAD_BYTES = 50 * 1024 * 1024


def create_app(data_dir: Path, device: torch.device) -> FastAPI:
    data_dir = data_dir.expanduser().resolve()
    dirs = {name: data_dir / name for name in ("inputs", "uploads", "results")}
    for d in dirs.values():
        d.mkdir(parents=True, exist_ok=True)

    app = FastAPI(title="seg-demo", version=__version__)
    index_html = (files("seg_demo") / "static" / "index.html").read_text(encoding="utf-8")
    gpu_lock = threading.Lock()  # one segmentation at a time on the (small) GPU

    @app.get("/", response_class=HTMLResponse)
    def index() -> str:
        return index_html

    @app.get("/api/info")
    def info() -> dict:
        return {
            "version": __version__,
            "device": describe_device(device),
            "host": socket.gethostname(),  # on the cluster: the compute node, e.g. node201
            "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
            "data_dir": str(data_dir),
        }

    @app.get("/api/inputs")
    def list_inputs() -> list[str]:
        """Images already on this machine in <data-dir>/inputs."""
        return sorted(p.name for p in dirs["inputs"].iterdir() if p.suffix.lower() in IMAGE_EXTS)

    @app.get("/api/results")
    def list_results(limit: int = 12) -> list[dict]:
        metas = sorted(dirs["results"].glob("*.json"), reverse=True)[:limit]
        return [json.loads(p.read_text()) for p in metas]

    # Sync (`def`, not `async def`) on purpose: FastAPI runs it in a worker
    # thread, so the GPU work doesn't block other requests.
    @app.post("/api/segment")
    def segment(
        k: Annotated[int, Form()] = 4,
        file: Annotated[UploadFile | None, File()] = None,
        input_name: Annotated[str | None, Form()] = None,
    ) -> dict:
        if not 2 <= k <= MAX_K:
            raise HTTPException(400, f"k must be between 2 and {MAX_K}")

        run_id = f"{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}"
        try:
            if file is not None and file.filename:
                raw = file.file.read(MAX_UPLOAD_BYTES + 1)
                if len(raw) > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "upload too large (max 50 MB)")
                source = f"upload: {file.filename}"
                suffix = Path(file.filename).suffix.lower() or ".bin"
                (dirs["uploads"] / f"{run_id}{suffix}").write_bytes(raw)  # keep the original
                image = Image.open(io.BytesIO(raw))
            elif input_name:
                # Only accept names we listed ourselves -> no "../../etc/passwd".
                if input_name not in list_inputs():
                    raise HTTPException(404, f"no such input: {input_name}")
                source = f"inputs/{input_name}"
                image = Image.open(dirs["inputs"] / input_name)
            else:
                raise HTTPException(400, "send an image file or pick an input")
            image = load_image(image)
        except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as err:
            raise HTTPException(400, f"could not read image: {err}") from err

        with gpu_lock:
            t0 = time.perf_counter()
            labels = kmeans_segment(image, k=k, device=device)
            seconds = time.perf_counter() - t0

        res = dirs["results"]
        image.save(res / f"{run_id}_input.png")
        overlay(image, labels).save(res / f"{run_id}_overlay.png")
        Image.fromarray(labels).save(res / f"{run_id}_labels.png")  # raw labels 0..k-1 for analysis

        meta = {
            "id": run_id,
            "source": source,
            "k": k,
            "size": list(image.size),
            "seconds": round(seconds, 3),
            "device": describe_device(device),
            "input": f"/files/results/{run_id}_input.png",
            "overlay": f"/files/results/{run_id}_overlay.png",
            "labels": f"/files/results/{run_id}_labels.png",
        }
        (res / f"{run_id}.json").write_text(json.dumps(meta, indent=2))
        print(f"[{run_id}] {source}  k={k}  {image.size[0]}x{image.size[1]}  {seconds:.3f}s", flush=True)
        return meta

    app.mount("/files/results", StaticFiles(directory=dirs["results"]), name="results")
    return app


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="seg-demo", description="Example segmentation web app.")
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="interface to bind (default 127.0.0.1: only reachable from this machine or through an SSH tunnel)",
    )
    parser.add_argument("--port", type=int, default=8000, help="port to listen on (default 8000)")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path(os.environ.get("SEG_DEMO_DATA_DIR", "data")),
        help="where inputs/uploads/results live (default ./data or $SEG_DEMO_DATA_DIR)",
    )
    parser.add_argument("--device", default="auto", help="'auto', 'cuda', 'cuda:0' or 'cpu' (default auto)")
    args = parser.parse_args(argv)

    device = pick_device(args.device)
    app = create_app(args.data_dir, device)

    print(f"seg-demo {__version__}", flush=True)
    print(f"  device   : {describe_device(device)}", flush=True)
    print(f"  data dir : {args.data_dir.expanduser().resolve()}", flush=True)
    print(f"  url      : http://{args.host}:{args.port}", flush=True)
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
