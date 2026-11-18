# Crenel website. Build context: the repository root, so the release notes in
# docs/releases are part of the build (Dokploy: Dockerfile "website/Dockerfile",
# context path ".").
FROM node:24-alpine AS build
RUN apk add --no-cache git
WORKDIR /repo
COPY website/package.json website/package-lock.json website/
RUN cd website && npm ci
COPY docs/releases docs/releases
COPY website website
ARG SITE_URL
ENV SITE_URL=${SITE_URL}
RUN cd website && npm run build

FROM nginx:1.29-alpine
COPY website/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/website/dist /usr/share/nginx/html
EXPOSE 80
