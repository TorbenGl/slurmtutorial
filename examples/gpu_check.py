#!/usr/bin/env python3
"""Tiny GPU sanity check + a small matrix multiply on the device.

Confirms the job actually sees a GPU and does a bit of work on it. If CUDA isn't
available it prints *why* — distinguishing a CPU-only torch build from a missing
GPU allocation — instead of failing cryptically.

Usage:
    python gpu_check.py
"""
import os

import torch


def main() -> None:
    print(f"torch {torch.__version__}  (built for CUDA: {torch.version.cuda})")

    if not torch.cuda.is_available():
        print("torch.cuda.is_available() -> False")
        if torch.version.cuda is None:
            # The wheel itself has no CUDA support — most common cause here.
            print(
                "  This is a CPU-only build of torch. Install a CUDA build, e.g.:\n"
                "    uv pip install --reinstall torch \\\n"
                "        --index-url https://download.pytorch.org/whl/cu124"
            )
        else:
            # CUDA-enabled wheel, but no GPU is visible to the process.
            print(
                "  CUDA build, but no GPU visible. Did you request --gres=gpu:1?\n"
                f"  CUDA_VISIBLE_DEVICES = {os.environ.get('CUDA_VISIBLE_DEVICES')!r}"
            )
        return

    dev = torch.device("cuda")
    print(f"CUDA available. Device: {torch.cuda.get_device_name(0)}")

    a = torch.randn(4096, 4096, device=dev)
    b = torch.randn(4096, 4096, device=dev)
    c = a @ b
    torch.cuda.synchronize()
    print(f"Matmul done. Result sum = {c.sum().item():.2f}")


if __name__ == "__main__":
    main()
