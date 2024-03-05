#! /bin/sh
zig build
sudo docker build -t krymancer/rinha-de-backend-2024-q1-zig .
sudo docker push krymancer/rinha-de-backend-2024-q1-zig:latest
