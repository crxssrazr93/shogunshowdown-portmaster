#!/usr/bin/env python3
"""Counts shader problems in capture runs' player.log (and game.out, where Mesa writes to stderr).

Usage: log_scan.py <run> [<run> ...]      (folders under tests/compare/runs/ or paths)
Looks for: compile or link failures, "not supported" and "unsupported" (GLSL version errors, "ShaderProgram
is unsupported"), "fallback", "Pass ... has no", Hidden/InternalErrorShader, and prints the matching lines
counted per shader name. Unity prints a GLSL error without the shader's name and names the shader in the
note that follows ("Creation of internal variant of shader 'X' failed"), so errors wait for the next
line that names a shader. The GL extension list (one long line that contains GL_KHR_no_error and
GL_KHR_parallel_shader_compile) is skipped.
"""
import collections, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATTERNS = [
    ('compile/link error', re.compile(r'(compile|compilation|link(ing)?)\W.{0,40}(fail|error)|(fail|error).{0,40}(compil|link)|GLSL|glsl.*error|error:.*\b0:\d+', re.I)),
    ('not supported', re.compile(r'not supported|unsupported|Shader is not|none of subshaders', re.I)),
    ('internal variant failed', re.compile(r'Creation of internal variant of shader .* failed', re.I)),
    ('fallback', re.compile(r'fallback', re.I)),
    ('pass has no', re.compile(r"has no (vertex|fragment) shader|Pass '.*' has no", re.I)),
    ('error shader', re.compile(r'InternalErrorShader|Hidden/InternalError|pink', re.I)),
]
IGNORE = re.compile(r'Fallback handler could not load library|^\s*GL_|Curl error|ALSA lib|Odin|Uploading Crash Report|GL_[A-Za-z0-9]+_[A-Za-z0-9_]+ GL_[A-Za-z0-9]+_')
NAME = re.compile(r"[Ss]hader\W+'?([A-Za-z0-9_/ .\-]+?)'?(?:,|:| - | pass|$)|'([A-Za-z0-9_/.\-]+/[A-Za-z0-9_/.\- ]+)'")


SHADER_NAME = re.compile(r"shader '([^']+)'", re.I)


def scan(path):
    kinds = collections.Counter(); names = collections.defaultdict(collections.Counter); sample = {}
    pending = []          # errors that did not name their shader yet: (kind, line)
    for fn in ('player.log', 'game.out'):
        p = os.path.join(path, fn)
        if not os.path.exists(p):
            continue
        for line in open(p, errors='replace'):
            if IGNORE.search(line):
                continue
            sn = SHADER_NAME.search(line)
            if sn:
                for kind, l in pending:
                    names[kind][sn.group(1)] += 1; sample.setdefault((kind, sn.group(1)), l.strip()[:160])
                pending = []
            for kind, rx in PATTERNS:
                if rx.search(line):
                    m = NAME.search(line)
                    kinds[kind] += 1
                    if sn:
                        names[kind][sn.group(1)] += 1; sample.setdefault((kind, sn.group(1)), line.strip()[:160])
                    elif m:
                        name = (m.group(1) or m.group(2)).strip()
                        names[kind][name] += 1; sample.setdefault((kind, name), line.strip()[:160])
                    else:
                        pending.append((kind, line))
    for kind, l in pending:
        names[kind]['(unnamed)'] += 1; sample.setdefault((kind, '(unnamed)'), l.strip()[:160])
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
