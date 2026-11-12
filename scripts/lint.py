#!/usr/bin/env python3 -I
"""Cra's own lint: the bug classes that kept shipping, as rules over Sources/Cra and CraCore.

Existing code is grandfathered in Tests/lint-baseline.txt (rule, file, count); a file that
gains a finding fails, one that loses one is reported so the baseline can come down
(scripts/lint.py --update-baseline). Rules:

  layer-colour-outside-transaction
      A colour or opacity set on a CALayer Cra made itself (not a view's backing layer)
      outside CATransaction.begin()/commit() with actions disabled animates for 0.25 s:
      a flash on every theme or window-activation change. Inits are exempt (not on screen), and
      so is a layer whose `actions` map the property to NSNull().
  timer-outside-scheduler
      Timer.scheduledTimer in App/ or Services/: decisions taken from time run on the
      injectable clock (Scheduler), or no test can reach them. UI animation timers are exempt.
  wall-clock-in-decision
      Date() in a file whose decisions run on the clock (store, tab sleep, live folders).
  raw-observation-tracking
      withObservationTracking reached directly. The closure must read properties of an
      @Observable class; a struct copied out before it (or a plain class) is never tracked and
      the view silently stops updating. New sites go through CraCore's observeChanges(of:apply:),
      where that is reviewed once.
  importer-without-fixture
      An importer (enum …Importer) without a checked-in profile under Tests/Fixtures/<Name>:
      parsers are tested against files in the source browser's format, not dictionaries.
  app-icon-without-png
      An AppIconManager preset without resources/app-icons/<id>.png (scripts/make-app-icons.swift
      writes them): the picker would show an empty tile and the Dock would keep the old icon.
  app-icon-size
      A resources/app-icons PNG that isn't 512×512 px. The generator once followed the display's
      scale and wrote 256 px icons on a 1x screen, which the Dock would draw blurry.
  app-icon-grid
      An app icon whose tile isn't on Apple's icon grid (824 of 1024 px, centred, clear around
      it): each image in resources/AppIcon.icns and each resources/app-icons PNG. AppIcon.icns
      was drawn edge to edge: Finder and the idle Dock fit it onto the grid themselves, but where
      the running app's tile drew the file as it is, Cra stood a fifth larger than Arc beside it
      (11 Nov 2026). scripts/make-app-icons.swift writes them all.
  core-platform-import
      Packages/CraCore importing AppKit, Cocoa, SwiftUI, UIKit or CraCEF. The core is models and
      decisions that build and test without a window or Chromium (#51); what needs one stays in
      the app, with the pure part in CraCore (Shortcut over KeyChord, FaviconCache over FaviconKey).
  perf-no-network
      Networking (URLSession, CFNetwork, Network.framework, sockets) under either Perf folder: the
      performance recorder never sends anything anywhere (#91); the export is the user's to share.
  sidebar-responsive-scrolling
      A plain NSScrollView() under UI/Sidebar. AppKit's responsive scrolling takes a gesture's
      events off the window's scroll monitor once it starts over such a view, so a space or
      Library swipe begun there never arrives, or loses its end and stays between two pages (the
      Library's Downloads list, 9 Nov 2026). Use SidebarListScrollView, which opts out.
  perf-boundary
      The performance recorder stays removable (#91, docs/performance.md): outside its two folders
      only the files in PERF_CALLERS reach it, and inside Sources/Cra/Perf only PerfCEF.swift sees
      Chromium (CraCEF), so the facade and recorder compile in the test harnesses.
"""
import collections
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources", "Cra")
CORE = os.path.join(ROOT, "Packages", "CraCore", "Sources")
BASELINE = os.path.join(ROOT, "Tests", "lint-baseline.txt")

