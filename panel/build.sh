#!/bin/bash
# 编译原生悬浮面板，安装到 ~/Applications
# 支持 arm64 + x86_64 通用二进制
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 先编到项目内的 dist/，再 mv 到目标位置（沙箱里 ~/Applications 可能受限）
STAGE="$ROOT/dist/Xmind 样式槽.app"
APP="$HOME/Applications/Xmind 样式槽.app"

mkdir -p "$(dirname "$STAGE")"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

SRC="$ROOT/panel/main.swift"
OUT="$STAGE/Contents/MacOS/XmindStylePanel"

ARCH="$(uname -m)"
SWIFT_VERSION="$(swiftc -version 2>&1 | grep -oE 'Swift version [0-9.]+' | awk '{print $3}')"
echo "  swiftc $SWIFT_VERSION on $ARCH"

# swiftc 不能直接 -arch arm64 -arch x86_64，要分架构编然后 lipo 合并
# 部署目标必须是 13.0：Command Line Tools 里的 Swift 兼容库只有 arm64 切片，
# 用 12.0 交叉编 x86_64 会因 libswiftCompatibility56 缺 x86_64 而链接失败
DEPLOY_TARGET="13.0"
build_arch() {
  local target_arch="$1"
  local target="${target_arch}-apple-macosx${DEPLOY_TARGET}"
  local tmp="$(mktemp)"
  if swiftc -O -swift-version 5 \
      -target "$target" \
      -framework Cocoa -framework WebKit \
      -o "$tmp" "$SRC" 2>/dev/null; then
    echo "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

TMP_ARM64=""; TMP_X86_64=""
if [ "$ARCH" = "arm64" ]; then
  TMP_ARM64="$(build_arch arm64 || true)"
  TMP_X86_64="$(build_arch x86_64 || true)"
else
  TMP_X86_64="$(build_arch x86_64 || true)"
  TMP_ARM64="$(build_arch arm64 || true)"
fi

if [ -n "$TMP_ARM64" ] && [ -n "$TMP_X86_64" ]; then
  lipo -create "$TMP_ARM64" "$TMP_X86_64" -output "$OUT"
  echo "  ✓ 通用二进制 (arm64 + x86_64)"
  rm -f "$TMP_ARM64" "$TMP_X86_64"
elif [ -n "$TMP_ARM64" ]; then
  mv "$TMP_ARM64" "$OUT"
  echo "  ✓ arm64 native"
elif [ -n "$TMP_X86_64" ]; then
  mv "$TMP_X86_64" "$OUT"
  echo "  ✓ x86_64 native"
else
  echo "  ✗ 编译失败"
  exit 1
fi

cp "$ROOT/panel/index.html" "$STAGE/Contents/Resources/index.html"
cp "$ROOT/panel/Info.plist" "$STAGE/Contents/Info.plist"

codesign --force --sign - "$STAGE" >/dev/null 2>&1 || true

# 尝试搬到 ~/Applications（沙箱可能拦；失败就让用户手动搬）
if rm -rf "$APP" 2>/dev/null && mv "$STAGE" "$APP" 2>/dev/null; then
  echo "已安装：$APP"
else
  echo "已编译：$STAGE"
  echo "请手动搬：mv -f \"$STAGE\" \"$APP\""
fi
