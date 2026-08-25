#!/bin/bash
# ~/bin/vscode-slurm-connect.sh, run on the login node
JOBNAME=vscode-dev

JOBID=$(squeue -u "$USER" -n "$JOBNAME" -h -t RUNNING -o %A | head -n1)

if [ -z "$JOBID" ]; then
  JOBID=$(sbatch --parsable ~/scripts/vscode-dev.sbatch)
  until [ "$(squeue -j "$JOBID" -h -o %T 2>/dev/null)" = "RUNNING" ]; do
    sleep 2
  done
fi

NODE=$(squeue -j "$JOBID" -h -o %N)
exec ssh -o StrictHostKeyChecking=no -W localhost:22 "$NODE"
