# Rust multi-stage: dependencies cached apart from the code, a release build, a slim Debian runtime as non-root
# target: Dockerfile
FROM rust:1-slim AS build
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src
COPY . .
RUN touch src/main.rs && cargo build --release

FROM debian:stable-slim
RUN useradd --create-home app && apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/{{binary}} /usr/local/bin/{{binary}}
USER app
EXPOSE 8080
CMD ["{{binary}}"]
