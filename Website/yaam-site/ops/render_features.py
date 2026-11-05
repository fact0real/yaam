"""Regenerate the static capability directory from features.json; no dependencies."""
from pathlib import Path
import html
import json
import re

root = Path(__file__).resolve().parent.parent
groups = json.loads((root / "features.json").read_text())
sections = []
for number, group in enumerate(groups, 1):
    items = "".join(
        '<article class="feature-item"><h4>' + html.escape(item["title"])
        + '</h4><p>' + html.escape(item["description"]) + '</p></article>'
        for item in group["items"]
    )
    opened = " open" if number == 1 else ""
    sections.append(
        f'<details class="feature-group" id="feature-{group["id"]}"{opened}>'
        f'<summary><span class="feature-number">{number:02}</span>'
        '<span class="feature-summary-copy"><strong>' + html.escape(group["title"])
        + '</strong><small>' + html.escape(group["subtitle"]) + '</small></span>'
        f'<span class="feature-count">{len(group["items"]):02} CAPABILITIES</span>'
        '<span class="detail-plus" aria-hidden="true">+</span></summary>'
        f'<div class="feature-items">{items}</div></details>'
    )
page = root / "index.html"
content, count = re.subn(
    r'(<div id="feature-directory">).*?(</div><p id="no-features")',
    lambda match: match[1] + "\n".join(sections) + match[2],
    page.read_text(), flags=re.S,
)
if count != 1:
    raise SystemExit("Expected exactly one feature directory; no files changed")
page.write_text(content)
print(f"Rendered {sum(len(group['items']) for group in groups)} capabilities")
