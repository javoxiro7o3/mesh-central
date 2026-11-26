# NSIS + osslsigncode builder — makensis o'rnatilmagan (yoki air-gapped) serverlar uchun.
# agent/build-agent.sh avtomatik ishlatadi; offline bundle ichiga ham qo'shiladi.
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends nsis osslsigncode ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /w
