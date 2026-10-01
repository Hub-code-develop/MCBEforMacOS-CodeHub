#!/usr/bin/env bash
#
# 汇总三个来源的产物为统一的运行时树,并对整棵树做自检。
#
# 输入(默认均位于 <repo>/artifacts/runtime 之下):
#   wine/    由 scripts/build-wine.sh 产出
#   xodus/   由 scripts/build-xodus-service.sh 产出
#   render/  由 scripts/fetch-render-stack.sh 产出
#
# 产物:<repo>/artifacts/runtime/
#   wine/{bin,lib,share}            Wine(WineGDK) 安装树
#   xodus/xodus-service             原生 macOS Xbox 服务
#   render/{lib,vulkan,dxvk,vkd3d-proton}
#   RUNTIME-MANIFEST.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${RUNTIME:-$REPO_ROOT/artifacts/runtime}"

log() { printf '\n==> %s\n' "$*"; }
fail() { echo "错误:$*" >&2; exit 1; }

log "自检运行时树:$RUNTIME"
[ -x "$RUNTIME/wine/bin/wine" ]                                   || fail "缺少 wine/bin/wine"
[ -f "$RUNTIME/wine/lib/wine/x86_64-windows/xgameruntime.dll" ]    || fail "缺少 xgameruntime.dll(PE)"
[ -f "$RUNTIME/wine/lib/wine/x86_64-unix/xgameruntime.so" ]        || fail "缺少 xgameruntime.so(unix)"
[ -x "$RUNTIME/xodus/xodus-service" ]                              || fail "缺少 xodus-service"
[ -f "$RUNTIME/render/lib/libMoltenVK.dylib" ]                     || fail "缺少 libMoltenVK.dylib"
[ -f "$RUNTIME/render/vulkan/icd.d/MoltenVK_icd.json" ]            || fail "缺少 MoltenVK ICD 清单"
[ -f "$RUNTIME/render/dxvk/d3d11.dll" ]                            || fail "缺少 DXVK d3d11.dll"
[ -f "$RUNTIME/render/vkd3d-proton/d3d12.dll" ]                    || fail "缺少 vkd3d-proton d3d12.dll"

log "关键检查:wine 内是否自带 GDK 组件"
ls -1 "$RUNTIME/wine/lib/wine/x86_64-windows" | grep -i -E 'xgameruntime|xgameruntime' || true
ls -1 "$RUNTIME/wine/lib/wine/x86_64-unix" | grep -i xgameruntime || true

log "检查 Wine 版本"
"$RUNTIME/wine/bin/wine" --version 2>/dev/null || echo "提示:无法在本机直接运行 wine(不影响打包)"

log "写入清单"
{
  echo "generated-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "wine-ref: ${WINE_GDK_REF:-unknown}"
  echo "xodus-ref: ${XODUS_REF:-unknown}"
  echo "moltenvk: ${MOLTENVK_VERSION:-unknown}"
  echo "dxvk: ${DXVK_VERSION:-unknown}"
  echo "vkd3d-proton: ${VKD3D_PROTON_VERSION:-unknown}"
  echo
  echo "wine:"
  find "$RUNTIME/wine" -type f | wc -l | tr -d ' '
  echo "render:"
  find "$RUNTIME/render" -type f | wc -l | tr -d ' '
} > "$RUNTIME/RUNTIME-MANIFEST.txt"

cat "$RUNTIME/RUNTIME-MANIFEST.txt"
log "总计:$(du -sh "$RUNTIME" | cut -f1)"