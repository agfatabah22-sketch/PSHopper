#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  INSTALLER MANAGER - Termux
#  Download location: /sdcard/Download
#  Cara pakai: bash installer.sh
# ============================================================

DIR="/sdcard/Download"
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$DIR" 2>/dev/null

# ---------- helper ----------

header() {
    clear
    echo -e "${CYAN}[${GREEN}INSTALLER MANAGER${CYAN}]${NC}"
    echo " Download location: $DIR"
    echo ""
}

# unduh file, tampilkan progres
unduh() {
    local url="$1"
    local nama
    # ambil nama file dari URL, kalau tidak ada pakai nama default
    nama=$(basename "${url%%\?*}")
    # ubah kode URL (%20 = spasi, dst) jadi nama file normal
    nama=$(printf '%b' "${nama//%/\\x}")
    case "$nama" in
        ""|*.php|*.html|/) nama="app_$(date +%s).apk" ;;
    esac
    echo -e "${YELLOW}Mengunduh: $nama${NC}"
    if curl -L --progress-bar -o "$DIR/$nama" "$url"; then
        # cek apakah benar-benar file (bukan halaman error)
        if file "$DIR/$nama" | grep -qiE "HTML|text"; then
            echo -e "${RED}Link tidak valid (bukan file APK).${NC}"
            rm -f "$DIR/$nama"
            return 1
        fi
        echo -e "${GREEN}Selesai: $DIR/$nama${NC}"
        return 0
    else
        echo -e "${RED}Gagal mengunduh.${NC}"
        return 1
    fi
}

# pasang APK (buka installer Android)
pasang() {
    local apk="$1"
    chmod 644 "$apk" 2>/dev/null
    echo -e "${YELLOW}Membuka installer untuk: $(basename "$apk")${NC}"
    if command -v termux-open >/dev/null 2>&1; then
        termux-open --chooser "$apk" && return 0
    fi
    am start -a android.intent.action.VIEW \
        -d "file://$apk" -t "application/vnd.android.package-archive" 2>/dev/null \
    && return 0
    echo -e "${RED}Gagal membuka installer. Install manual dari $DIR${NC}"
}

# hapus APK setelah sukses (opsional)
bersihkan() {
    local apk="$1"
    read -rp "Hapus file APK setelah terpasang? [y/N]: " jwb
    if [[ "$jwb" == "y" || "$jwb" == "Y" ]]; then
        rm -f "$apk"
        echo -e "${GREEN}File dihapus.${NC}"
    fi
}

# ---------- GoFile ----------

