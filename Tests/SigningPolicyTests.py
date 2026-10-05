"""Negative-path release guards. Apple tools are mocked; not an Apple acceptance test."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ledger-signing-policy-")
        self.folder = Path(self.tmp.name)
        self.bin = self.folder / "bin"
        self.bin.mkdir()
        self.trace = self.folder / "trace.jsonl"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        LEDGER_POLICY_TRACE=str(self.trace), CODEX_LEDGER_SIGNING_MODE="local")
        for key in ["CODEX_LEDGER_SIGNING_IDENTITY", "CODEX_LEDGER_NOTARY_PROFILE", "CODEX_LEDGER_NATIVE_ICON"]:
            self.env.pop(key, None)
        self.env["CODEX_LEDGER_OUTPUT_DIR"] = str(self.folder / "output")
        Path(self.env["CODEX_LEDGER_OUTPUT_DIR"]).mkdir()
        tool = "#!" + sys.executable + "\n" + '''
import json,os,pathlib,sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['LEDGER_POLICY_TRACE'],'a') as f: f.write(json.dumps([name,args])+'\\n')
if name=='codesign':
    if '--force' in args and os.environ.get('LEDGER_POLICY_SIGN_FAIL')=='1': sys.exit(2)
    if '-d' in args:
        if os.environ.get('LEDGER_POLICY_CERT')=='developer-id':
            print('Authority=Developer ID Application: Policy Fixture (TESTTEAM)\\nTeamIdentifier=TESTTEAM\\nflags=0x10000(runtime)',file=sys.stderr)
        else: print('Signature=adhoc\\nTeamIdentifier=not set',file=sys.stderr)
elif name=='lipo': print('x86_64 arm64')
elif name=='spctl': sys.exit(int(os.environ.get('LEDGER_POLICY_ASSESS_EXIT','0')))
elif name=='xcrun':
    if args[:2]==['notarytool','submit']:
        print(json.dumps({'id':'synthetic-policy-check','status':os.environ.get('LEDGER_POLICY_NOTARY_STATUS','Invalid')}))
    if args[:2]==['stapler','validate']:
        if '/archive-check/' in args[-1]: sys.exit(int(os.environ.get('LEDGER_POLICY_ARCHIVE_TICKET_EXIT','0')))
        sys.exit(int(os.environ.get('LEDGER_POLICY_STAPLER_EXIT','0')))
'''
        for name in ["codesign", "lipo", "spctl", "xcrun"]:
            file = self.bin / name
            file.write_text(tool)
            file.chmod(0o700)
        self.app = self.folder / "Codex Ledger.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/Resources").mkdir()
        (self.app / "Contents/Info.plist").write_bytes((ROOT / "Info.plist").read_bytes())
        (self.app / "Contents/MacOS/CodexLedger").write_text("synthetic policy fixture")
        version = plistlib.loads((ROOT / "Info.plist").read_bytes())["LedgerReleaseVersion"]
        self.zip = Path(self.env["CODEX_LEDGER_OUTPUT_DIR"]) / f"Codex-Ledger-{version}-macOS-universal.zip"
        subprocess.run(["/usr/bin/ditto", "--norsrc", "--noextattr", "-c", "-k", "--keepParent", str(self.app), str(self.zip)], check=True)
        self.before = hashlib.sha256(self.zip.read_bytes()).hexdigest()

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, name, *args):
        return subprocess.run(["/bin/zsh", str(ROOT / name), *map(str, args)],
                              env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def assert_archive_unchanged(self):
        self.assertEqual(hashlib.sha256(self.zip.read_bytes()).hexdigest(), self.before)

    def test_local_build_needs_no_certificate(self):
        self.assertEqual(self.run_script("distribution/sign-mac.sh", self.app).returncode, 0)
        self.assertIn(["codesign", ["--force", "--sign", "-", str(self.app)]], self.calls())

    def test_formal_build_requires_developer_identity(self):
        self.env["CODEX_LEDGER_SIGNING_MODE"] = "developer-id"
        self.assertNotEqual(self.run_script("distribution/sign-mac.sh", self.app).returncode, 0)
        self.assertEqual(self.calls(), [])
        self.env["CODEX_LEDGER_SIGNING_IDENTITY"] = "Apple Development: Policy Fixture"
        self.assertNotEqual(self.run_script("distribution/sign-mac.sh", self.app).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_sign_failure_never_falls_back_to_adhoc(self):
        self.env.update(CODEX_LEDGER_SIGNING_MODE="developer-id",
                        CODEX_LEDGER_SIGNING_IDENTITY="Developer ID Application: Policy Fixture (TESTTEAM)",
                        LEDGER_POLICY_SIGN_FAIL="1")
        self.assertNotEqual(self.run_script("distribution/sign-mac.sh", self.app).returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn("-", self.calls()[0][1])

    def test_notarization_rejects_adhoc_before_upload(self):
        self.env["CODEX_LEDGER_NOTARY_PROFILE"] = "synthetic-policy-profile"
        self.assertNotEqual(self.run_script("distribution/notarize-mac.sh").returncode, 0)
        self.assertFalse(any(name == "xcrun" for name, _ in self.calls()))
        self.assert_archive_unchanged()

    def test_apple_rejection_preserves_original_archive(self):
        self.env.update(CODEX_LEDGER_NOTARY_PROFILE="synthetic-policy-profile", LEDGER_POLICY_CERT="developer-id")
        result = self.run_script("distribution/notarize-mac.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not accepted", result.stderr)
        self.assertFalse(any(args[:2] == ["stapler", "staple"] for _, args in self.calls()))
        self.assert_archive_unchanged()

    def test_failed_gatekeeper_assessment_cannot_replace_archive(self):
        self.env.update(CODEX_LEDGER_NOTARY_PROFILE="synthetic-policy-profile", LEDGER_POLICY_CERT="developer-id",
                        LEDGER_POLICY_NOTARY_STATUS="Accepted", LEDGER_POLICY_ASSESS_EXIT="3")
        self.assertNotEqual(self.run_script("distribution/notarize-mac.sh").returncode, 0)
        self.assertTrue(any(name == "spctl" for name, _ in self.calls()))
        self.assert_archive_unchanged()

    def test_formal_packaging_requires_stapled_ticket(self):
        self.env.update(CODEX_LEDGER_SIGNING_MODE="developer-id", LEDGER_POLICY_STAPLER_EXIT="65")
        self.assertNotEqual(self.run_script("package.sh").returncode, 0)
        self.assertFalse(list(Path(self.env["CODEX_LEDGER_OUTPUT_DIR"]).glob("*.dmg")))
        self.assertFalse((Path(self.env["CODEX_LEDGER_OUTPUT_DIR"]) / "CHECKSUMS.txt").exists())
        self.assert_archive_unchanged()

    def test_zip_roundtrip_losing_ticket_cannot_replace_archive(self):
        self.env.update(CODEX_LEDGER_NOTARY_PROFILE="synthetic-policy-profile", LEDGER_POLICY_CERT="developer-id",
                        LEDGER_POLICY_NOTARY_STATUS="Accepted", LEDGER_POLICY_ARCHIVE_TICKET_EXIT="65")
        self.assertNotEqual(self.run_script("distribution/notarize-mac.sh").returncode, 0)
        self.assertTrue(any(args[:2] == ["stapler", "validate"] and "/archive-check/" in args[-1] for _, args in self.calls()))
        self.assert_archive_unchanged()


if __name__ == "__main__":
    unittest.main()
