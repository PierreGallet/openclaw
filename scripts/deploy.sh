#!/bin/bash
set -e

echo "Starting OpenClaw deployment..."

cd "$DEPLOY_PATH"

# Backup .env before git operations (git reset --hard would overwrite it)
if [ -f ".env" ]; then
  cp .env /tmp/openclaw_env_backup
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

# Restore .env
if [ -f "/tmp/openclaw_env_backup" ]; then
  cp /tmp/openclaw_env_backup .env
  rm -f /tmp/openclaw_env_backup
fi

# Ensure OPENCLAW_SERVER_NAME is in .env
if grep -q '^OPENCLAW_SERVER_NAME=' .env 2>/dev/null; then
  sed -i "s/^OPENCLAW_SERVER_NAME=.*/OPENCLAW_SERVER_NAME=${OPENCLAW_SERVER_NAME}/" .env
else
  echo "OPENCLAW_SERVER_NAME=${OPENCLAW_SERVER_NAME}" >> .env
fi

# Rebuild Docker image
echo "Building Docker image..."
docker build -t openclaw:local .

# Restart services
echo "Restarting services..."
docker compose -f docker-compose.yml -f docker-compose.override.yml down --remove-orphans --timeout 30 2>/dev/null || true
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
