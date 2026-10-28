"""Copy-only Scarlett save migration. Standard library only; no game prose embedded.

The source folder is never edited. Unknown layouts and unmapped execution
positions are errors, not a reason to discard progress or guess a continuation.
"""
import argparse
import base64
import hashlib
import gzip
import json
from pathlib import Path
import struct
import zlib


class MigrationError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise MigrationError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_manifest(path):
    raw=Path(path).read_bytes()
    if raw.startswith(b'\x1f\x8b'):
        raw=gzip.decompress(raw)
    return json.loads(raw)


def u32(data, at):
    require(0 <= at <= len(data)-4, 'Truncated save data')
    return struct.unpack_from('<I', data, at)[0]


def layout(data):
    """Native 417610/417ABC serialization, with exact EOF accounting."""
    if data.startswith(b'MajiroSysV1.100\0'):
        start = 0x9C58
        count, heapsize = u32(data, 16), u32(data, 20)
        frames = []
    elif data.startswith(b'MajiroSavV1.102\0'):
        depth, w, h, n1, n2, n3, heapsize = (u32(data, x) for x in range(0x90, 0xAC, 4))
        require(depth < 64 and w <= 2048 and h <= 2048, 'Invalid save frame/thumbnail dimensions')
        framebase = 0x9FD0 + 3*w*h
        frames = [framebase + i*0xA8 for i in range(depth+1)]
        start = framebase + (depth+1)*0xA8
        count = n1+n2+n3
    else:
        raise MigrationError('Unsupported save signature')
    require(count <= 1000000 and heapsize <= 128*1024*1024, 'Unreasonable save section size')
    heap = start+count*16
    require(heap+heapsize == len(data), 'Save section lengths do not match file length')
    for at in frames:
        require(b'\0' in data[at:at+128], 'Unterminated script filename')
    return {'variables':start, 'count':count, 'heap':heap, 'heapsize':heapsize, 'frames':frames}


def migrate_bytes(data, manifest, release, dictionary):
    info = layout(data)
    out = bytearray(data)
    changes = []
    for number, at in enumerate(info['frames']):
        # Native uppercasing acts on CP932 BYTES, including ASCII-valued trail
        # bytes. Unicode casefolding is not equivalent.
        name = data[at:at+128].split(b'\0',1)[0].hex()
        spec = manifest['releases'].get(release, {}).get('scripts', {}).get(name)
        if isinstance(spec,str):
            spec=manifest['tables'][spec]
        require(spec is not None, 'Unknown script in frame '+str(number))
        require(spec.get('supported', False), 'This release has an unverified script change in frame '+str(number))
        if 'positions' not in spec:
            encoded=zlib.decompress(base64.b64decode(spec['position_data']))
            spec['positions']={str(a):b for a,b in struct.iter_unpack('<II',encoded)}
        for relative in (0x80,0x94,0x98,0x9C,0xA0,0xA4):
            pos = u32(data, at+relative)
            if relative != 0x80 and (pos == 0 or (relative <= 0x9C and pos >= 0x80000000)):
                continue
            mapped = spec['positions'].get(str(pos))
            require(mapped is not None, 'Unmapped script position in frame '+str(number))
            if mapped != pos:
                struct.pack_into('<I', out, at+relative, mapped)
                changes.append({'kind':'script_position','frame':number,'field':relative,'old':pos,'new':mapped})
    found = 0
    for i in range(info['count']):
        at = info['variables']+16*i
        if u32(data, at) != 0x037CA38A:
            continue
        found += 1
        require(found == 1 and u32(data, at+4) == 3, 'Unexpected glossary variable type or duplicate')
        obj = info['heap']+u32(data, at+8)
        require(info['heap'] <= obj and obj+20+3*14*108*4 <= len(data), 'Invalid glossary array bounds')
        require(tuple(u32(data,obj+x) for x in (8,12,16)) == (3,14,108), 'Unsupported glossary dimensions')
        mapping = manifest['dictionaries'].get(dictionary)
        require(mapping is not None, 'Unknown source dictionary layout')
        for index in range(3*14*108):
            cell = obj+20+4*index
            old = u32(data, cell)
            if old == 0:
                continue
            new = mapping.get(str(old))
            require(new is not None, 'Glossary progress contains an index outside the selected source layout')
            if old != new:
                struct.pack_into('<I',out,cell,new)
                changes.append({'kind':'glossary_index','cell':index,'old':old,'new':new})
    require(layout(out) == info, 'Migration changed the save structure')
    return bytes(out), changes


def convert(source, destination, manifest, release, dictionary):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    require(source.is_dir(), 'Source savedata folder does not exist')
    require(not destination.exists(), 'Destination already exists; choose a new empty folder name')
    require(source not in destination.parents and destination not in source.parents,
            'Source and destination folders must be separate')
    require(release in manifest['releases'], 'Unknown source release')
    require(dictionary in manifest['dictionaries'], 'Unknown source dictionary layout')
    files = sorted(source.iterdir())
    require(all(p.is_file() and not p.is_symlink() for p in files), 'Unexpected subfolder or linked file in savedata')
    snapshots = {p.name:p.read_bytes() for p in files}
    require('scarlett-migration.json' not in snapshots, 'This folder already has a migration receipt; do not migrate it again as an older release')
    outputs, reports = {}, []
    for name, data in snapshots.items():
        if name.lower().endswith('.sav') or name.lower() == 'majiro_system.mss':
            converted, changes = migrate_bytes(data,manifest,release,dictionary)
        else:
            converted, changes = data, []
        outputs[name] = converted
        reports.append({'file':name,'before':sha(data),'after':sha(converted),'changes':changes})
    # Validate the entire folder before writing anything. Recheck for a running
    # game's writes before publishing the new folder.
    require({p.name:p.read_bytes() for p in source.iterdir()} == snapshots, 'Source changed during migration; close the game first')
    destination.mkdir()
    for name, data in outputs.items():
        (destination/name).write_bytes(data)
    receipt = {'format':1,'source_release':release,'source_dictionary':dictionary,
               'target_release':manifest['target'],'original_folder_untouched':True,'files':reports}
    (destination/'scarlett-migration.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', help='Existing savedata folder; never modified')
    p.add_argument('destination', help='New sibling folder for converted copies')
    p.add_argument('--from-release', required=True)
    p.add_argument('--dictionary', choices=['japanese','english-rc1-rc7'], required=True,
                   help='Layout that originally registered glossary progress, which may predate the scene saves')
    p.add_argument('--manifest', type=Path, default=Path(__file__).with_name('save-migration-maps.json.gz'))
    args=p.parse_args()
    try:
        result=convert(args.source,args.destination,read_manifest(args.manifest),args.from_release,args.dictionary)
    except (MigrationError,OSError,ValueError) as e:
        p.exit(1,'Migration stopped: '+str(e)+'\nThe original savedata folder was not changed.\n')
    print('Converted copies created. Original savedata untouched.')
    print('Files:',len(result['files']),'Changed:',sum(r['before']!=r['after'] for r in result['files']))


if __name__ == '__main__':
    main()
