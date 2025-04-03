FROM node:22-alpine

WORKDIR /app

# Install build dependencies for native modules
RUN apk add --no-cache python3 make g++ build-base

# Copy all files at once
COPY . .

# Install dependencies (including dev dependencies needed for build)
RUN npm install 

# Build the project
RUN npm run build

# Expose the port for HTTP transport
EXPOSE 8080

# Command will be provided by smithery.yaml
CMD ["node", "dist/index.js"]