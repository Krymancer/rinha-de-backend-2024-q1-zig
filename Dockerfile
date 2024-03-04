FROM alpine:3.18.3 as runtime
USER root
WORKDIR /app
COPY ./zig-out/bin/rinha-de-backend-2024-q1-zig /app/rinha-de-backend-2024-q1-zig
ENTRYPOINT ["/app/rinha-de-backend-2024-q1-zig"]
