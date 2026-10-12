#!/usr/bin/env python3
"""Counts shader problems in capture runs' player.log (and game.out, where Mesa writes to stderr).

Usage: log_scan.py <run> [<run> ...]      (folders under tests/compare/runs/ or paths)
Looks for: compile or link failures, "not supported", "Unsupported", "fallback", "Shader error",
"GLSL", "SHADER", "Pass ... has no", "invalid", and prints the matching lines counted per shader
name (the first quoted name or "Shader <name>" on the line, else "(unnamed)"), followed by the
number of lines of each kind.
"""
import collections, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATTERNS = [
    ('compile/link error', re.compile(r'(compile|compilation|link(ing)?)\W.{0,40}(fail|error)|(fail|error).{0,40}(compil|link)|GLSL|glsl.*error|error:.*\b0:\d+', re.I)),
    ('not supported', re.compile(r'not supported|unsupported|Shader is not|none of subshaders', re.I)),
    ('fallback', re.compile(r'fallback', re.I)),
    ('pass has no', re.compile(r"has no (vertex|fragment) shader|Pass '.*' has no", re.I)),
    ('error shader', re.compile(r'InternalErrorShader|Hidden/InternalError|pink', re.I)),
]
IGNORE = re.compile(r'Fallback handler could not load library|^\s*GL_|Curl error|ALSA lib|Odin|Uploading Crash Report|\bGL_[A-Z0-9_]+ GL_')
NAME = re.compile(r"[Ss]hader\W+'?([A-Za-z0-9_/ .\-]+?)'?(?:,|:| - | pass|$)|'([A-Za-z0-9_/.\-]+/[A-Za-z0-9_/.\- ]+)'")


def scan(path):
    kinds = collections.Counter(); names = collections.defaultdict(collections.Counter); sample = {}
    for fn in ('player.log', 'game.out'):
        p = os.path.join(path, fn)
        if not os.path.exists(p):
            continue
        for line in open(p, errors='replace'):
            if IGNORE.search(line):
                continue
            for kind, rx in PATTERNS:
                if rx.search(line):
                    m = NAME.search(line)
                    name = (m.group(1) or m.group(2)).strip() if m else '(unnamed)'
                    kinds[kind] += 1; names[kind][name] += 1; sample.setdefault((kind, name), line.strip()[:160])
    return kinds, names, sample


def main():
    for r in sys.argv[1:]:
        path = r if os.path.isdir(r) else os.path.join(HERE, 'runs', r)
        kinds, names, sample = scan(path)
        print(f'== {os.path.basename(path.rstrip("/"))}: ' + (', '.join(f'{k}: {v}' for k, v in kinds.items()) or 'no shader problems found'))
        for kind in names:
            for name, n in names[kind].most_common():
                print(f'   {kind:20} {n:4}  {name}    e.g. {sample[(kind, name)]}')


if __name__ == '__main__':
    main()
