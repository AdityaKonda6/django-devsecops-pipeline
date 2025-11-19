# Use the Alpine base image
FROM python:3.11-alpine

# Set environment
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create app dir
WORKDIR /app

# --- Dependency Installation Block ---
# Install system deps (for psycopg2) and build tools using 'apk'
# 'build-base' is the Alpine equivalent of build-essential/gcc.
# 'postgresql-dev' is the Alpine equivalent of libpq-dev.
RUN apk update && apk add --no-cache \
    postgresql-dev \
    build-base

# Copy dependency files first for caching
COPY requirements.txt /app/

# Install Python dependencies and immediately remove build tools
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt \
    # Cleanup: Remove the build dependencies to shrink the final image size
    && apk del build-base \
    && rm -rf /var/cache/apk/* # --- Application Setup ---

# Copy application code
COPY . /app

# Collect static files (ensure this only runs if needed)
ENV DJANGO_SETTINGS_MODULE=helloworld.settings
RUN python manage.py collectstatic --noinput || true

# Entrypoint setup
COPY ./entrypoint.sh /app/entrypoint.sh

# 🔑 FIX: Run chmod as root user (before switching the user context)
RUN chmod +x /app/entrypoint.sh

# 1. Create a non-root group explicitly
RUN addgroup -S django_user

# 2. Create the non-root user and assign them to the existing group
RUN adduser -S -D -G django_user django_user
    
# 3. Switch to the non-root user (ALL subsequent commands run as this user)
USER django_user

# Expose port (gunicorn will listen here)
EXPOSE 8000

# Default command
CMD ["/app/entrypoint.sh"]
