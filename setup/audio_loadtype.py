"""Change AudioClip load types so music is not decoded into RAM.

Every clip in this game is Vorbis with load type DecompressOnLoad, and all of them sit in the
boot scene's sharedassets0.assets, so the player decodes about 577 MB of PCM at startup (453 MB
of it the 19 music loops). Only m_LoadType changes; the Vorbis data is untouched:
  longer than STREAM_FROM seconds    -> Streaming (2): decoded while playing, read from the .resource
  longer than COMPRESSED_FROM seconds -> CompressedInMemory (1): decoded per playing voice
  shorter                             -> unchanged (decoded once, cheapest to play)

Usage: python audio_loadtype.py <Data dir> [STREAM_FROM=60] [COMPRESSED_FROM=10]   (in place)
"""
import os, sys, UnityPy

DECOMPRESS, COMPRESSED, STREAMING = 0, 1, 2


def main():
    data = sys.argv[1]
    stream_from = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
    comp_from = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    path = os.path.join(data, 'sharedassets0.assets')
    env = UnityPy.load(path)
    counts = {STREAMING: 0, COMPRESSED: 0}
    for o in env.objects:
        if o.type.name != 'AudioClip':
            continue
        t = o.read_typetree()
        if t['m_LoadType'] != DECOMPRESS:
            continue
        want = STREAMING if t['m_Length'] > stream_from else COMPRESSED if t['m_Length'] > comp_from else None
        if want is None:
            continue
        t['m_LoadType'] = want
        o.save_typetree(t); counts[want] += 1
    if any(counts.values()):
        out = list(env.files.values())[0].save()
        with open(path + '.tmp', 'wb') as fh:
            fh.write(out)
        os.replace(path + '.tmp', path)
    print(f'audio: streaming={counts[STREAMING]} compressed={counts[COMPRESSED]}', flush=True)


if __name__ == '__main__':
    main()
