"""Validate explicit release inventory; never publish stale files by globbing dist."""
import hashlib, pathlib, plistlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
version = plistlib.loads((root / 'Info.plist').read_bytes())['LedgerReleaseVersion']
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-beta\.\d+)?', version)
folder = pathlib.Path(sys.argv[1])
names = [f'Codex-Ledger-{version}-macOS-universal.{ext}' for ext in ['zip', 'dmg']]
names += [f'Codex-Ledger-{version}-Windows-{rid}-{suffix}' for rid in ['win-x64', 'win-arm64'] for suffix in ['Setup.exe', 'Portable.zip']]
expected = set(names)
actual = {p.name for p in folder.iterdir() if p.name.startswith('Codex-Ledger-')}
assert actual == expected, f'Asset mismatch: {actual ^ expected}'
# Verify producer checksums before generating one combined inventory.
for manifest in ['CHECKSUMS.txt', 'WINDOWS-CHECKSUMS.txt']:
    for line in (folder / manifest).read_text(encoding='utf-8-sig').splitlines():
        checksum, name = line.split(None, 1)
        name = name.lstrip('*')
        assert name in expected and hashlib.sha256((folder / name).read_bytes()).hexdigest() == checksum.lower(), name
checksums = '\n'.join(hashlib.sha256((folder / n).read_bytes()).hexdigest() + '  ' + n for n in names) + '\n'
(folder / 'CHECKSUMS.txt').write_text(checksums)
print(f'Verified {len(names)} immutable release assets for {version}')
