# Stage 1: Download binaries
FROM node:18-alpine AS bins
RUN apk add --no-cache curl unzip
WORKDIR /bins

# Download xray (amd64 for build, runtime will use correct arch via TARGETARCH)
ARG TARGETARCH=amd64
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64"; \
    else \
      XRAY_ARCH="64"; CF_ARCH="amd64"; \
    fi && \
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" && \
    unzip -o xray.zip xray -d . && rm -f xray.zip && chmod +x xray && \
    curl -L -o cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" && \
    chmod +x cloudflared

# Stage 2: Install dependencies
FROM node:18-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm install --production --no-audit --no-fund && \
    npm cache clean --force

# Stage 3: Runtime image
FROM node:18-alpine
ENV NODE_ENV=production \
    PORT=3000 \
    FILE_PATH=/app/tmp

RUN apk add --no-cache \
    openssl curl gcompat iproute2 coreutils \
    bash unzip ca-certificates tzdata procps && \
    update-ca-certificates

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup && \
    mkdir -p /app/tmp /app/bin && \
    chown -R appuser:appgroup /app

# Copy pre-built binaries
COPY --from=bins --chown=appuser:appgroup /bins/xray /app/bin/xray
COPY --from=bins --chown=appuser:appgroup /bins/cloudflared /app/bin/cloudflared

# Copy node_modules
COPY --from=deps /app/node_modules /app/node_modules

# Copy application code
COPY --chown=appuser:appgroup . /app
WORKDIR /app

ENTRYPOINT ["node", "/app/app.js"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "const http=require('http');\
    const req=http.get('http://localhost:'+process.env.PORT+'/health',(r)=>{process.exit(r.statusCode===200?0:1)});\
    req.on('error',()=>process.exit(1))"

USER appuser
EXPOSE 3000
