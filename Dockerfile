FROM debian:bookworm-slim AS upstream-source
ARG ANYTHINGLLM_VERSION=v1.17.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/upstream
RUN curl -fsSL "https://github.com/Mintplex-Labs/anything-llm/archive/refs/tags/${ANYTHINGLLM_VERSION}.tar.gz" -o anythingllm.tar.gz \
 && tar -xzf anythingllm.tar.gz --strip-components=1 \
 && rm anythingllm.tar.gz

FROM --platform=$BUILDPLATFORM node:18-slim AS frontend-build
WORKDIR /app/frontend
COPY --from=upstream-source /tmp/upstream/frontend/package.json ./
COPY --from=upstream-source /tmp/upstream/frontend/yarn.lock ./
RUN corepack enable && corepack prepare yarn@1.22.19 --activate
RUN yarn install --network-timeout 100000 && yarn cache clean
COPY --from=upstream-source /tmp/upstream/frontend/ ./
RUN yarn build

FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c
ARG ANYTHINGLLM_VERSION=v1.17.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    ANYTHING_LLM_RUNTIME=cloudron \
    DEPLOYMENT_VERSION=1.17.0 \
    HOME=/app/data \
    PATH=/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    ffmpeg \
    fonts-liberation \
    git \
    gnupg \
    libappindicator3-1 \
    libasound2t64 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgfortran5 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    ne \
    netcat-openbsd \
    tzdata \
    unzip \
    xdg-utils \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs \
 && ln -sf /usr/bin/node /usr/local/bin/node \
 && ln -sf /usr/bin/npm /usr/local/bin/npm \
 && ln -sf /usr/bin/npx /usr/local/bin/npx \
 && ln -sf /usr/bin/corepack /usr/local/bin/corepack \
 && /usr/bin/node --version | grep -E '^v18\.' \
 && /usr/bin/npm --version >/dev/null \
 && /usr/bin/npm install --global yarn@1.22.19 \
 && curl -LsSf https://astral.sh/uv/0.6.10/install.sh | sh \
 && mv /app/data/.local/bin/uv /usr/local/bin/uv \
 && mv /app/data/.local/bin/uvx /usr/local/bin/uvx \
 && node --version | grep -E '^v18\.' \
 && npm --version >/dev/null \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app/code
RUN mkdir -p /app/code /app/code/defaults /app/data

COPY --from=upstream-source /tmp/upstream/server /app/code/server
COPY --from=upstream-source /tmp/upstream/collector /app/code/collector
COPY --from=frontend-build /app/frontend/dist /app/code/server/public
COPY --from=upstream-source /tmp/upstream/LICENSE /app/code/UPSTREAM-LICENSE
COPY start.sh /app/code/start.sh
COPY server.env.template /app/code/defaults/server.env
COPY --from=upstream-source /tmp/upstream/server/storage /app/code/defaults/storage

RUN set -eux; \
    cd /app/code/server; \
    yarn install --production --network-timeout 100000; \
    yarn cache clean || true; \
    cd /app/code/collector; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
      curl -fSL https://webassets.anythingllm.com/chromium-1088-linux-arm64.zip -o /tmp/chrome-linux.zip; \
      unzip /tmp/chrome-linux.zip -d /app; \
      rm -f /tmp/chrome-linux.zip; \
      export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true; \
      export CHROME_PATH=/app/chrome-linux/chrome; \
      export PUPPETEER_EXECUTABLE_PATH=/app/chrome-linux/chrome; \
    else \
      export PUPPETEER_DOWNLOAD_BASE_URL=https://storage.googleapis.com/chrome-for-testing-public; \
    fi; \
    yarn install --production --network-timeout 100000; \
    yarn cache clean || true

RUN mkdir -p /app/code/defaults/server /app/code/defaults/collector \
 && mv /app/code/server/node_modules /app/code/defaults/server/node_modules \
 && mv /app/code/collector/node_modules /app/code/defaults/collector/node_modules \
 && rm -rf /app/code/server/storage \
 && rm -rf /app/code/collector/hotdir \
 && rm -rf /app/code/collector/outputs \
 && rm -rf /app/code/collector/storage \
 && ln -s /app/data/server/node_modules /app/code/server/node_modules \
 && ln -s /app/data/collector/node_modules /app/code/collector/node_modules \
 && ln -s /app/data/storage /app/code/server/storage \
 && ln -s /app/data/collector/hotdir /app/code/collector/hotdir \
 && ln -s /app/data/collector/outputs /app/code/collector/outputs \
 && ln -s /app/data/collector/storage /app/code/collector/storage \
 && ln -s /app/data/server.env /app/code/server/.env \
 && ln -s /app/data/server.env /app/code/collector/.env \
 && chmod +x /app/code/start.sh \
 && chown -R cloudron:cloudron /app/code

EXPOSE 3001
CMD ["/app/code/start.sh"]
