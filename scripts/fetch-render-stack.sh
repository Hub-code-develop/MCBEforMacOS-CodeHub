#!/usr/bin/env bash
#
# 收集可再分发的图形渲染栈:
#   MoltenVK    —— macOS 上的 Vulkan 实现(unix 侧 winevulkan 依赖它)
#   DXVK        —— d3d9/d3d10/d3d11/dxgi -> Vulkan 转换层
#   vkd3d-proton—— d3d12 -> Vulkan 转换层
#
# 说明:Apple Game Porting Toolkit 的 D3DMetal 不可再分发,不在此列,由用户自行安装。
#
# 环境变量:
#   WORKDIR             工作目录(默认 <repo>/.work)
#   MOLTENVK_VERSION / DXVK_VERSION / VKD3D_PROTON_VERSION
#   OUT                 产物目录(默认 <repo>/artifacts/runtime/render)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-$REPO_ROOT/.work}"
OUT="${OUT:-$REPO_ROOT/artifacts/runtime/render}"
MOLTENVK_VERSION="${MOLTENVK_VERSION:-1.4.2}"
DXVK_VERSION="${DXVK_VERSION:-3.1.1}"
VKD3D_PROTON_VERSION="${VKD3D_PROTON_VERSION:-3.0.1}"
DL="$WORKDIR/render-download"

log() { printf '\n==> %s\n' "$*"; }
fetch() { # fetch <url> <输出文件名>
  mkdir -p "$DL"
  if [ ! -s "$DL/$2" ]; then
    curl -fL --retry 3 --retry-delay 5 -o "$DL/$2" "$1"
  fi
}

rm -rf "$OUT"
mkdir -p "$OUT/lib" "$OUT/vulkan/icd.d" "$OUT/dxvk" "$OUT/vkd3d-proton" "$OUT/licenses"

log "MoltenVK $MOLTENVK_VERSION"
fetch "https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-macos.tar" MoltenVK-macos.tar
rm -rf "$DL/moltenvk"; mkdir -p "$DL/moltenvk"
tar -xf "$DL/MoltenVK-macos.tar" -C "$DL/moltenvk"
MOLTENVK_DYLIB="$(find "$DL/moltenvk" -name 'libMoltenVK.dylib' | head -1)"
test -n "$MOLTENVK_DYLIB" || { echo "MoltenVK 包中未找到 libMoltenVK.dylib" >&2; exit 1; }
cp "$MOLTENVK_DYLIB" "$OUT/lib/libMoltenVK.dylib"
MOLTENVK_LICENSE="$(find "$DL/moltenvk" -iname 'LICENSE*' | head -1)"
[ -n "$MOLTENVK_LICENSE" ] && cp "$MOLTENVK_LICENSE" "$OUT/licenses/MoltenVK-LICENSE" || true

# ICD 清单用 @loader_path 表达相对位置,整棵树搬走后仍然有效。
cat > "$OUT/vulkan/icd.d/MoltenVK_icd.json" <<'JSON'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "../../lib/libMoltenVK.dylib",
    "api_version": "1.2.0",
    "is_portability_driver": true
  }
}
JSON

log "DXVK $DXVK_VERSION"
fetch "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz" "dxvk-${DXVK_VERSION}.tar.gz"
rm -rf "$DL/dxvk"; mkdir -p "$DL/dxvk"
tar -xf "$DL/dxvk-${DXVK_VERSION}.tar.gz" -C "$DL/dxvk"
DXVK_X64="$(find "$DL/dxvk" -type d -name x64 | head -1)"
test -n "$DXVK_X64" || { echo "DXVK 包中未找到 x64 目录" >&2; exit 1; }
cp "$DXVK_X64"/*.dll "$OUT/dxvk/"
cp "$DL/dxvk"/*/LICENSE "$OUT/licenses/DXVK-LICENSE" 2>/dev/null || true

log "vkd3d-proton $VKD3D_PROTON_VERSION"
fetch "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_PROTON_VERSION}/vkd3d-proton-${VKD3D_PROTON_VERSION}.tar.zst" "vkd3d-proton-${VKD3D_PROTON_VERSION}.tar.zst"
rm -rf "$DL/vkd3d"; mkdir -p "$DL/vkd3d"
tar --zstd -xf "$DL/vkd3d-proton-${VKD3D_PROTON_VERSION}.tar.zst" -C "$DL/vkd3d"
VKD3D_X64="$(find "$DL/vkd3d" -type d -name x64 | head -1)"
test -n "$VKD3D_X64" || { echo "vkd3d-proton 包中未找到 x64 目录" >&2; exit 1; }
cp "$VKD3D_X64"/*.dll "$OUT/vkd3d-proton/"
cp "$DL/vkd3d"/*/LICENSE "$OUT/licenses/vkd3d-proton-LICENSE" 2>/dev/null || true

log "完成"
find "$OUT" -type f | sed "s|$OUT/||" | sort
du -sh "$OUT" | cut -f1