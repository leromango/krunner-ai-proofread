#!/usr/bin/env bash
set -e

INSTALL_DIR="$HOME/.local/share/krunner-proofread"
DBUS_SERVICE_DIR="$HOME/.local/share/dbus-1/services"
SYSTEMD_DIR="$HOME/.config/systemd/user"
PYTHON=$(which python3)

echo "==> Installing krunner-proofread..."

# Dependencies
echo "==> Installing Python dependencies..."
pip install dbus-python requests --break-system-packages -q

# PyQt6 
python3 -c "import PyQt6" 2>/dev/null || pip install PyQt6 --break-system-packages -q

# Copy files
mkdir -p "$INSTALL_DIR"
cp proofread.py "$INSTALL_DIR/proofread.py"
cp diffview.py "$INSTALL_DIR/diffview.py"
chmod +x "$INSTALL_DIR/proofread.py"
chmod +x "$INSTALL_DIR/diffview.py"

echo "==> Files installed to $INSTALL_DIR"

# DBus 
mkdir -p "$DBUS_SERVICE_DIR"
cat > "$DBUS_SERVICE_DIR/org.kde.krunner.proofread.service" << EOF
[D-BUS Service]
Name=org.kde.krunner.proofread
Exec=$PYTHON $INSTALL_DIR/proofread.py
EOF
echo "==> DBus service registered"

# Systemd
mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/krunner-proofread.service" << EOF
[Unit]
Description=KRunner Proofread Plugin (Ollama)
After=network.target

[Service]
ExecStart=$PYTHON $INSTALL_DIR/proofread.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now krunner-proofread.service

echo "==> Restarting KRunner..."
kquitapp6 krunner 2>/dev/null || true
sleep 1
kstart6 krunner 2>/dev/null || true

echo ""
echo "Done. Use KRunner (Alt+Space) and type: proof <your text>"
echo "Default action: copies corrected text to clipboard."
echo "Secondary action: opens diff viewer."
