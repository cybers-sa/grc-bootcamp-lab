#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${CODESPACE_NAME:-}" ]; then
  CA_HOST="${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  CA_URL="https://${CA_HOST}"
else
  CA_HOST="localhost"
  CA_URL="http://localhost:8080"
fi
printf 'CA_HOST=%s\nCA_URL=%s\n' "$CA_HOST" "$CA_URL" > .env

FIRST_RUN=false
if [ ! -d db ]; then
  FIRST_RUN=true
  mkdir -p db
  sudo chown -R 1001:1001 db
fi

echo "==> Starting CISO Assistant..."
docker compose up -d

echo "==> Waiting for the platform to be ready (first run can take a few minutes)..."
for i in $(seq 1 60); do
  if docker compose exec -T backend python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health/', timeout=5)" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 10
done

if [ "${READY:-false}" != "true" ]; then
  echo "The platform did not start in time. Recent logs:"
  docker compose logs --tail=50 backend
  exit 1
fi

if [ "$FIRST_RUN" = "true" ]; then
  ADMIN_EMAIL="admin@bootcamp.local"
  ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
  if docker compose exec -T \
      -e DJANGO_SUPERUSER_EMAIL="$ADMIN_EMAIL" \
      -e DJANGO_SUPERUSER_PASSWORD="$ADMIN_PASSWORD" \
      backend python manage.py createsuperuser --noinput >/dev/null 2>&1; then
    printf 'Email: %s\nPassword: %s\n' "$ADMIN_EMAIL" "$ADMIN_PASSWORD" > admin-credentials.txt
  else
    echo "Automatic admin creation failed. Create it manually with:"
    echo "  docker compose exec backend python manage.py createsuperuser"
  fi
fi

echo ""
echo "=============================================="
echo " CISO Assistant is ready"
echo " Open: ${CA_URL}"
if [ -f admin-credentials.txt ]; then
  echo ""
  echo " Admin account:"
  sed 's/^/   /' admin-credentials.txt
fi
echo "=============================================="
