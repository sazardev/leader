# Rust multi-stage with a distroless runtime: no shell, no package manager, only the binary and its libc
# target: Dockerfile
FROM rust:1-slim AS build
WORKDIR /app
COPY . .
RUN cargo build --release

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /app/target/release/{{binary}} /{{binary}}
EXPOSE 8080
ENTRYPOINT ["/{{binary}}"]
