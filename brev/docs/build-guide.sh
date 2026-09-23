#!/usr/bin/env bash
# Build the attendee guide PDF from WORKSHOP.md (python-markdown -> HTML -> LibreOffice headless -> PDF).
# Usage: bash brev/docs/build-guide.sh     (needs: python3 -m markdown, libreoffice)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import markdown, re
md = open("WORKSHOP.md", encoding="utf-8").read()
body = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])
css = """
body { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 10.5pt; line-height: 1.35; margin: 0; }
h1 { font-size: 20pt; color: #76b900; border-bottom: 2px solid #76b900; padding-bottom: 4px; }
h2 { font-size: 14pt; color: #1a1a1a; margin-top: 18px; border-bottom: 1px solid #cccccc; }
code { font-family: 'DejaVu Sans Mono', monospace; font-size: 9.5pt; background: #f2f2f2; }
pre { background: #f2f2f2; border: 1px solid #d0d0d0; padding: 6px; font-size: 9pt; }
table { border-collapse: collapse; width: 100%; font-size: 9.5pt; }
th, td { border: 1px solid #bbbbbb; padding: 4px 6px; vertical-align: top; }
th { background: #e9f3d6; }
img { width: 560px; border: 1px solid #cccccc; }
"""
html = f"<!DOCTYPE html><html><head><meta charset='utf-8'><title>Trakr Newton workshop guide</title><style>{css}</style></head><body>{body}</body></html>"
open("Trakr-Newton-Workshop-Guide.html", "w", encoding="utf-8").write(html)
print("html ok")
PY
soffice --headless --convert-to pdf --outdir brev/docs Trakr-Newton-Workshop-Guide.html >/dev/null 2>&1
rm -f Trakr-Newton-Workshop-Guide.html
ls -la brev/docs/Trakr-Newton-Workshop-Guide.pdf
