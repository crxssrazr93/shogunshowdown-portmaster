#!/usr/bin/env python3
"""Convert Shogun Showdown's large textures to ASTC 4x4, in place, for this device's GPU.

The game ships its sprites uncompressed (RGBA32 / RGB24), which takes about 250 MB of GPU memory;
on a handheld with 1 GB of RAM shared with the GPU, starting a run then runs out of memory. ASTC
4x4 keeps every texel at a quarter of the size and looks the same at the game's pixel scale.

tools/astc_manifest.json (made by the port's setup/astc_manifest.py from the supported Steam build)
lists each texture: where its pixels are in the .resS file and the offsets of the fixed size
fields to rewrite in the .assets file. This script reads each texture from the player's own files,
encodes it with PortMaster's astcenc, appends the result to the .resS file and points the texture
at it. Files that do not match the manifest's MD5s are left alone.

Usage: astc_textures.py <Data dir> <astcenc> <manifest> <work dir>
Each converted file gets a marker next to it (<file>.astc_done, the MD5 it was left with), so the
marker travels with the game files; markers from older releases in <work dir> are moved there.
Prints progress lines; exit status 0 when every file is converted (or already was).
"""
import hashlib, json, os, struct, subprocess, sys


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def write_tga(path, raw, w, h, bpp):
    # Unity stores rows bottom up; a top-left origin TGA keeps that order through astcenc, so the
    # ASTC blocks come out in the order Unity uploads them.
    px = bytearray(raw)
    px[0::bpp], px[2::bpp] = raw[2::bpp], raw[0::bpp]   # RGB(A) -> BGR(A)
    with open(path, 'wb') as f:
        f.write(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, bpp * 8,
                            0x28 if bpp == 4 else 0x20))
        f.write(px)


def convert(data_dir, enc, entry, work, done_marker):
    assets = os.path.join(data_dir, entry['assets'])
    ress = os.path.join(data_dir, entry['ress'])
    for path in (assets, ress):
        if not os.path.exists(path):
            print(f"  {os.path.relpath(path, data_dir)} is missing: copy the whole game again", flush=True)
            return False
    if os.path.exists(done_marker) and open(done_marker).read().strip() == md5(assets):
        # the converted textures live past the original end of the .resS; a fresh copy of the
        # .resS alone would leave them pointing past its end
        if os.path.getsize(ress) > entry['ress_size']:
            print(f"  {entry['assets']}: already converted", flush=True)
            return True
        print(f"  {entry['ress']} does not match {entry['assets']}: copy the whole game again", flush=True)
        return False
    if md5(assets) != entry['assets_md5']:
        print(f"  {entry['assets']}: unexpected version, not converted", flush=True)
        return False
    # an interrupted earlier attempt may have appended data; the original part is kept intact
    if os.path.getsize(ress) > entry['ress_size']:
        with open(ress, 'r+b') as f:
            f.truncate(entry['ress_size'])
    if os.path.getsize(ress) != entry['ress_size'] or md5(ress) != entry['ress_md5']:
        print(f"  {entry['ress']}: unexpected version, not converted", flush=True)
        return False

    tga, out = os.path.join(work, 'tex.tga'), os.path.join(work, 'tex.astc')
    texs = entry['textures']
    placed = []
    with open(ress, 'r+b') as res:
        end = entry['ress_size']
        for i, t in enumerate(texs):
            res.seek(t['src'])
            raw = res.read(t['w'] * t['h'] * t['bpp'])
            write_tga(tga, raw, t['w'], t['h'], t['bpp'])
            r = subprocess.run([enc, '-cl', tga, out, '4x4', '-fast', '-silent'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if r.returncode != 0:
                print(f"  astcenc failed: {r.stderr.decode(errors='replace').strip()}", flush=True)
                return False
            with open(out, 'rb') as f:
                blocks = f.read()[16:]
            end = (end + 15) & ~15
            res.seek(end)
            res.write(blocks)
            placed.append((end, len(blocks)))
            end += len(blocks)
            if (i + 1) % 50 == 0 or i + 1 == len(texs):
                print(f"  {entry['assets']}: {i + 1} of {len(texs)} textures", flush=True)
        res.flush()
        os.fsync(res.fileno())

    tmp = assets + '.astc_tmp'
    with open(assets, 'rb') as f:
        buf = bytearray(f.read())
    for t, (off, size) in zip(texs, placed):
        struct.pack_into('<i', buf, t['format_field'], 48)          # TextureFormat.ASTC_4x4
        struct.pack_into('<I', buf, t['size_field'], size)          # m_CompleteImageSize
        struct.pack_into('<QI', buf, t['stream_field'], off, size)  # m_StreamData offset, size
    with open(tmp, 'wb') as f:
        f.write(buf)
        f.flush()
        os.fsync(f.fileno())
    # The marker goes first: if the setup is stopped between the two renames, the .assets file is
    # still the unconverted one, which a rerun converts again.
    with open(done_marker + '.tmp', 'w') as f:
        f.write(hashlib.md5(buf).hexdigest() + '\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(done_marker + '.tmp', done_marker)
    os.replace(tmp, assets)
    return True


def main():
    data_dir, enc, manifest, work = sys.argv[1:5]
    os.makedirs(work, exist_ok=True)
    with open(manifest) as f:
        m = json.load(f)
    ok = True
    for entry in m['files']:
        marker = os.path.join(data_dir, entry['assets'] + '.astc_done')
        old = os.path.join(work, entry['assets'] + '.astc_done')
        if os.path.exists(old):
            if not os.path.exists(marker):
                os.replace(old, marker)
            else:
                os.remove(old)
        ok = convert(data_dir, enc, entry, work, marker) and ok
    for n in ('tex.tga', 'tex.astc'):
        try:
            os.remove(os.path.join(work, n))
        except OSError:
            pass
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
