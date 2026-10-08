#!/bin/bash
# ============================================
# PS HOPPER v4.0 — INSTALLER
# Jalankan: curl -sL https://raw.githubusercontent.com/agfatabah22-sketch/PSHopper/main/install.sh | bash
# ============================================

REPO="https://raw.githubusercontent.com/agfatabah22-sketch/PSHopper/main"
DIR="/sdcard/PSHopper"

echo ""
echo "=========================================="
echo "  PS HOPPER v4.0 — INSTALLER"
echo "=========================================="
echo ""

# 1. Install dependency
echo "[1/4] Install dependency..."
pkg update -y -q 2>/dev/null
pkg install -y lua53 curl jq 2>/dev/null
echo "  ✓ lua53, curl, jq"

# 2. Buat folder
echo "[2/4] Buat folder..."
mkdir -p "$DIR"
echo "  ✓ $DIR"

# 3. Download script
echo "[3/4] Download hopper.lua..."
curl -sL "$REPO/hopper.lua" -o "$DIR/hopper.lua"
if [ $? -eq 0 ] && [ -s "$DIR/hopper.lua" ]; then
    echo "  ✓ hopper.lua downloaded"
else
    echo "  ✗ GAGAL download! Cek koneksi internet"
    exit 1
fi

# 4. Selesai
echo "[4/4] Selesai!"
echo ""
echo "=========================================="
echo "  INSTALL BERHASIL!"
echo ""
echo "  File: $DIR/hopper.lua"
echo ""
echo "  CARA RUN:"
echo "    termux-wake-lock"
echo "    lua $DIR/hopper.lua"
echo ""
echo "  JANGAN LUPA ISI:"
echo "    $DIR/private_servers.txt  (link PS)"
echo "    $DIR/roblox_cookie.txt   (cookie)"
echo "=========================================="
echo ""

# Auto run
read -p "  Langsung run sekarang? (y/n) > " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    termux-wake-lock 2>/dev/null
    lua "$DIR/hopper.lua"
fi
