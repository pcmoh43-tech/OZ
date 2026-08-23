#!/usr/bin/env bash
# مشاركة الطابعة على الحاسوب المضيف (Linux/Ubuntu)
# يتطلب: sudo ./host-share-printer.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/host-config.json"

header() {
    clear
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}   مشاركة الطابعة - الحاسوب المضيف (Host)${NC}"
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

install_cups() {
    if ! command -v lpstat &>/dev/null; then
        echo -e "${YELLOW}جاري تثبيت CUPS...${NC}"
        apt-get update -qq && apt-get install -y cups cups-client
    fi
}

list_printers() {
    lpstat -p 2>/dev/null | awk '{print $2}' | grep -v "^$"
}

enable_sharing() {
    local share_mode="$1"

    echo -e "\n${YELLOW}[1/4] تفعيل مشاركة CUPS...${NC}"

    cupsctl --share-printers

    case "$share_mode" in
        full|domain)
            cupsctl --remote-any
            echo -e "   ${GREEN}✓${NC} مشاركة عن بُعد (Remote Any)"
            ;;
        *)
            cupsctl --remote-admin --remote-printers
            echo -e "   ${GREEN}✓${NC} مشاركة شبكة محلية"
            ;;
    esac

    # Allow port 631 through firewall if ufw is active
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow 631/tcp comment "CUPS printer sharing" 2>/dev/null || true
        ufw allow from 192.168.0.0/16 to any port 631 2>/dev/null || true
        ufw allow from 10.0.0.0/8 to any port 631 2>/dev/null || true
        echo -e "   ${GREEN}✓${NC} تم فتح المنفذ 631 في جدار الحماية"
    fi

    systemctl enable cups 2>/dev/null || true
    systemctl restart cups
}

share_printer() {
    local printer_name="$1"
    local share_name="$2"
    local share_mode="$3"

    echo -e "\n${YELLOW}[2/4] مشاركة الطابعة: $printer_name${NC}"

    # Enable sharing via lpadmin
    lpadmin -p "$printer_name" -o printer-is-shared=true 2>/dev/null || true

    case "$share_mode" in
        full)
            # Allow all users on network
            lpadmin -p "$printer_name" -o auth-info-required=none 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} مشاركة كاملة - جميع المستخدمين"
            ;;
        domain)
            echo -e "   ${GREEN}✓${NC} مشاركة شركة/مجال"
            ;;
        *)
            echo -e "   ${GREEN}✓${NC} مشاركة أساسية"
            ;;
    esac
}

show_connection_info() {
    local share_name="$1"
    local hostname ip wifi_ip

    echo -e "\n${YELLOW}[3/4] معلومات الاتصال للحاسوب الآخر:${NC}"

    hostname="$(hostname)"
    wifi_ip="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1)"
    ip="${wifi_ip:-$(hostname -I | awk '{print $1}')}"

    echo ""
    echo -e "   اسم الحاسوب:  ${CYAN}$hostname${NC}"
    echo -e "   عنوان IP:     ${CYAN}$ip${NC}"
    echo -e "   اسم المشاركة: ${CYAN}$share_name${NC}"
    echo ""
    echo -e "   ${CYAN}للاتصال من الحاسوب الآخر:${NC}"
    echo -e "   ${GREEN}ipp://$ip:631/printers/$share_name${NC}"
    echo -e "   ${GREEN}http://$ip:631/printers/$share_name${NC}"

    cat > "$CONFIG_FILE" <<EOF
{
  "hostname": "$hostname",
  "ip": "$ip",
  "shareName": "$share_name",
  "ippUrl": "ipp://$ip:631/printers/$share_name",
  "sharedAt": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    echo -e "\n   ${GREEN}✓${NC} تم حفظ الإعدادات في: $CONFIG_FILE"
}

test_share() {
    local printer_name="$1"

    echo -e "\n${YELLOW}[4/4] اختبار المشاركة...${NC}"

    if lpstat -p "$printer_name" &>/dev/null; then
        local shared
        shared="$(lpstat -l -p "$printer_name" 2>/dev/null | grep -c 'printer-is-shared=true' || true)"
        if [[ "$shared" -gt 0 ]]; then
            echo -e "   ${GREEN}✓${NC} الطابعة مشتركة بنجاح!"
            return 0
        fi
    fi
    echo -e "   ${RED}✗${NC} فشل التحقق - راجع http://localhost:631"
    return 1
}

# ========== Main ==========
header
require_root
install_cups

mapfile -t PRINTERS < <(list_printers)

if [[ ${#PRINTERS[@]} -eq 0 ]]; then
    echo -e "${RED}لم يتم العثور على طابعات!${NC}"
    echo "تأكد من توصيل الطابعة. يمكنك إضافتها عبر:"
    echo "  http://localhost:631"
    exit 1
fi

echo "الطابعات المتاحة:"
echo ""
for i in "${!PRINTERS[@]}"; do
    echo "  $((i + 1)). ${PRINTERS[$i]}"
done
echo ""

read -rp "اختر رقم الطابعة: " selection
index=$((selection - 1))

if [[ $index -lt 0 || $index -ge ${#PRINTERS[@]} ]]; then
    echo -e "${RED}اختيار غير صالح!${NC}"
    exit 1
fi

SELECTED_PRINTER="${PRINTERS[$index]}"
echo -e "\nالطابعة المختارة: ${CYAN}$SELECTED_PRINTER${NC}"

default_share="$(echo "$SELECTED_PRINTER" | tr -cd '[:alnum:]')"
read -rp "اسم المشاركة (Enter للافتراضي: $default_share): " SHARE_NAME
SHARE_NAME="${SHARE_NAME:-$default_share}"

echo -e "\nنوع المشاركة:"
echo "  1. مشاركة أساسية (Basic) - شبكة محلية"
echo "  2. مشاركة كاملة (Full) - جميع المستخدمين"
echo "  3. مشاركة شركة/مجال (Domain)"
echo ""
read -rp "اختر نوع المشاركة [1-3]: " mode_sel

case "$mode_sel" in
    2) SHARE_MODE="full" ;;
    3) SHARE_MODE="domain" ;;
    *) SHARE_MODE="basic" ;;
esac

enable_sharing "$SHARE_MODE"
share_printer "$SELECTED_PRINTER" "$SHARE_NAME" "$SHARE_MODE"
show_connection_info "$SHARE_NAME"

if test_share "$SELECTED_PRINTER"; then
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${GREEN}   تم إعداد المشاركة بنجاح!${NC}"
    echo -e "   شغّل client-connect-printer.sh على الحاسوب الآخر."
    echo -e "${CYAN}============================================${NC}"
else
    echo -e "\n${RED}   حدثت مشكلة. راجع http://localhost:631${NC}"
fi
