# Use the official Node.js image as base
FROM node:22-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy application code
COPY . .

# Build the SvelteKit application using the node adapter
RUN npm run build

# Production image
FROM node:22-alpine

WORKDIR /app

# We only need the built build directory and package files in production
COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/package-lock.json ./package-lock.json

# Install only production dependencies
RUN npm ci --omit=dev

# Expose port (Cloud Run defaults to 8080)
ENV PORT=8080
EXPOSE 8080

# Map application credentials dynamically provided by Cloud Run
ENV GOOGLE_CLOUD_PROJECT=curbscout-project

# Start the Node server adapter
CMD ["node", "build"]
