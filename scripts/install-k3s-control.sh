#!/usr/bin/env bash
#
# Install the K3s server (control plane) on the control-plane node.
#
# Usage (run on the control-plane node, or pipe in via ssh):
#   ./install-k3s-control.sh [NODE_IP]
#
# Configuration follows IMPLEMENTATION_PLAN.md Phase 3:
#   --disable=traefik         use a different ingress controller later
#   --disable=servicelb       use MetalLB or similar later
#   --write-kubeconfig-mode    world-readable kubeconfig for easy retrieval
#
set -euo pipefail

NODE_IP="${1:-192.168.50.10}"

if command -v k3s >/dev/null 2>&1; then
  echo "k3s already installed; skipping install."
else
  echo "Installing k3s server (control plane) on ${NODE_IP}..."
  curl -sfL https://get.k3s.io | sudo sh -s - server \
    --disable=traefik \
    --disable=servicelb \
    --write-kubeconfig-mode=644 \
    --node-ip="${NODE_IP}" \
    --tls-san="${NODE_IP}"
fi

echo "Waiting for the control-plane node to become Ready..."
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=180s

echo ""
echo "=== k3s service status ==="
sudo systemctl is-active k3s

echo ""
echo "=== nodes ==="
sudo k3s kubectl get nodes -o wide

echo ""
echo "Control plane ready. Worker join token is at:"
echo "  /var/lib/rancher/k3s/server/node-token"
echo "Kubeconfig is at:"
echo "  /etc/rancher/k3s/k3s.yaml"