LAYER_SET = re.compile(r"\b(?!layer\b)(\w*[Ll]ayer)\.(backgroundColor|borderColor|colors|opacity|shadowColor|fillColor|strokeColor)\s*=")
FUNC_START = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:private|fileprivate|internal|public|override|static|final|class|nonisolated|convenience|required|@objc)\s+)*(func\s|init[(?!])")
CORE_IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(AppKit|Cocoa|SwiftUI|UIKit|CraCEF)\b")
PERF_DIRS = ("Perf/",)
PERF_CORE = os.path.join("Packages", "CraCore", "Sources", "CraCore", "Perf") + os.sep
PERF_CALLERS = {"App/main.swift", "App/AppDelegate.swift", "Services/BrowserManager.swift", "Services/Persistence.swift",
                "Services/HitchMonitor.swift", "Services/Diagnostics.swift", "Services/ExtensionActions.swift",
                "UI/Settings/SettingsWindowController.swift"}
PERF_NAME = re.compile(r"\b(?:Perf(?:[A-Z]\w*)?|PerformancePane)\b")
NETWORK = re.compile(r"\bURLSession\b|\bCFNetwork\b|\bNWConnection\b|\bNWPathMonitor\b|^\s*import\s+Network\b|\bCFSocket\w*|\bCFStream\w*|\bsocket\(")
CLOCK_FILES = {"Services/SidebarStore.swift", "Services/BrowserManager.swift", "Services/LiveFolderManager.swift",
               "Services/SidebarIntegrity.swift", "App/AppComposition.swift"}


def swift_files():
    for dirpath, _, names in os.walk(SOURCES):
        for n in sorted(names):
            if n.endswith(".swift"):
                full = os.path.join(dirpath, n)
                yield os.path.relpath(full, SOURCES), full


def code(line):
    """The line without a trailing // comment (good enough: no rule matches inside strings)."""
    return line.split("//", 1)[0]


def findings():
    out = collections.Counter()
    where = collections.defaultdict(list)

    def hit(rule, rel, lineno):
        out[(rule, rel)] += 1
        where[(rule, rel)].append(lineno)

    for rel, full in swift_files():
        with open(full, encoding="utf-8") as f:
            lines = f.readlines()
        depth, in_init = 0, False
        top = rel.split("/", 1)[0]
        # Layers with the animation turned off for good: fillLayer.actions = ["backgroundColor": NSNull(), …]
        quiet = {(name, prop) for name, body in re.findall(r"\b(\w+)\.actions\s*=\s*\[([^\]]*)\]", "".join(lines))
                 for prop in re.findall(r'"(\w+)"\s*:\s*NSNull\(\)', body)}
        for i, raw in enumerate(lines, 1):
            line = code(raw)
            m = FUNC_START.match(line)
            if m:
                depth, in_init = 0, m.group(1).startswith("init")
            depth += line.count("CATransaction.begin()") - line.count("CATransaction.commit()")
            for m in LAYER_SET.finditer(line):
                if depth <= 0 and not in_init and "setDisableActions" not in line and (m.group(1), m.group(2)) not in quiet:
                    hit("layer-colour-outside-transaction", rel, i)
            if "Timer.scheduledTimer" in line and top in ("App", "Services") and rel != "Services/Scheduler.swift":
                hit("timer-outside-scheduler", rel, i)
            if rel in CLOCK_FILES and re.search(r"\bDate\(\)", line):
                hit("wall-clock-in-decision", rel, i)
            if "withObservationTracking" in line:
                hit("raw-observation-tracking", rel, i)
            if rel.startswith(PERF_DIRS):
                if NETWORK.search(line):
                    hit("perf-no-network", rel, i)
                if CORE_IMPORT.match(line) and re.search(r"\bCraCEF\b", line) and rel != "Perf/PerfCEF.swift":
                    hit("perf-boundary", rel, i)
            elif rel not in PERF_CALLERS and PERF_NAME.search(line):
                hit("perf-boundary", rel, i)
            if rel.startswith("UI/Sidebar/") and re.search(r"\bNSScrollView\(\)", line):
                hit("sidebar-responsive-scrolling", rel, i)
            for name in re.findall(r"\benum (\w+)Importer\b", line):
                if not os.path.isdir(os.path.join(ROOT, "Tests", "Fixtures", name)):
                    hit("importer-without-fixture", f"{rel}:{name}", i)
            if rel == "Services/AppIconManager.swift":
                for icon in re.findall(r'\bOption\(id: "(\w+)"', line):
                    if not os.path.isfile(os.path.join(ROOT, "resources", "app-icons", f"{icon}.png")):
                        hit("app-icon-without-png", f"{rel}:{icon}", i)
    icons = os.path.join(ROOT, "resources", "app-icons")
    for n in sorted(os.listdir(icons)) if os.path.isdir(icons) else []:
        if n.endswith(".png"):
            with open(os.path.join(icons, n), "rb") as f:
                data = f.read()
            if data[12:16] != b"IHDR" or data[16:24] != (512).to_bytes(4, "big") * 2:
                hit("app-icon-size", f"resources/app-icons/{n}", 1)
            if not on_icon_grid(data):
                hit("app-icon-grid", f"resources/app-icons/{n}", 1)
    bundled = os.path.join(ROOT, "resources", "AppIcon.icns")
    if os.path.isfile(bundled):
        with open(bundled, "rb") as f:
            for kind, png in icns_pngs(f.read()):
                if not on_icon_grid(png):
                    hit("app-icon-grid", f"resources/AppIcon.icns:{kind}", 1)
    for dirpath, _, names in os.walk(CORE):
        for n in sorted(names):
            if n.endswith(".swift"):
                full = os.path.join(dirpath, n)
                with open(full, encoding="utf-8") as f:
                    for i, line in enumerate(f, 1):
                        if CORE_IMPORT.match(code(line)):
                            hit("core-platform-import", os.path.relpath(full, ROOT), i)
                        if os.path.relpath(full, ROOT).startswith(PERF_CORE) and NETWORK.search(code(line)):
                            hit("perf-no-network", os.path.relpath(full, ROOT), i)
    return out, where


def load_baseline():
    base = collections.Counter()
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    rule, rel, n = line.rstrip("\n").split("\t")
                    base[(rule, rel)] = int(n)
    return base


def icns_pngs(data):
    """The PNG images in an .icns file, with their chunk types (the 16 and 32 px ARGB ones aren't PNG)."""
    out, i = [], 8
    while i + 8 <= len(data):
        kind, length = data[i:i + 4], struct.unpack(">I", data[i + 4:i + 8])[0]
        if length < 8:
            break
        body = data[i + 8:i + length]
        if body[:8] == b"\x89PNG\r\n\x1a\n":
            out.append((kind.decode("latin-1"), body))
        i += length
    return out


def png_alpha_rows(data):
    """Width, height and each row's alpha bytes of an 8-bit RGBA, non-interlaced PNG; None otherwise."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    i, idat, head = 8, [], None
    while i + 8 <= len(data):
        length, kind = struct.unpack(">I", data[i:i + 4])[0], data[i + 4:i + 8]
        chunk = data[i + 8:i + 8 + length]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
        i += 12 + length
    if not head or head[2:5] != (8, 6, 0) or head[6] != 0:
        return None
    w, h = head[0], head[1]
    raw, stride, rows, prev = zlib.decompress(b"".join(idat)), w * 4, [], bytearray(w * 4)
    for y in range(h):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if kind == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 255
        elif kind == 2:
            line = bytearray((a + b) & 255 for a, b in zip(line, prev))
        elif kind == 3:
            for x in range(stride):
                line[x] = (line[x] + ((line[x - 4] if x >= 4 else 0) + prev[x]) // 2) & 255
        elif kind == 4:
            for x in range(stride):
                a, b, c = (line[x - 4] if x >= 4 else 0), prev[x], (prev[x - 4] if x >= 4 else 0)
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line[3::4])
        prev = line
    return w, h, rows


def on_icon_grid(png):
    """Whether the icon's more-than-half-opaque part is Apple's tile: 824/1024 of the canvas each
    way, centred."""
    read = png_alpha_rows(png)
    if not read:
        return False
    w, h, rows = read
    xs = [x for row in rows for x in (next((i for i, a in enumerate(row) if a > 127), None),
                                       next((w - 1 - i for i, a in enumerate(reversed(row)) if a > 127), None))
          if x is not None]
    ys = [y for y, row in enumerate(rows) if max(row) > 127]
    if not xs or not ys:
        return False
    slack = max(1.5, w * 0.012)
    def fits(lo, hi, n):
        return abs((hi - lo + 1) - n * 824 / 1024) <= slack and abs(lo - (n - 1 - hi)) <= slack
    return fits(min(xs), max(xs), w) and fits(min(ys), max(ys), h)


def main():
    found, where = findings()
    if "--update-baseline" in sys.argv:
        with open(BASELINE, "w", encoding="utf-8") as f:
            f.write("# scripts/lint.py findings in code older than the rule. Only ever lower these.\n")
            for (rule, rel), n in sorted(found.items()):
                f.write(f"{rule}\t{rel}\t{n}\n")
        print(f"Baseline: {sum(found.values())} findings in {len(found)} files")
        return 0
    base = load_baseline()
    failed = False
    for key, n in sorted(found.items()):
        if n > base.get(key, 0):
            failed = True
            rule, rel = key
            lines = ", ".join(map(str, where[key]))
            path = rel.split(":")[0]
            print(f"{path if path.startswith(('Packages/', 'resources/')) else 'Sources/Cra/' + path}: {rule}: {n} (baseline {base.get(key, 0)}), lines {lines}")
    lower = [(k, base[k], found.get(k, 0)) for k in sorted(base) if found.get(k, 0) < base[k]]
    for (rule, rel), was, now in lower:
        print(f"note: {rel}: {rule} down from {was} to {now}; run scripts/lint.py --update-baseline")
    if failed:
        print("lint: new findings (see the rule descriptions at the top of scripts/lint.py)")
        return 1
    print(f"lint: clean ({sum(found.values())} grandfathered findings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
