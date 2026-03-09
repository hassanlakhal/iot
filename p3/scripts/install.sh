#!/bin/bash

# 1. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh && rm get-docker.sh
fi

# 2. Install K3d
if ! command -v k3d &> /dev/null; then
    echo "Installing K3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# 3. Install Kubectl (FIXED PATH)
if ! command -v kubectl &> /dev/null; then
    echo "Installing Kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 ./kubectl /usr/local/bin/kubectl && rm ./kubectl
fi
# 4. Create K3d Cluster (Cleanup first)
k3d cluster delete iot-cluster &> /dev/null
echo "Creating cluster with port 8888..."
k3d cluster create iot-cluster -p "8888:8888@loadbalancer" --agents 1

# 5. Create Namespaces
kubectl create namespace argocd
kubectl create namespace dev

# 6. Install Argo CD (FIXED with --server-side to avoid 'Too long' error)
echo "Installing Argo CD..."
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 7. Wait for Argo CD to be ready
echo "Waiting for Argo CD (this takes ~4 mins)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s

# 8. Get ArgoCD credentials
echo ""
echo "=========================================="
echo "✓ Installation Complete!"
echo "=========================================="
echo ""
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)

# Get the IP address of the machine
HOST_IP=$(hostname -I | awk '{print $1}')

echo "✓ ArgoCD accessible at: https://${HOST_IP}:4443"
echo "✓ ArgoCD Username: admin"
echo "✓ ArgoCD Password: $ARGOCD_PASS"
echo ""
echo "Starting port-forward in background..."
nohup kubectl port-forward --address 0.0.0.0 service/argocd-server 4443:443 -n argocd > /tmp/argocd-forward.log 2>&1 &
sleep 2

echo "✓ Port-forward started"
echo ""
echo "To stop port-forward:"
echo "  pkill -f 'kubectl port-forward.*argocd-server'"
echo ""
echo "=========================================="

# 9. Deploy application
echo "[*] Deploying application..."
kubectl apply -f confs/application.yaml

echo "[✓] Application deployed!"