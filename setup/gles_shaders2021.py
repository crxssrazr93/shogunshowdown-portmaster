"""Rewrite the OpenGLCore shader programs of a Unity 2021.3 build as GLSL ES 3.00, in place.

The 2021.3 Linux player only accepts OpenGLCore (17) or Vulkan (21) in BuildSettings.m_GraphicsAPIs
("Unknown renderer 11" for GLES3), and picks OpenGLCore shader programs (platform 15) from the
renderer, not from the context. Its GL backend does run on an OpenGL ES 3.x context, though (it
reports "GLES: 3"). So instead of adding GLES3 (platform 9) programs, the code of every GLCore
program is replaced by its GLSL ES 3.00 translation while it keeps its GLCore type. The text
rewriter is unityport's convert_program (Knifethrower/PM-Porting-Tools, 0BSD).

2021.3 layout (blob entry version 202012090): per platform, nested offsets/compressedLengths/
decompressedLengths (one list of segments per platform); a decompressed segment is a count, a table
of 12 byte (offset, length, segment) records and the entries; program entries are only told apart
from parameter entries through m_PlayerSubPrograms[].m_BlobIndex.

Usage: python gles_shaders2021.py <Data dir> [files...]    (patches in place; use a copy)
"""
import os, re, struct, sys
import lz4.block, UnityPy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vendor'))
from gles_shaders import convert_program  # unityport's GLSL 150/330 -> ES 3.00 rewriter

PLAT_GLCORE = 15
GPU_GLCORE_OK = {6, 7}                 # GLCore32/41; GLCore43 (8) is 4.2+ only, left alone
PROGS = ('progVertex', 'progFragment', 'progGeometry', 'progHull', 'progDomain', 'progRayTracing')
BAD = ('GL_AMD_vertex_shader_layer', 'GL_ARB_shading_language_420pack', 'GL_OVR_multiview2')
FILES = ['Resources/unity_builtin_extra', 'globalgamemanagers.assets', 'resources.assets',
         'sharedassets0.assets', 'sharedassets2.assets']
# Converted programs carry no marker: a second run skips them because they declare #version 300 es
# (see convertible). Earlier versions of this script prefixed OLD_MARK, which breaks on Mali: GLSL ES
# wants #version on the first line, and Unity puts any text outside a program's stage sections in
# front of every stage. So OLD_MARK is removed where found.
OLD_MARK = b'// port: GLSL ES 3.00\n'


def a4(n): return (n + 3) & ~3


def parse_blob(b):
    n, = struct.unpack_from('<i', b)
    table = [struct.unpack_from('<3i', b, 4 + 12 * i) for i in range(n)]
    return [(b[o:o + l], seg) for o, l, seg in table]


def build_blob(entries):
    out = bytearray(struct.pack('<i', len(entries))); off = 4 + 12 * len(entries)
    for e, seg in entries:
        out += struct.pack('<3i', off, len(e), seg); off += len(e)
    for e, _ in entries:
        out += e
    return bytes(out)


def split_program(e):
    """-> (head up to the code length, code, tail)."""
    p = 24
    nkw, = struct.unpack_from('<i', e, p); p += 4
    for _ in range(nkw):
        n, = struct.unpack_from('<i', e, p); p = a4(p + 4 + n)
    clen, = struct.unpack_from('<i', e, p)
    return e[:p], e[p + 4:p + 4 + clen], e[a4(p + 4 + clen):]


def join_program(head, code, tail):
    b = head + struct.pack('<i', len(code)) + code
    return b + b'\0' * (a4(len(b)) - len(b)) + tail


def convertible(code):
    s = code.decode('utf-8', 'replace')
    return re.search(r'#version (150|330)\b', s) and not any(x in s for x in BAD)


def patch(t):
    """Returns the number of programs converted in one Shader typetree."""
    plats = list(t['platforms'])
    if PLAT_GLCORE not in plats:
        return 0
    raw = bytes(t['compressedBlob'])
    prog_idx = {s['m_BlobIndex'] for ss in t['m_ParsedForm']['m_SubShaders'] for p in ss['m_Passes']
                for k in PROGS for tier in p[k]['m_PlayerSubPrograms'] for s in tier
                if s['m_GpuProgramType'] in GPU_GLCORE_OK}
    n = 0
    new_raw = bytearray(); offs, clens, dlens = [], [], []
    for pi in range(len(plats)):
        po, pc, pd = [], [], []
        for o, c, d in zip(t['offsets'][pi], t['compressedLengths'][pi], t['decompressedLengths'][pi]):
            comp = raw[o:o + c]
            if plats[pi] == PLAT_GLCORE:
                seg = lz4.block.decompress(comp, uncompressed_size=d)
                entries = parse_blob(seg)
                out = []
                for i, (e, sg) in enumerate(entries):
                    if i in prog_idx:
                        head, code, tail = split_program(e)
                        if code.startswith(OLD_MARK):
                            e = join_program(head, code[len(OLD_MARK):], tail); n += 1
                        elif convertible(code):
                            e = join_program(head, convert_program(code), tail); n += 1
                    out.append((e, sg))
                seg = build_blob(out)
                comp = lz4.block.compress(seg, store_size=False, mode='high_compression')
                d = len(seg)
            po.append(len(new_raw)); pc.append(len(comp)); pd.append(d)
            new_raw += comp
        offs.append(po); clens.append(pc); dlens.append(pd)
    if n:
        t['compressedBlob'] = list(new_raw)
        t['offsets'], t['compressedLengths'], t['decompressedLengths'] = offs, clens, dlens
    return n


def main():
    data_dir = sys.argv[1]
    for f in sys.argv[2:] or FILES:
        path = os.path.join(data_dir, f)
        env = UnityPy.load(path); n = sh = 0
        for o in env.objects:
            if o.type.name != 'Shader':
                continue
            t = o.read_typetree(); k = patch(t)
            if k:
                o.save_typetree(t); n += k; sh += 1
        if n:
            data = list(env.files.values())[0].save()
            with open(path + '.tmp', 'wb') as fh:
                fh.write(data)
            os.replace(path + '.tmp', path)
        print(f'{f}: {sh} shaders, {n} programs converted', flush=True)


if __name__ == '__main__':
    main()
