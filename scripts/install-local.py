#!/usr/bin/env python3
"""Install the signed build, preserving the user's existing model and preferences."""
import json,plistlib,shutil,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
source=root/'outputs/言叶 Kotonoha.app'
destination=Path('/Applications/言叶 Kotonoha.app')
identifier='app.kotonoha.localtranslator'
assert plistlib.loads((source/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']==identifier
if destination.exists():
    assert plistlib.loads((destination/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']==identifier,'Refusing to replace an unrelated app'
subprocess.run([str(root/'work/build/close-kotonoha')],check=True)
staging=Path('/Applications')/('.Kotonoha-install-'+str(time.time_ns())+'.app')
subprocess.run(['ditto',str(source),str(staging)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(staging)],check=True)
if destination.exists():
    shutil.move(str(destination),str(root/'work'/('installed-backup-'+str(time.time_ns())+'.app')))
staging.rename(destination)
subprocess.run(['codesign','--verify','--deep','--strict',str(destination)],check=True)
report={'installed':str(destination),'version':plistlib.loads((destination/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString'],'preferencesPreserved':True,'modelIncludedInApp':False}
(root/'outputs/install-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
print(json.dumps(report,ensure_ascii=False))
