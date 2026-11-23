#!/usr/bin/env python3
"""Docs-loop metrics snapshot: M1 boot context and M2 corpus size.

Usage: python3 scripts/docs-loop-metrics.py [--db PATH] [--repo PATH]
          [--match SUBSTRING] [--since YYYY-MM-DD] [--until YYYY-MM-DD]
          [--global-instructions PATH]

Prints a markdown snapshot to stdout (ASCII only). Stdlib only. Both
inputs are read-only: the database is opened with mode=ro and git is
queried without touching the worktree.

M1 -- boot context. For every session that booted under THIS
repository's rules: the prompt tokens of its FIRST assistant message
(input + cache read + cache write), median per ISO week (local time),
leads (no parent_id) and subagents (parent_id set) apart. The
`tokens.input` figure alone is the UNCACHED part of the prompt -- a
prompt-cache hit on the first message shrinks it -- so the table also
carries the uncached and the cache-read medians.

A session counts as a REPO session when its instruction record shows
exactly one AGENTS.md of its own -- <working directory>/AGENTS.md --
besides the global user file: none from an ancestor directory (a
workspace-level AGENTS.md) and none from a subdirectory. Every other
session is excluded and counted, per week, in the excluded table.
Read (opencode.db V2): session_v2(id, parent_id, directory,
time_created), session_message(session_id, type, seq, data),
instruction_state(session_id, initial_values) and
instruction_blob(hash, value) -- keys core/environment (the working
directory) and core/instructions (the loaded files, path + content).
Sessions are selected by --match (default: the origin remote's
repository name) in session_v2.directory, an SQL LIKE match:
case-insensitive, with _ and % in the value acting as wildcards. The
working directory is read up to its first space -- one that contains a
space is not recognized, and its sessions count as having no AGENTS.md
of their own.

M2 -- corpus size. AGENTS.md, agent/*.md and the rule-meta count at
HEAD, and the same per ISO week from git history, read on the
first-parent chain: the last commit at or before each week's end whose
tree differs from its first parent in AGENTS.md, agent/ or
internal/rules-meta. A side-branch commit counts from its merge, never
from its own date (needs a full clone -- CI checkouts are depth-1).
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import statistics
import subprocess
import sys

PROG = "docs-loop-metrics"
M2_PATHS = ("AGENTS.md", "agent", "internal/rules-meta")
AGENT_MD_RE = re.compile(r"agent/[^/]+\.md$")
META_RE = re.compile(r"internal/rules-meta/(?:.*/)?RM-[0-9]{4}\.md$")


def die(msg, code=2):
    sys.stderr.write("%s: %s\n" % (PROG, msg))
    sys.exit(code)


def parse_date(text, flag):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        die("%s expects YYYY-MM-DD, got %r" % (flag, text))


def iso_week(day):
    year, week, _ = day.isocalendar()
    return "%d-W%02d" % (year, week)


def week_start(day):
    return day - datetime.timedelta(days=day.weekday())


def default_db():
    data_home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(data_home, "opencode", "opencode.db")


def default_global_instructions():
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(config_home, "opencode", "AGENTS.md")


def git(repo, *args):
    proc = subprocess.run(
        ["git", "-C", repo] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        encoding="utf-8",
    )
    if proc.returncode != 0:
        die("git %s failed in %s: %s" % (args[0], repo, proc.stderr.strip()))
    return proc.stdout


def default_match(repo):
    try:
        url = git(repo, "remote", "get-url", "origin").strip()
    except SystemExit:
        die("no origin remote in %s -- pass --match" % repo)
    name = url.rstrip("/").rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    if not name:
        die("cannot derive --match from the origin remote -- pass --match")
    return name


# ---------------------------------------------------------------- M1

def int_or_zero(value):
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def first_prompt(con, session_id):
    """(prompt, uncached, cache_read) of the first assistant message, or None."""
    row = con.execute(
        "SELECT data FROM session_message"
        " WHERE session_id = ? AND type = 'assistant' ORDER BY seq LIMIT 1",
        (session_id,),
    ).fetchone()
    if not row:
        return None
    try:
        data = json.loads(row[0])
    except ValueError:
        return None
    tokens = data.get("tokens") if isinstance(data, dict) else None
    if not isinstance(tokens, dict):
        return None
    uncached = tokens.get("input")
    if not isinstance(uncached, int) or isinstance(uncached, bool):
        return None
    cache = tokens.get("cache")
    cache = cache if isinstance(cache, dict) else {}
    read = int_or_zero(cache.get("read"))
    write = int_or_zero(cache.get("write"))
    prompt = uncached + read + write
    if prompt <= 0:
        return None
    return (prompt, uncached, read)


def blob(con, hashes, key, cache):
    value_hash = hashes.get(key)
    if not value_hash:
        return None
    if value_hash not in cache:
        row = con.execute(
            "SELECT value FROM instruction_blob WHERE hash = ?", (value_hash,)
        ).fetchone()
        cache[value_hash] = row[0] if row else None
    return cache[value_hash]


def working_directory(environment):
    """The `Working directory:` of the core/environment blob, or None."""
    if not environment:
        return None
    try:
        text = json.loads(environment)
    except ValueError:
        text = environment
    if not isinstance(text, str):
        text = environment
    found = re.search(r"Working directory:[ \t]*(\S+)", text)
    return found.group(1) if found else None


def agent_md_paths(instructions):
    """Paths of the loaded AGENTS.md files (core/instructions blob)."""
    if not instructions:
        return []
    try:
        entries = json.loads(instructions)
    except ValueError:
        return []
    paths = []
    for entry in entries if isinstance(entries, list) else []:
        path = entry.get("path") if isinstance(entry, dict) else None
        if isinstance(path, str) and os.path.basename(path) == "AGENTS.md":
            paths.append(path)
    return paths


def classify(con, session_id, global_instructions, cache):
    """'repo' when only the session's own AGENTS.md was loaded; else the reason."""
    row = con.execute(
        "SELECT initial_values FROM instruction_state WHERE session_id = ?",
        (session_id,),
    ).fetchone()
    if not row or not row[0]:
        return "no-instruction-record"
    try:
        hashes = json.loads(row[0])
    except ValueError:
        return "no-instruction-record"
    if not isinstance(hashes, dict):
        return "no-instruction-record"
    cwd = working_directory(blob(con, hashes, "core/environment", cache))
    paths = agent_md_paths(blob(con, hashes, "core/instructions", cache))
    own = [p for p in paths if cwd and p == os.path.join(cwd, "AGENTS.md")]
    if not own:
        return "no-repo-rules"
    global_path = os.path.normpath(global_instructions)
    for path in paths:
        if path in own:
            continue
        if os.path.normpath(path) != global_path:
            return "foreign-rules"
    return "repo"


