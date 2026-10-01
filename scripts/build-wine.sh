#!/usr/bin/env bash
#
# 在 macOS(x86_64)上构建 WineGDK 分支的 Wine,产出可重定位的 wine 运行时树。
#
# 产物:$OUT/{bin,lib,share} —— 即一份完整的 wine 安装树(bin/wine 与 lib/wine 必须保持同级)。
# 配方对齐上游 tools/gitlab/build-mac,但改为完整 install(上游只 install-lib 供测试用)。
#
# 环境变量:
#   WORKDIR       工作目录(默认 <repo>/.work)
#   WINE_GDK_REF  WineGDK 提交(默认钉住的 master SHA)
#   OUT           产物目录(默认 <repo>/artifacts/runtime/wine)
#   SKIP_DEPS     设为 1 跳过 brew install

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-$REPO_ROOT/.work}"
WINE_GDK_REPO="${WINE_GDK_REPO:-https://github.com/Weather-OS/WineGDK.git}"
WINE_GDK_REF="${WINE_GDK_REF:-b03ba49c4f326c36aa6930fbe6cf72841ef3738c}"
OUT="${OUT:-$REPO_ROOT/artifacts/runtime/wine}"
SRC="$WORKDIR/WineGDK"
STAGE="$WORKDIR/wine-stage"
BUILD="$SRC/build64"

log() { printf '\n==> %s\n' "$*"; }

BREW="$(brew --prefix)"
log "Homebrew 根目录:$BREW"

if [ "${SKIP_DEPS:-0}" != "1" ]; then
  log "安装构建依赖"
  brew install --quiet mingw-w64 autoconf automake libtool bison pkg-config \
    freetype fontconfig gnutls gettext zstd
fi

MINGW="$BREW/opt/mingw-w64"
BISON_BIN="$BREW/opt/bison/bin/bison"

log "检查 mingw-w64 交叉编译器"
"$MINGW/bin/x86_64-w64-mingw32-gcc" --version | head -1
"$MINGW/bin/x86_64-w64-mingw32-g++" --version | head -1

export PATH="$MINGW/bin:$BREW/opt/bison/bin:$BREW/bin:$PATH"
export PKG_CONFIG_PATH="$BREW/opt/freetype/lib/pkgconfig:$BREW/opt/fontconfig/lib/pkgconfig:$BREW/opt/gnutls/lib/pkgconfig:$BREW/lib/pkgconfig:$BREW/share/pkgconfig"

log "获取源码 WineGDK@$WINE_GDK_REF"
mkdir -p "$WORKDIR"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$WINE_GDK_REPO"
fi
git -C "$SRC" remote set-url origin "$WINE_GDK_REPO"
# 先按 SHA 浅取;仓库以 master 头部为钉点时两种取法等价。
if ! git -C "$SRC" fetch --depth 1 -q origin "$WINE_GDK_REF" 2>/dev/null; then
  echo "按 SHA 取源码失败,回退到默认分支"
  git -C "$SRC" fetch --depth 1 -q origin master
fi
git -C "$SRC" checkout -q -f FETCH_HEAD
git -C "$SRC" fetch --depth 1 -q --tags origin || true
git config --global --add safe.directory "$SRC" || true
echo "HEAD: $(git -C "$SRC" rev-parse HEAD)"

# 上游 master 的 dlls/gameinput/padinput.c 没写进 dlls/gameinput/Makefile.in 的 SOURCES（WIP 文件，
# 引用了尚未定义的结构体 game_input_device / game_input_reading）。make_makefiles 会把目录下所有 .c
# 自动补进 SOURCES，于是它被编译并报 "invalid use of undefined type 'struct game_input_device'"。
# 该文件本不属于 gameinput.dll，构建前移除。
rm -f "$SRC/dlls/gameinput/padinput.c"

log "生成 configure / Makefile / spec"
cd "$SRC"
./tools/make_requests
./tools/make_specfiles
./tools/make_makefiles
autoreconf -f

log "configure(win64 + mingw 交叉编译)"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"
../configure -C --enable-win64 --with-mingw \
  --prefix=/usr/local \
  --disable-tests \
  --without-alsa --without-capi --without-cups --without-dbus --without-gphoto \
  --without-gssapi --without-gstreamer --without-hwloc --without-inotify \
  --without-krb5 --without-netapi --without-opencl --without-oss --without-pcap \
  --without-pcsclite --without-pulse --without-sane --without-sdl --without-udev \
  --without-usb --without-v4l2 --without-wayland \
  BISON="$BISON_BIN"

log "make -j$(sysctl -n hw.activecpu)"
make -s -j"$(sysctl -n hw.activecpu)"

log "make install -> $STAGE"
rm -rf "$STAGE"
make -s install DESTDIR="$STAGE"

log "校验关键产物"
test -f "$STAGE/usr/local/lib/wine/x86_64-windows/xgameruntime.dll"
test -f "$STAGE/usr/local/lib/wine/x86_64-unix/xgameruntime.so"

log "裁剪并组装到 $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$STAGE/usr/local/." "$OUT/"

# 去掉不需要的内容:开发头文件、静态库、man、桌面集成文件。
rm -rf "$OUT/include" "$OUT/share/man" "$OUT/share/applications" "$OUT/share/icons"
find "$OUT" -name '*.a' -delete
find "$OUT" -name '*.la' -delete
find "$OUT" -name '*.def' -delete

log "strip"
find "$OUT/lib/wine/x86_64-unix" -type f -name '*.so' -exec strip -x {} + 2>/dev/null || true
find "$OUT/lib/wine/x86_64-windows" -type f -name '*.dll' \
  -exec "$MINGW/bin/x86_64-w64-mingw32-strip" --strip-unneeded {} + 2>/dev/null || true
strip -x "$OUT/bin/wine" 2>/dev/null || true
find "$OUT/bin" -type f ! -name 'wine' -exec strip -x {} + 2>/dev/null || true

log "完成,$(du -sh "$OUT" | cut -f1)"
"$OUT/bin/wine" --version || echo "警告:当前环境无法直接执行 wine(--version 失败),产物已生成"