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

# --- Security and Run Commands ---

# 1. Create a non-root user (Fixes Trivy Misconfig issue)
RUN adduser -S -D -G django_user django_user

# 2. Switch to the non-root user
USER django_user

# Expose port (gunicorn will listen here)
EXPOSE 8000

# Entrypoint setup
COPY ./entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Default command
CMD ["/app/entrypoint.sh"]


# # Use a slim Python image
# FROM python:3.11-slim

# # Set environment
# ENV PYTHONDONTWRITEBYTECODE=1
# ENV PYTHONUNBUFFERED=1

# # Create app dir
# WORKDIR /app

# # Install system deps (for psycopg2) and build tools
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     build-essential \
#     gcc \
#     libpq-dev \
#  && rm -rf /var/lib/apt/lists/*

# # Copy dependency files first for caching
# COPY requirements.txt /app/

# # Install Python dependencies
# RUN pip install --upgrade pip
# RUN pip install -r requirements.txt

# # Copy application code
# COPY . /app

# # Collect static files (only necessary if DEBUG=False and you use static files)
# ENV DJANGO_SETTINGS_MODULE=helloworld.settings
# RUN python manage.py collectstatic --noinput || true

# # 1. Create a non-root user
# RUN adduser --system --group django_user

# # 2. Switch to the non-root user
# USER django_user

# # Expose port (gunicorn will listen here)
# EXPOSE 8000

# # Entrypoint will run migrations and start server (see entrypoint.sh below)
# COPY ./entrypoint.sh /app/entrypoint.sh
# RUN chmod +x /app/entrypoint.sh

# # Default command
# CMD ["/app/entrypoint.sh"]
