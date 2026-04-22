#!/usr/bin/env bash
# build.sh — Adafruit nRF52 Bootloader 编译/烧录脚本
# 用法:
#   build.sh                  — 等同 build.sh all, 编译全部产物
#   build.sh all              — 编译全部产物
#   build.sh flash            — 编译并通过 JLink 烧录
#   build.sh flash-sd         — 仅烧录 SoftDevice
#   build.sh clean            — 清除构建产物
#   build.sh DEBUG=1          — debug 模式编译 (RTT 日志, 较大 bootloader)
#   build.sh DEBUG=1 flash    — debug 模式编译并烧录
#   build.sh DEBUG=1 all      — debug 模式编译全部产物

# ── 定位工程根目录 (脚本位于 .github/tools/shell/) ───────────────────────
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ── 板级配置 (修改此处切换目标板, 或 export BOARD=xxx 覆盖) ──────────────
BOARD="${BOARD:-meshtastic_v1}"

# ── ARM GCC 工具链 (或 export CROSS_COMPILE=xxx 覆盖) ───────────────────
CROSS_COMPILE="${CROSS_COMPILE:-$HOME/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/10.3.1-2.3.1/.content/bin/arm-none-eabi-}"

# ── 加载 NCS Python 环境 (或 export NCS_ENV_PATH=xxx 覆盖) ─────────────
NCS_ENV="${NCS_ENV_PATH:-/him/ncs_pro/.github/tmp/ncs_env.sh}"
source "$NCS_ENV"

set -euo pipefail

# ── 解析传参: 无参数默认 all, 否则全部透传给 make ────────────────────────
# 规则: 不含 '=' 的参数视为 make target, 含 '=' 的视为 make 变量赋值
# 示例:
#   build.sh              → make ... all
#   build.sh flash        → make ... flash
#   build.sh DEBUG=1      → make ... DEBUG=1 all  (自动补 all)
#   build.sh DEBUG=1 flash→ make ... DEBUG=1 flash
if [[ $# -eq 0 ]]; then
    MAKE_ARGS=(all)
else
    MAKE_ARGS=("$@")
    # 检查参数中是否有 target (不含 '=' 的参数)
    # 若全部都是变量赋值 (如只传 DEBUG=1) , 则追加默认 target: all
    has_target=0
    for arg in "$@"; do
        [[ "$arg" != *=* ]] && { has_target=1; break; }
    done
    [[ $has_target -eq 0 ]] && MAKE_ARGS+=("all")
fi

# ── 日志文件命名: 提取第一个 target (非变量赋值的参数) 用于日志命名 ────
LOG_TARGET="all"
for arg in "${MAKE_ARGS[@]}"; do
    [[ "$arg" != *=* ]] && { LOG_TARGET="$arg"; break; }
done

LOG_DIR="$ROOT_DIR/.github/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${LOG_TARGET}-$(date +%Y%m%d-%H%M%S).log"

echo ">>> ROOT  : $ROOT_DIR"
echo ">>> BOARD : $BOARD"
echo ">>> GCC   : $CROSS_COMPILE"
echo ">>> ARGS  : ${MAKE_ARGS[*]}"
echo ">>> LOG   : $LOG_FILE"
echo ""

# ── 切换到工程根目录并执行────────────────────────────────────────────────
cd "$ROOT_DIR"
make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" "${MAKE_ARGS[@]}" 2>&1 | tee "$LOG_FILE"

echo ""
echo "===================================================================="
echo ""

compiledb make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 | tee "$LOG_FILE.log"