def median(values):
    if not values:
        return "-"
    value = statistics.median(values)
    return "%d" % value if float(value).is_integer() else "%.1f" % value


def m1(con, match, since, until, global_instructions):
    """-> (rows, excluded) : per ISO week, repo-session stats and exclusion counts."""
    since_ms = int(datetime.datetime(since.year, since.month, since.day).timestamp() * 1000)
    end = until + datetime.timedelta(days=1)
    until_ms = int(datetime.datetime(end.year, end.month, end.day).timestamp() * 1000)
    sessions = con.execute(
        "SELECT id, parent_id, time_created FROM session_v2"
        " WHERE directory LIKE ? AND time_created >= ? AND time_created < ?"
        " ORDER BY time_created",
        ("%" + match + "%", since_ms, until_ms),
    ).fetchall()
    rows = {}
    excluded = {}
    cache = {}
    for session_id, parent_id, created in sessions:
        day = datetime.datetime.fromtimestamp(created / 1000).date()
        week = iso_week(day)
        reason = classify(con, session_id, global_instructions, cache)
        stats = rows.setdefault(week, {"lead": [], "sub": []})
        counts = excluded.setdefault(
            week, {"repo": 0, "foreign-rules": 0, "no-repo-rules": 0,
                   "no-instruction-record": 0, "no-first-message": 0}
        )
        if reason != "repo":
            counts[reason] += 1
            continue
        prompt = first_prompt(con, session_id)
        if prompt is None:
            counts["no-first-message"] += 1
            continue
        counts["repo"] += 1
        stats["sub" if parent_id else "lead"].append(prompt)
    return rows, excluded


