#!/bin/bash
#SBATCH --job-name=pi-demo
#SBATCH --partition=compute-node # CPU partition (see `sinfo`)
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:05:00
#SBATCH --output=logs/%x-%j.out  # %x = job name, %j = job id

# Minimal CPU batch job. Submit with:  sbatch srun_demo.sbatch
echo "Running on host: $(hostname)"
echo "Job $SLURM_JOB_ID on partition $SLURM_JOB_PARTITION"

srun python examples/pi_estimate.py 5000000
