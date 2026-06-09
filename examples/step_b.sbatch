#!/bin/bash
#SBATCH --job-name=step-b
#SBATCH --partition=compute-node # CPU partition
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x-%j.out

# Step B of a pipeline: only runs once step A finishes successfully.
# It reads the file step A produced.
if [[ ! -f primes_result.txt ]]; then
    echo "primes_result.txt missing -- did step A succeed?" >&2
    exit 1
fi

count=$(cat primes_result.txt)
echo "Step B read result from step A: $count primes"
