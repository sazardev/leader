# Alpine base for {{name}}: small image with a static server
# target: Dockerfile
FROM alpine:3.20
WORKDIR /app
COPY . .
EXPOSE 8080
CMD ["sh", "-c", "echo {{name}}"]
