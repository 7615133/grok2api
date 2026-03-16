# 第一阶段：builder
FROM python:3.13-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai \
    UV_PROJECT_ENVIRONMENT=/opt/venv

ENV PATH="$UV_PROJECT_ENVIRONMENT/bin:$PATH"

# slim 版用 apt 安装依赖（对应原 apk 的包）
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    ca-certificates \
    build-essential \
    libffi-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    cargo \
    rustc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 安装 uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-dev --no-install-project \
    && find /opt/venv -type d -name "__pycache__" -prune -exec rm -rf {} + \
    && find /opt/venv -type f -name "*.pyc" -delete \
    && find /opt/venv -type d -name "tests" -prune -exec rm -rf {} + \
    && find /opt/venv -type d -name "test" -prune -exec rm -rf {} + \
    && find /opt/venv -type d -name "testing" -prune -exec rm -rf {} + \
    && find /opt/venv -type f -name "*.so" -exec strip --strip-unneeded {} + || true \
    && rm -rf /root/.cache /tmp/uv-cache

# 第二阶段：运行时镜像
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai \
    VIRTUAL_ENV=/opt/venv \
    SERVER_HOST=0.0.0.0 \
    SERVER_PORT=8000 \
    SERVER_WORKERS=1

ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# 运行时依赖（对应原 apk）
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    ca-certificates \
    libffi8 \
    libssl3 \
    libgcc-s1 \
    libstdc++6 \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

COPY config.defaults.toml ./
COPY app ./app
COPY _public ./_public
COPY main.py ./
COPY scripts ./scripts

RUN mkdir -p /app/data /app/logs \
    && chmod +x /app/scripts/entrypoint.sh

EXPOSE 8000

# 保持原 ENTRYPOINT 和 CMD，但 slim 版有标准 sh，所以兼容 Claw
ENTRYPOINT ["/app/scripts/entrypoint.sh"]

# CMD 用 exec 形式，避免 sh wrapper 问题
CMD ["granian", "--interface", "asgi", "--host", "${SERVER_HOST:-0.0.0.0}", "--port", "${SERVER_PORT:-8000}", "--workers", "${SERVER_WORKERS:-1}", "main:app"]
