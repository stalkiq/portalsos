FROM node:22-alpine
WORKDIR /app
COPY backend/server.js ./server.js
COPY web ./web
ENV PORT=8080
ENV NEBIUS_MODEL=nvidia/Nemotron-3_5-Lightning
EXPOSE 8080
CMD ["node", "server.js"]
