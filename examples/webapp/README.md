# seg-demo — notebook prototype → uv web app → GPU job

A small, complete template for turning a Jupyter prototype into a web app that
runs on your laptop **and** as a Slurm job on a GPU slice. The "model" is a
k-means colour segmentation in PyTorch (no downloaded weights) — swap in your own.

- **Example 1** — the uv project itself (this folder)
- **Example 2** — SSH setup: [`../ssh/`](../ssh/)
- **Example 3** — [`run_slurm.sh`](run_slurm.sh): the app on a 33 GB MIG slice + reverse tunnel

```
webapp/
├── pyproject.toml          # dependencies + the `seg-demo` command
├── run_slurm.sh            # Example 3: sbatch script
└── src/seg_demo/
    ├── segment.py          # the science: pure functions (was: notebook cells)
    ├── app.py              # the web layer: FastAPI routes + CLI (main)
    └── static/index.html   # the page you see in the browser
```

## Example 1 — from notebook to uv project

How this folder was made, and what to do with your own notebook:

1. **Create the project:** `uv init --package seg-demo` (gives you `pyproject.toml`
   and `src/seg_demo/`).
2. **Add dependencies** instead of `pip install` in a cell:
   `uv add fastapi uvicorn python-multipart pillow numpy torch`.
   They land in `pyproject.toml`, exact versions in `uv.lock` — commit both.
3. **Notebook → Python files:** `uv run --with jupyter jupyter nbconvert --to script prototype.ipynb`,
   then sort the code:
   - cells that compute something → **functions** in `segment.py` (no globals,
     no plotting, no `!pip`);
   - widgets / `display()` / plots → the **web layer** in `app.py` + `index.html`;
   - hard-coded paths and settings → **command-line flags** (`--data-dir`, `--port`, …).
4. **Make it a command:** `[project.scripts] seg-demo = "seg_demo.app:main"` in
   `pyproject.toml` — that's your new "Run All".

Run it locally:

```bash
uv sync                    # once: build .venv
uv run seg-demo            # -> http://127.0.0.1:8000
uv run seg-demo --help     # all flags
```

All files go to `--data-dir` (default `./data`, git-ignored):

| folder              | what                                                                  |
| ------------------- | --------------------------------------------------------------------- |
| `<data-dir>/inputs` | your own images — copy them there and pick them in the UI             |
| `<data-dir>/uploads`| originals uploaded through the browser                                |
| `<data-dir>/results`| `<id>_input.png`, `<id>_overlay.png`, `<id>_labels.png` (labels 0…k-1), `<id>.json` |

## Example 3 — run it on the cluster

Once, on the login node (`ssh slurm`, it has internet — compute nodes may not):

```bash
git clone git@github.com:<you>/<repo>.git && cd <repo>/examples/webapp
uv sync                                  # .venv incl. CUDA build of torch
bash ../ssh/setup_cluster_key.sh         # lets jobs open the tunnel back (Example 2)
```

Every time:

```bash
mkdir -p logs
sbatch run_slurm.sh                      # submit from THIS folder
squeue --me                              # wait for state R
cat logs/seg-demo-<jobid>.out            # prints the exact ssh command for your laptop
```

On your **laptop** run the command from the log — `ssh -N -L <port>:localhost:<port> slurm` —
leave it open and browse to `http://localhost:<port>`. The header shows the
compute node, the job id and the MIG device the app is running on.
`scancel <jobid>` stops the app and frees the GPU.

What `run_slurm.sh` does:

```
laptop ──(ssh -L)──▶ login node sl-li ◀──(ssh -R)── compute node: seg-demo on 127.0.0.1:<port>
```

- asks for `--partition=gpu-node-mig --gres=gpu:1g.33gb:1` (one ~33 GB MIG slice);
- picks a port from your uid, so students don't collide on the shared login node;
- opens the reverse tunnel *from the node to the login node* and fails loudly if
  it can't (wrong key, port taken);
- starts the app bound to `127.0.0.1` — reachable only through the tunnel;
- stores everything in `DATA_DIR` (default `~/seg-demo-data`, folders are created
  on the first start). Images for `inputs/` get there with e.g.
  `scp *.png slurm:seg-demo-data/inputs/`.

Change defaults at submit time: `DATA_DIR=/other/dir PORT=23456 sbatch run_slurm.sh`.

## Troubleshooting

| symptom (in the job log)                         | fix                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------- |
| `.venv/bin/seg-demo not found`                   | `uv sync` on the login node; submit from `examples/webapp`             |
| `Permission denied (publickey)`                  | `bash ../ssh/setup_cluster_key.sh` once                                |
| `remote port forwarding failed`                  | port taken — `PORT=<other> sbatch run_slurm.sh`                        |
| page loads, but header says `device: cpu`        | no GPU visible: check `--gres` line / `nvidia-smi -L` in the log       |
| laptop: `bind: Address already in use`           | something local uses that port — `ssh -N -L 9000:localhost:<port> slurm`, open `localhost:9000` |
