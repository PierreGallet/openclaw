#!/bin/bash
set -e

echo "Starting OpenClaw deployment..."

cd "$DEPLOY_PATH"

# Load .env into shell environment BEFORE any git operations
# This ensures variables survive even if .env gets modified
if [ -f ".env" ]; then
  echo "Loading .env ($(wc -l < .env) lines)..."
  set -a
  source .env
  set +a
else
  echo "WARNING: No .env found, will need one after clone"
fi

# Update repository from fork
if [ -d ".git" ]; then
  echo "Updating existing repository..."
  git remote set-url origin "https://${GHP_TOKEN}@github.com/PierreGallet/openclaw.git"
  git fetch origin
  git reset --hard origin/main
else
  echo "Cloning repository..."
  mkdir -p "$DEPLOY_PATH"
  git clone "https://${GHP_TOKEN}@github.com/PierreGallet/openclaw.git" .
fi

# Verify required variables are set (from .env sourced earlier)
if [ -z "$OPENCLAW_CONFIG_DIR" ]; then
  echo "ERROR: OPENCLAW_CONFIG_DIR not set. Check .env on server."
  exit 1
fi

# Ensure GITHUB_TOKEN is in .env (for gh CLI inside container)
if [ -n "$GHP_TOKEN" ]; then
  if grep -q '^GITHUB_TOKEN=' .env 2>/dev/null; then
    sed -i "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=${GHP_TOKEN}|" .env
  else
    echo "GITHUB_TOKEN=${GHP_TOKEN}" >> .env
  fi
fi

# Rebuild Docker images
echo "Building base Docker image..."
docker build -t openclaw:local .
echo "Building custom Docker image (with brew)..."
docker build -t openclaw:custom -f Dockerfile.custom .

# Restart services
echo "Restarting services..."
docker compose --env-file .env -f docker-compose.yml -f docker-compose.override.yml down --remove-orphans --timeout 30 2>/dev/null || true
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Wait and verify
echo "Waiting for services to start..."
sleep 10

if docker compose -f docker-compose.yml -f docker-compose.override.yml ps | grep -q "Up"; then
  echo "Deployment successful!"
  docker compose -f docker-compose.yml -f docker-compose.override.yml ps
else
  echo "Deployment failed!"
  docker compose -f docker-compose.yml -f docker-compose.override.yml logs --tail 50
  exit 1
fi

docker image prune -f
echo "Deployment completed!"
