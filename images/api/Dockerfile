# Backend for the 3-tier apps: small JSON API backed by PostgreSQL.
# Runs as non-root (uid 10001) on port 8080.
# Includes curl, psql and pg_isready for network connectivity tests.
FROM docker.io/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl postgresql-client \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "psycopg[binary]==3.2.*"

WORKDIR /app
COPY app.py .

USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
