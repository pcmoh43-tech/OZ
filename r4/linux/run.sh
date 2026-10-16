#!/usr/bin/env bash
# قائمة تشغيل موحدة - Linux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
echo "============================================"
echo "   مشاركة الطابعة - Printer Sharing"
echo "   Linux / Ubuntu"
echo "============================================"
echo ""
echo "  اختر السكربت المطلوب:"
echo ""
echo "    [1] الحاسوب المضيف (Host) - مشاركة الطابعة"
echo "    [2] الحاسوب العميل (Client) - الاتصال بالطابعة"
echo "    [3] خروج"
echo ""

read -rp "  اختر [1-3]: " choice

case "$choice" in
    1)
        echo ""
        echo "  جاري تشغيل سكربت المشاركة..."
        sudo bash "$SCRIPT_DIR/host-share-printer.sh"
        ;;
    2)
        echo ""
        echo "  جاري تشغيل سكربت الاتصال..."
        sudo bash "$SCRIPT_DIR/client-connect-printer.sh"
        ;;
    3)
        exit 0
        ;;
    *)
        echo "  اختيار غير صالح!"
        exit 1
        ;;
esac
