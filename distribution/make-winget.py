"""Prepare manifests from verified public installer checksums; does not submit them."""
import hashlib,pathlib,plistlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
version=plistlib.loads((root/'Info.plist').read_bytes())['LedgerReleaseVersion']
assets=pathlib.Path(sys.argv[1]);out=root/'distribution/winget'/version;out.mkdir(parents=True,exist_ok=True)
identifier='ZhangLigong.CodexLedger';prefix=f'PackageIdentifier: {identifier}\nPackageVersion: {version}\n'
installers=[]
for rid,arch in [('win-x64','x64'),('win-arm64','arm64')]:
 name=f'Codex-Ledger-{version}-Windows-{rid}-Setup.exe';checksum=hashlib.sha256((assets/name).read_bytes()).hexdigest().upper()
 installers.append(f'  - Architecture: {arch}\n    InstallerUrl: https://github.com/zhangligong0826/codex-ledger/releases/download/v{version}/{name}\n    InstallerSha256: {checksum}\n')
(out/(identifier+'.installer.yaml')).write_text(prefix+'MinimumOSVersion: 10.0.22000.0\nInstallerType: inno\nScope: user\nUpgradeBehavior: install\nInstallers:\n'+''.join(installers)+'ManifestType: installer\nManifestVersion: 1.9.0\n')
(out/(identifier+'.locale.en-US.yaml')).write_text(prefix+'PackageLocale: en-US\nPublisher: Codex Ledger contributors\nPackageName: Codex Ledger\nLicense: MIT\nLicenseUrl: https://github.com/zhangligong0826/codex-ledger/blob/main/LICENSE\nShortDescription: Local Codex goal, token and estimated API cost accounting\nPackageUrl: https://zhangligong0826.github.io/codex-ledger/\nManifestType: defaultLocale\nManifestVersion: 1.9.0\n')
(out/(identifier+'.yaml')).write_text(prefix+'DefaultLocale: en-US\nManifestType: version\nManifestVersion: 1.9.0\n')
print('Prepared; community submission/acceptance is separate:',out)
