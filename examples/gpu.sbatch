#!/bin/bash
#SBATCH --job-name=gpu-check
#SBATCH --partition=gpu-node-mig # GPU partition (MIG slices on node201)
#SBATCH --gres=gpu:1             # request 1 GPU (one MIG slice here)
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=logs/%x-%j.out

# GPU batch job. Submit with:  sbatch gpu.sbatch
echo "Running on host: $(hostname)"
nvidia-smi || echo "nvidia-smi not found on this node"

# Activate your environment as appropriate, e.g.:
# module load cuda
# source ~/venvs/torch/bin/activate

srun python examples/gpu_check.py
