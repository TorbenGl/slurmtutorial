#!/bin/bash
#SBATCH --job-name=jupyter
#SBATCH --partition=compute-node # CPU partition; jupyter.sh switches this for GPU
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=04:00:00          # max on our partitions is 1-00:00:00
#SBATCH --output=logs/%x-%j.out

# Run Jupyter Lab on a compute node. Your laptop reaches it with a forward
# tunnel THROUGH the login node -- the login node resolves the compute node's
# name and routes to it over the cluster network. Nothing SSHes from the
# compute node back to the login node, so this works even on clusters that
# forbid compute->login SSH (e.g. pam_slurm_adopt).
#
# Submit with the wrapper (recommended):  ./examples/jupyter.sh
# Or directly:                            sbatch examples/jupyter.sbatch
#
# Ports are picked automatically, so two people can run this at the same time
# without colliding.

set -euo pipefail

NOTEBOOK_DIR="${JUPYTER_DIR:-$SLURM_SUBMIT_DIR}"  # the repo you submitted from
CONNFILE="$SLURM_SUBMIT_DIR/logs/${SLURM_JOB_NAME}.conn"
NODE=$(hostname -s)

cd "$SLURM_SUBMIT_DIR"
mkdir -p logs

echo "Running on host: $(hostname)"
echo "Job $SLURM_JOB_ID on partition $SLURM_JOB_PARTITION"
nvidia-smi -L 2>/dev/null || true

# --- Environment ------------------------------------------------------------
# Activate the prebuilt venv (run `uv sync` on the login node first — it installs
# jupyterlab). We avoid `uv run` here: compute nodes may be offline.
if [ ! -f .venv/bin/activate ]; then
  echo "ERROR: no .venv found. Run 'uv sync' on the login node first." >&2
  exit 1
fi
source .venv/bin/activate

# --- Pick a free port on THIS compute node ----------------------------------
# Jupyter binds this port on the node's interface so the login node can reach
# it; the laptop's forward tunnel lands here.
PORT=$(python -c '
import socket
s = socket.socket(); s.bind(("", 0))
print(s.getsockname()[1]); s.close()
')

echo "Jupyter will listen on ${NODE}:${PORT}"

# Bind to the node's cluster IP (the address the login node resolves for the
# forward tunnel) so the port isn't offered on every interface. If we can't
# resolve a sane, non-loopback address, fall back to all interfaces -- that
# keeps things working, and the token + TLS still guard the port.
BIND_IP=$(getent hosts "$NODE" 2>/dev/null | awk '{print $1; exit}')
case "$BIND_IP" in
  ""|127.*|::1) BIND_IP="0.0.0.0";;
esac
echo "Binding ${BIND_IP}:${PORT}"

# --- Token ------------------------------------------------------------------
# Generated up front. It is written only to the mode-600 .conn file below and
# handed to Jupyter via the JUPYTER_TOKEN environment variable -- never on the
# command line (argv is world-readable via /proc and `ps`) and never echoed to
# the Slurm log, so a co-tenant job on this node can't scrape it.
TOKEN=$(openssl rand -hex 24 2>/dev/null || python -c 'import secrets; print(secrets.token_hex(24))')

# --- SSL/TLS certificate ----------------------------------------------------
# Serve Jupyter over HTTPS with a self-signed cert. It's generated once and
# reused by later jobs, so the browser only has to be told to trust it the
# first time. The laptop always reaches Jupyter as https://localhost:8888
# through the tunnel, so the cert only needs to be valid for localhost.
CERTFILE="$SLURM_SUBMIT_DIR/logs/jupyter.crt"
KEYFILE="$SLURM_SUBMIT_DIR/logs/jupyter.key"

# A lock serialises generation so two jobs sharing this repo can't race and
# clobber each other's key/cert pair.
(
  flock 9
  need_cert=false
  if [ ! -s "$CERTFILE" ] || [ ! -s "$KEYFILE" ]; then
    need_cert=true
  elif ! openssl x509 -checkend 86400 -noout -in "$CERTFILE" >/dev/null 2>&1; then
    echo "TLS certificate expired; regenerating."
    need_cert=true
  fi

  if $need_cert; then
    echo "Generating self-signed TLS certificate in logs/ ..."
    umask 077
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$KEYFILE" -out "$CERTFILE" \
      -days 365 -subj "/CN=localhost" \
      -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
  else
    echo "Reusing TLS certificate in logs/."
  fi
) 9>"$SLURM_SUBMIT_DIR/logs/.jupyter-cert.lock"

# --- Publish connection details on the shared filesystem --------------------
umask 077
cat > "$CONNFILE" <<EOF
JOBID=${SLURM_JOB_ID}
NODE=${NODE}
PORT=${PORT}
TOKEN=${TOKEN}
DIR=${NOTEBOOK_DIR}
EOF

cleanup() {
  rm -f "$CONNFILE"
}
trap cleanup EXIT TERM INT

echo
echo "From your laptop, run:"
echo "    ssh -N -L 8888:${NODE}:${PORT} slurm"
echo "Then open https://localhost:8888/lab and paste the token when prompted."
echo "The token is in ${CONNFILE} (readable only by you); or just run"
echo "./examples/jupyter.sh to print the full URL."
echo

# --- Launch -----------------------------------------------------------------
# Bound to the node's cluster IP so the login node can route the forward tunnel
# to it. The port is reachable from the cluster's internal network, but it's
# guarded by the random token and TLS. The token is exported (JUPYTER_TOKEN)
# rather than passed on argv, so it can't be read from `ps` / /proc/*/cmdline
# by another user's job on this node.
export JUPYTER_TOKEN="$TOKEN"
jupyter lab \
  --no-browser \
  --ip="$BIND_IP" \
  --port="$PORT" \
  --port-retries=0 \
  --certfile="$CERTFILE" \
  --keyfile="$KEYFILE" \
  --ServerApp.root_dir="$NOTEBOOK_DIR"