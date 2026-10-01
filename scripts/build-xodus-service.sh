#!/usr/bin/env bash
#
# 构建 xodus-gaming/xodus 的原生 macOS 服务端。
#
# xodus-service 监听 $XDG_RUNTIME_DIR/xodus.sock(macOS 上为 /tmp/xodus.sock),
# 与 Wine 内 xgameruntime.dll 的 unix 模块通过 Xodus IPC 协议通信:
#   帧 = magic(u32 LE) + msg_type(u16) + len(u16) + body
#   XML_MAGIC = 0x58445358,PROTO_MAGIC = 0x58445350
#
# 环境变量:
#   WORKDIR    工作目录(默认 <repo>/.work)
#   XODUS_REPO 源码地址
#   XODUS_REF  提交/分支(默认 main)
#   OUT        产物目录(默认 <repo>/artifacts/runtime/xodus)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-$REPO_ROOT/.work}"
XODUS_REPO="${XODUS_REPO:-https://github.com/xodus-gaming/xodus.git}"
XODUS_REF="${XODUS_REF:-main}"
OUT="${OUT:-$REPO_ROOT/artifacts/runtime/xodus}"
SRC="$WORKDIR/xodus"

log() { printf '\n==> %s\n' "$*"; }

command -v cargo >/dev/null 2>&1 || { echo "未找到 cargo,请先安装 Rust 工具链" >&2; exit 1; }
cargo --version

log "获取源码 xodus@$XODUS_REF"
mkdir -p "$WORKDIR"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$XODUS_REPO"
fi
git -C "$SRC" remote set-url origin "$XODUS_REPO"
git -C "$SRC" fetch --depth 1 -q origin "$XODUS_REF"
git -C "$SRC" checkout -q -f FETCH_HEAD
echo "HEAD: $(git -C "$SRC" rev-parse HEAD)"

log "cargo build --release -p xodus-service"
cd "$SRC"
cargo build --release -p xodus-service

BIN="$SRC/target/release/xodus-service"
test -x "$BIN" || { echo "未生成 xodus-service 可执行文件" >&2; exit 1; }

log "组装到 $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BIN" "$OUT/xodus-service"
cp "$SRC/LICENSE" "$OUT/LICENSE-xodus" 2>/dev/null || true
strip "$OUT/xodus-service" 2>/dev/null || true
file "$OUT/xodus-service"

log "完成,$(du -sh "$OUT" | cut -f1)"