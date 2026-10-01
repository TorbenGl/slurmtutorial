#!/bin/bash
#SBATCH --job-name=seg-demo
#SBATCH --partition=gpu-node-mig
#SBATCH --gres=gpu:1g.33gb:1        # one ~33 GB MIG slice on node201 (see Readme: "The hardware")
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=04:00:00             # the app stays up until this runs out (or you scancel)
#SBATCH --output=logs/%x-%j.out
#
# Example 3 — run the web app from Example 1 as a GPU job and open it in the
# browser on your laptop:
#
#   laptop ──(ssh -L)──▶ login node sl-li ◀──(ssh -R)── compute node: seg-demo on 127.0.0.1:$PORT
#
# Once, on the login node (it has internet, compute nodes may not):
#   cd slurmtutorial/examples/webapp
#   uv sync                                   # builds .venv incl. the CUDA build of torch
#   bash ../ssh/setup_cluster_key.sh          # lets jobs ssh back to sl-li (Example 2)
#
# Every time:
#   mkdir -p logs && sbatch run_slurm.sh      # submit FROM this folder
#   squeue --me                               # wait until the state is R
#   cat logs/seg-demo-<jobid>.out             # shows the ssh command for your laptop
#   scancel <jobid>                           # stop the app and free the GPU
#
# Override the defaults at submit time if needed, e.g.:
#   DATA_DIR=/some/other/dir PORT=23456 sbatch run_slurm.sh

set -euo pipefail

LOGIN_NODE=${LOGIN_NODE:-sl-li}
# One port per user (derived from your uid) -> no clashes with other people on
# the shared login node. The same number is used on the node, the login node
# and your laptop.
PORT=${PORT:-$(( 20000 + $(id -u) % 10000 ))}
# Where inputs/uploads/results live. Must be on a file system the compute nodes
# can see (your home directory is). Put your own images into $DATA_DIR/inputs.
DATA_DIR=${DATA_DIR:-$HOME/seg-demo-data}

if [ ! -x .venv/bin/seg-demo ]; then
  echo "ERROR: .venv/bin/seg-demo not found in $(pwd)."
  echo "       Run 'uv sync' in examples/webapp on the login node and submit from that folder."
  exit 1
fi

# --- 1. Reverse tunnel: make $PORT on the login node lead to this node ----------
TUNNEL_OPTS=(
  -N                                    # no remote command, only forward the port
  -o BatchMode=yes                      # never ask for a password (nobody is there to type it)
  -o ExitOnForwardFailure=yes           # fail loudly if $PORT is already taken on the login node
  -o StrictHostKeyChecking=accept-new   # first connection from this node: accept the login node's host key
  -o ServerAliveInterval=30             # keep the tunnel alive
  -R "${PORT}:127.0.0.1:${PORT}"
)
ssh "${TUNNEL_OPTS[@]}" "$LOGIN_NODE" &
TUNNEL_PID=$!
trap 'kill "$TUNNEL_PID" 2>/dev/null || true' EXIT   # close the tunnel when the job ends

sleep 5
if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
  echo "ERROR: reverse tunnel to $LOGIN_NODE failed (ssh error above)."
  echo "  'Permission denied ...'           -> run examples/ssh/setup_cluster_key.sh once (Example 2)"
  echo "  'remote port forwarding failed'   -> port $PORT is taken; resubmit with PORT=<other> sbatch run_slurm.sh"
  exit 1
fi

cat <<EOF
==============================================================================
 seg-demo   job $SLURM_JOB_ID on $(hostname), port $PORT
 data dir   $DATA_DIR   (put your own images into $DATA_DIR/inputs)

 On your LAPTOP, open the tunnel and leave it running:

     ssh -N -L ${PORT}:localhost:${PORT} slurm

 then open   http://localhost:${PORT}   in your browser.

 Stop the app (frees the GPU):   scancel $SLURM_JOB_ID
==============================================================================
EOF
nvidia-smi -L || true    # should list exactly one MIG device

# --- 2. Start the app on this node -------------------------------------------
# Runs the entry point from the .venv that `uv sync` built on the login node —
# the same as `uv run --no-sync seg-demo ...`, but uv never touches the network
# here. --host 127.0.0.1: only the tunnel can reach the app, not the whole network.
export PYTHONUNBUFFERED=1
srun .venv/bin/seg-demo --host 127.0.0.1 --port "$PORT" --data-dir "$DATA_DIR"
