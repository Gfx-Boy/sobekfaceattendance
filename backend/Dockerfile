FROM node:20-alpine

LABEL version="1.1.0"

WORKDIR /app

# Install dependencies
COPY package.json ./
RUN npm install --omit=dev

# Copy source
COPY src/ ./src/

# Create uploads directory
RUN mkdir -p uploads

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "src/server.js"]
