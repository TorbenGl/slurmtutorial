#!/bin/bash
#SBATCH --job-name=checkpointed
#SBATCH --partition=compute-node # CPU partition
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:01:00          # deliberately short to trigger the limit
#SBATCH --output=logs/%x-%j.out
#SBATCH --requeue                # allow Slurm to put the job back in the queue
#SBATCH --signal=B:USR1@30       # send SIGUSR1 to the batch shell 30s before the limit

# Demonstrates checkpoint + requeue. The script traps SIGUSR1, saves a
# checkpoint, and exits; we then ask Slurm to requeue this same job so it
# resumes from the checkpoint on the next run.

# Run the work in the background so the trap below can fire while it runs.
srun python examples/checkpoint.py 300 state.ckpt &
work_pid=$!

# When Slurm signals us near the time limit, requeue ourselves.
trap 'echo "Time almost up -- requeueing $SLURM_JOB_ID"; scontrol requeue "$SLURM_JOB_ID"' USR1

wait "$work_pid"
