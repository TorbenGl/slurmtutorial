#!/bin/bash
# Submit, connect to, list and stop Jupyter Lab jobs. Run this on the login node.
#
#   ./examples/jupyter.sh                 # CPU job, then connect
#   ./examples/jupyter.sh --gpu           # any free MIG slice
#   ./examples/jupyter.sh --gpu33 torch   # a 33 GB slice, job named jupyter-torch
#   ./examples/jupyter.sh --list
#   ./examples/jupyter.sh --stop torch
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # always operate from the repo root

# --- Config defaults (override via environment) ---
PARTITION="${JUPYTER_PARTITION:-compute-node}"
GRES="${JUPYTER_GRES:-}"
TIME="${JUPYTER_TIME:-04:00:00}"
CPUS="${JUPYTER_CPUS:-4}"
MEM="${JUPYTER_MEM:-8G}"

AUTO_CONFIRM=false
STOP_ONLY=false
LIST_ONLY=false
CONNECT=true

usage() {
  echo "Usage: $0 [name] [--gpu|--gpu33|--gpu16|--full-gpu] [--list] [--stop] [--no-connect] [-y]"
  echo "  [name]         Optional suffix -> job named jupyter-<name> (default: jupyter)"
  echo "  --gpu          gpu-node-mig partition, any free MIG slice"
  echo "  --gpu33        gpu-node-mig, a ~33 GB slice (4 available)"
  echo "  --gpu16        gpu-node-mig, a ~16 GB slice (7 available)"
  echo "  --full-gpu     gpu-node partition, a whole H200"
  echo "  --list         Show your running/pending Jupyter jobs"
  echo "  --stop         scancel the job (frees the GPU and drops the tunnel)"
  echo "  --no-connect   Submit only; don't wait or print tunnel instructions"
  echo "  -y             Don't ask before replacing an existing job"
  echo
  echo "Env: JUPYTER_PARTITION JUPYTER_GRES JUPYTER_TIME JUPYTER_CPUS JUPYTER_MEM"
  exit 1
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpu)        PARTITION="gpu-node-mig"; GRES="gpu:1"; shift;;
    --gpu33)      PARTITION="gpu-node-mig"; GRES="gpu:1g.33gb:1"; shift;;
    --gpu16)      PARTITION="gpu-node-mig"; GRES="gpu:1g.16gb:1"; shift;;
    --full-gpu)   PARTITION="gpu-node"; GRES="gpu:1"; shift;;
    --list)       LIST_ONLY=true; shift;;
    --stop|--remove) STOP_ONLY=true; shift;;
    --no-connect) CONNECT=false; shift;;
    -y)           AUTO_CONFIRM=true; shift;;
    -h|--help)    usage;;
    -*)           usage;;
    *)            POSITIONAL_ARGS+=("$1"); shift;;
  esac
done

# --- List mode ---
if $LIST_ONLY; then
  echo "Your Jupyter jobs:"
  found=$(squeue --me -h -o '%.10i %.20j %.14P %.9T %.10L %.12N' | awk '$2 ~ /^jupyter/' || true)
  if [[ -n "$found" ]]; then
    echo "     JOBID                 NAME      PARTITION     STATE  TIME_LEFT     NODELIST"
    echo "$found"
  else
    echo "  (none)"
  fi
  exit 0
fi

