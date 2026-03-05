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

# Rebuild Docker images
echo "Building base Docker image..."
docker build -t openclaw:local .
echo "Building custom Docker image (with brew)..."
docker build -t openclaw:custom -f Dockerfile.custom .

# Restart services
echo "Restarting services..."
echo "DEBUG: pwd=$(pwd)"
echo "DEBUG: .env exists=$(test -f .env && echo yes || echo no)"
echo "DEBUG: .env first 3 lines:"
head -3 .env 2>/dev/null || echo "DEBUG: cannot read .env"
echo "DEBUG: docker compose version:"
docker compose version

# Source .env into shell environment as fallback
set -a
source .env
set +a

COMPOSE="docker compose --env-file .env -f docker-compose.yml -f docker-compose.override.yml"
$COMPOSE down --remove-orphans --timeout 30 2>/dev/null || true
$COMPOSE up -d

# Wait and verify
echo "Waiting for services to start..."
sleep 10

if $COMPOSE ps | grep -q "Up"; then
  echo "Deployment successful!"
  $COMPOSE ps
else
  echo "Deployment failed!"
  $COMPOSE logs --tail 50
  exit 1
fi

docker image prune -f
echo "Deployment completed!"
