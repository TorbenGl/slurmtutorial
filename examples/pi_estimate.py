#!/usr/bin/env python3
"""Estimate pi with a Monte Carlo dart-throw.

A tiny, CPU-bound toy job: throw random darts at the unit square and count how
many land inside the quarter circle. The ratio approximates pi/4.

Usage:
    python pi_estimate.py [num_samples]
"""
import random
import sys


def estimate_pi(num_samples: int) -> float:
    inside = 0
    for _ in range(num_samples):
        x, y = random.random(), random.random()
        if x * x + y * y <= 1.0:
            inside += 1
    return 4.0 * inside / num_samples


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10_000_000
    print(f"Estimating pi with {n:,} samples...")
    print(f"pi ~= {estimate_pi(n):.6f}")
