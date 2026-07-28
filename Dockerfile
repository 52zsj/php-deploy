# GitShip 框架镜像：含运行时依赖，不含业务密钥 / 真实项目配置
# 构建: docker build -t gitship:local .
# 离线/复用旧镜像: docker build --build-arg BASE_IMAGE=php-deploy:local -t gitship:local .
# 运行: docker compose up -d
ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

ARG TARGETARCH=amd64
ARG YQ_VERSION=v4.45.4
ARG VERSION=0.0.0

LABEL org.opencontainers.image.title="GitShip" \
      org.opencontainers.image.description="Git pull → replace → multi-host rsync sync tool" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://gitee.com/json_decode/php-deploy"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    SYNC_UI_HOST=0.0.0.0 \
    SYNC_UI_PORT=8765 \
    SYNC_UI_NO_BROWSER=1 \
    APP_HOME=/app \
    GITSHIP_VERSION=${VERSION}

# 依赖已存在（例如基于旧 php-deploy 镜像）则跳过，便于离线构建
RUN set -eux; \
    need=0; \
    for c in bash git rsync sshpass python3 yq; do command -v "$c" >/dev/null 2>&1 || need=1; done; \
    python3 -c "import yaml" 2>/dev/null || need=1; \
    if [ "$need" = 1 ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        bash ca-certificates curl git openssh-client \
        python3 python3-yaml rsync sshpass; \
      arch="$TARGETARCH"; \
      case "$arch" in amd64|x86_64) yq_arch=amd64 ;; arm64|aarch64) yq_arch=arm64 ;; *) yq_arch=amd64 ;; esac; \
      curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}"; \
      chmod +x /usr/local/bin/yq; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    yq --version; \
    python3 -c "import yaml"; \
    git --version; \
    rsync --version | head -n1

WORKDIR /app

COPY sync.sh LICENSE NOTICE VERSION ./
COPY data/configs/demo.yml data/configs/demo-dir.yml ./config.seed/
COPY script/docker-entrypoint.sh script/start-ui.sh script/migrate-secrets.sh ./script/
COPY script/sync-ui/ ./script/sync-ui/
COPY replace/.gitignore ./replace/.gitignore
COPY logs/.gitignore ./logs/.gitignore

RUN chmod +x sync.sh script/*.sh \
    && find script/sync-ui -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true \
    && find script/sync-ui -name '*.pyc' -delete 2>/dev/null || true \
    && mkdir -p \
         logs .secrets .credentials replace .uploads config.seed \
         data/configs data/repos data/uploads data/ssh \
         /data/configs /data/secrets /data/credentials \
         /data/replace /data/logs /data/ssh /data/repos /data/uploads \
    && git config --global --add safe.directory '*' \
    && git config --global init.defaultBranch master || true

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${SYNC_UI_PORT}/" >/dev/null || exit 1

ENTRYPOINT ["/app/script/docker-entrypoint.sh"]
CMD ["ui"]
