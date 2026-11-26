# syntax=docker/dockerfile:1.7
# =============================================================================
#  Korxona MeshCentral image (custom fork + white-label + air-gapped)
#  Build context = repo ildizi:   docker compose build   (yoki setup.sh)
#
#  Build vaqtida internet KERAK (git, npm, GitHub release'dan agent binarlari).
#  Tayyor image esa internetsiz ishlaydi: barcha npm modullar, tarjimalar,
#  minify qilingan sahifalar va agent binarlari image ichida.
# =============================================================================
ARG NODE_IMAGE=node:24.22.1-alpine3.24

# ---------------------------------------------------------------- builder ----
FROM ${NODE_IMAGE} AS builder
RUN apk add --no-cache git bash jq curl python3 make g++

ARG MESHCENTRAL_REPO=https://github.com/Ylianst/MeshCentral.git
ARG MESHCENTRAL_REF=01f2d97fd818bbc7c7bb61a0d93c580e8eb10ba4
WORKDIR /build

# 1) Upstream (yoki sizning fork'ingiz) aniq commit bo'yicha
RUN git init -q meshcentral \
 && git -C meshcentral remote add origin "$MESHCENTRAL_REPO" \
 && git -C meshcentral fetch -q --depth 1 origin "$MESHCENTRAL_REF" \
 && git -C meshcentral checkout -q FETCH_HEAD \
 && echo "MeshCentral $(jq -r .version meshcentral/package.json) @ $(git -C meshcentral rev-parse --short HEAD)"

# 2) Korxona patch'lari (patches/meshcentral/*.patch, tartib bo'yicha)
COPY patches/meshcentral/ /build/patches/
RUN cd meshcentral && for p in $(ls /build/patches/*.patch 2>/dev/null | sort); do \
      echo "apply $p"; git apply --whitespace=nowarn "$p"; done

# 3) Brending: matnlar (views, emails, translate.json)
COPY branding/brand.env /build/branding/brand.env
COPY scripts/rebrand.js scripts/pin-optional-modules.js scripts/fetch-agent-binaries.sh /build/scripts/
RUN set -a && . /build/branding/brand.env && set +a && node /build/scripts/rebrand.js /build/meshcentral

# 4) Tarjima + minify (o'zgargan inglizcha matnlardan qayta generatsiya)
RUN cd meshcentral \
 && npm install --no-save --no-audit --no-fund html-minifier-terser@7.2.0 jsdom@26.0.0 esprima@4.0.1 >/dev/null \
 && cd translate && node translate.js minifyall && node translate.js translateall \
 && cd .. && rm -rf node_modules

# 5) Bog'liqliklar: asosiy + air-gapped uchun oldindan o'rnatiladigan ixtiyoriy modullar
RUN cd meshcentral \
 && node /build/scripts/pin-optional-modules.js . \
      mongodb @mongodb-js/saslprep ssh2 image-size wildleek nodemailer https-proxy-agent \
 && npm install --package-lock-only --no-audit --no-fund \
 && npm ci --omit=dev --no-audit --no-fund \
 && npm cache clean --force

# 6) Agent binarlari (SHA384 bilan tekshirilib) image ichiga
RUN bash /build/scripts/fetch-agent-binaries.sh /build/meshcentral

# 7) Ixtiyoriy: o'zingiz kompilyatsiya qilgan MeshAgent (agent/custom-bin/)
COPY agent/custom-bin/ /build/custom-bin/
RUN if [ -f /build/custom-bin/custom-manifest.json ]; then \
      cp /build/custom-bin/custom-manifest.json /build/meshcentral/agents/custom-manifest.json; \
      for f in $(jq -r '.releases[].files[].filename' /build/custom-bin/custom-manifest.json); do \
        cp "/build/custom-bin/$f" "/build/meshcentral/agents/$f"; done; \
      echo "custom MeshAgent binaries included"; fi \
 && rm -rf /build/meshcentral/docker /build/meshcentral/docs /build/meshcentral/.git

# ---------------------------------------------------------------- runtime ----
FROM ${NODE_IMAGE}
RUN apk add --no-cache bash jq curl tzdata mongodb-tools tini

ENV NODE_ENV=production \
    # npm hech qachon internetga chiqmasin (versiya tekshiruvi, modul o'rnatish)
    NPM_CONFIG_OFFLINE=true \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false

COPY --from=builder --chown=node:node /build/meshcentral /opt/meshcentral/meshcentral
COPY --chown=node:node server/entrypoint.sh /opt/meshcentral/entrypoint.sh
RUN chmod +x /opt/meshcentral/entrypoint.sh \
 && mkdir -p /opt/meshcentral/meshcentral-data /opt/meshcentral/meshcentral-files \
             /opt/meshcentral/meshcentral-web /opt/meshcentral/meshcentral-backups /opt/meshcentral/tls \
 && chown -R node:node /opt/meshcentral

ARG BUILD_REVISION=unknown
LABEL org.opencontainers.image.title="corp-meshcentral" \
      org.opencontainers.image.revision="${BUILD_REVISION}" \
      org.opencontainers.image.licenses="Apache-2.0"

USER node
WORKDIR /opt/meshcentral
EXPOSE 4430
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS http://127.0.0.1:4430/health.ashx || exit 1
ENTRYPOINT ["/sbin/tini", "--", "/opt/meshcentral/entrypoint.sh"]
