"""Builds the two shader pack ZIPs from this repository.

    python build.py            -> dist/Shiroi Visuals <version>.zip and dist/Shiroi Visuals <version> for Vitrail.zip
    python build.py --dev      -> also unpacks both into dist/ as folders, handy to symlink into shaderpacks/

Only the Python standard library is needed (3.8 or newer).

The Iris edition is shaders/ as it is. The Vitrail edition is the same files with two changes:
  * lib/common.glsl: the VITRAIL_EDITION marker line becomes "#define SHIROI_VITRAIL_SINGLE_CASCADE 1";
  * the shadow geometry shaders (*.gsh) are left out, since Vitrail cannot run them.
Each ZIP also gets its README (packaging/), CHANGELOG.md, MOD_SUPPORT.md, THIRD_PARTY_NOTICES.md and LICENSE.
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SHADERS = ROOT / 'shaders'
DIST = ROOT / 'dist'
MARKER = b'// VITRAIL_EDITION:'
VITRAIL_DEFINE = b'#define SHIROI_VITRAIL_SINGLE_CASCADE 1'


def version():
    return (ROOT / 'VERSION').read_text(encoding='utf-8').strip()


def vitrail_common(data):
    lines = data.split(b'\n')
    hits = [i for i, line in enumerate(lines) if line.startswith(MARKER)]
    if len(hits) != 1:
        sys.exit('build.py: expected exactly one VITRAIL_EDITION marker in shaders/lib/common.glsl')
    i = hits[0]
    lines[i] = VITRAIL_DEFINE + (b'\r' if lines[i].endswith(b'\r') else b'')
    return b'\n'.join(lines)


def edition_files(vitrail):
    """(path inside the ZIP, bytes) for every shader file of one edition."""
    for path in sorted(SHADERS.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(SHADERS).as_posix()
        if vitrail and path.suffix == '.gsh':
            continue
        data = path.read_bytes()
        if vitrail and rel == 'lib/common.glsl':
            data = vitrail_common(data)
        yield 'shaders/' + rel, data


def build(vitrail, dev):
    name = f'Shiroi Visuals {version()}' + (' for Vitrail' if vitrail else '')
    readme = ROOT / 'packaging' / ('README_vitrail.md' if vitrail else 'README_iris.md')
    extras = [('README.md', readme)] + [(n, ROOT / n) for n in
                                        ('CHANGELOG.md', 'MOD_SUPPORT.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE')]
    files = list(edition_files(vitrail)) + [(n, p.read_bytes()) for n, p in extras]
    DIST.mkdir(exist_ok=True)
    out = DIST / (name + '.zip')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arcname, data in files:
            z.writestr(arcname, data)
    if dev:
        folder = DIST / name
        for arcname, data in files:
            target = folder / arcname
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print(f'{out.relative_to(ROOT)}  ({out.stat().st_size // 1024} KiB, {len(files)} files)')


if __name__ == '__main__':
    dev = '--dev' in sys.argv[1:]
    build(vitrail=False, dev=dev)
    build(vitrail=True, dev=dev)
