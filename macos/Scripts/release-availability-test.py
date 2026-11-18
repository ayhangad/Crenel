#!/usr/bin/env python3
"""Read-only acceptance test for the public download and Sparkle feed after publication."""

import json
import re
import subprocess
import sys
from xml.etree import ElementTree


def fetch(url, *, headers_only=False):
    # macOS curl uses the system trust store on the build and acceptance machines.
    args = ["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "25"]
    if headers_only:
        args.append("--head")
    return subprocess.check_output([*args, url])


def check_public_release(version):
    repo = "ayhangad/Crenel"
    name = f"Crenel-{version}.dmg"
    download = f"https://github.com/{repo}/releases/download/v{version}/{name}"
    feed_url = "https://ayhangad.github.io/Crenel/appcast.xml"
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    release = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/tags/v{version}"))
    assets = {asset["name"]: asset for asset in release["assets"]}
    if release["draft"] or release["prerelease"] or assets.get(name, {}).get("browser_download_url") != download:
        raise ValueError("Public stable DMG missing")
    if f"{name}.sha256" not in assets:
        raise ValueError("Published checksum missing")
    fetch(download, headers_only=True)
    items = ElementTree.fromstring(fetch(feed_url)).findall("./channel/item")
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None or enclosure.get("url") != download:
            continue
        short_version = item.findtext(namespace + "shortVersionString") or enclosure.get(namespace + "shortVersionString")
        if short_version == version and enclosure.get(namespace + "edSignature") and assets[name]["size"] == int(enclosure.get("length", "0")) > 0:
            return
    raise ValueError("Matching signed Sparkle feed entry missing")


if __name__ == "__main__":
    if len(sys.argv) != 2 or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", sys.argv[1]):
        sys.exit("Usage: release-availability-test.py <version>")
    try:
        check_public_release(sys.argv[1])
    except (subprocess.CalledProcessError, ValueError, KeyError, ElementTree.ParseError) as error:
        sys.exit(f"Public release acceptance pending: {error}")
    print("Public release assets and feed entry are available.")
