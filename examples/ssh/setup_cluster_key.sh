#!/usr/bin/env bash
# Example 2b — let your jobs SSH back to the login node. Needed for the reverse
# tunnel in Example 3 (and the Jupyter section). Run ONCE, on the login node:
#
#   bash examples/ssh/setup_cluster_key.sh
#
# It first tests whether a job can already open a tunnel to sl-li without a
# password. Only if not, it creates a cluster-only key (~/.ssh/id_ed25519_cluster,
# without passphrase because a batch job can't type one) and authorizes it for
# YOUR account, restricted to port forwarding: it can open tunnels, but it can't
# give anyone a shell. Never copy this key off the cluster.
set -euo pipefail

LOGIN_NODE=${LOGIN_NODE:-sl-li}
PARTITION=${PARTITION:-compute-node}
KEY="$HOME/.ssh/id_ed25519_cluster"

can_tunnel_from_node() {
  # A tiny job that opens (and closes again) a reverse tunnel to the login node.
  srun --job-name=ssh-test --partition="$PARTITION" --time=00:01:00 --mem=100M --quiet \
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -o ExitOnForwardFailure=yes -R 0:127.0.0.1:22 "$LOGIN_NODE" true
}

echo "== Can a job on '$PARTITION' open a tunnel to '$LOGIN_NODE'?"
if can_tunnel_from_node; then
  echo "   yes — nothing to do."
  exit 0
fi

echo "== No. Creating cluster-only key $KEY"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "cluster-tunnel $(whoami)" -f "$KEY"

# Authorize it for tunnels only (no shell, no agent, no X11).
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
if ! grep -qF "$(cut -d' ' -f2 "$KEY.pub")" "$HOME/.ssh/authorized_keys"; then
  echo "restrict,port-forwarding,command=\"echo tunnel-only key\" $(cat "$KEY.pub")" >> "$HOME/.ssh/authorized_keys"
fi

# Tell ssh to use the key when it talks to the login node.
CONFIG="$HOME/.ssh/config"
if grep -qiE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?$LOGIN_NODE([[:space:]]|\$)" "$CONFIG" 2>/dev/null; then
  echo "   NOTE: $CONFIG already has a 'Host $LOGIN_NODE' block — make sure it contains:"
  echo "         IdentityFile $KEY"
else
  printf '\nHost %s\n    IdentityFile %s\n' "$LOGIN_NODE" "$KEY" >> "$CONFIG"
fi
chmod 600 "$CONFIG"

echo "== Testing again"
if can_tunnel_from_node; then
  echo "   OK — your jobs can now open tunnels to $LOGIN_NODE."
else
  echo "   Still failing. Send the output above to the cluster admin."
  exit 1
fi
