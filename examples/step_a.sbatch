#!/bin/bash
#SBATCH --job-name=step-a
#SBATCH --partition=compute-node # CPU partition
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:02:00
#SBATCH --output=logs/%x-%j.out

# Step A of a pipeline: produces primes_result.txt that step B consumes.
echo "Step A computing primes..."
srun python examples/primes.py 2000000 primes_result.txt

# Linger ~90s so the dependency is visible: step B stays in state (Dependency)
# in `squeue` until step A finishes. Drop/shorten this for real work.
echo "Step A: working for ~90s (watch step B wait in squeue)..."
sleep 90
echo "Step A done."
