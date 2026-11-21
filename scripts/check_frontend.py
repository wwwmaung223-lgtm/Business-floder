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
    "UUID format validation": "!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)",
    "user-scoped product deletion": ".eq('user_id',currentUser.id)",
    "OCR upload MIME validation": "function validateImageFile(file)",
    "10 MiB client-side upload limit": "file.size>10*1024*1024",
    "OCR cloud/local status is tracked": "let ocrNotesCloudAvailable=true",
    "OCR fallback is disclosed to the user": "OCR notes are device-local until cloud access is restored.",
    "basic order limitations are disclosed": "Basic order register only. This saves an order header;",
    "order history does not expose customer UUIDs": "customer:o.customer_id?'Linked customer':'No linked customer',item:'Order record'",

    "restricted image picker types": 'accept="image/jpeg,image/png,image/webp"',
}
for label, token in required.items():
    if token not in source:
        raise SystemExit(f"FAIL: missing invariant: {label}")

# Guard against wiring the currently unaudited POS RPC or bypassing its
# transactional workflow from browser code. These checks are deliberate release
# guardrails until the server-side sale contract has been hardened and tested.
unsafe_pos_tokens = {
    "unaudited POS RPC must not be called by browser code": "northstar_create_pos_sale",
    "order items must not be written outside the transactional sale workflow": ".from('order_items').insert",
    "stock movements must not be written directly by browser code": ".from('stock_movements').insert",
}
for label, token in unsafe_pos_tokens.items():
    if token in source:
        raise SystemExit(f"FAIL: {label}")

# The current order form is intentionally a basic order-header capture only;
# do not let static CI imply it is a complete inventory-aware POS.
if "async function orderSubmit(e)" not in source:
    raise SystemExit("FAIL: order submission handler not found")

print(f"PASS: parsed HTML and checked {len(parser.parts)} inline JavaScript block(s)")
print("PASS: product deletion retains delegated handling, UUID validation, and user scoping")
print("PASS: browser code does not call the unaudited POS RPC or bypass transactional order/stock writes")
