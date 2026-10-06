"""Build the manifest that tools/astc_textures.py uses on the device (run on the PC at build time).

Shogun Showdown's textures are uncompressed RGBA32/RGB24 (about 250 MB of GPU memory, which on a
1 GB handheld with a Mali GPU is plain RAM). The device converts them to ASTC 4x4 at first start
with PortMaster's astcenc, on the player's own copy of the game. This script records, for every
texture to convert, where its pixels are in the .resS file and the file offsets of the fixed size
fields to rewrite in the .assets file (m_TextureFormat, m_CompleteImageSize, m_StreamData offset
and size), so the device needs no Unity file parser. The offsets hold only for the exact files
this port supports, so the manifest also carries their MD5s (the .assets after the port's xdelta
patches, the .resS as Steam ships it). No game content goes into the manifest.

Usage: python astc_manifest.py <patched Data dir> <original Data dir> > astc_manifest.json
"""
import hashlib, json, os, struct, sys
import UnityPy

FILES = ['sharedassets2.assets', 'resources.assets', 'sharedassets1.assets']
MIN_TEXELS = 64 * 64          # smaller textures are not worth it
FORMATS = {3: 3, 4: 4}        # Unity RGB24 / RGBA32 -> bytes per texel


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    patched, original = sys.argv[1], sys.argv[2]
    out = {'astc_format': 48, 'block': '4x4', 'files': []}
    for name in FILES:
        path = os.path.join(patched, name)
        env = UnityPy.load(path)
        sf = list(env.files.values())[0]
        raw = open(path, 'rb').read()
        entry = {'assets': name, 'assets_md5': md5(path), 'textures': []}
        res_name = None
        for o in env.objects:
            if o.type.name != 'Texture2D':
                continue
            t = o.read_typetree()
            sd = t['m_StreamData']
            fmt, w, h = t['m_TextureFormat'], t['m_Width'], t['m_Height']
            if fmt not in FORMATS or not sd['path'] or t['m_MipCount'] != 1 or w * h < MIN_TEXELS:
                continue
            assert sd['size'] == w * h * FORMATS[fmt], t['m_Name']
            res_name = res_name or sd['path']
            assert sd['path'] == res_name
            start = o.byte_start
            body = raw[start:start + o.byte_size]
            head = struct.pack('<iiIii', w, h, t['m_CompleteImageSize'], t['m_MipsStripped'], fmt)
            p = body.find(head)
            assert p >= 0 and body.find(head, p + 1) < 0, t['m_Name']
            pb = sd['path'].encode()
            tail = struct.pack('<QII', sd['offset'], sd['size'], len(pb)) + pb
            q = body.rfind(tail)
            assert q >= 0, t['m_Name']
            entry['textures'].append({
                'w': w, 'h': h, 'bpp': FORMATS[fmt], 'src': sd['offset'],
                'size_field': start + p + 8, 'format_field': start + p + 16,
                'stream_field': start + q})
        res_path = os.path.join(original, res_name)
        entry['ress'] = res_name
        entry['ress_size'] = os.path.getsize(res_path)
        entry['ress_md5'] = md5(res_path)
        out['files'].append(entry)
        print(f'{name}: {len(entry["textures"])} textures', file=sys.stderr)
    json.dump(out, sys.stdout, separators=(',', ':'))


if __name__ == '__main__':
    main()