install_gofile() {
    header
    echo -e "${CYAN}1) Install dari GoFile link${NC}"
    read -rp "Tempel link GoFile: " link
    [[ -z "$link" ]] && { echo -e "${RED}Link kosong.${NC}"; sleep 1; return; }

    # ambil ID konten dari link
    id=$(echo "$link" | grep -oE '[a-zA-Z0-9]{8,}$')
    [[ -z "$id" ]] && { echo -e "${RED}ID GoFile tidak ditemukan.${NC}"; sleep 2; return; }

    # buat akun guest untuk token unduh
    echo "Menghubungi GoFile..."
    resp=$(curl -s -X POST https://api.gofile.io/accounts)
    token=$(echo "$resp" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    if [[ -z "$token" ]]; then
        echo -e "${RED}Gagal mendapat token GoFile.${NC}"; sleep 2; return
    fi

    info=$(curl -s -H "Authorization: Bearer $token" \
        "https://api.gofile.io/contents/$id?wt=gofile")
    link_dl=$(echo "$info" | sed -n 's/.*"link":"\([^"]*\)".*/\1/p' | head -1)
    nama=$(echo "$info" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1)

    if [[ -z "$link_dl" ]]; then
        echo -e "${RED}File tidak ditemukan / butuh password.${NC}"; sleep 2; return
    fi
    [[ -z "$nama" ]] && nama="app_$(date +%s).apk"

    echo -e "${YELLOW}Mengunduh: $nama${NC}"
    if curl -L --progress-bar -H "Cookie: accountToken=$token" \
         -o "$DIR/$nama" "$link_dl"; then
        echo -e "${GREEN}Selesai: $DIR/$nama${NC}"
        pasang "$DIR/$nama" && bersihkan "$DIR/$nama"
    else
        echo -e "${RED}Gagal mengunduh.${NC}"
    fi
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- Direct URL ----------

install_url() {
    header
    echo -e "${CYAN}2) Install dari direct URL${NC}"
    echo "Tempel link langsung ke file APK (akhiran .apk)"
    read -rp "Link: " link
    [[ -z "$link" ]] && { echo -e "${RED}Link kosong.${NC}"; sleep 1; return; }

    if unduh "$link"; then
        pasang "$DIR/$(basename "${link%%\?*}")" && bersihkan "$DIR/$(basename "${link%%\?*}")"
    fi
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- Web file (browse APK dari halaman) ----------

install_web() {
    header
    echo -e "${CYAN}3) Install dari web file${NC}"
    read -rp "Tempel link halaman web (berisi daftar APK): " link
    [[ -z "$link" ]] && { echo -e "${RED}Link kosong.${NC}"; sleep 1; return; }

    echo "Mencari link APK di halaman..."
    mapfile -t daftar < <(curl -sL "$link" \
        | grep -oiE 'href="[^"]+\.apk[^"]*"' \
        | sed 's/href="//; s/"$//' | sort -u)

    if [[ ${#daftar[@]} -eq 0 ]]; then
        echo -e "${RED}Tidak ada link .apk di halaman itu.${NC}"
        read -rp "Tekan Enter untuk kembali..."
        return
    fi

    echo ""
    echo "Link APK ditemukan:"
    for i in "${!daftar[@]}"; do
        echo "  $((i+1))) ${daftar[$i]}"
    done
    echo "  0) Batal"
    read -rp "Pilih nomor: " pilih
    [[ "$pilih" == "0" || -z "$pilih" ]] && return

    target="${daftar[$((pilih-1))]}"
    # jika link relatif, gabungkan dengan domain
    [[ "$target" != http* ]] && target="$(echo "$link" | sed -E 's#(https?://[^/]+).*#\1#')$target"

    if unduh "$target"; then
        pasang "$DIR/$(basename "${target%%\?*}")" && bersihkan "$DIR/$(basename "${target%%\?*}")"
    fi
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- Local file ----------

install_lokal() {
    header
    echo -e "${CYAN}4) Install dari local file (.apk)${NC}"
    echo "File di $DIR:"
    ls -1 "$DIR"/*.apk 2>/dev/null | nl || echo "  (tidak ada file .apk)"
    read -rp "Ketik nama file apk (atau Enter untuk batal): " nama
    [[ -z "$nama" ]] && return
    apk="$DIR/$nama"
    if [[ -f "$apk" ]]; then
        pasang "$apk" && bersihkan "$apk"
    else
        echo -e "${RED}File tidak ditemukan.${NC}"
    fi
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- WhatsApp cloud ----------

install_wa() {
    header
    echo -e "${CYAN}5) Install dari WhatsApp cloud${NC}"
    echo "Tempel link media WhatsApp (misal dari wa.me / status / cloud drive yang dibagikan)."
    read -rp "Link: " link
    [[ -z "$link" ]] && { echo -e "${RED}Link kosong.${NC}"; sleep 1; return; }

    # ikuti redirect (t.co, bit.ly, link wa, dsb) lalu unduh
    final=$(curl -sIL -o /dev/null -w '%{url_effective}' "$link")
    echo "Link tujuan: $final"
    if unduh "$final"; then
        pasang "$DIR/$(basename "${final%%\?*}")" && bersihkan "$DIR/$(basename "${final%%\?*}")"
    fi
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- Uninstall ----------

uninstall_pkg() {
    header
    echo -e "${CYAN}6) Uninstall package${NC}"
    echo "Daftar paket Termux terpasang:"
    dpkg -l | awk '/^ii/{print "  "$2}' | column -c 60 2>/dev/null || dpkg -l | awk '/^ii/{print "  "$2}'
    read -rp "Nama paket yang mau di-uninstall (Enter = batal): " pkg
    [[ -z "$pkg" ]] && return
    apt-get remove -y "$pkg" && echo -e "${GREEN}$pkg dihapus.${NC}" || echo -e "${RED}Gagal menghapus $pkg.${NC}"
    read -rp "Tekan Enter untuk kembali..."
}

# ---------- Menu utama ----------

while true; do
    header
    echo -e "${YELLOW}[INSTALL]${NC}"
    echo " 1) Install dari GoFile link"
    echo " 2) Install dari direct URL"
    echo " 3) Install dari web file"
    echo " 4) Install dari local file (.apk)"
    echo " 5) Install dari WhatsApp cloud"
    echo ""
    echo -e "${RED}[UNINSTALL]${NC}"
    echo " 6) Uninstall package"
    echo ""
    echo " 0) Back"
    read -rp " Enter choice : " pilih
    case "$pilih" in
        1) install_gofile ;;
        2) install_url ;;
        3) install_web ;;
        4) install_lokal ;;
        5) install_wa ;;
        6) uninstall_pkg ;;
        0) exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
done
