#!/bin/bash
set -e
cd "$(dirname "$0")"

# ── Build binary ───────────────────────────────────
echo "🔨 Building..."
swift build -c release 2>&1

# ── Bundle ─────────────────────────────────────────
echo "📦 Creating app bundle..."
rm -rf dist/BusyLight.app
mkdir -p dist/BusyLight.app/Contents/MacOS
mkdir -p dist/BusyLight.app/Contents/Resources
cp .build/release/BusyLight dist/BusyLight.app/Contents/MacOS/
cp Info.plist dist/BusyLight.app/Contents/

# ── Icon (after bundle dir exists) ─────────────────
echo "🎨 Generating icon..."
swift Scripts/generate_icon.swift 2>&1

echo ""
echo "✅  dist/BusyLight.app ready"
echo "    Launch: open dist/BusyLight.app"

# ── Auto-launch ────────────────────────────────────
if [ "$1" = "--run" ]; then
    echo "🚀 Launching..."
    pkill -f "BusyLight.app" 2>/dev/null || true
    sleep 1
    open dist/BusyLight.app
    echo "    Check menu bar for 🟢"
fi
