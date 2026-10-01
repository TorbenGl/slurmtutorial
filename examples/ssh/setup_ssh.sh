#!/usr/bin/env bash
# Example 2a — SSH setup on your LAPTOP (Linux, macOS, WSL or Git Bash).
# On Windows PowerShell use setup_ssh.ps1 instead.
#
#   bash examples/ssh/setup_ssh.sh <your-uni-username>
#
# Safe to run again — every step is skipped if it is already done:
#   1. creates ~/.ssh/id_ed25519            (asks for a passphrase — please set one)
#   2. installs the public key on sl-li     (asks for your uni password once)
#   3. adds a "Host slurm" block to ~/.ssh/config, so `ssh slurm` just works
#   4. tests the login and prints the public key for GitHub
set -euo pipefail

USER_NAME=${1:?usage: bash setup_ssh.sh <your-uni-username>}
HOST=sl-li.informatik.uni-rostock.de
ALIAS=slurm
KEY="$HOME/.ssh/id_ed25519"
CONFIG="$HOME/.ssh/config"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

echo "== 1/4  SSH key"
if [ -f "$KEY" ]; then
  echo "   exists: $KEY"
else
  ssh-keygen -t ed25519 -C "$USER_NAME@uni-rostock" -f "$KEY"
fi

echo "== 2/4  Public key on $HOST"
if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$KEY" "$USER_NAME@$HOST" true 2>/dev/null; then
  echo "   already accepted"
elif command -v ssh-copy-id >/dev/null; then
  ssh-copy-id -i "$KEY.pub" "$USER_NAME@$HOST"
else
  ssh "$USER_NAME@$HOST" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' < "$KEY.pub"
fi

echo "== 3/4  'Host $ALIAS' in $CONFIG"
if grep -qiE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?$ALIAS([[:space:]]|\$)" "$CONFIG" 2>/dev/null; then
  echo "   already there — left unchanged"
else
  cat >> "$CONFIG" <<EOF

Host $ALIAS
    HostName $HOST
    User $USER_NAME
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent yes
    # Lends your laptop's key to the cluster (e.g. for git clone/push to
    # GitHub there) without copying the private key onto the cluster.
    ForwardAgent yes
    ServerAliveInterval 60
EOF
  echo "   added"
fi
chmod 600 "$CONFIG"

echo "== 4/4  Test"
ssh "$ALIAS" 'echo "   OK: logged in to $(hostname) as $(whoami)"'

rc=0; ssh-add -l >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  echo
  echo "Note: no ssh-agent is running, so agent forwarding (git on the cluster) won't work yet."
  echo "      Start one with:  eval \"\$(ssh-agent -s)\" && ssh-add $KEY"
fi

cat <<EOF

Last step (once): add this PUBLIC key to GitHub
  -> https://github.com/settings/keys -> "New SSH key"

$(cat "$KEY.pub")

Check:  ssh -T git@github.com            (on the laptop)
        ssh slurm, then ssh -T git@github.com   (on the cluster, via agent forwarding)
EOF
