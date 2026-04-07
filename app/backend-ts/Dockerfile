# syntax=docker/dockerfile:1@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
# Build
#FROM microservice-build as build
FROM docker.io/node:24-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS build
ENV NODE_ENV=production
WORKDIR /app
COPY package.json .npmrc ./
RUN npm ci

# Run
FROM docker.io/node:24-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS runtime
WORKDIR /app
COPY --from=build /app /app
COPY /src /app/src
EXPOSE 3000
CMD [ "npm", "run", "start" ]
