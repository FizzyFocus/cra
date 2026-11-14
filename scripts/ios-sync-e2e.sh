#!/bin/bash
# The Mac's folder sync read by the iPhone app, end to end (14 Nov 2026). A throwaway Pane.app
# (build/Pane.app, its own data folder, behind your windows) on a seeded sidebar syncs into
# /tmp/pane-sync-test; each write is timed as its folders, a section and Pinned open and shut
# (the synced sidebar's `layout`). Then the UI tests in SyncFolderTests read that folder in the
# Simulator, change it under the open Spaces sheet, and open slow pages from a Space. Pages come
# from a local server on 127.0.0.1:8765 (the Simulator shares the Mac's network).
#
#   scripts/ios-sync-e2e.sh          the Mac part, then the UI tests (CRA_IOS_SIM picks the simulator)
#   scripts/ios-sync-e2e.sh mac      only the Mac part; the folder and the server are left for the
#                                    UI tests (stop the server with: pkill -f pane-e2e-server.py)
#
# The installed Pane can stay open: a CRA_DATA_DIR copy has its own profile and leaves it alone.
set -uo pipefail
cd "$(dirname "$0")/.."
SYNC=/tmp/pane-sync-test
PORT=8765
APP="${CRA_APP:-build/Pane.app}"
[ -x "$APP/Contents/MacOS/Pane" ] || { echo "No Pane at $APP (just build)" >&2; exit 2; }

failed=0
check() { if [ "$1" = ok ]; then echo "  ✓ $2"; else echo "  ✗ $2"; failed=1; fi; }

# The pages: /page is at once, /slowhead answers after 8 s (nothing to draw until then), /slowbody
# sends its heading and first paragraph at once and the rest 12 s later. Long, so a slow Simulator
# still sees each state.
pkill -f pane-e2e-server.py 2>/dev/null
cat >/tmp/pane-e2e-server.py <<'PY'
import http.server, sys, time, urllib.parse
def page(t, rest=""):
    return (f"<html><head><meta name=viewport content='width=device-width'><title>{t}</title></head>"
            f"<body style='font-family:-apple-system;padding:24px'><h1>{t}</h1>{rest}")
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        t = urllib.parse.parse_qs(u.query).get("t", ["Page"])[0]
        if u.path == "/slowhead": time.sleep(8)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        if u.path == "/slowbody":
            intro = "<p>" + "The first part of an article arrives before the rest of it. " * 7 + "</p>"
            self.wfile.write(page(t, intro).encode() + b" " * 2048)
            self.wfile.flush()
            time.sleep(12)
            self.wfile.write(b"<p>The rest of the page.</p></body></html>")
        else:
            self.wfile.write((page(t) + "</body></html>").encode())
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 -I -u /tmp/pane-e2e-server.py "$PORT" >/tmp/pane-e2e-server.log 2>&1 &
SERVER=$!
for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$PORT/page" >/dev/null && break; sleep 0.1; done

# A Mac sidebar: "Personal" (purple) with a favorite, a slow pinned tab, Work holding Docs and the
# folder Specs, Today's A Story and the section Reading; "Play" (blue) with one pinned tab.
DATA="$(mktemp -d /tmp/pane-e2e-data.XXXXXX)"
rm -rf "$SYNC" && mkdir -p "$SYNC"
python3 -I - "$DATA" "$SYNC" "$PORT" <<'PY'
import datetime, json, sys
data, sync, port = sys.argv[1], sys.argv[2], sys.argv[3]
at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")  # Today tabs older than 12 h archive
def uid(kind, n): return f"{kind}0000000-0000-0000-0000-{n:012d}"
def url(path, t): return f"http://127.0.0.1:{port}/{path}?t={t}"
items = []
def item(n, parent, data, children=(), title=None, **extra):
    it = {"id": uid("D", n) if n < 100 else uid("C", n - 100), "children": [uid("D", c) for c in children],
          "createdAt": at, "isUnread": False, "data": data}
    if parent: it["parentID"] = parent
    if title: it["title"] = title
    it.update(extra)
    items.append(it)
def tab(n, parent, t, path="page"):
    u = url(path, t.replace(" ", "+"))
    item(n, parent, {"tab": {"_0": {"muted": False, "savedTitle": t, "savedURL": u, "url": u}}})
spaces = []
for s, (title, emoji, colour) in enumerate([("Personal", "🌱", "#8A57B5"), ("Play", "🎮", "#3E8EDE")]):
    sid = uid("A", s + 1)
    fav, pin, today = (uid("C", 3 * s + k) for k in (1, 2, 3))
    spaces.append({"id": sid, "title": title, "emoji": emoji, "createdAt": at,
                   "theme": {"appearance": "light", "colors": [colour], "intensity": 0.6, "noise": 0.0, "solid": False, "vibrant": False},
                   "favoritesContainerID": fav, "pinnedContainerID": pin, "todayContainerID": today})
    kids = {fav: [], pin: [], today: []}
    if s == 0:
        kids = {fav: [1], pin: [2, 3], today: [7, 8]}
    else:
        kids = {fav: [], pin: [10], today: []}
    for cid, kind in ((fav, "favorites"), (pin, "pinned"), (today, "today")):
        items.append({"id": cid, "children": [uid("D", c) for c in kids[cid]], "createdAt": at, "isUnread": False,
                      "data": {"container": {"_0": {kind: {"spaceID": sid}}}}})