# --- Job name ---
NAME="${POSITIONAL_ARGS[0]:-}"
if [[ -n "$NAME" ]]; then
  NAME=${NAME#jupyter-}
  if ! [[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid name '$NAME'. Use letters, digits, '.', '_' and '-'." >&2
    exit 1
  fi
  JOB_NAME="jupyter-$NAME"
else
  JOB_NAME="jupyter"
fi
CONNFILE="logs/${JOB_NAME}.conn"

get_jobid() { squeue --me -h -n "$JOB_NAME" -o '%i' | head -1; }

# --- Stop mode ---
if $STOP_ONLY; then
  JOBID=$(get_jobid)
  if [[ -z "$JOBID" ]]; then
    echo "No running or pending job named $JOB_NAME."
    exit 0
  fi
  if ! $AUTO_CONFIRM; then
    read -r -p "Cancel job $JOBID ($JOB_NAME)? (y/N): " r
    [[ ! "$r" =~ ^[Yy]$ ]] && { echo "Skipped."; exit 0; }
  fi
  scancel "$JOBID"
  rm -f "$CONNFILE"
  echo "Cancelled job $JOBID."
  echo "Your notebooks are untouched -- they live in the repo, not in the job."
  exit 0
fi

# --- Print connection details from the job's .conn file ---
connect() {
  local waited=0
  while [[ ! -s "$CONNFILE" ]]; do
    if [[ $waited -ge 120 ]]; then
      echo "No connection file after 120s. Check logs/${JOB_NAME}-*.out." >&2
      exit 1
    fi
    sleep 2; waited=$((waited + 2))
  done
  # shellcheck disable=SC1090
  source "$CONNFILE"

  cat <<EOF

  Jupyter Lab is up (job $JOBID on $NODE).

  1. On your laptop, in a new terminal, leave this running:

       ssh -N -L 8888:${NODE}:${PORT} slurm

  2. Then open:

       https://localhost:8888/lab?token=${TOKEN}

     (self-signed cert -- your browser will warn once; accept it to proceed.)

  3. When you're done:  ./examples/jupyter.sh ${NAME:+$NAME }--stop

EOF
  echo "Tailing the log (Ctrl-C detaches; the job keeps running):"
  tail -f "logs/${JOB_NAME}-${JOBID}.out"
}

# --- Already running? ---
JOBID=$(get_jobid)
if [[ -n "$JOBID" ]]; then
  STATE=$(squeue -h -j "$JOBID" -o '%T')
  if [[ "$STATE" == "RUNNING" ]]; then
    echo "$JOB_NAME is already running as job $JOBID."
    connect
    exit 0
  fi
  echo "$JOB_NAME already exists as job $JOBID ($STATE)."
  if ! $AUTO_CONFIRM; then
    read -r -p "Replace it? (y/N): " r
    [[ ! "$r" =~ ^[Yy]$ ]] && { echo "Skipped."; exit 0; }
  fi
  scancel "$JOBID"; rm -f "$CONNFILE"; sleep 3
fi

# --- Submit ---
mkdir -p logs                      # the --output path must exist
rm -f "$CONNFILE"

SBATCH_OPTS=(
  --job-name="$JOB_NAME"
  --partition="$PARTITION"
  --time="$TIME"
  --cpus-per-task="$CPUS"
  --mem="$MEM"
)
[[ -n "$GRES" ]] && SBATCH_OPTS+=(--gres="$GRES")

echo "Submitting $JOB_NAME: $PARTITION, ${CPUS} CPU, $MEM, $TIME${GRES:+, $GRES}"
JOBID=$(sbatch --parsable "${SBATCH_OPTS[@]}" examples/jupyter.sbatch)
echo "Submitted job $JOBID"

if ! $CONNECT; then
  echo "Run '$0${NAME:+ $NAME}' again once it starts, or watch with: squeue --me"
  exit 0
fi

# --- Wait for the job to start ---
echo "Waiting for the scheduler..."
waited=0
while true; do
  STATE=$(squeue -h -j "$JOBID" -o '%T' 2>/dev/null | head -1)
  case "$STATE" in
    RUNNING) break;;
    PENDING) ;;
    "")      echo "Job left the queue. See logs/${JOB_NAME}-${JOBID}.out" >&2; exit 1;;
    *)       echo "Unexpected state: $STATE"; break;;
  esac
  if [[ $waited -ge 300 ]]; then
    echo
    echo "Still pending after 5 minutes. Reason:"
    squeue -j "$JOBID" -o '%.10i %.9T %.30r %.20S'   # %r = reason, %S = est. start
    echo
    echo "The job stays queued -- re-run '$0${NAME:+ $NAME}' later to connect."
    exit 0
  fi
  sleep 5; waited=$((waited + 5))
done

connect
