#!/usr/bin/env bash
set -e

INSTALL_DIR="$HOME/.local/share/krunner-proofread"
DBUS_SERVICE="$HOME/.local/share/dbus-1/services/org.kde.krunner.proofread.service"
DBUS_PLUGIN="$HOME/.local/share/krunner/dbusplugins/krunner-proofread.desktop"
SYSTEMD_SERVICE="$HOME/.config/systemd/user/krunner-proofread.service"

echo "==> Stopping and disabling krunner-proofread service..."
systemctl --user stop krunner-proofread.service 2>/dev/null || true
systemctl --user disable krunner-proofread.service 2>/dev/null || true

echo "==> Removing files..."
rm -rf "$INSTALL_DIR"
rm -f "$DBUS_SERVICE"
rm -f "$DBUS_PLUGIN"
rm -f "$SYSTEMD_SERVICE"

systemctl --user daemon-reload

echo "==> Restarting KRunner..."
kquitapp6 krunner 2>/dev/null || true
sleep 1
krunner &>/dev/null &

echo ""
echo "Done. krunner-proofread has been removed."
echo "The Ollama model (gemma4:e2b) was NOT removed. To delete it:"
echo "  ollama rm gemma4:e2b"