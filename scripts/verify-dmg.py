#!/usr/bin/env python3
"""Verify a read-only DMG against the built and installed applications."""
import argparse,hashlib,json,plistlib,subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--installed",action="store_true",help="Also compare the copy in /Applications")
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
app=root/'outputs/言叶 Kotonoha.app'
version=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
dmg=root/f'outputs/Kotonoha-{version}-AppleSilicon.dmg'
mount=root/'work/dmg-verify'
mount.mkdir(exist_ok=True)
def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()
subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(dmg)],check=True)
try:
    mounted=mount/'言叶 Kotonoha.app'
    installed=Path('/Applications/言叶 Kotonoha.app')
    bundles=[mounted,app]+([installed] if args.installed else [])
    for bundle in bundles:subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
    executables=[bundle/'Contents/MacOS/Kotonoha' for bundle in bundles]
    assert len({sha(p) for p in executables})==1,'Executable mismatch'
    assert (mount/'Applications').is_symlink() and (mount/'Applications').readlink()==Path('/Applications')
    assert not [p for p in mount.rglob('*') if p.is_file() and p.suffix.lower() in ['.gguf','.safetensors','.mov','.mp4','.bin']]
    report=dict(version=version,readOnlyMountVerified=True,sameExecutableAsInstalled=True if args.installed else None,modelWeightsIncluded=False,applicationShortcutVerified=True,notarized=False,dmgSizeBytes=dmg.stat().st_size,sha256=sha(dmg))
    (root/'outputs/dmg-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
finally:subprocess.run(['hdiutil','detach',str(mount)],check=True)
