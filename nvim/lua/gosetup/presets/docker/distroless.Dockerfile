# Dockerfile, distroless: multi-stage, static binary in an image with no shell or package manager. Smallest attack surface
# target: Dockerfile
FROM golang:{{go}} AS build
WORKDIR /src

# modules first: this layer is rebuilt only when go.mod / go.sum change
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/{{binary}} {{main}}

# static: no libc, runs as an unprivileged user, CA certificates and tzdata included
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/{{binary}} /{{binary}}
EXPOSE 8080
ENTRYPOINT ["/{{binary}}"]
