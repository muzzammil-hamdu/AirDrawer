#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# AirDrawer – Build → Push to ACR → Deploy to AKS
# Usage:  ./deploy.sh [image-tag]   (default: latest)
# ─────────────────────────────────────────────────────────────

ACR_NAME="mujjuacr1122"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
IMAGE_NAME="airdrawer"
TAG="${1:-latest}"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${TAG}"
K8S_CONTEXT="luminary-aks-cluster"
NAMESPACE="airdrawer"

echo "======================================================"
echo " AirDrawer Deployment"
echo " Image  : ${FULL_IMAGE}"
echo " Cluster: ${K8S_CONTEXT}"
echo " NS     : ${NAMESPACE}"
echo "======================================================"

# ── Step 1: Log in to ACR ─────────────────────────────────
echo ""
echo "[1/5] Logging in to ACR..."
az acr login --name "${ACR_NAME}"

# ── Step 2: Build Docker image ────────────────────────────
echo ""
echo "[2/5] Building Docker image..."
docker build -t "${FULL_IMAGE}" .

# ── Step 3: Push image to ACR ─────────────────────────────
echo ""
echo "[3/5] Pushing image to ACR..."
docker push "${FULL_IMAGE}"

# ── Step 4: Switch kubectl context ────────────────────────
echo ""
echo "[4/5] Switching kubectl context to ${K8S_CONTEXT}..."
kubectl config use-context "${K8S_CONTEXT}"

# ── Step 5: Apply Kubernetes manifests ────────────────────
echo ""
echo "[5/5] Applying Kubernetes manifests..."

# Create namespace (safe – will not fail if it already exists)
kubectl apply -f k8s/namespace.yaml

# Create ACR pull secret if it doesn't already exist
if ! kubectl get secret acr-secret -n "${NAMESPACE}" &>/dev/null; then
    echo "  → Creating ACR image pull secret..."
    kubectl create secret docker-registry acr-secret \
        --namespace "${NAMESPACE}" \
        --docker-server="${ACR_LOGIN_SERVER}" \
        --docker-username="$(az acr credential show --name ${ACR_NAME} --query username -o tsv)" \
        --docker-password="$(az acr credential show --name ${ACR_NAME} --query 'passwords[0].value' -o tsv)"
else
    echo "  → ACR pull secret already exists, skipping."
fi

# Update the image tag in the deployment manifest on-the-fly and apply
kubectl set image deployment/airdrawer airdrawer="${FULL_IMAGE}" -n "${NAMESPACE}" 2>/dev/null || \
    kubectl apply -f k8s/deployment.yaml

kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# ── Wait for rollout ──────────────────────────────────────
echo ""
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/airdrawer -n "${NAMESPACE}" --timeout=120s

# ── Show external IP ──────────────────────────────────────
echo ""
echo "======================================================"
echo " Deployment complete!"
echo " Fetching external access info..."
echo "======================================================"
kubectl get ingress airdrawer -n "${NAMESPACE}"
echo ""
kubectl get svc airdrawer -n "${NAMESPACE}"
