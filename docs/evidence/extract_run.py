#!/usr/bin/env python3
"""Pull key evidence out of a `claude -p --output-format stream-json --include-hook-events`
transcript: agent spawns, autopilot/check commands with output, and gate hook verdicts.
Usage: extract_run.py TRANSCRIPT.jsonl [--scrub PREFIX]"""
import json, sys

args = sys.argv[1:]
scrub = None
if "--scrub" in args:
    i = args.index("--scrub"); scrub = args[i + 1]; del args[i:i + 2]
pending = {}

def s(x):
    x = x if isinstance(x, str) else json.dumps(x)
    return x.replace(scrub, "<demo>") if scrub else x

def short(text, n=14):
    lines = s(text).rstrip().splitlines()
    out = lines[:n]
    if len(lines) > n: out.append(f"    ... ({len(lines) - n} more lines)")
    return "\n".join("    " + l for l in out)

for line in open(args[0]):
    try: d = json.loads(line)
    except ValueError: continue
    t, st = d.get("type"), d.get("subtype", "")
    if t == "assistant":
        for c in d["message"]["content"]:
            if c["type"] != "tool_use": continue
            inp = c["input"]
            if c["name"] == "Agent":
                first = (inp.get("prompt") or "").splitlines()[:1]
                print(f"AGENT  {inp.get('subagent_type')}: {s(first[0]) if first else ''}")
            elif c["name"] == "Bash":
                cmd = inp.get("command", "")
                if any(k in cmd for k in ("autopilot", "checks.sh", "pytest", "git diff --stat", "git log")):
                    pending[c["id"]] = cmd
            elif c["name"] == "Skill":
                print(f"SKILL  {inp}")
    elif t == "user":
        cont = d["message"].get("content")
        if isinstance(cont, list):
            for c in cont:
                if c.get("type") == "tool_result" and c.get("tool_use_id") in pending:
                    body = c.get("content")
                    if isinstance(body, list): body = "\n".join(b.get("text", "") for b in body if isinstance(b, dict))
                    print(f"$ {s(pending.pop(c['tool_use_id']))}")
                    print(short(body or ""))
    elif t == "system" and st == "hook_response":
        ev = d.get("hook_event") or ""
        if ev in ("Stop", "SubagentStop") or d.get("exit_code") not in (0, None):
            out = (d.get("stderr") or d.get("stdout") or "").strip()
            verdict = "BLOCK" if d.get("exit_code") == 2 else ("ALLOW+msg" if out else "allow")
            print(f"HOOK   {d.get('hook_name')} exit={d.get('exit_code')} {verdict}")
            if out: print(short(out, 8))
    elif t == "result":
        print(f"RESULT {d.get('subtype')} turns={d.get('num_turns')} cost_usd={d.get('total_cost_usd')}")
