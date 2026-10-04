#!/usr/bin/env python3
"""The JSON catalog is authoritative; sync derived metadata, or check it in CI."""
import json, plistlib, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
v = json.loads((root / 'Common/version.json').read_text(encoding='utf-8'))
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-beta\.\d+)?', v['release'])
assert re.fullmatch(r'\d+\.\d+\.\d+', v['numeric']) and isinstance(v['build'], int) and v['build'] > 0
sync = '--sync' in sys.argv
errors = []
p = root / 'Info.plist'
info = plistlib.loads(p.read_bytes())
expected = {'LedgerReleaseVersion': v['release'], 'CFBundleShortVersionString': v['numeric'], 'CFBundleVersion': str(v['build'])}
if sync:
    for key, value in expected.items():
        text=p.read_text(encoding='utf-8');text=re.sub(r'(<key>'+key+r'</key>\s*<string>)[^<]+',lambda m:m[1]+value,text);p.write_text(text, encoding='utf-8')
elif any(info.get(k)!=value for k,value in expected.items()): errors.append('Info.plist')
substitutions = {
    'Windows/Ledger.App/Ledger.App.csproj': [(r'(<Version>)[^<]+',v['release']), (r'(<AssemblyVersion>)[^<]+',v['numeric']+'.0'), (r'(<FileVersion>)[^<]+',v['numeric']+'.'+str(v['build']))],
    'Windows/package.ps1': [(r"(\$Version = ')[^']+",v['release'])],
    'Windows/setup.iss': [(r'(#define Version ")[^"]+',v['release'])],
    'site/app.js': [(r"(const version=')[^']+",v['release'])],
    'site/index.html': [(r'(<span id="version">)[^<]+',v['release'])],
}
for name, rules in substitutions.items():
    path=root/name;text=path.read_text(encoding='utf-8')
    for pattern, value in rules:
        match=re.search(pattern,text)
        if match is None: errors.append(name+': missing version marker'); continue
        updated=re.sub(pattern,lambda m:m[1]+value,text)
        if sync: text=updated
        elif text!=updated: errors.append(name)
    if sync: path.write_text(text, encoding='utf-8')
if errors: raise SystemExit('Version mismatch: '+', '.join(sorted(set(errors))))
print('Version metadata matches '+v['release'])
