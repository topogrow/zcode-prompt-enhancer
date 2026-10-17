#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

APP_NAME="ZCODE提示词润色"
DIST_DIR="$DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "=========================================================="
echo "📦 开始构建 macOS 独立客户端应用: ${APP_NAME}.app"
echo "=========================================================="

echo "🧹 [1/5] 清理构建产物目录..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES/server"

echo "⚡ [2/5] 编译原生 Swift 应用程序 (优化级别 -O)..."
swiftc -O -target arm64-apple-macos15.0 \
  -framework Cocoa -framework WebKit -framework CoreGraphics \
  "$DIR/src/native/main.swift" \
  -o "$MACOS/$APP_NAME"

# 同时更新开发用单二进制
cp "$MACOS/$APP_NAME" "$DIST_DIR/PromptEnhancer"

echo "📁 [3/5] 注入完整 Node 后端逻辑、高清图标与现代 UI 资源..."
cp -R "$DIR/src/core" "$RESOURCES/server/"
cp -R "$DIR/src/bridge" "$RESOURCES/server/"
cp -R "$DIR/src/ui" "$RESOURCES/server/"
cp "$DIR/src/server.js" "$RESOURCES/server/"

# 注入 macOS 原生高清 App 图标
if [ -f "$DIR/assets/AppIcon.icns" ]; then
  cp "$DIR/assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

echo "📝 [4/5] 生成标准 Apple App 规范 Info.plist 与元数据..."
cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ZCODE提示词润色</string>
    <key>CFBundleDisplayName</key>
    <string>ZCODE提示词润色</string>
    <key>CFBundleIdentifier</key>
    <string>com.lifengju.zcode-prompt-enhancer</string>
    <key>CFBundleVersion</key>
    <string>1.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleExecutable</key>
    <string>ZCODE提示词润色</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>用于模拟快捷按键执行文本原位替换与选择工程目录</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$CONTENTS/PkgInfo"

echo "🔏 [5/5] 执行 macOS 本地安全代码签名 (Ad-hoc Sign)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "=========================================================="
echo "🎉 打包完成！生成标准 macOS 独立应用程序："
echo "👉 应用路径: $APP_BUNDLE"
echo "👉 可直接在 Finder 中双击运行，或拖入 /Applications 安装"
echo "=========================================================="
