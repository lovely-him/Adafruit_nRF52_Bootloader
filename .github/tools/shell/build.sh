#!/usr/bin/env bash
# build.sh — Adafruit nRF52 Bootloader 编译/烧录脚本
# 用法:
#   build.sh all                    — 编译全部产物
#   build.sh flash                  — 编译并通过 JLink 烧录
#   build.sh flash-sd               — 仅烧录 SoftDevice
#   build.sh clean                  — 清除构建产物
#   build.sh compiledb              — 生成 .vscode/compile_commands.json
#   build.sh all DEBUG=1            — debug 模式编译
#   build.sh @recover               — 解锁芯片 APPROTECT (nrfjprog --recover)
#   build.sh @flash <hex>           — 烧录指定 hex (sectorerase, 不重新编译)
#
# 配置: 板名/工具链/NCS python 全部来自同目录 .env (模板见 .env.example)。
#       命令行或环境变量优先, 例如 BOARD=feather_nrf52840_express build.sh all
set -euo pipefail

# ── 路径与常量 ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_DIR="$ROOT_DIR/.github/logs"

# ── 函数 ─────────────────────────────────────────────────────────────────
die() {
    echo "错误: $*" >&2
    exit 1
}

load_env() {
    [[ -f "$ENV_FILE" ]] || die "缺少配置 $ENV_FILE, 请参考 $SCRIPT_DIR/.env.example 创建"
    . "$ENV_FILE"
    [[ -n "${BOARD:-}" ]] || die ".env 未设置 BOARD"
    [[ -n "${CROSS_COMPILE:-}" ]] || die ".env 未设置 CROSS_COMPILE"
}

new_log() {
    mkdir -p "$LOG_DIR"
    echo "$LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
}

do_recover() {
    echo ">>> Recovering device (ERASEALL via CTRL-AP)..."
    nrfjprog --recover
}

do_flash() {
    local hex="${2:-}"
    [[ -n "$hex" ]] || die "用法: build.sh @flash <hex文件路径>"
    [[ -f "$hex" ]] || die "文件不存在: $hex"
    echo ">>> Flashing: $hex"
    nrfjprog --program "$hex" --sectorerase --verify --reset
}

do_compiledb() {
    command -v compiledb >/dev/null || die "未找到 compiledb, 请先安装: pip install compiledb"
    local vscode_dir="$ROOT_DIR/.vscode"
    local log_file
    log_file="$(new_log compiledb)"
    mkdir -p "$vscode_dir"
    echo ">>> BOARD : $BOARD"
    echo ">>> GCC   : $CROSS_COMPILE"
    echo ">>> LOG   : $log_file"
    cd "$ROOT_DIR"
    compiledb -o "$vscode_dir/compile_commands.json" \
        make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 | tee "$log_file"
    cat > "$vscode_dir/c_cpp_properties.json" <<EOF
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
    echo ">>> Generated: $vscode_dir/c_cpp_properties.json"
}

do_make() {
    local target="make"
    for arg in "$@"; do
        [[ "$arg" == *=* ]] || { target="$arg"; break; }
    done
    local log_file
    log_file="$(new_log "$target")"
    echo ">>> ROOT  : $ROOT_DIR"
    echo ">>> BOARD : $BOARD"
    echo ">>> GCC   : $CROSS_COMPILE"
    echo ">>> ARGS  : $*"
    echo ">>> LOG   : $log_file"
    cd "$ROOT_DIR"
    make BOARD="$BOARD" CROSS_COMPILE="$CROSS_COMPILE" "$@" 2>&1 | tee "$log_file"
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        "")
            die "请指定 make target, 例如: build.sh all"
            ;;
        @recover)
            do_recover
            return 0
            ;;
        @flash)
            do_flash "$@"
            return 0
            ;;
        @*)
            die "未知命令: $1"
            ;;
    esac

    load_env

    if [[ "$1" == compiledb ]]; then
        do_compiledb
    else
        do_make "$@"
    fi
}

main "$@"
