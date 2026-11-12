#!/usr/bin/env python3
"""What became of every upstream (VictorKildahl/cra) commit since main forked: the check behind
UPSTREAM_SYNC.md. Pane ports upstream commit by commit and never merges it, so nothing in git
says which commits are in; this does.

  scripts/upstream-audit.py              every upstream commit since the merge base, with its status
  scripts/upstream-audit.py --new        only the ones UPSTREAM_SYNC.md doesn't account for yet
  scripts/upstream-audit.py --conflicts  also dry-run each unported one onto main (git merge-tree,
                                         nothing written) and list the files it would conflict in

Run `git fetch upstream` first. A commit counts as
  ported     main has a `(cherry picked from commit <sha>)` trailer for it (git cherry-pick -x), a
             message naming it ("after upstream <sha>", "hand-port of upstream <sha>"), the same
             patch, or UPSTREAM_SYNC.md lists it under Ported
  skipped    UPSTREAM_SYNC.md lists it under Skipped
  pending    UPSTREAM_SYNC.md lists it under Pending (triaged, waiting for a decision)
  NEW        none of those: triage it and add it to UPSTREAM_SYNC.md
Exits 1 when a NEW commit exists, so a reminder can run it.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYNC = os.path.join(ROOT, "UPSTREAM_SYNC.md")
UPSTREAM = "upstream/main"


def git(*args, check=True):
    r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r


def sync_file_sections():
    """SHAs per top-level section of UPSTREAM_SYNC.md (Ported / Skipped / Pending): the first
    column of each table row."""
    sections, current = {}, None
    if not os.path.isfile(SYNC):
        return sections
    for line in open(SYNC, encoding="utf-8"):
        m = re.match(r"^## (\w+)", line)
        if m:
            current = m.group(1).lower()
            continue
        m = re.match(r"^\|\s*`?([0-9a-f]{7,40})`?", line)
        if m and current:
            sections.setdefault(current, set()).add(m.group(1))
    return sections


def patch_ids(rev_range):
    log = subprocess.run(["git", "-C", ROOT, "log", "-p", "--no-merges", rev_range], capture_output=True)
    out = subprocess.run(["git", "-C", ROOT, "patch-id", "--stable"], input=log.stdout, capture_output=True).stdout.decode()
    return {line.split()[1]: line.split()[0] for line in out.splitlines() if line.strip()}


def main():
    only_new = "--new" in sys.argv
    conflicts = "--conflicts" in sys.argv
    base = git("merge-base", "main", UPSTREAM).stdout.strip()
    named = {}
    for rec in git("log", "--format=%h%x09%B%x00", f"{base}..main").stdout.split("\0"):
        sha, _, body = rec.strip().partition("\t")
        for m in re.finditer(r"cherry picked from commit ([0-9a-f]{7,40})"
                             r"|\bupstream\s+(?:commit\s+)?([0-9a-f]{7,40})\b", body):
            named.setdefault(m.group(1) or m.group(2), sha)
    ours = set(patch_ids(f"{base}..main").values())
    theirs = patch_ids(f"{base}..{UPSTREAM}")
    listed = sync_file_sections()

    def status(full):
        for short, where in named.items():
            if full.startswith(short):
                return "ported", where
        if theirs.get(full) in ours:
            return "ported", "same patch"
        for section in ("ported", "skipped", "pending"):
            if any(full.startswith(s) for s in listed.get(section, ())):
                return section, ""
        return "NEW", ""

    new = 0
    for line in git("log", "--reverse", "--no-merges", "--format=%H%x09%s", f"{base}..{UPSTREAM}").stdout.splitlines():
        full, subject = line.split("\t", 1)
        kind, where = status(full)
        new += kind == "NEW"
        if only_new and kind != "NEW":
            continue
        extra = f" ({where})" if where else ""
        if conflicts and kind in ("NEW", "pending"):
            r = git("merge-tree", "--write-tree", "--name-only", "--no-messages", f"--merge-base={full}^", "main", full, check=False)
            files = [f for f in r.stdout.splitlines()[1:] if f]
            extra += "  clean" if r.returncode == 0 else "  conflicts: " + " ".join(files)
        print(f"{full[:7]}  {kind:8} {subject[:100]}{extra}")
    print(f"upstream {git('rev-parse', '--short', UPSTREAM).stdout.strip()}, merge base {base[:7]}: {new} NEW", file=sys.stderr)
    sys.exit(1 if new else 0)


if __name__ == "__main__":
    main()
