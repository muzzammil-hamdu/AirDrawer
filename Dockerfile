# ──────────────────────────────────────────────
# Stage 1 – Build the React/Vite application
# ──────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies first (layer cache)
COPY package.json package-lock.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# ──────────────────────────────────────────────
# Stage 2 – Serve with Nginx (minimal image)
# ──────────────────────────────────────────────
FROM nginx:1.27-alpine

# Copy custom nginx config for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Nginx listens on port 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
