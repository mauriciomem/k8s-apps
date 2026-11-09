# Frontend for the 3-tier apps: static page + reverse proxy /api/ -> service "backend"
# Runs as non-root (uid 101) on port 8080.
# Includes curl, psql and pg_isready for network connectivity tests.
FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine

USER root
RUN apk add --no-cache curl postgresql17-client
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