def render_m1(rows, excluded, weeks):
    out = []
    out.append("## M1 - boot context (first assistant message, prompt tokens)")
    out.append("")
    out.append("Repo sessions only: leads and subagents apart, medians per ISO week.")
    out.append("")
    out.append(
        "| Week | Lead n | Lead prompt | Lead uncached | Lead cache read"
        " | Subagent n | Subagent prompt | Subagent uncached | Subagent cache read |"
    )
    out.append("|---|---|---|---|---|---|---|---|---|")
    for week in weeks:
        stats = rows.get(week, {"lead": [], "sub": []})
        lead, sub = stats["lead"], stats["sub"]
        out.append(
            "| %s | %d | %s | %s | %s | %d | %s | %s | %s |"
            % (
                week, len(lead), median([p[0] for p in lead]),
                median([p[1] for p in lead]), median([p[2] for p in lead]),
                len(sub), median([p[0] for p in sub]),
                median([p[1] for p in sub]), median([p[2] for p in sub]),
            )
        )
    out.append("")
    out.append("### Excluded sessions (counted, not measured)")
    out.append("")
    out.append(
        "A session counts as a repo session only when its own `AGENTS.md` is the"
        " sole one loaded besides the global user file."
    )
    out.append("")
    out.append(
        "| Week | Repo sessions | Another AGENTS.md loaded (ancestor or subdirectory)"
        " | No own AGENTS.md | No instruction record | Repo session, no first message |"
    )
    out.append("|---|---|---|---|---|---|")
    for week in weeks:
        counts = excluded.get(week, {})
        out.append(
            "| %s | %d | %d | %d | %d | %d |"
            % (
                week, counts.get("repo", 0), counts.get("foreign-rules", 0),
                counts.get("no-repo-rules", 0), counts.get("no-instruction-record", 0),
                counts.get("no-first-message", 0),
            )
        )
    out.append("")
    return out


# ---------------------------------------------------------------- M2

def tree_state(repo, commit):
    """-> (agents_md_bytes, agent_md_bytes, meta_count) of the commit's tree."""
    out = git(repo, "ls-tree", "-l", "-r", commit, "--", *M2_PATHS)
    agents_md = agent_md = metas = 0
    for line in out.splitlines():
        meta, _, path = line.partition("\t")
        fields = meta.split()
        if len(fields) < 4 or fields[3] == "-":
            continue
        size = int(fields[3])
        if path == "AGENTS.md":
            agents_md = size
        elif AGENT_MD_RE.fullmatch(path):
            agent_md += size
        elif META_RE.fullmatch(path):
            metas += 1
    return agents_md, agent_md, metas


def m2(repo, since, until):
    """-> [(week, label, commit, agents_md, agent_md, metas)], last row = HEAD."""
    head = git(repo, "rev-parse", "HEAD").strip()
    head_date = git(repo, "show", "-s", "--format=%cs", head).strip()
    rows = []
    day = week_start(since)
    last = week_start(until)
    while day <= last:
        week_end = day + datetime.timedelta(days=6)
        as_of = min(week_end, until)
        label = as_of.isoformat() + (" (in progress)" if week_end > until else "")
        commit = git(
            repo, "rev-list", "--first-parent", "-1",
            "--before=" + as_of.isoformat() + " 23:59:59",
            "HEAD", "--", *M2_PATHS,
        ).strip()
        if commit:
            agents_md, agent_md, metas = tree_state(repo, commit)
            rows.append((iso_week(day), label, commit[:7], agents_md, agent_md, metas))
        else:
            rows.append((iso_week(day), label, "none", 0, 0, 0))
        day = week_end + datetime.timedelta(days=1)
    agents_md, agent_md, metas = tree_state(repo, head)
    rows.append(("HEAD", head_date, head[:7], agents_md, agent_md, metas))
    return rows, head_date


