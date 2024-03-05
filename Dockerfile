FROM ubuntu:latest
USER root
WORKDIR /app
COPY ./zig-out/bin/rinha-de-backend-2024-q1-zig /app/rinha-de-backend-2024-q1-zig
RUN chmod +x /app/rinha-de-backend-2024-q1-zig
ENTRYPOINT ["/app/rinha-de-backend-2024-q1-zig"]
