#!/usr/bin/env bash
set -e

INSTALL_DIR="$HOME/.local/share/krunner-proofread"
DBUS_SERVICE_DIR="$HOME/.local/share/dbus-1/services"
SYSTEMD_DIR="$HOME/.config/systemd/user"

ERRORS=()
WARNINGS=()

echo "==> Checking system requirements..."

# Python 
if ! command -v python3 &>/dev/null; then
    echo "[ERROR] python3 not found. Install it and re-run."
    exit 1
fi
PYTHON=$(which python3)
PYTHON_VERSION=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$("$PYTHON" -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$("$PYTHON" -c "import sys; print(sys.version_info.minor)")
if [[ "$PYTHON_MAJOR" -lt 3 || ("$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 10) ]]; then
    echo "[ERROR] Python 3.10+ required. Found: $PYTHON_VERSION"
    exit 1
fi
echo "    Python $PYTHON_VERSION — OK"

# KDE / KRunner 
if ! command -v krunner &>/dev/null; then
    WARNINGS+=("krunner not found — are you on KDE Plasma?")
else
    echo "    KRunner — OK"
fi

# Wayland / wl-clipboard 
if ! command -v wl-copy &>/dev/null; then
    echo "[!] wl-clipboard not found. Attempting to install..."
    # Detect immutable vs normal
    if [ -f /run/ostree-booted ]; then
        echo "    Detected Fedora Atomic / Bazzite — using rpm-ostree"
        rpm-ostree install wl-clipboard --apply-live || \
            ERRORS+=("Failed to install wl-clipboard via rpm-ostree. Run manually: rpm-ostree install wl-clipboard --apply-live")
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y wl-clipboard || \
            ERRORS+=("Failed to install wl-clipboard via dnf.")
    elif command -v apt &>/dev/null; then
        sudo apt install -y wl-clipboard || \
            ERRORS+=("Failed to install wl-clipboard via apt.")
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm wl-clipboard || \
            ERRORS+=("Failed to install wl-clipboard via pacman.")
    else
        ERRORS+=("wl-clipboard not found and package manager unknown. Install it manually.")
    fi
else
    echo "    wl-clipboard — OK"
fi

# Ollama 
if ! command -v ollama &>/dev/null; then
    WARNINGS+=("Ollama is not installed. The plugin will not work without it.")
    WARNINGS+=("Install from: https://ollama.com or run: curl -fsSL https://ollama.ai/install.sh | sh")
else
    echo "    Ollama — OK"
    # Check Ollama
    if ! curl -s --connect-timeout 2 http://localhost:11434 &>/dev/null; then
        WARNINGS+=("Ollama is installed but not running. Start it with: systemctl --user start ollama")
    else
        echo "    Ollama reachable — OK"
    fi
fi

# pip 
if ! command -v pip3 &>/dev/null && ! "$PYTHON" -m pip --version &>/dev/null 2>&1; then
    ERRORS+=("pip not found. Install python3-pip and re-run.")
fi

# Python dependencies 
echo "==> Installing Python dependencies..."

install_pip_pkg() {
    local pkg="$1"
    local import_name="${2:-$1}"
    if "$PYTHON" -c "import $import_name" &>/dev/null; then
        echo "    $pkg — already installed"
        return
    fi
    echo "    Installing $pkg..."
    "$PYTHON" -m pip install "$pkg" --break-system-packages -q 2>/dev/null || \
    "$PYTHON" -m pip install "$pkg" -q 2>/dev/null || \
        ERRORS+=("Failed to install Python package: $pkg. Run manually: pip install $pkg")
}

install_pip_pkg "dbus-python" "dbus"
install_pip_pkg "requests" "requests"
install_pip_pkg "PyQt6" "PyQt6"

# Abort if hard errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "══════════════════════════════════════════"
    echo " Installation failed. Fix these errors:"
    echo "══════════════════════════════════════════"
    for err in "${ERRORS[@]}"; do
        echo "  [ERROR] $err"
    done
    exit 1
fi

# Copy files
echo "==> Copying files..."
if [ ! -f proofread.py ] || [ ! -f diffview.py ]; then
    echo "[ERROR] proofread.py or diffview.py not found in current directory."
    echo "        Run install.sh from the repo root."
    exit 1
fi

mkdir -p "$INSTALL_DIR"
cp proofread.py "$INSTALL_DIR/proofread.py"
cp diffview.py "$INSTALL_DIR/diffview.py"
chmod +x "$INSTALL_DIR/proofread.py"
chmod +x "$INSTALL_DIR/diffview.py"
echo "    Files installed to $INSTALL_DIR"

# DBus service
echo "==> Registering DBus service..."
mkdir -p "$DBUS_SERVICE_DIR"
cat > "$DBUS_SERVICE_DIR/org.kde.krunner.proofread.service" << DBUS
[D-BUS Service]
Name=org.kde.krunner.proofread
Exec=$PYTHON $INSTALL_DIR/proofread.py
DBUS
echo "    DBus service registered"

# Systemd service 
echo "==> Creating systemd user service..."
mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/krunner-proofread.service" << SYSTEMD
[Unit]
Description=KRunner Proofread Plugin (Ollama)
After=network.target

[Service]
ExecStart=$PYTHON $INSTALL_DIR/proofread.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
SYSTEMD

systemctl --user daemon-reload
systemctl --user enable --now krunner-proofread.service

# Verify service started
sleep 2
if ! systemctl --user is-active --quiet krunner-proofread.service; then
    echo "[ERROR] Service failed to start. Check: journalctl --user -u krunner-proofread -n 30"
    ERRORS+=("krunner-proofread.service did not start.")
fi

# Restart KRunner
echo "==> Restarting KRunner..."
kquitapp6 krunner 2>/dev/null || true
sleep 1
kstart6 krunner 2>/dev/null || true

# Summary 
echo ""
echo "══════════════════════════════════════════"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo " Installed with errors:"
    for err in "${ERRORS[@]}"; do
        echo "  [ERROR] $err"
    done
else
    echo " Installation complete."
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo " Warnings:"
    for w in "${WARNINGS[@]}"; do
        echo "  [!] $w"
    done
fi

echo "══════════════════════════════════════════"
echo ""
echo "Usage: open KRunner (Alt+Space) and type:  proof <your text>"
echo "  Enter        — copy corrected text to clipboard"
echo "  Tab → Diff   — open diff viewer"
echo ""
echo "Logs: journalctl --user -u krunner-proofread -f"