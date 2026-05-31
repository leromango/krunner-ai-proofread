#!/usr/bin/env bash
set -e

INSTALL_DIR="$HOME/.local/share/krunner-proofread"
DBUS_SERVICE_DIR="$HOME/.local/share/dbus-1/services"
DBUS_PLUGIN_DIR="$HOME/.local/share/krunner/dbusplugins"
SYSTEMD_DIR="$HOME/.config/systemd/user"
ERRORS=()
WARNINGS=()

echo "==> Checking system requirements..."

if ! command -v python3 &>/dev/null; then
    echo "[ERROR] python3 not found. Install it and re-run."
    exit 1
fi
PYTHON=$(which python3)
PYTHON_MAJOR=$("$PYTHON" -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$("$PYTHON" -c "import sys; print(sys.version_info.minor)")
if [[ "$PYTHON_MAJOR" -lt 3 || ("$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 10) ]]; then
    echo "[ERROR] Python 3.10+ required. Found: $("$PYTHON" --version)"
    exit 1
fi
echo "    Python $PYTHON_MAJOR.$PYTHON_MINOR — OK"

if ! command -v krunner &>/dev/null; then
    WARNINGS+=("krunner not found — are you on KDE Plasma?")
else
    echo "    KRunner — OK"
fi

if ! command -v wl-copy &>/dev/null; then
    echo "[!] wl-clipboard not found. Attempting to install..."
    if [ -f /run/ostree-booted ]; then
        rpm-ostree install wl-clipboard --apply-live || \
            ERRORS+=("Failed to install wl-clipboard. Run: rpm-ostree install wl-clipboard --apply-live")
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y wl-clipboard || ERRORS+=("Failed to install wl-clipboard via dnf.")
    elif command -v apt &>/dev/null; then
        sudo apt install -y wl-clipboard || ERRORS+=("Failed to install wl-clipboard via apt.")
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm wl-clipboard || ERRORS+=("Failed to install wl-clipboard via pacman.")
    else
        ERRORS+=("wl-clipboard not found and no supported package manager detected. Install it manually.")
    fi
else
    echo "    wl-clipboard — OK"
fi

if ! command -v ollama &>/dev/null; then
    ERRORS+=("Ollama not installed. Install from https://ollama.com or: curl -fsSL https://ollama.ai/install.sh | sh")
else
    echo "    Ollama — OK"
    if ! curl -s --connect-timeout 2 http://localhost:11434 &>/dev/null; then
        WARNINGS+=("Ollama is not running. Start it with: systemctl --user start ollama")
    else
        echo "    Ollama reachable — OK"
    fi
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "══ Installation failed ══════════════════"
    for err in "${ERRORS[@]}"; do echo "  [ERROR] $err"; done
    exit 1
fi

echo "==> Installing Python dependencies..."

install_pip_pkg() {
    local pkg="$1" import_name="${2:-$1}"
    "$PYTHON" -c "import $import_name" &>/dev/null && { echo "    $pkg — already installed"; return; }
    echo "    Installing $pkg..."
    "$PYTHON" -m pip install "$pkg" --break-system-packages -q 2>/dev/null || \
    "$PYTHON" -m pip install "$pkg" -q 2>/dev/null || \
        ERRORS+=("Failed to install $pkg. Run: pip install $pkg")
}

install_pip_pkg "dbus-python" "dbus"
install_pip_pkg "requests"
install_pip_pkg "PyQt6"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "══ Installation failed ══════════════════"
    for err in "${ERRORS[@]}"; do echo "  [ERROR] $err"; done
    exit 1
fi

if curl -s --connect-timeout 2 http://localhost:11434 &>/dev/null; then
    echo "==> Checking model..."
    MODEL="gemma4:e2b"
    if ollama list 2>/dev/null | grep -q "$MODEL"; then
        echo "    $MODEL — already installed"
    else
        echo "    Pulling $MODEL (this may take a few minutes)..."
        ollama pull "$MODEL" || WARNINGS+=("Model pull failed. Run manually: ollama pull $MODEL")
    fi
fi

echo "==> Copying files..."
if [ ! -f proofread.py ] || [ ! -f diffview.py ]; then
    echo "[ERROR] proofread.py or diffview.py not found. Run install.sh from the repo root."
    exit 1
fi

mkdir -p "$INSTALL_DIR"
cp proofread.py "$INSTALL_DIR/proofread.py"
cp diffview.py "$INSTALL_DIR/diffview.py"
chmod +x "$INSTALL_DIR/proofread.py"
chmod +x "$INSTALL_DIR/diffview.py"
echo "    Installed to $INSTALL_DIR"

mkdir -p "$DBUS_SERVICE_DIR"
cat > "$DBUS_SERVICE_DIR/org.kde.krunner.proofread.service" << DBUS
[D-BUS Service]
Name=org.kde.krunner.proofread
Exec=$PYTHON -u $INSTALL_DIR/proofread.py
DBUS
echo "==> DBus service registered"

mkdir -p "$DBUS_PLUGIN_DIR"
cat > "$DBUS_PLUGIN_DIR/krunner-proofread.desktop" << DESKTOP
[Desktop Entry]
Name=AI Proofreader
Comment=Proofread text using local Ollama
Type=Service
Icon=accessories-text-editor
X-KDE-ServiceTypes=Plasma/Runner
X-KDE-PluginInfo-Name=krunner-proofread
X-KDE-PluginInfo-Version=1.0
X-KDE-PluginInfo-License=MIT
X-KDE-PluginInfo-EnabledByDefault=true
X-Plasma-API=DBus
X-Plasma-DBusRunner-Service=org.kde.krunner.proofread
X-Plasma-DBusRunner-Path=/proofread
X-Plasma-Runner-Match-Regex=^proof 
DESKTOP
echo "==> KRunner plugin registered"

mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/krunner-proofread.service" << SYSTEMD
[Unit]
Description=KRunner Proofread Plugin (Ollama)
After=network.target

[Service]
ExecStart=$PYTHON -u $INSTALL_DIR/proofread.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
SYSTEMD

systemctl --user daemon-reload
systemctl --user enable --now krunner-proofread.service

sleep 2
if ! systemctl --user is-active --quiet krunner-proofread.service; then
    WARNINGS+=("Service may not have started. Check: journalctl --user -u krunner-proofread -n 30")
fi

echo "==> Restarting KRunner..."
kquitapp6 krunner 2>/dev/null || true
sleep 1
krunner &>/dev/null &

echo ""
echo "══ Done ═════════════════════════════════"
if [ ${#WARNINGS[@]} -gt 0 ]; then
    for w in "${WARNINGS[@]}"; do echo "  [!] $w"; done
    echo ""
fi
echo "  Usage: open KRunner and type:  proof <your text>"
echo "  Logs:  journalctl --user -u krunner-proofread -f"
echo "═════════════════════════════════════════"