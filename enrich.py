#!/usr/bin/env python3
"""Adds pictures to an Ai.N edition.

    python3 -I enrich.py editions/2026-11-13.json

- For each story without an "image", reads the article's og:image / twitter:image
  and saves it to editions/images/<date>/<n>.<ext>.
- Adds a "funnies" list with the latest xkcd and Joy of Tech strips, skipping any
  strip an earlier edition already ran.
Standard library only. Safe to re-run: existing images are kept.
"""
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
EXT = {"image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif"}
MAX_PAGE = 3_000_000
MAX_IMAGE = 10_000_000


def fetch(url, limit):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=15) as r:
        ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        data = r.read(limit + 1)
        if len(data) > limit:
            raise ValueError("too large")
        return data, ctype, r.geturl()


def meta_image(page, base):
    text = page.decode("utf-8", "ignore")
    for tag in re.findall(r"<meta\b[^>]*>", text, re.I):
        prop = re.search(r'(?:property|name)\s*=\s*["\']([^"\']+)["\']', tag, re.I)
        content = re.search(r'content\s*=\s*["\']([^"\']+)["\']', tag, re.I)
        if prop and content and prop.group(1).lower() in ("og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"):
            return urllib.parse.urljoin(base, html.unescape(content.group(1).strip()))
    return None


def save_image(url, dest_stem):
    """Downloads url to dest_stem.<ext>; returns the Path or None."""
    data, ctype, _ = fetch(url, MAX_IMAGE)
    ext = EXT.get(ctype)
    if not ext:
        # Some CDNs send octet-stream; trust the file signature instead.
        sig = {b"\xff\xd8\xff": "jpg", b"\x89PNG": "png", b"GIF8": "gif", b"RIFF": "webp"}
        ext = next((e for s, e in sig.items() if data.startswith(s)), None)
    if not ext or len(data) < 2_000:  # skip tracking pixels / tiny logos
        return None
    path = dest_stem.with_suffix("." + ext)
    path.write_bytes(data)
    return path


def story_images(edition, root, img_dir):
    for i, s in enumerate(edition["stories"], 1):
        existing = s.get("image")
        if existing and (root / existing).exists():
            continue
        try:
            page, _, final = fetch(s["url"], MAX_PAGE)
            src = meta_image(page, final)
            if not src:
                print(f"  {i:2} no image      {s['source']}")
                continue
            path = save_image(src, img_dir / f"{i:02d}")
            if path:
                s["image"] = str(path.relative_to(root))
                print(f"  {i:2} image         {s['source']}")
            else:
                print(f"  {i:2} unusable img  {s['source']}")
        except Exception as e:  # network errors, blocks, timeouts
            print(f"  {i:2} skipped ({type(e).__name__})  {s['source']}")


def previous_funnies(root, date):
    seen = set()
    for f in sorted(root.glob("*.json")):
        if f.stem >= date:
            continue
        try:
            for c in json.loads(f.read_text()).get("funnies", []):
                seen.add(c.get("url"))
        except Exception:
            pass
    return seen


def latest_xkcd():
    data, _, _ = fetch("https://xkcd.com/info.0.json", MAX_PAGE)
    j = json.loads(data)
    return {"name": "xkcd", "credit": "Randall Munroe", "title": j["safe_title"],
            "caption": j.get("alt", ""), "url": f"https://xkcd.com/{j['num']}/", "src": j["img"]}


def latest_joy_of_tech():
    feed, _, _ = fetch("https://www.joyoftech.com/joyoftech/jotblog/index.xml", MAX_PAGE)
    link = re.search(r'rdf:li rdf:resource="([^"]+)"', feed.decode("utf-8", "ignore")).group(1)
    page, _, final = fetch(link, MAX_PAGE)
    text = page.decode("latin-1", "ignore")
    num = re.search(r"/(\d+b?)\.html", link).group(1)
    img = re.search(r'<img[^>]+src="([^"]*joyimages/%s\.(?:png|gif|jpg))"' % re.escape(num), text, re.I)
    title = re.search(r"<title>The Joy of Tech comic\.\.\.\s*(.*?)</title>", text, re.I | re.S)
    if not img:
        raise ValueError("comic image not found")
    return {"name": "The Joy of Tech", "credit": "Nitrozac & Snaggy",
            "title": html.unescape(title.group(1).strip().rstrip(".")) if title else "The Joy of Tech",
            "caption": "", "url": link, "src": urllib.parse.urljoin(final, img.group(1))}


def funnies(edition, root, img_dir):
    seen = previous_funnies(root, edition["date"])
    have = {c.get("url") for c in edition.get("funnies", [])}
    out = list(edition.get("funnies", []))
    for name, getter in (("xkcd", latest_xkcd), ("joyoftech", latest_joy_of_tech)):
        try:
            c = getter()
            if c["url"] in seen or c["url"] in have:
                print(f"  {name}: already ran")
                continue
            path = save_image(c.pop("src"), img_dir / f"comic-{name}")
            if path:
                c["image"] = str(path.relative_to(root))
                out.append(c)
                print(f"  {name}: {c['title']}")
        except Exception as e:
            print(f"  {name}: skipped ({type(e).__name__}: {e})")
    edition["funnies"] = out


def main():
    path = Path(sys.argv[1]).resolve()
    root = path.parent            # editions/
    edition = json.loads(path.read_text())
    img_dir = root / "images" / edition["date"]
    img_dir.mkdir(parents=True, exist_ok=True)
    # Image paths in the JSON are relative to editions/.
    print("Story images:")
    story_images(edition, root, img_dir)
    print("Funnies:")
    funnies(edition, root, img_dir)
    path.write_text(json.dumps(edition, indent=2, ensure_ascii=False) + "\n")
    n = sum(1 for s in edition["stories"] if s.get("image"))
    print(f"Done: {n}/{len(edition['stories'])} stories with images, {len(edition.get('funnies', []))} comics")


if __name__ == "__main__":
    main()
