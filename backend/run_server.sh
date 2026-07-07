#!/usr/bin/env bash
# 赛博小镇后端启动脚本 - 从 .env 注入环境变量后启动 uvicorn
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "[ERROR] .env 不存在，请先配置 .env" >&2
  exit 1
fi

# 从 .env 注入环境变量(项目代码不会自动 load_dotenv)
set -a
# shellcheck disable=SC1091
source .env
set +a

export PYTHONIOENCODING=utf-8

exec ./venv/Scripts/python.exe -m uvicorn main:app \
  --host "${API_HOST:-0.0.0.0}" --port "${API_PORT:-8000}"
