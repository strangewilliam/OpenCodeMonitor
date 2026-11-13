#!/bin/bash
# OpenCodeMonitor 构建脚本：编译 + 组装 .app + 安装到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OpenCodeMonitor"
BUNDLE_ID="com.strangewilliam.opencodemonitor"
BUILD_DIR="build"
APP="$HOME/Applications/${APP_NAME}.app"

echo "==> 编译（需要 Xcode Command Line Tools: xcode-select --install）"
mkdir -p "$BUILD_DIR"
swiftc -O -swift-version 5 -o "$BUILD_DIR/$APP_NAME" main.swift

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenCodeMonitor</string>
    <key>CFBundleIdentifier</key><string>com.strangewilliam.opencodemonitor</string>
    <key>CFBundleName</key><string>OpenCode Monitor</string>
    <key>CFBundleDisplayName</key><string>OpenCode Monitor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
EOF

echo "==> 完成：$APP"
echo "==> 启动：open \"$APP\""
echo ""
echo "首次使用请在菜单里打开「连接设置…」填入 OpenCode Console 的 API Key。"
