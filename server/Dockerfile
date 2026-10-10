FROM node:24-alpine
WORKDIR /app
COPY package.json schema.sql ./
COPY src ./src
RUN mkdir /data && chown node:node /data
USER node
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 DB_PATH=/data/sync.db TRUST_PROXY=1
VOLUME /data
EXPOSE 8787
HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1:8787/v1/health || exit 1
CMD ["node", "src/node.js"]
