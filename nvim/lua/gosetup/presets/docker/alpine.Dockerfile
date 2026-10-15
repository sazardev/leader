# Dockerfile, alpine: multi-stage, cached modules, static binary, non-root user. Small and debuggable (has a shell)
# target: Dockerfile
FROM golang:{{go}}-alpine AS build
WORKDIR /src

# modules first: this layer is rebuilt only when go.mod / go.sum change
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/{{binary}} {{main}}

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 app
COPY --from=build /out/{{binary}} /usr/local/bin/{{binary}}
USER app
EXPOSE 8080
ENTRYPOINT ["{{binary}}"]
