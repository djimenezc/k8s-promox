#!/usr/bin/env bash
#
# Install the K3s agent (worker) and join it to the control plane.
#
# Usage (run on the worker node, or pipe in via ssh):
#   ./install-k3s-worker.sh <NODE_IP> <SERVER_IP> <NODE_TOKEN>
#
# Follows IMPLEMENTATION_PLAN.md Phase 4: install agent, join cluster using the
# control-plane IP and the server node-token.
#
set -euo pipefail

NODE_IP="${1:?usage: install-k3s-worker.sh <NODE_IP> <SERVER_IP> <NODE_TOKEN>}"
SERVER_IP="${2:?missing SERVER_IP}"
NODE_TOKEN="${3:?missing NODE_TOKEN}"

if command -v k3s >/dev/null 2>&1; then
  echo "k3s already installed on ${NODE_IP}; skipping install."
else
  echo "Installing k3s agent on ${NODE_IP}, joining server https://${SERVER_IP}:6443..."
  curl -sfL https://get.k3s.io | sudo sh -s - agent \
    --server "https://${SERVER_IP}:6443" \
    --token "${NODE_TOKEN}" \
    --node-ip "${NODE_IP}"
fi

echo ""
echo "=== k3s-agent service status ==="
sudo systemctl is-active k3s-agent
