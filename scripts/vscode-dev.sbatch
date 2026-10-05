#!/bin/bash
#SBATCH --job-name=vscode-dev
#SBATCH --time=08:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu-node-mig
#SBATCH --output=/dev/null

IDLE_LIMIT=300   # seconds of no ssh activity before self-cancel
LAST_ACTIVE=$(date +%s)

while true; do
  sleep 60
  ACTIVE=$(ss -tn state established '( sport = :22 )' | tail -n +2 | wc -l)
  if [ "$ACTIVE" -gt 0 ]; then
    LAST_ACTIVE=$(date +%s)
  fi
  if [ $(( $(date +%s) - LAST_ACTIVE )) -gt $IDLE_LIMIT ]; then
    scancel "$SLURM_JOB_ID"
  fi
done
