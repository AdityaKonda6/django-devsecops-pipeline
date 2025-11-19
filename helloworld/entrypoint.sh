#!/bin/sh

# Fail fast
set -e

# Optionally wait for DB (simple loop)
if [ "$DATABASE_URL" ]; then
  echo "Waiting for database..."
  # You could use dj-database-url + a wait script here. Keep simple:
  sleep 1
fi

# Run migrations
echo "Running migrations..."
python manage.py migrate --noinput

# Collect static if in production (DEBUG=False)
if [ "$DJANGO_COLLECTSTATIC" = "1" ]; then
  echo "Collecting static files..."
  python manage.py collectstatic --noinput
fi

# Start server with gunicorn
echo "Starting Gunicorn..."
exec gunicorn helloworld.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3 \
  --log-level info
