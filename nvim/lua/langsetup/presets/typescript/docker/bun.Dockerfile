# Bun: install, then run the app with Bun itself (no build step), as the bun user
# target: Dockerfile
FROM oven/bun:1-slim
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production
COPY . .
USER bun
EXPOSE 3000
CMD ["bun", "run", "src/index.ts"]
