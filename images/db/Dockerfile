# PostgreSQL with a small seed table. Port 5432.
# Credentials are passed at runtime via POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB.
FROM docker.io/library/postgres:16-alpine

COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 5432