def render_m2(rows):
    out = []
    out.append("## M2 - corpus size")
    out.append("")
    out.append(
        "Bytes of `AGENTS.md` and `agent/*.md`, and the rule-meta count, on the"
        " first-parent chain: the last commit on or before each date that"
        " touches them (a side branch counts from its merge)."
    )
    out.append("")
    out.append("| Week | State at | Commit | AGENTS.md | agent/*.md | AGENTS.md + agent/*.md | Rule metas |")
    out.append("|---|---|---|---|---|---|---|")
    for week, label, commit, agents_md, agent_md, metas in rows:
        total = agents_md + agent_md
        out.append(
            "| %s | %s | %s | %s | %s | %s | %s |"
            % (
                week, label, commit,
                "n/a" if commit == "none" else "{:,}".format(agents_md),
                "n/a" if commit == "none" else "{:,}".format(agent_md),
                "n/a" if commit == "none" else "{:,}".format(total),
                "n/a" if commit == "none" else "{:,}".format(metas),
            )
        )
    out.append("")
    return out


# ---------------------------------------------------------------- main

def open_db(path):
    if not os.path.isfile(path):
        die("database not found: %s (pass --db)" % path)
    uri = "file:" + path.replace("?", "%3f").replace("#", "%23") + "?mode=ro"
    try:
        con = sqlite3.connect(uri, uri=True)
        names = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'")]
    except sqlite3.Error as exc:
        die("cannot open %s read-only: %s" % (path, exc))
    missing = [t for t in ("session_v2", "session_message", "instruction_state",
                           "instruction_blob") if t not in names]
    if missing:
        die("%s lacks the table(s) %s -- not an opencode V2 session database"
            % (path, ", ".join(missing)))
    return con


def main(argv):
    parser = argparse.ArgumentParser(prog=PROG, description=__doc__.splitlines()[0])
    parser.add_argument("--db", default=default_db(),
                        help="opencode.db path (default: the XDG location)")
    parser.add_argument("--repo", default=os.path.dirname(os.path.dirname(
                        os.path.abspath(__file__))),
                        help="the repository to measure (default: this script's)")
    parser.add_argument("--match", default=None,
                        help="substring of session_v2.directory selecting sessions"
                             " (default: the origin remote's repository name)")
    parser.add_argument("--since", default=None,
                        help="first ISO week to report, YYYY-MM-DD (default: 8 weeks"
                             " before --until)")
    parser.add_argument("--until", default=datetime.date.today().isoformat(),
                        help="last day to report, YYYY-MM-DD (default: today)")
    parser.add_argument("--global-instructions", default=default_global_instructions(),
                        help="the global user AGENTS.md every session loads"
                             " (default: the XDG location)")
    args = parser.parse_args(argv)
    until = parse_date(args.until, "--until")
    since = (parse_date(args.since, "--since") if args.since
             else until - datetime.timedelta(days=55))
    match = args.match or default_match(args.repo)
    con = open_db(args.db)
    weeks = []
    day = week_start(since)
    while day <= week_start(until):
        weeks.append(iso_week(day))
        day += datetime.timedelta(days=7)
    rows, excluded = m1(con, match, since, until, args.global_instructions)
    m2_rows, head_date = m2(args.repo, since, until)

    print("# Docs-loop metrics snapshot - %s" % until.isoformat())
    print()
    print("Generated by `scripts/docs-loop-metrics.py` at commit `%s` (%s)."
          % (m2_rows[-1][2], head_date))
    print("Sessions: `%s` in `%s` (opened read-only), ISO weeks in local time."
          % (match, args.db))
    print()
    for line in render_m1(rows, excluded, weeks) + render_m2(m2_rows):
        print(line)

    repo_sessions = sum(c.get("repo", 0) for c in excluded.values())
    if repo_sessions == 0:
        sys.stderr.write(
            "%s: no repo session found since %s (--match %r, --db %s)"
            " -- check the selection before trusting an empty M1\n"
            % (PROG, since.isoformat(), match, args.db))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
