# Node image for {{name}} (Astro): build to static files, serve with nginx
# target: Dockerfile
FROM node:{{node}}-alpine AS build
WORKDIR /app
RUN corepack enable
COPY package*.json pnpm-lock.yaml* yarn.lock* bun.lock* ./
RUN corepack enable && {{install}}
COPY . .
RUN {{run}} build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
