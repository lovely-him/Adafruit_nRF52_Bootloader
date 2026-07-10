#!/usr/bin/env bash
# build.sh — Adafruit nRF52 Bootloader 编译/烧录脚本
# 用法:
#   build.sh all                    — 编译全部产物
#   build.sh flash                  — 编译并通过 JLink 烧录
#   build.sh flash-sd               — 仅烧录 SoftDevice
#   build.sh clean                  — 清除构建产物
#   build.sh all DEBUG=1 flash      — debug 模式编译并烧录
#
# 脚本原生命令 (@-prefix, 不调用 make):
#   build.sh @recover               — 解锁芯片 APPROTECT (nrfjprog --recover)
#   build.sh @flash <hex>           — 烧录指定 hex (sectorerase, 不重新编译)

# ── 定位工程根目录 (脚本位于 .github/tools/shell/) ───────────────────────
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ── 板级配置 (修改此处切换目标板, 或 export BOARD=xxx 覆盖) ──────────────
BOARD="${BOARD:-meshtastic_v1}"

# ── ARM GCC 工具链 (或 export CROSS_COMPILE=xxx 覆盖) ───────────────────
CROSS_COMPILE="${CROSS_COMPILE:-$HOME/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/arm-none-eabi-}"

# ── 加载 NCS Python 环境 (或 export NCS_ENV_PATH=xxx 覆盖) ─────────────
NCS_ENV="${NCS_ENV_PATH:-$ROOT_DIR/.github/tmp/ncs_env.sh}"
source "$NCS_ENV"

set -euo pipefail

# ── 脚本原生命令 (@-prefix, 不调用 make) ─────────────────────────────────
case "${1:-}" in
  @recover)
    echo ">>> Recovering device (ERASEALL via CTRL-AP)..."
    nrfjprog --recover
    exit 0
    ;;
  @flash)
    HEX="${2:-}"
    if [[ -z "$HEX" ]]; then
        echo "错误: 用法: build.sh @flash <hex文件路径>" >&2
        exit 1
    fi
    if [[ ! -f "$HEX" ]]; then
        echo "错误: 文件不存在: $HEX" >&2
        exit 1
    fi
    echo ">>> Flashing: $HEX"
    nrfjprog --program "$HEX" --sectorerase --verify --reset
    exit 0
    ;;
esac

# ── 参数直接透传给 make ───────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    echo "错误: 请指定 make target，例如: build.sh all" >&2
    exit 1
fi
MAKE_ARGS=("$@")

# ── 日志文件命名: 取第一个非赋值参数 ────────────────────────────────────
LOG_TARGET="${1}"

LOG_DIR="$ROOT_DIR/.github/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${LOG_TARGET}-$(date +%Y%m%d-%H%M%S).log"

echo ">>> ROOT  : $ROOT_DIR"
echo ">>> BOARD : $BOARD"
echo ">>> GCC   : $CROSS_COMPILE"
echo ">>> NCS   : $NCS_ENV"
echo ">>> ARGS  : ${MAKE_ARGS[*]}"
echo ">>> LOG   : $LOG_FILE"

# ── 切换到工程根目录并执行────────────────────────────────────────────────
cd "$ROOT_DIR"
if [[ "$LOG_TARGET" != "compiledb" ]]; then
    echo ">>> Running: make BOARD=\"$BOARD\" CROSS_COMPILE=\"$CROSS_COMPILE\" ${MAKE_ARGS[*]}"
    make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" "${MAKE_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
else
    # ── 自动安装 compiledb ────────────────────────────────────────────
    if ! command -v compiledb &>/dev/null; then
        echo ">>> compiledb 未找到，正在安装..."
        pip install compiledb
    fi

    VSCODE_DIR="$ROOT_DIR/.vscode"
    mkdir -p "$VSCODE_DIR"
    COMPILE_COMMANDS="$VSCODE_DIR/compile_commands.json"
    C_CPP_PROPS="$VSCODE_DIR/c_cpp_properties.json"

    echo ">>> Running: compiledb -o $COMPILE_COMMANDS make BOARD=\"$BOARD\" CROSS_COMPILE=\"$CROSS_COMPILE\""
    compiledb -o "$COMPILE_COMMANDS" make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 | tee "$LOG_FILE"

    # ── 生成/覆盖 c_cpp_properties.json ─────────────────────────────
    cat > "$C_CPP_PROPS" <<EOF
{
  "version": 4,
  "configurations": [
    {
      "name": "nRF52 (${BOARD})",
      "compileCommands": "\${workspaceFolder}/.vscode/compile_commands.json",
      "intelliSenseMode": "gcc-arm"
    }
  ]
}
EOF
    echo ">>> Generated: $C_CPP_PROPS"
fi
