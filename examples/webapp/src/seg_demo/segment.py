"""Segmentation logic — the part that used to live in notebook cells.

No web code in here: these are plain functions you can import and test on their
own, e.g.

    uv run python -c "from seg_demo.segment import pick_device; print(pick_device())"

The "model" is a small k-means colour clustering written in PyTorch. It needs no
downloaded weights (compute nodes may be offline) but still does its work on the
GPU, so it is a stand-in for whatever model your own project runs.
"""

from __future__ import annotations

import numpy as np
import torch
from PIL import Image

# One colour per cluster label (label 0 = darkest cluster).
PALETTE = np.array(
    [
        [31, 119, 180], [255, 127, 14], [44, 160, 44], [214, 39, 40],
        [148, 103, 189], [140, 86, 75], [227, 119, 194], [127, 127, 127],
        [188, 189, 34], [23, 190, 207], [255, 187, 120], [152, 223, 138],
    ],
    dtype=np.uint8,
)
MAX_K = len(PALETTE)


def pick_device(requested: str = "auto") -> torch.device:
    """'auto' -> the GPU if one is visible to this process, else the CPU."""
    if requested == "auto":
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
    return torch.device(requested)


def describe_device(device: torch.device) -> str:
    """Human-readable device name, e.g. 'cuda (NVIDIA H200 MIG 1g.33gb)'."""
    if device.type == "cuda":
        return f"cuda ({torch.cuda.get_device_name(device)})"
    return device.type


def load_image(image: Image.Image, max_side: int = 1024) -> Image.Image:
    """RGB copy of `image`, downscaled so its longest side is <= max_side."""
    img = image.convert("RGB")
    img.thumbnail((max_side, max_side))
    return img


@torch.no_grad()
def kmeans_segment(
    image: Image.Image,
    k: int = 4,
    iters: int = 20,
    device: torch.device | None = None,
    seed: int = 0,
) -> np.ndarray:
    """Cluster the pixel colours of `image` into k groups.

    Returns an (H, W) uint8 label map. Labels are sorted by brightness, so the
    darkest cluster is always 0 and colours stay stable between runs.
    """
    if not 2 <= k <= MAX_K:
        raise ValueError(f"k must be between 2 and {MAX_K}, got {k}")
    device = device or pick_device()

    rgb = np.asarray(image.convert("RGB"))
    h, w, _ = rgb.shape
    x = torch.from_numpy(rgb).to(device).reshape(-1, 3).float() / 255.0  # (N, 3)

    # Initialise the centres with k random pixels (seeded -> reproducible).
    gen = torch.Generator().manual_seed(seed)
    centres = x[torch.randperm(x.shape[0], generator=gen)[:k].to(device)].clone()

    for _ in range(iters):
        labels = torch.cdist(x, centres).argmin(dim=1)                 # (N,)
        sums = torch.zeros_like(centres).index_add_(0, labels, x)       # (k, 3)
        counts = torch.bincount(labels, minlength=k).unsqueeze(1)       # (k, 1)
        # Keep the old centre if a cluster ran empty.
        centres = torch.where(counts > 0, sums / counts.clamp_min(1), centres)

    labels = torch.cdist(x, centres).argmin(dim=1)
    order = centres.sum(dim=1).argsort()                 # dark -> bright
    remap = torch.empty_like(order)
    remap[order] = torch.arange(k, device=device)
    return remap[labels].reshape(h, w).to(torch.uint8).cpu().numpy()


def colorize(labels: np.ndarray) -> Image.Image:
    """Label map -> RGB image using PALETTE."""
    return Image.fromarray(PALETTE[labels])


def overlay(image: Image.Image, labels: np.ndarray, alpha: float = 0.5) -> Image.Image:
    """Blend the coloured label map over the original image."""
    return Image.blend(image.convert("RGB"), colorize(labels), alpha)
