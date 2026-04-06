# syntax=docker/dockerfile:1
# Build
FROM microservice-build as build
ENV NODE_ENV=production
WORKDIR /app
COPY package.json .
RUN npm ci

# Run
FROM microservice-build
WORKDIR /app
COPY --from=build /app /app
COPY /src /app/src
EXPOSE 3000
CMD [ "npm", "run", "start" ]
