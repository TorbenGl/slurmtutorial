#!/bin/bash
#SBATCH --job-name=mig-33gb
#SBATCH --partition=gpu-node-mig
#SBATCH --gres=gpu:1g.33gb:1     # one ~33 GB MIG slice (node201 has 4 of these)
#                ^^^^^^^^^^^ MIG type name, from: scontrol show node node201
#                    Gres=gpu:1g.33gb:4,gpu:1g.16gb:7
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=logs/%x-%j.out

# Job pinned to a ~33 GB MIG slice. Submit with:  sbatch gpu_mig_33gb.sbatch
echo "Running on host: $(hostname)"
nvidia-smi                      # should show a single ~33 GB MIG device

# Activate your environment as appropriate, e.g.:
# module load cuda
# source ~/venvs/torch/bin/activate   (or run via: uv run python ...)

srun python gpu_check.py
