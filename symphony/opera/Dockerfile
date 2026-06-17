# Step 1: Build the base image with Node.js
FROM docker.io/library/node:18-alpine as builder

# Set the working directory in the container
WORKDIR /app

# Copy package.json and package-lock.json
COPY package.json package-lock.json ./

# Install dependencies (including dev dependencies for build)
RUN npm install --legacy-peer-deps

# Copy the rest of the application code
COPY . .

# Build the application
RUN npm run build

# Keep the runtime image small enough for the board's root filesystem.
RUN rm -rf .next/cache

# Step 2: Use a smaller base image for the production environment
FROM docker.io/library/node:18-alpine

# Set the working directory in the container
WORKDIR /app

# Set NODE_ENV to production
ENV NODE_ENV=production

# Copy only the traced standalone runtime and static assets.
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

# Expose the port Next.js runs on
EXPOSE 3000

# Command to run the application
CMD ["node", "server.js"]