p = [s["pinnedContainerID"] for s in spaces]
tab(1, spaces[0]["favoritesContainerID"], "Calendar")
tab(2, p[0], "Inbox", "slowhead")
item(3, p[0], {"folder": {}}, [4, 5], title="Work")
tab(4, uid("D", 3), "Docs")
item(5, uid("D", 3), {"folder": {}}, [6], title="Specs")
tab(6, uid("D", 5), "Spec")
tab(7, spaces[0]["todayContainerID"], "A Story", "slowbody")
item(8, spaces[0]["todayContainerID"], {"folder": {}}, [9], title="Reading", tabGroup=True)
tab(9, uid("D", 8), "A Paper")
tab(10, p[1], "Scores")
doc = {"version": 1, "spaceOrder": [s["id"] for s in spaces], "spaces": spaces, "items": items}
json.dump(doc, open(f"{data}/sidebar.json", "w"), indent=1)
json.dump({"hasSeenImportPrompt": True, "toolbarDefaultMigrated": True}, open(f"{data}/settings.json", "w"))
json.dump({"location": {"folder": {"_0": sync}}, "devices": []}, open(f"{data}/sync.json", "w"))
PY

# The synced sidebar's layout, by title: "open=Work shut=Reading pinned=Personal" (sorted).
layout() {
  python3 -I - "$SYNC/Pane/sidebar.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
names = {i["id"]: i.get("title", "?") for i in d["items"]} | {s["id"]: s["title"] for s in d["spaces"]}
l = d.get("layout")
if l is None: print("none"); sys.exit()
part = lambda k: ",".join(sorted(names.get(i, "?") for i in l.get(k, [])))
print(f"open={part('expandedFolders')} shut={part('collapsedSections')} pinned={part('collapsedPinnedSpaces')}")
PY
}

CMD="$DATA/commands"
: >"$CMD"
echo "Mac: a test copy of $APP syncing into $SYNC"
CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$CMD" CRA_TEST_BACKGROUND=1 "$APP/Contents/MacOS/Pane" >"$DATA/stdout.log" 2>&1 &
PID=$!
cleanup() {
  kill -KILL "$PID" 2>/dev/null
  [ "${KEEP_SERVER:-}" = 1 ] || kill "$SERVER" 2>/dev/null
  rm -rf "$DATA"
}
trap cleanup EXIT
for _ in $(seq 1 150); do grep -q "pid $PID reads commands" "$DATA"/cra*.log 2>/dev/null && break; sleep 0.2; done
for _ in $(seq 1 100); do [ -f "$SYNC/Pane/manifest.json" ] && break; sleep 0.1; done
now="$(layout)"
[ "$now" = "open= shut= pinned=" ] && check ok "the first bundle carries the layout ($now)" || check no "the first bundle carries the layout ($now)"

# Each change, and how long until the folder has it.
step() {
  local command="$1" want="$2" start end got
  start=$(python3 -c 'import time; print(time.time())')
  printf '%s\n' "pane://debug?$command" >>"$CMD"
  for _ in $(seq 1 100); do got="$(layout)"; [ "$got" = "$want" ] && break; sleep 0.05; done
  end=$(python3 -c 'import time; print(time.time())')
  local ms; ms=$(python3 -c "print(int(($end - $start) * 1000))")
  [ "$got" = "$want" ] && check ok "$command → $want in $ms ms" || check no "$command → $got, wanted $want"
}
step "expandFolder=Work" "open=Work shut= pinned="
step "expandFolder=Specs" "open=Specs,Work shut= pinned="
step "folder=D0000000-0000-0000-0000-000000000005,0" "open=Work shut= pinned="
step "groupAction=collapse&group=Reading" "open=Work shut=Reading pinned="
step "collapsePinned=1" "open=Work shut=Reading pinned=Personal"
step "collapsePinned=0" "open=Work shut=Reading pinned="
sleep 2.5
grep -q '"layout"' "$DATA/sidebar.json" && check no "the data folder's sidebar.json has a layout" || check ok "the data folder's sidebar.json has none"
python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print("  manifest:", m["device"], m["writtenAt"], sorted(m["files"]))' "$SYNC/Pane/manifest.json"

printf '%s\n' "pane://debug?quit=1" >>"$CMD"
for _ in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
[ "$failed" = 0 ] || { echo "Mac part failed"; exit 1; }
[ "${1:-}" = mac ] && { KEEP_SERVER=1; echo "Folder and server left for SyncFolderTests"; exit 0; }

echo "iPhone: SyncFolderTests in the Simulator"
scripts/ios.sh test CraUITests/SyncFolderTests
