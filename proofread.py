#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
import requests
import subprocess
import sys
import os

OBJPATH = "/proofread"
IFACE = "org.kde.krunner1"
SERVICE = "org.kde.krunner.proofread"
OLLAMA_BASE = "http://localhost:11434"
MODEL = "gemma4:e2b"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

SYSTEM_PROMPT = (
    "You are a minimal proofreader. Fix ONLY: spelling mistakes, missing punctuation, and clear grammatical errors (wrong verb tense, missing articles). "
    "NEVER expand contractions or informal expressions. 'gonna', 'wanna', 'gotta', 'kinda', 'sorta' must stay exactly as written. "
    "NEVER change pronouns. NEVER substitute synonyms. NEVER reorder or restructure sentences. "
    "NEVER add or remove words unless a word is misspelled or grammatically impossible to parse. "
    "Treat all informal phrasing — 'me and my friend', 'like four hours', 'gonna', 'we been' — as deliberate stylistic choices. "
    "If in doubt, leave it unchanged. When uncertain whether something is an error or a style choice, do not change it. "
    "Return only the corrected text. No explanations, no comments, no additions."
)


def ensure_model():
    try:
        resp = requests.get(f"{OLLAMA_BASE}/api/tags", timeout=5)
        if resp.status_code != 200:
            print(f"[proofread] Ollama not reachable (status {resp.status_code}), skipping model check.")
            return
        tags = resp.json().get("models", [])
        installed = [m.get("name", "") for m in tags]
        if any(MODEL == m or m.startswith(MODEL) for m in installed):
            print(f"[proofread] Model {MODEL} already installed.")
            return
        print(f"[proofread] Model {MODEL} not found. Pulling now (this may take a while)...")
        pull_resp = requests.post(
            f"{OLLAMA_BASE}/api/pull",
            json={"name": MODEL, "stream": False},
            timeout=600
        )
        if pull_resp.status_code == 200:
            print(f"[proofread] Model {MODEL} pulled successfully.")
        else:
            print(f"[proofread] Pull failed: {pull_resp.status_code} {pull_resp.text}")
    except requests.exceptions.ConnectionError:
        print("[proofread] Ollama is not running. Start it with: systemctl --user start ollama")
    except Exception as e:
        print(f"[proofread] Model check error: {e}")


def proofread_text(text):
    try:
        resp = requests.post(
            f"{OLLAMA_BASE}/api/chat",
            json={
                "model": MODEL,
                "think": False,
                "stream": False,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": text}
                ]
            },
            timeout=30
        )
        data = resp.json()
        return data.get("message", {}).get("content", "").strip()
    except requests.exceptions.ConnectionError:
        return "Error: Ollama not running"
    except Exception as e:
        return f"Error: {e}"


class ProofreadRunner(dbus.service.Object):
    def __init__(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()
        bus.request_name(SERVICE)
        super().__init__(bus, OBJPATH)
        self._last_original = ""
        self._last_corrected = ""

    @dbus.service.method(IFACE, in_signature='s', out_signature='a(sssida{sv})')
    def Match(self, query):
        if not query.startswith("proof "):
            return []
        text = query[6:].strip()
        if len(text) < 3:
            return []
        corrected = proofread_text(text)
        if not corrected or corrected == text:
            return []
        self._last_original = text
        self._last_corrected = corrected
        return [(corrected, corrected, "accessories-text-editor", 1, 1.0, {})]

    @dbus.service.method(IFACE, in_signature='', out_signature='a(sss)')
    def Actions(self):
        return [("show_diff", "Show Diff", "view-split-left-right")]

    @dbus.service.method(IFACE, in_signature='ss')
    def Run(self, match_id, action_id):
        if action_id == "show_diff":
            diffview = os.path.join(SCRIPT_DIR, "diffview.py")
            subprocess.Popen([sys.executable, diffview, self._last_original, self._last_corrected])
        else:
            subprocess.run(["wl-copy", match_id])

    @dbus.service.method(IFACE, in_signature='', out_signature='a{sv}')
    def Config(self):
        return {}


if __name__ == "__main__":
    ensure_model()
    runner = ProofreadRunner()
    print(f"[proofread] KRunner plugin running. Model: {MODEL}")
    GLib.MainLoop().run()
