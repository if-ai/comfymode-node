#!/usr/bin/env bash
# ComfyDeploy Web deploy — VPS tar+scp fallback
# Works even when Dokploy GitHub provider is not configured.
#
# Usage: ./deploy-web.sh
# Build args are the public Clerk/API URLs — NOT secrets.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
APP_SRC="/Users/edgarfernandes/comfydeploy_private_work/apps/app"
VPS_HOST="impactframes-vps"
SERVICE_NAME="comfymode-comfydeployweb-fyjrwy"
DEPLOY_USER="${DEPLOY_USER:-root}"

TAG="web-$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Build args — these are public values baked at image build time
# Clerk key MUST come from Infisical to use the correct Clerk app
# ---------------------------------------------------------------------------
NEXT_PUBLIC_CD_API_URL="${NEXT_PUBLIC_CD_API_URL:-https://api.comfy.impactframes.ai}"

# Use hardcoded Clerk publishable key
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="pk_test_c3VwZXItbGxhbWEtODcuY2xlcmsuYWNjb3VudHMuZGV2JA"

# ---------------------------------------------------------------------------
# Step 1: Package source
# ---------------------------------------------------------------------------
TAR_PATH="/tmp/comfydeploy-web-${TAG}.tar"
echo "Packaging Web source -> ${TAG} ..."
tar --exclude='.git' \
    --exclude='.yalc' \
    --exclude='node_modules/.cache' \
    -cf "$TAR_PATH" -C "$APP_SRC" .

# ---------------------------------------------------------------------------
# Step 2: Upload to VPS
# ---------------------------------------------------------------------------
echo "Uploading to VPS (${VPS_HOST}) ..."
scp -o StrictHostKeyChecking=no "$TAR_PATH" "${DEPLOY_USER}@${VPS_HOST}:/tmp/"

# ---------------------------------------------------------------------------
# Step 3: Build and update service on VPS
# ---------------------------------------------------------------------------
echo "Building and rolling service on VPS ..."
ssh -o StrictHostKeyChecking=no "${DEPLOY_USER}@${VPS_HOST}" <<EOF
  set -e
  SERVICE_NAME="${SERVICE_NAME}"
  TAG="${TAG}"
  NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}"
  NEXT_PUBLIC_CD_API_URL="${NEXT_PUBLIC_CD_API_URL}"

  echo "==> Extracting source"
  rm -rf "/tmp/comfydeploy-web-\${TAG}"
  mkdir -p "/tmp/comfydeploy-web-\${TAG}"
  tar -xf "/tmp/comfydeploy-web-\${TAG}.tar" -C "/tmp/comfydeploy-web-\${TAG}"

  echo "==> Building image \${SERVICE_NAME}:\${TAG}"
  docker build \
    --build-arg NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="\${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}" \
    --build-arg NEXT_PUBLIC_CD_API_URL="\${NEXT_PUBLIC_CD_API_URL}" \
    --build-arg NEXT_PUBLIC_CLERK_SIGN_IN_FORCE_REDIRECT_URL="/workflows" \
    --build-arg NEXT_PUBLIC_CLERK_SIGN_UP_FORCE_REDIRECT_URL="/pricing" \
    --build-arg NEXT_PUBLIC_CLERK_SIGN_IN_FALLBACK_REDIRECT_URL="/" \
    --build-arg NEXT_PUBLIC_CLERK_SIGN_UP_FALLBACK_REDIRECT_URL="/" \
    -t "\${SERVICE_NAME}:\${TAG}" \
    "/tmp/comfydeploy-web-\${TAG}"

  echo "==> Updating Swarm service"
  docker service update \
    --image "${SERVICE_NAME}:${TAG}" \
    --detach=false \
    "${SERVICE_NAME}"

  echo "==> Done. Image: \${SERVICE_NAME}:\${TAG}"
  rm -f "/tmp/comfydeploy-web-\${TAG}.tar"
  rm -rf "/tmp/comfydeploy-web-\${TAG}"
EOF

echo "Web deploy complete: ${SERVICE_NAME}:${TAG}"
