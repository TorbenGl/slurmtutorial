#!/bin/bash
#SBATCH --job-name=mig-16gb
#SBATCH --partition=gpu-node-mig
#SBATCH --gres=gpu:1g.16gb:1     # one ~16 GB MIG slice (node201 has 7 of these)
#                ^^^^^^^^^^^ MIG type name, from: scontrol show node node201
#                    Gres=gpu:1g.33gb:4,gpu:1g.16gb:7
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=logs/%x-%j.out

# Job pinned to a ~16 GB MIG slice. Submit with:  sbatch gpu_mig_16gb.sbatch
echo "Running on host: $(hostname)"
nvidia-smi                      # should show a single ~16 GB MIG device

# Activate your environment as appropriate, e.g.:
# module load cuda
# source ~/venvs/torch/bin/activate   (or run via: uv run python ...)

srun python gpu_check.py
