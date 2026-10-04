# Third-party components

macOS uses Apple system frameworks and the OS-provided SQLite library. Windows embeds the .NET 10 runtime for self-contained deployment.

Windows package dependencies (versions pinned in the project files; transitive inventory is available through `dotnet list package --include-transitive`):

- .NET / WPF / Windows Forms — Microsoft, MIT; https://github.com/dotnet/runtime and https://github.com/dotnet/wpf
- Microsoft.Data.Sqlite.Core 10.0.12 — Microsoft, MIT; https://github.com/dotnet/efcore
- SQLitePCLRaw.bundle_e_sqlite3 3.0.5 and its provider/native dependencies — Apache-2.0 and SQLite public-domain components (SQLite 3.53.4); https://github.com/ericsink/SQLitePCL.raw
- QRCoder 1.6.0 — MIT; https://github.com/codebude/QRCoder

Build-only Windows installer tool: Inno Setup, https://jrsoftware.org. It is not installed as part of the app. Respect the license of the tool version used for packaging.

GitHub Actions are pinned to source commits. No proprietary fonts or third-party hosted services are required to generate share images or installation QR codes.

License and notice copies in `distribution/licenses/` are included in Windows installer and portable packages.
