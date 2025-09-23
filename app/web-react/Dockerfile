# Build
#FROM microservice-build as build
FROM docker.io/node:22-alpine AS build
ENV NODE_ENV=production
WORKDIR /app
COPY package.json .
RUN npm ci

# Run
FROM docker.io/node:22-alpine AS runtime
WORKDIR /app
COPY --from=build /app /app
COPY /src /app/src
EXPOSE 3000
CMD [ "npm", "run", "start" ]
