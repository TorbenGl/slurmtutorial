#!/usr/bin/env python3
"""Tiny GPU sanity check + a small matrix multiply on the device.

Confirms the job actually sees a GPU (via --gres=gpu:1) and does a bit of work
on it. Falls back to a clear message if CUDA isn't available so it doesn't crash
on a CPU-only node.

Usage:
    python gpu_check.py
"""
import torch


def main() -> None:
    if not torch.cuda.is_available():
        print("No CUDA device visible to this job. Did you request --gres=gpu:1?")
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
