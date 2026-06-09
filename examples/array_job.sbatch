#!/bin/bash
#SBATCH --job-name=pi-array
#SBATCH --partition=compute-node   # CPU partition
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
#SBATCH --time=00:05:00
#SBATCH --array=0-4                 # 5 tasks: task ids 0,1,2,3,4
#SBATCH --output=logs/%x-%A_%a.out  # %A = array job id, %a = task id

# A job array: one submission fans out into many tasks that differ only by
# $SLURM_ARRAY_TASK_ID. Here each task runs the pi estimate with a different
# sample count -- a tiny parameter sweep. Each task gets its own log file.
samples=$(( (SLURM_ARRAY_TASK_ID + 1) * 1000000 ))

echo "Array task $SLURM_ARRAY_TASK_ID of array job $SLURM_ARRAY_JOB_ID on $(hostname)"
echo "Estimating pi with $samples samples..."

srun python examples/pi_estimate.py "$samples"
