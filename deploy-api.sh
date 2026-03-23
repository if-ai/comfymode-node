#!/usr/bin/env bash
# ComfyDeploy API deploy — VPS tar+scp fallback
# Works even when Dokploy GitHub provider is not configured.
#
# Usage: ./deploy-api.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
API_SRC="/Users/edgarfernandes/comfydeploy/apps/api"
INFISICAL_ENV_LOCAL="/Users/edgarfernandes/comfydeploy/.env.infisical"
VPS_HOST="impactframes-vps"
SERVICE_NAME="comfymode-comfydeployapi-nmek1z"
DEPLOY_USER="${DEPLOY_USER:-root}"

TAG="api-$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Step 1: Package source
# ---------------------------------------------------------------------------
TAR_PATH="/tmp/comfydeploy-api-${TAG}.tar"
echo "Packaging API source -> ${TAG} ..."
tar --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.venv' \
    -cf "$TAR_PATH" -C "$API_SRC" .

# ---------------------------------------------------------------------------
# Step 2: Upload Source and Secrets to VPS
# ---------------------------------------------------------------------------
echo "Uploading Source to VPS (${VPS_HOST}) ..."
scp -o StrictHostKeyChecking=no "$TAR_PATH" "${DEPLOY_USER}@${VPS_HOST}:/tmp/"

echo "Uploading Secrets to VPS (${VPS_HOST}) ..."
scp -o StrictHostKeyChecking=no "$INFISICAL_ENV_LOCAL" "${DEPLOY_USER}@${VPS_HOST}:/etc/comfydeploy/.env.infisical"
ssh -o StrictHostKeyChecking=no "${DEPLOY_USER}@${VPS_HOST}" "chown root:root /etc/comfydeploy/.env.infisical && chmod 600 /etc/comfydeploy/.env.infisical"

# ---------------------------------------------------------------------------
# Step 3: Build and update service on VPS
# ---------------------------------------------------------------------------
echo "Building and rolling service on VPS ..."
ssh -o StrictHostKeyChecking=no "${DEPLOY_USER}@${VPS_HOST}" <<EOF
  set -e
  SERVICE_NAME="${SERVICE_NAME}"
  TAG="${TAG}"

  echo "==> Extracting source"
  rm -rf "/tmp/comfydeploy-api-\${TAG}"
  mkdir -p "/tmp/comfydeploy-api-\${TAG}"
  tar -xf "/tmp/comfydeploy-api-\${TAG}.tar" -C "/tmp/comfydeploy-api-\${TAG}"

  echo "==> Building image \${SERVICE_NAME}:\${TAG}"
  docker build \
    --build-arg NIXPACKS_NODE_VERSION=20 \
    -t "\${SERVICE_NAME}:\${TAG}" \
    "/tmp/comfydeploy-api-\${TAG}"

  echo "==> Updating Swarm service"
  if docker service ls --format '{{.Name}}' | grep -q "^${SERVICE_NAME}$"; then
    docker service update \
      --image "\${SERVICE_NAME}:\${TAG}" \
      --mount-add type=bind,source=/etc/comfydeploy/.env.infisical,target=/etc/comfydeploy/.env.infisical \
      --cap-add CAP_DAC_OVERRIDE \
      --detach=false \
      "\${SERVICE_NAME}"
  else
    echo "Service does not exist, creating new one..."
    docker service create \
      --name "\${SERVICE_NAME}" \
      --network dokploy-network \
      --publish published=8080,target=8080,mode=host \
      --mount type=bind,source=/etc/comfydeploy/.env.infisical,target=/etc/comfydeploy/.env.infisical \
      --cap-add CAP_DAC_OVERRIDE \
      --detach=false \
      "\${SERVICE_NAME}:\${TAG}"
  fi

  echo "==> Done. Image: \${SERVICE_NAME}:\${TAG}"
  rm -f "/tmp/comfydeploy-api-\${TAG}.tar"
  rm -rf "/tmp/comfydeploy-api-\${TAG}"
EOF

echo "API deploy complete: ${SERVICE_NAME}:${TAG}"
