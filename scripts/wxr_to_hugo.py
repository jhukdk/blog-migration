#!/usr/bin/env python3
"""Convert a WordPress WXR export into Hugo page-bundle Markdown.

- Each `post` becomes content/posts/<slug>/index.md (leaf bundle) with its
  images copied alongside as bundle resources and image paths rewritten to the
  local filename. The original slug is preserved so permalinks stay identical.
- The `page` ("About Me") becomes content/<slug>/index.md.
- Front matter: title, date, slug, categories, tags, draft.

Idempotent: regenerates the bundles it manages on each run.
"""
from __future__ import annotations

import re
import shutil
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from bs4 import BeautifulSoup, Comment
from markdownify import MarkdownConverter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "migration-source"
XML = SRC / "jhuktechnews.WordPress.2026-06-15.xml"
UPLOADS = SRC / "uploads"
POSTS_DIR = ROOT / "site" / "content" / "posts"
CONTENT_DIR = ROOT / "site" / "content"

NS = {
    "wp": "http://wordpress.org/export/1.2/",
    "content": "http://purl.org/rss/1.0/modules/content/",
    "dc": "http://purl.org/dc/elements/1.1/",
}

UPLOAD_RE = re.compile(r"/wp-content/uploads/(.+)$")
SIZE_SUFFIX_RE = re.compile(r"-\d+x\d+(?=\.\w+$)")


class HugoConverter(MarkdownConverter):
    """ATX headings; leave fenced code blocks without a language guess."""

    def convert_figcaption(self, el, text, parent_tags):
        text = text.strip()
        return f"\n\n*{text}*\n\n" if text else ""


def md(soup) -> str:
    return HugoConverter(heading_style="ATX", bullets="-").convert_soup(soup)


def resolve_image(src: str) -> Path | None:
    """Map a content image URL to a file in migration-source/uploads."""
    m = UPLOAD_RE.search(src)
    if not m:
        return None
    rel = m.group(1)
    candidate = UPLOADS / rel
    if candidate.exists():
        return candidate
    stripped = UPLOADS / SIZE_SUFFIX_RE.sub("", rel)
    if stripped.exists():
        return stripped
    return None


def parse_date(item) -> datetime:
    raw = item.findtext("wp:post_date_gmt", namespaces=NS)
    if not raw or raw.startswith("0000"):
        raw = item.findtext("wp:post_date", namespaces=NS)
    dt = datetime.strptime(raw.strip(), "%Y-%m-%d %H:%M:%S")
    return dt.replace(tzinfo=timezone.utc)


def taxonomies(item):
    cats, tags = [], []
    for c in item.findall("category"):
        domain, label = c.get("domain"), (c.text or "").strip()
        if not label:
            continue
        if domain == "category":
            cats.append(label)
        elif domain == "post_tag":
            tags.append(label)
    return cats, tags


def yaml_list(values) -> str:
    return "[" + ", ".join(f'"{v}"' for v in values) + "]"


def esc(s: str) -> str:
    return s.replace('"', '\\"')


def process_content(html: str, bundle_dir: Path, front_matter: str) -> int:
    """Rewrite image paths to local filenames, copy the files in, write index.md.

    Returns the number of images copied. Missing images are logged, not copied.
    """
    soup = BeautifulSoup(html, "html.parser")
    # Drop Gutenberg block comments (<!-- wp:... -->).
    for c in soup.find_all(string=lambda t: isinstance(t, Comment)):
        c.extract()

    copied = 0
    for img in soup.find_all("img"):
        src = img.get("src", "")
        resolved = resolve_image(src)
        if resolved is None:
            print(f"    WARN missing image: {src}")
            continue
        dest_name = resolved.name
        shutil.copy2(resolved, bundle_dir / dest_name)
        img["src"] = dest_name
        # WordPress emits responsive attrs that point at absolute URLs.
        for attr in ("srcset", "sizes", "class", "width", "height"):
            img.attrs.pop(attr, None)
        copied += 1

    body = md(soup).strip()
    (bundle_dir / "index.md").write_text(front_matter + "\n" + body + "\n")
    return copied


def write_item(item, dest_root: Path, is_post: bool):
    title = (item.findtext("title", namespaces=NS) or "").strip()
    slug = (item.findtext("wp:post_name", namespaces=NS) or "").strip()
    status = item.findtext("wp:status", namespaces=NS)
    dt = parse_date(item)
    cats, tags = taxonomies(item)
    html = item.findtext("content:encoded", namespaces=NS) or ""

    bundle = dest_root / slug
    if bundle.exists():
        shutil.rmtree(bundle)
    bundle.mkdir(parents=True)

    lines = ["---", f'title: "{esc(title)}"', f"date: {dt.isoformat()}", f'slug: "{slug}"']
    if cats:
        lines.append(f"categories: {yaml_list(cats)}")
    if tags:
        lines.append(f"tags: {yaml_list(tags)}")
    lines.append(f"draft: {'true' if status == 'draft' else 'false'}")
    lines.append("---")
    front_matter = "\n".join(lines)

    n = process_content(html, bundle, front_matter)
    kind = "post" if is_post else "page"
    print(f"  [{kind}] {slug}  ({dt.date()}, {n} img, draft={status=='draft'})")


def main():
    if not XML.exists():
        sys.exit(f"WXR file not found: {XML}")
    root = ET.parse(XML).getroot()
    channel = root.find("channel")
    posts = pages = 0
    for item in channel.findall("item"):
        ptype = item.findtext("wp:post_type", namespaces=NS)
        if ptype == "post":
            write_item(item, POSTS_DIR, is_post=True)
            posts += 1
        elif ptype == "page" and item.findtext("wp:status", namespaces=NS) == "publish":
            write_item(item, CONTENT_DIR, is_post=False)
            pages += 1
    print(f"\nDone: {posts} posts, {pages} page(s).")


if __name__ == "__main__":
    main()
