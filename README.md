# krunner-proofread

A local AI proofreading plugin for KDE's KRunner, powered by [Ollama](https://ollama.com). No cloud, no API keys. Originally inspired by Apple Intelligence ease of use.

Type `proof <your text>` in KRunner and get a corrected version instantly. The model runs entirely on your machine.

![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6-blue) ![Python 3](https://img.shields.io/badge/Python-3.10+-green) ![Ollama](https://img.shields.io/badge/Ollama-local-orange)

---

## Features

- **KRunner integration** — trigger with `proof ` prefix
- **Minimal correction** — fixes spelling, punctuation, and clear grammar errors only; preserves your voice, contractions, and informal style
- **Diff viewer** — PyQt6 window showing word-level changes (green = changed, blue = added, red = removed)
- **Click-to-explain** — click any highlighted word to get a one-sentence explanation of why it was changed
- **Auto model download** — pulls `gemma4:e2b` automatically on first run if not installed
- **Clipboard integration** — default action copies corrected text via `wl-copy`
- **Fully local** — runs via Ollama, no data leaves your machine

---

## Requirements

- KDE Plasma 6 (Wayland)
- Python 3.10+
- [Ollama](https://ollama.com) installed and running
- `wl-clipboard` (`wl-copy`)

```bash
# Fedora/Nobara
sudo dnf install wl-clipboard python3-pip

# Arch
sudo pacman -S wl-clipboard python-pip

# Debian/Ubuntu
sudo apt install wl-clipboard python3-pip
```

---

## Install

```bash
git clone https://github.com/leromango/krunner-ai-proofread
cd krunner-proofread
chmod +x install.sh
./install.sh
```

The installer:
1. Installs Python dependencies (`dbus-python`, `requests`, `PyQt6`)
2. Copies files to `~/.local/share/krunner-proofread/`
3. Registers the DBus service
4. Creates and enables a systemd user service
5. Restarts KRunner

On first launch, `proofread.py` will pull `gemma4:e2b` from Ollama automatically (~2GB). Make sure Ollama is running first:

```bash
systemctl --user start ollama
```
or just:
```bash
ollama serve
```

---

## Usage

Open KRunner (`Alt+Space` or `Meta+Space`) and type:

```
proof this is somethign i wrote qickly
```

KRunner will show the corrected text as a result.

- **Enter** — copies corrected text to clipboard
- **Tab → Show Diff** — opens the diff viewer window

---

## What it fixes

| It will fix | It will NOT change |
|---|---|
| `teh` → `the` | `gonna` → ~~going to~~ |
| `i` → `I` (when subject) | `wanna`, `kinda`, `sorta` |
| Missing period at end | Contractions (`don't`, `it's`) |
| Wrong verb tense | Informal sentence openers |
| Missing articles (`a`, `the`) | Your word order |

The system prompt is tuned to be conservative. If in doubt, the model leaves text unchanged.

---

## Files

```
~/.local/share/krunner-proofread/
├── proofread.py       # DBus KRunner plugin + Ollama client
└── diffview.py        # PyQt6 diff viewer

~/.local/share/dbus-1/services/
└── org.kde.krunner.proofread.service

~/.config/systemd/user/
└── krunner-proofread.service
```

---

## Troubleshooting

**KRunner doesn't show results:**
```bash
systemctl --user status krunner-proofread
journalctl --user -u krunner-proofread -n 50
```

**Restart the plugin:**
```bash
systemctl --user restart krunner-proofread
kquitapp6 krunner && kstart6 krunner
```

**Model not downloading:**
Make sure Ollama is running and reachable at `http://localhost:11434`. Then manually pull:
```bash
ollama pull gemma4:e2b
```

---

## Model

Uses [`gemma4:e2b`](https://ollama.com/library/gemma4) — Google's Gemma 4 2B instruction model, fast enough for interactive use even on CPU. Thinking mode is disabled (`think: False`) for lower latency.

To switch models, edit the `MODEL` constant at the top of `proofread.py` and `diffview.py`.

---

## License

MIT
