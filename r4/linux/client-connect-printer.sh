#!/usr/bin/env bash
# الاتصال بطابعة مشتركة على حاسوب آخر (Linux/Ubuntu)
# يتطلب: sudo ./client-connect-printer.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_CONFIG="$SCRIPT_DIR/host-config.json"
CLIENT_CONFIG="$SCRIPT_DIR/client-config.json"

header() {
    clear
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}   الاتصال بطابعة مشتركة - الحاسوب العميل${NC}"
    echo -e "${CYAN}   Linux / Ubuntu${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}يجب تشغيل السكربت بصلاحيات root:${NC}"
        echo "  sudo $0"
        exit 1
    fi
}

install_deps() {
    local packages=(cups cups-client)
    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            echo -e "${YELLOW}جاري تثبيت $pkg...${NC}"
            apt-get update -qq && apt-get install -y "$pkg"
            break
        fi
    done
}

test_host() {
    local host="$1"
    echo -e "   جاري التحقق من الاتصال بـ ${CYAN}$host${NC}..."

    if ping -c 2 -W 3 "$host" &>/dev/null; then
        echo -e "   ${GREEN}✓${NC} الحاسوب المضيف متصل"
        return 0
    fi

    echo -e "   ${RED}✗${NC} لا يمكن الوصول للحاسوب المضيف"
    echo -e "${YELLOW}   تأكد من:${NC}"
    echo "     - كلا الحاسوبين على نفس شبكة الواي-فاي"
    echo "     - عنوان IP صحيح"
    echo "     - CUPS يعمل على الحاسوب المضيف (منفذ 631)"
    return 1
}

discover_printers() {
    local host="$1"
    echo -e "\n   جاري البحث عن الطابعات على ${CYAN}$host${NC}..."

    # Try IPP discovery
    local url="http://$host:631/printers/"
    if curl -sf --connect-timeout 5 "$url" &>/dev/null; then
        echo -e "   ${GREEN}✓${NC} خادم CUPS متاح"
        lpstat -h "$host:631" -p 2>/dev/null | awk '{print $2}' || true
        return 0
    fi

    echo -e "   ${YELLOW}تحذير:${NC} لم يتم اكتشاف CUPS تلقائياً"
    return 1
}

add_printer() {
    local host="$1"
    local share_name="$2"
    local printer_uri="ipp://$host:631/printers/$share_name"
    local local_name="Shared_${share_name}"

    echo -e "\n   جاري تثبيت الطابعة: ${CYAN}$printer_uri${NC}"

    # Remove existing if present
    lpadmin -x "$local_name" 2>/dev/null || true

    if lpadmin -p "$local_name" -E -v "$printer_uri" -m everywhere 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} تم تثبيت الطابعة: $local_name"
        echo "$local_name"
        return 0
    fi

    # Fallback: raw IPP
    if lpadmin -p "$local_name" -E -v "$printer_uri" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} تم تثبيت الطابعة (IPP): $local_name"
        echo "$local_name"
        return 0
    fi

    echo -e "   ${RED}✗${NC} فشل التثبيت"
    return 1
}

set_default_printer() {
    local printer_name="$1"
    lpoptions -d "$printer_name" 2>/dev/null || lpadmin -d "$printer_name"
    echo -e "   ${GREEN}✓${NC} تم تعيين '$printer_name' كطابعة افتراضية"
}

test_print() {
    local printer_name="$1"
    echo -e "\n   إرسال صفحة اختبار..."
    echo "Printer Test - $(date)" | lp -d "$printer_name" 2>/dev/null && \
        echo -e "   ${GREEN}✓${NC} تم إرسال صفحة الاختبار" || \
        echo -e "   ${YELLOW}!${NC} لم تُرسل الصفحة (تحقق يدوياً)"
}

save_config() {
    local host="$1"
    local share_name="$2"
    local printer_name="$3"

    cat > "$CLIENT_CONFIG" <<EOF
{
  "hostAddress": "$host",
  "shareName": "$share_name",
  "printerName": "$printer_name",
  "connectedAt": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    echo -e "   ${GREEN}✓${NC} تم حفظ الإعدادات في: $CLIENT_CONFIG"
}

# ========== Main ==========
header
require_root
install_deps

HOST=""
SHARE_NAME=""

# Load saved host config if available
if [[ -f "$HOST_CONFIG" ]]; then
    echo -e "${GREEN}تم العثور على إعدادات محفوظة من الحاسوب المضيف.${NC}"
    HOST="$(python3 -c "import json; print(json.load(open('$HOST_CONFIG'))['ip'])" 2>/dev/null || \
            grep -oP '"ip"\s*:\s*"\K[^"]+' "$HOST_CONFIG")"
    SHARE_NAME="$(python3 -c "import json; print(json.load(open('$HOST_CONFIG'))['shareName'])" 2>/dev/null || \
                 grep -oP '"shareName"\s*:\s*"\K[^"]+' "$HOST_CONFIG")"
    echo -e "  IP: ${CYAN}$HOST${NC} | المشاركة: ${CYAN}$SHARE_NAME${NC}"
    read -rp $'\nاستخدام الإعدادات المحفوظة؟ [Y/n]: ' use_saved
    if [[ "$use_saved" =~ ^[Nn]$ ]]; then
        HOST=""
        SHARE_NAME=""
    fi
fi

if [[ -z "$HOST" ]]; then
    echo "أدخل معلومات الحاسوب الذي عليه الطابعة:"
    echo ""
    echo "  1. بالعنوان IP (مثال: 192.168.1.50)"
    echo "  2. باسم الحاسوب (مثال: ubuntu-desktop)"
    echo ""
    read -rp "طريقة الاتصال [1/2]: " input_type
    if [[ "$input_type" == "2" ]]; then
        read -rp "اسم الحاسوب: " HOST
    else
        read -rp "عنوان IP: " HOST
    fi
fi

test_host "$HOST" || exit 1

if [[ -z "$SHARE_NAME" ]]; then
    discover_printers "$HOST" || true
    read -rp $'\nأدخل اسم مشاركة الطابعة (Share Name): ' SHARE_NAME
fi

echo -e "\nخيارات الإعداد:"
read -rp "  تعيين كطابعة افتراضية؟ [Y/n]: " set_default
read -rp "  طباعة صفحة اختبار؟ [Y/n]: " do_test

INSTALLED_NAME="$(add_printer "$HOST" "$SHARE_NAME")" || exit 1

if [[ ! "$set_default" =~ ^[Nn]$ ]]; then
    set_default_printer "$INSTALLED_NAME"
fi

if [[ ! "$do_test" =~ ^[Nn]$ ]]; then
    test_print "$INSTALLED_NAME"
fi

save_config "$HOST" "$SHARE_NAME" "$INSTALLED_NAME"

echo -e "\n${CYAN}============================================${NC}"
echo -e "${GREEN}   تم الاتصال بالطابعة بنجاح!${NC}"
echo -e "   URI: ipp://$HOST:631/printers/$SHARE_NAME"
echo -e "${CYAN}============================================${NC}"
