# Create a new service using a scaffold generator

The scaffold generators can be found in `scaffolds/generators` directory. The generators are used to create new services using a predefined template.

Generators:
- `express-backend`: A backend microservice using TypeScript and Express.
- `nextjs-frontend`: A frontend microservice using Next.js.
- `react-frontend`: A frontend SPA using React and Vite.

## Prerequisites
Yeoman must be installed globally. Use pnpm:
```bash
pnpm add -g yo
```

## Steps
1. From project root directory run a generator. Example;
    - `yo ./scaffolds/generators/express-backend {name}`
2. The new service will be created using the provided scaffold and can be found in `app/{name}`.
3. From the project root, run `pnpm install` so the workspace symlinks the new package and resolves its dependencies.
    - Modify `docker-compose.yaml` (and any other docker-compose files to set environment variables, ports, volumes, etc).
4. From the project root directory, perform the following steps:
    - Add the new service to the projects root `docker-compose.yaml` file under `include:`.
    - Build the new services image by running `make build`.
    - Start the services by running `make up`.
