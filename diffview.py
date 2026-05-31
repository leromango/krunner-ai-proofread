#!/usr/bin/env python3
import sys
import difflib
import subprocess
import requests
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QFrame, QTextBrowser
)
from PyQt6.QtCore import QThread, pyqtSignal, Qt, QUrl
from PyQt6.QtGui import QFont

OLLAMA_BASE = "http://localhost:11434"
MODEL = "gemma4:e2b"


def word_diff_html(original, corrected):
    orig_words = original.split()
    corr_words = corrected.split()
    matcher = difflib.SequenceMatcher(None, orig_words, corr_words)
    parts = []
    i = 0
    for op, a1, a2, b1, b2 in matcher.get_opcodes():
        if op == "equal":
            parts.append(" ".join(corr_words[b1:b2]).replace("&", "&amp;").replace("<", "&lt;"))
        elif op == "replace":
            for idx, (orig, corr) in enumerate(zip(orig_words[a1:a2], corr_words[b1:b2])):
                enc_orig = orig.replace("&", "&amp;").replace("<", "&lt;")
                enc_corr = corr.replace("&", "&amp;").replace("<", "&lt;")
                parts.append(
                    f'<a href="change:{i}:{orig}:{corr}" style="'
                    f'background-color:#2d4a2d;color:#90ee90;'
                    f'text-decoration:none;border-radius:3px;padding:1px 4px;">'
                    f'{enc_corr}</a>'
                )
                i += 1
            extra_orig = orig_words[a1:a2][len(corr_words[b1:b2]):]
            extra_corr = corr_words[b1:b2][len(orig_words[a1:a2]):]
            for w in extra_corr:
                enc = w.replace("&", "&amp;").replace("<", "&lt;")
                parts.append(
                    f'<a href="change:{i}::{w}" style="'
                    f'background-color:#1a3a4a;color:#87ceeb;'
                    f'text-decoration:none;border-radius:3px;padding:1px 4px;">'
                    f'{enc}</a>'
                )
                i += 1
        elif op == "insert":
            for w in corr_words[b1:b2]:
                enc = w.replace("&", "&amp;").replace("<", "&lt;")
                parts.append(
                    f'<a href="change:{i}::{w}" style="'
                    f'background-color:#1a3a4a;color:#87ceeb;'
                    f'text-decoration:none;border-radius:3px;padding:1px 4px;">'
                    f'{enc}</a>'
                )
                i += 1
        elif op == "delete":
            for w in orig_words[a1:a2]:
                enc = w.replace("&", "&amp;").replace("<", "&lt;")
                parts.append(
                    f'<a href="change:{i}:{w}:" style="'
                    f'background-color:#4a1a1a;color:#ff6b6b;'
                    f'text-decoration:none;border-radius:3px;padding:1px 4px;">'
                    f'[removed: {enc}]</a>'
                )
                i += 1
    return '<p style="line-height:1.8;font-size:14px;">' + " ".join(parts) + "</p>"


class ExplainThread(QThread):
    result_ready = pyqtSignal(str)

    def __init__(self, original, corrected):
        super().__init__()
        self.original = original
        self.corrected = corrected

    def run(self):
        try:
            if self.original and self.corrected:
                prompt = f'A proofreader changed "{self.original}" to "{self.corrected}". In one short sentence, explain why.'
            elif self.original:
                prompt = f'A proofreader removed "{self.original}". In one short sentence, explain why.'
            else:
                prompt = f'A proofreader added "{self.corrected}". In one short sentence, explain why.'

            resp = requests.post(
                f"{OLLAMA_BASE}/api/chat",
                json={
                    "model": MODEL,
                    "think": False,
                    "stream": False,
                    "messages": [{"role": "user", "content": prompt}]
                },
                timeout=20
            )
            text = resp.json().get("message", {}).get("content", "").strip()
            self.result_ready.emit(text)
        except Exception as e:
            self.result_ready.emit(f"Error: {e}")


class DiffView(QWidget):
    def __init__(self, original, corrected):
        super().__init__()
        self.original = original
        self.corrected = corrected
        self.explain_thread = None
        self.setWindowTitle("Proofread Diff")
        self.setMinimumSize(700, 420)
        self._build_ui()

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        layout.setContentsMargins(16, 16, 16, 16)

        # Legend
        legend = QLabel(
            '<span style="background:#2d4a2d;color:#90ee90;padding:2px 6px;border-radius:3px;">changed</span> &nbsp;'
            '<span style="background:#1a3a4a;color:#87ceeb;padding:2px 6px;border-radius:3px;">added</span> &nbsp;'
            '<span style="background:#4a1a1a;color:#ff6b6b;padding:2px 6px;border-radius:3px;">removed</span> &nbsp;'
            '<small style="color:#888;">Click a word for an explanation.</small>'
        )
        legend.setTextFormat(Qt.TextFormat.RichText)
        layout.addWidget(legend)

        # Diff viewer
        self.browser = QTextBrowser()
        self.browser.setOpenLinks(False)
        self.browser.setFont(QFont("monospace", 13))
        self.browser.setStyleSheet("background:#1e1e1e;color:#ddd;border:1px solid #333;border-radius:6px;padding:10px;")
        self.browser.setHtml(word_diff_html(self.original, self.corrected))
        self.browser.anchorClicked.connect(self.handle_anchor_clicked)
        layout.addWidget(self.browser)

        # Explanation
        self.explanation_frame = QFrame()
        self.explanation_frame.setStyleSheet("background:#252525;border:1px solid #444;border-radius:6px;padding:8px;")
        self.explanation_frame.setVisible(False)
        exp_layout = QVBoxLayout(self.explanation_frame)
        exp_layout.setContentsMargins(8, 8, 8, 8)
        self.explanation_label = QLabel("")
        self.explanation_label.setWordWrap(True)
        self.explanation_label.setStyleSheet("color:#ccc;font-size:13px;")
        exp_layout.addWidget(self.explanation_label)
        layout.addWidget(self.explanation_frame)

        # Buttons
        btn_layout = QHBoxLayout()
        copy_btn = QPushButton("Copy Corrected Text")
        copy_btn.clicked.connect(self.copy_corrected)
        copy_btn.setFixedHeight(38)
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.close)
        close_btn.setFixedHeight(38)
        btn_layout.addWidget(copy_btn)
        btn_layout.addStretch()
        btn_layout.addWidget(close_btn)
        layout.addLayout(btn_layout)

    def handle_anchor_clicked(self, url: QUrl):
        anchor = url.toString()
        if not anchor.startswith("change:"):
            return
        parts = anchor.split(":", 3)
        if len(parts) < 4:
            return
        _, idx, orig, corr = parts
        self.explanation_label.setText("⏳ Explaining...")
        self.explanation_frame.setVisible(True)
        self.explain_thread = ExplainThread(orig, corr)
        self.explain_thread.result_ready.connect(self.show_explanation)
        self.explain_thread.start()

    def show_explanation(self, text):
        self.explanation_label.setText(f"💡 {text}")

    def copy_corrected(self):
        subprocess.run(["wl-copy", self.corrected])
        self.explanation_label.setText("✓ Copied to clipboard!")
        self.explanation_frame.setVisible(True)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: diffview.py <original> <corrected>")
        sys.exit(1)
    original = sys.argv[1]
    corrected = sys.argv[2]
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = DiffView(original, corrected)
    window.show()
    sys.exit(app.exec())
