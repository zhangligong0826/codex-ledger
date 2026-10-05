param([string]$Version = '1.2.0-beta.4')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $out | Out-Null
$iscc = Get-ChildItem "${env:ProgramFiles(x86)}\Inno Setup*\ISCC.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $iscc) { throw 'Install Inno Setup from https://jrsoftware.org/isdl.php before packaging.' }
foreach ($rid in @('win-x64','win-arm64')) {
  dotnet publish "$PSScriptRoot/Ledger.App" -c Release -r $rid --self-contained true -o "$out/$rid" -p:Version=$Version
  if ($LASTEXITCODE -ne 0) { throw "Publish failed: $rid" }
  Copy-Item "$root/LICENSE" "$out/$rid/LICENSE.txt"
  Copy-Item "$root/THIRD-PARTY.md" "$out/$rid/THIRD-PARTY.md"
  Copy-Item "$root/distribution/licenses" "$out/$rid/licenses" -Recurse -Force
  Compress-Archive -Path "$out/$rid/*" -DestinationPath "$out/Codex-Ledger-$Version-Windows-$rid-Portable.zip" -Force
  & $iscc.FullName "/DRID=$rid" "/DVersion=$Version" "$PSScriptRoot/setup.iss"
  if ($LASTEXITCODE -ne 0) { throw "Installer failed: $rid" }
}
$names = @('win-x64','win-arm64') | ForEach-Object { "Codex-Ledger-$Version-Windows-$_-Setup.exe"; "Codex-Ledger-$Version-Windows-$_-Portable.zip" }
$names | ForEach-Object { $h=Get-FileHash "$out/$_" -Algorithm SHA256; "$($h.Hash.ToLower())  $_" } | Set-Content "$out/WINDOWS-CHECKSUMS.txt" -Encoding utf8
