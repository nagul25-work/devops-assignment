# Stage 1 — install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --only=production

# Stage 2 — final image
FROM node:20-alpine AS runner
WORKDIR /app

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy deps and source
COPY --from=deps /app/node_modules ./node_modules
COPY app/src ./src
COPY app/public ./public

# Set ownership
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

EXPOSE 3000
CMD ["node", "src/index.js"]