#!/usr/bin/env python3
import sys
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
import requests
import subprocess
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
        return resp.json().get("message", {}).get("content", "").strip()
    except requests.exceptions.ConnectionError:
        return None
    except Exception:
        return None


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

        if corrected is None:
            return [("Ollama not running — start with: systemctl --user start ollama",
                     "ollama-error", "dialog-error", 1, 0.5, {})]

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
        if match_id == "ollama-error":
            return
        if action_id == "show_diff":
            diffview = os.path.join(SCRIPT_DIR, "diffview.py")
            subprocess.Popen([sys.executable, diffview, self._last_original, self._last_corrected])
        else:
            subprocess.run(["wl-copy", match_id])

    @dbus.service.method(IFACE, in_signature='', out_signature='a{sv}')
    def Config(self):
        return {}


if __name__ == "__main__":
    print(f"[proofread] Starting. Model: {MODEL}", flush=True)
    runner = ProofreadRunner()
    GLib.MainLoop().run()