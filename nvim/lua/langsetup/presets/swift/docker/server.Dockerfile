# Swift server multi-stage: a release build with the static stdlib, then a slim runtime as non-root
# target: Dockerfile
FROM swift:{{swift}} AS build
WORKDIR /app
COPY Package.* ./
RUN swift package resolve
COPY . .
RUN swift build -c release --static-swift-stdlib

FROM swift:{{swift}}-slim
RUN useradd --create-home app
COPY --from=build /app/.build/release/{{binary}} /usr/local/bin/{{binary}}
USER app
EXPOSE 8080
CMD ["{{binary}}"]
