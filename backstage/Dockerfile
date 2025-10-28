# Multi-stage build for Backstage
FROM node:18-bullseye-slim AS base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json yarn.lock ./

# Install dependencies
RUN yarn install --frozen-lockfile --production=false

# Copy source code
COPY . .

# Build the application
RUN yarn build

# Production stage
FROM node:18-bullseye-slim AS production

# Install system dependencies for production
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN groupadd -r backstage && useradd -r -g backstage backstage

# Set working directory
WORKDIR /app

# Copy built application from build stage
COPY --from=base /app/package.json /app/yarn.lock ./
COPY --from=base /app/packages/backend/dist ./packages/backend/dist
COPY --from=base /app/packages/backend/package.json ./packages/backend/
COPY --from=base /app/packages/app/dist ./packages/app/dist
COPY --from=base /app/packages/app/package.json ./packages/app/

# Install only production dependencies
RUN yarn install --frozen-lockfile --production=true

# Change ownership to backstage user
RUN chown -R backstage:backstage /app

# Switch to non-root user
USER backstage

# Expose ports
EXPOSE 4001 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4001/healthcheck || exit 1

# Start the application
CMD ["node", "packages/backend/dist/index.cjs"]