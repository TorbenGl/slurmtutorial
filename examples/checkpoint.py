#!/usr/bin/env python3
"""Long-running job that checkpoints its progress and resumes after a requeue.

Demonstrates the pattern for jobs that outlive the partition time limit:
  1. On startup, load progress from a checkpoint file if one exists.
  2. Trap SIGUSR1 (sent by Slurm shortly before the time limit via --signal).
  3. On the signal, save a checkpoint, then exit so Slurm can requeue the job.
  4. The requeued job picks up where it left off.

Usage:
    python checkpoint.py [target_iterations] [checkpoint_file]
"""
import os
import signal
import sys
import time

_should_checkpoint = False


def _handle_signal(signum, frame):
    global _should_checkpoint
    _should_checkpoint = True


def load(path: str) -> int:
    if os.path.exists(path):
        with open(path) as f:
            return int(f.read().strip())
    return 0


def save(path: str, step: int) -> None:
    with open(path, "w") as f:
        f.write(str(step))


def main() -> None:
    target = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    ckpt = sys.argv[2] if len(sys.argv) > 2 else "state.ckpt"

    signal.signal(signal.SIGUSR1, _handle_signal)

    step = load(ckpt)
    print(f"Starting at step {step}/{target}")

    while step < target:
        # ... pretend each step is real work ...
        time.sleep(1)
        step += 1
        print(f"step {step}/{target}", flush=True)

        if _should_checkpoint:
            save(ckpt, step)
            print(f"Caught signal -> checkpointed at step {step}. Exiting for requeue.")
            sys.exit(0)

    save(ckpt, step)
    print("Done!")


if __name__ == "__main__":
    main()
