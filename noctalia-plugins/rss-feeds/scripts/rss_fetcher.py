#!/usr/bin/env python3
"""RSS/Atom fetcher for the Noctalia rss-feeds plugin.

Called by service.luau as:  rss_fetcher.py <limit> <url1> [url2 ...]
Prints one JSON object:
  {"feeds": [{"url","title":<feed's own title or null>,"items":[{title,link,time}],"error":<msg or null>} ...],
   "status": "ok" | "partial" | "error"}
Time is a unix timestamp (0 when unknown). Items are newest first, at most
<limit> per feed. Exits 0 even on per-feed failures (status carries that);
exits 3 only on bogus usage.
"""

import email.utils
import json
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

UA = "noctalia-rss-feeds/1.0 (desktop widget)"
TIMEOUT = 12


def local_name(tag):
    return tag.rsplit("}", 1)[-1] if tag else ""


def find_by_name(body, what):
    """Namespace-aware find: first child element whose localname matches."""
    if body is None:
        return None
    if local_name(body.tag) == what:
        return body
    for child in body:
        if local_name(child.tag) == what:
            return child
    return None


def iter_named(root, what):
    def walk(node):
        for child in node:
            if local_name(child.tag) == what:
                yield child
            yield from walk(child)
    yield from walk(root)


def text_of(body, what):
    found = find_by_name(body, what)
    if found is None:
        return ""
    return strip_markup((found.text or "").strip())


def strip_markup(text):
    if not text:
        return ""
    if "<" in text:
        text = re.sub(r"<[^>]+>", " ", text)
    # collapse html entities of a few common shapes without depending on html5
    text = re.sub(r"&#x?[0-9a-fA-F]+;", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def parse_time(raw):
    from datetime import datetime, timezone
    import calendar
    if not raw:
        return 0
    raw = raw.strip()
    stamped = None
    try:
        stamped = email.utils.parsedate_to_datetime(raw)
    except Exception:
        stamped = None
    if stamped is None:
        for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
            try:
                stamped = datetime.strptime(raw, fmt)
                break
            except ValueError:
                continue
    if stamped is None:
        try:
            stamped = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            stamped = None
    if stamped is None:
        return 0
    if stamped.tzinfo is None:
        stamped = stamped.replace(tzinfo=timezone.utc)
    return max(0, int(stamped.timestamp()))


def rss_items(root, limit):
    channel = find_by_name(root, "channel")
    feed_title = text_of(channel, "title")
    items = []
    for item in iter_named(root, "item"):
        title = text_of(item, "title")
        link = text_of(item, "link")
        if not link:
            enclosure = find_by_name(item, "enclosure")
            if enclosure is not None:
                link = enclosure.attrib.get("url", "")
        published = parse_time(text_of(item, "pubDate"))
        if title and link:
            items.append({"title": title, "link": link, "time": published})
        if len(items) >= limit * 3:
            break
    items.sort(key=lambda entry: entry["time"], reverse=True)
    return feed_title, items[:limit]


def atom_items(root, limit):
    feed_title = text_of(root, "title")
    items = []
    for entry in root:
        if local_name(entry.tag) != "entry":
            continue
        title = text_of(entry, "title")
        link = ""
        fallback = ""
        for child in entry:
            if local_name(child.tag) == "link":
                fallback = fallback or child.attrib.get("href", "")
                if child.attrib.get("rel", "alternate") == "alternate":
                    link = link or child.attrib.get("href", "")
        link = link or fallback
        published = parse_time(text_of(entry, "published") or text_of(entry, "updated"))
        if title and link.startswith("http"):
            items.append({"title": title, "link": link, "time": published})
        if len(items) >= limit * 3:
            break
    items.sort(key=lambda entry: entry["time"], reverse=True)
    return feed_title, items[:limit]


def fetch(url, limit):
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            raw = response.read(4 * 1024 * 1024)
        decoded = ET.fromstring(raw)
        name = local_name(decoded.tag)
        if name in ("rss", "rdf"):
            feed_title, items = rss_items(decoded, limit)
        elif name == "feed":
            feed_title, items = atom_items(decoded, limit)
        else:
            wrap = next((el for el in decoded.iter() if local_name(el.tag) in ("rss", "rdf", "feed")), None)
            if wrap is None:
                return {"items": [], "error": "unbekanntes Format"}
            feed_title, items = (atom_items if local_name(wrap.tag) == "feed" else rss_items)(wrap, limit)
        return {"items": items, "error": None, "title": feed_title}
    except urllib.error.HTTPError as exc:
        return {"items": [], "error": f"HTTP {exc.code}"}
    except (urllib.error.URLError, OSError, ET.ParseError) as exc:
        return {"items": [], "error": str(exc)}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"feeds": [], "status": "ok"}))
        return
    try:
        limit = max(1, min(30, int(sys.argv[1])))
    except ValueError:
        print(json.dumps({"feeds": [], "status": "ok"}))
        return
    feeds = []
    for url in sys.argv[2:]:
        entry = {"url": url, "title": None, "items": [], "error": None}
        if url.startswith("http://") or url.startswith("https://"):
            result = fetch(url, limit)
            entry["items"] = result["items"]
            entry["title"] = result.get("title")
            entry["error"] = result.get("error")
        else:
            entry["error"] = "keine http(s)-URL"
        feeds.append(entry)
    failed = sum(1 for feed in feeds if feed["error"])
    status = "ok" if not failed else ("error" if failed == len(feeds) else "partial")
    print(json.dumps({"feeds": feeds, "status": status}, ensure_ascii=False))


if __name__ == "__main__":
    main()
