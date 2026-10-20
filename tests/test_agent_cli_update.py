"""Exercise updater boundaries without network or the real home directory."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'lib/agent-cli-update.py'


class AgentCliUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home))
        self.config = self.home / '.config/mise/config.toml'
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[tools]\ncodex="latest"\nclaude="latest"\nnode="26.10.0"\n')
        for tool in ('codex', 'claude'):
            binary = self.home / '.local/share/mise/installs' / tool / '1.0/bin' / tool
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\n[ "${FAIL_TOOL:-}" != "' + tool + '" ]\n')
            binary.chmod(0o755)
        self.mise = self.home / 'mise'
        self.mise.write_text(f'#!{sys.executable}\n' + '''import os,sys,json
from pathlib import Path
h=Path.home()
with (h/'calls').open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
assert sys.argv[1:3] == ['--cd', '/']
assert os.environ['MISE_MINIMUM_RELEASE_AGE'] == '24h'
assert os.environ['MISE_GLOBAL_CONFIG_FILE'] == str(h/'.config/mise/config.toml')
if sys.argv[3] == 'install':
    assert sys.argv[4:] == ['codex@latest','claude@latest','--yes','--minimum-release-age','24h']
    sys.exit(int(os.environ.get('FAIL_UPGRADE','0')))
if os.environ.get('OUTSIDE_INSTALLS'):
    print('/bin/sh')
else:
    assert sys.argv[3] == 'where'
    print(h/'.local/share/mise/installs'/sys.argv[4]/'1.0')
''')
        self.mise.chmod(0o755)
        self.links = self.home / '.local/state/agent-cli-update/bin'

    def run_update(self, **extra):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.mise)],
                              env=self.env | extra, capture_output=True, text=True)

    def test_success_does_not_rewrite_config(self):
        original = self.config.read_bytes()
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.links/'codex').resolve().is_file())
        self.assertTrue((self.links/'claude').resolve().is_file())
        self.assertEqual(self.config.read_bytes(), original)

    def test_failed_update_or_verification_preserves_launchers(self):
        self.assertEqual(self.run_update().returncode, 0)
        before = (self.links/'codex').lstat().st_mtime_ns
        for failure in ({'FAIL_TOOL': 'claude'}, {'FAIL_UPGRADE': '1'}, {'OUTSIDE_INSTALLS': '1'}):
            with self.subTest(failure=failure):
                self.assertEqual(self.run_update(**failure).returncode, 1)
                self.assertEqual((self.links/'codex').lstat().st_mtime_ns, before)

    def test_lock_prevents_concurrent_mise_runs(self):
        self.links.parent.mkdir(parents=True)
        with (self.links.parent/'lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_update()
            self.assertEqual(result.returncode, 0)
            self.assertIn('already running', result.stdout)
            self.assertFalse((self.home/'calls').exists())

    def test_pinned_or_missing_config_is_not_overwritten(self):
        self.config.write_text('[tools]\ncodex="0.1.0"\nclaude="latest"\n')
        self.assertEqual(self.run_update().returncode, 1)
        self.assertFalse((self.home/'calls').exists())
        self.config.unlink()
        self.assertEqual(self.run_update().returncode, 1)
        self.assertFalse((self.home/'calls').exists())


if __name__ == '__main__':
    unittest.main()
