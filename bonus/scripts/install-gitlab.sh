#!/bin/bash
set -e

cd /vagrant/scripts

echo "=========================================="
echo "Installing k3d cluster with GitLab & ArgoCD"
echo "=========================================="
echo ""

# Update /etc/hosts with DNS entries
echo "[*] Configuring /etc/hosts..."
if ! grep -q "gitlab.k3d.local" /etc/hosts; then
  echo "127.0.0.1 gitlab.k3d.local registry.k3d.local minio.k3d.local" | sudo tee -a /etc/hosts > /dev/null
  echo "[✓] DNS entries added to /etc/hosts"
else
  echo "[✓] DNS entries already in /etc/hosts"
fi

# Cleanup iothings cluster
echo "[*] Cleaning up existing cluster..."
k3d cluster delete iothings 2>/dev/null || true

# Create cluster with 1% free space eviction policy
echo "[*] Creating k3d cluster..."
k3d cluster create iothings \
  -p "80:80@loadbalancer" -p "443:443@loadbalancer" --agents 1 \
  --k3s-arg '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@agent:*' \
  --k3s-arg '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@agent:*'

echo "[*] Setting kubectl context..."
kubectl config use-context k3d-iothings
sleep 5
kubectl get nodes

# Add gitlab helm repository
echo "[*] Adding GitLab Helm repository..."
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Install/Upgrade gitlab helm charts using values from confs
echo "[*] Installing GitLab Helm chart..."
helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  --create-namespace \
  --timeout 600s \
  -f /vagrant/confs/gitlab-helm-values.yaml

# Create GitLab Ingress
echo "[*] Creating GitLab Ingress..."
kubectl apply -f /vagrant/confs/gitlab-ingress.yaml

# Install ArgoCD
echo "[*] Installing ArgoCD..."
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 10

# Add test ArgoCD Application
echo "[*] Deploying test application..."
kubectl apply -f /vagrant/confs/argocd-app-wil42.yaml

# Wait for gitlab to start
echo "[*] Waiting for GitLab to be ready (10-15 minutes)..."
kubectl wait --for=condition=available --timeout=9000s deployment/gitlab-webservice-default -n gitlab

echo ""
echo "=========================================="
echo "✓ Setup Complete!"
echo "=========================================="
echo ""

# Get credentials
GITLAB_PASS=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 --decode)
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)

echo "✓ GitLab:"
echo "  Username: root"
echo "  Password: $GITLAB_PASS"
echo "  URL: http://gitlab.k3d.local"
echo ""
echo "✓ ArgoCD:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASS"
echo ""
echo "✓ DNS entries added to /etc/hosts:"
echo "  127.0.0.1 gitlab.k3d.local registry.k3d.local minio.k3d.local"
echo ""
echo "=========================================="
echo "Starting ArgoCD Port-Forward..."
echo "=========================================="
echo ""

# Start port-forward in background
nohup kubectl port-forward --address 0.0.0.0 service/argocd-server 4443:443 -n argocd > /tmp/argocd-forward.log 2>&1 &
sleep 2

echo "✓ ArgoCD accessible at: https://127.0.0.1:4443"
echo "✓ ArgoCD Username: admin"
echo "✓ ArgoCD Password: $ARGOCD_PASS"
echo ""
echo "✓ Port-forward started (running in background)"
echo ""
echo "To stop port-forward:"
echo "  pkill -f 'kubectl port-forward.*argocd-server'"
echo ""
echo "=========================================="
echo "==========================================="
