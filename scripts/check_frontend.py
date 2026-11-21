#!/usr/bin/env python3
"""Dependency-free static checks for Northstar's single-file frontend."""
from html.parser import HTMLParser
from pathlib import Path
import subprocess
import tempfile

HTML = Path("index.html")
if not HTML.is_file():
    raise SystemExit("FAIL: index.html not found")
source = HTML.read_text(encoding="utf-8")

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.external = False
        self.parts = []
        self.current = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script":
            self.in_script = True
            self.external = any(k.lower() == "src" for k, _ in attrs)
            self.current = []

    def handle_data(self, data):
        if self.in_script and not self.external:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.in_script:
            if not self.external:
                self.parts.append("".join(self.current))
            self.in_script = False
            self.external = False

parser = InlineScripts()
parser.feed(source)
if not parser.parts:
    raise SystemExit("FAIL: no inline JavaScript blocks found")

for number, js in enumerate(parser.parts, 1):
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as tmp:
        tmp.write(js)
        tmp.flush()
        result = subprocess.run(
            ["node", "--check", tmp.name],
            text=True,
            capture_output=True,
        )
        if result.returncode:
            print(result.stderr)
            raise SystemExit(f"FAIL: inline script block {number} has a syntax error")

required = {
    "delegated product delete handler": "productRows.addEventListener('click'",
    "product action data attribute": 'data-action="delete-product"',
    "UUID format validation": "!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(id)",
    "user-scoped product deletion": ".eq('user_id',currentUser.id)",
}
for label, token in required.items():
    if token not in source:
        raise SystemExit(f"FAIL: missing invariant: {label}")

print(f"PASS: parsed HTML and checked {len(parser.parts)} inline JavaScript block(s)")
print("PASS: product deletion retains delegated handling, UUID validation, and user scoping")
