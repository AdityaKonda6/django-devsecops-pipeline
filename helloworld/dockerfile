# Use a slim Python image
FROM python:3.11-slim

# Set environment
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create app dir
WORKDIR /app

# Install system deps (for psycopg2) and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for caching
COPY requirements.txt /app/

# Install Python dependencies
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Copy application code
COPY . /app

# Collect static files (only necessary if DEBUG=False and you use static files)
ENV DJANGO_SETTINGS_MODULE=helloworld.settings
RUN python manage.py collectstatic --noinput || true

# Expose port (gunicorn will listen here)
EXPOSE 8000

# Entrypoint will run migrations and start server (see entrypoint.sh below)
COPY ./entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Default command
CMD ["/app/entrypoint.sh"]
