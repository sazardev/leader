# Node multi-stage: dependencies, build, then a small runtime image running as the node user
# target: Dockerfile
FROM node:{{node}}-slim AS deps
WORKDIR /app
COPY package*.json pnpm-lock.yaml* yarn.lock* bun.lock* ./
RUN corepack enable && {{install}}

FROM deps AS build
COPY . .
RUN {{run}} build

FROM node:{{node}}-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
