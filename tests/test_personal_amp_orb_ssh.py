"""Run with python3 -m unittest discover -s tests -p test_personal_amp_orb_ssh.py.

Requires Nix with the locked nixpkgs input available, sshd, and ssh-keygen.
Renders the real Spark module without activating it or building host packages.
"""

import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def render(host):
    expression = r'''
      let
        f = builtins.getFlake (toString ./.);
        lib = f.inputs.nixpkgs.lib // {
          hm.dag.entryAfter = _: text: text;
          mkIf = condition: value: if condition then value else null;
        };
        pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux // {
          writeText = builtins.toFile;
          writeShellScript = name: text:
            builtins.toFile name (builtins.unsafeDiscardStringContext text);
        };
        m = (import ./users/dgx-spark.nix { currentSystemName = HOST; }) {
          inherit lib pkgs;
        };
      in m.home.activation.dgxSparkRootSync
    '''.replace("HOST", json.dumps(host))
    result = subprocess.check_output(
        ["nix", "eval", "--impure", "--json", "--expr", expression], cwd=ROOT
    )
    activation = json.loads(result)
    if not activation:
        return None, {}
    script_path = re.search(r"sudo -n (/nix/store/\S+-dgx-spark-root-sync)", activation)[1]
    script = Path(script_path).read_text()
    files = {}
    for line in script.splitlines():
        if line.strip().startswith("sync_file /etc/"):
            args = shlex.split(line)
            files[args[1]] = (args[2], Path(args[3]).read_text())
    return script, files


class PersonalAmpOrbSSH(unittest.TestCase):
    def test_spark_scope_and_effective_sshd_configuration(self):
        key_path = "/etc/ssh/personal-amp-orbs-authorized_keys"
        canonical = (ROOT / "users/joost/ssh/personal-amp-orbs.pub").read_text()
        # An empty file is the documented revoked state.
        for line in canonical.splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            self.assertIn('from="100.64.0.0/10,fd7a:115c:a1e0::/48"', line)
            for option in (
                "no-agent-forwarding", "no-port-forwarding",
                "no-X11-forwarding", "no-user-rc",
            ):
                self.assertIn(option, line)
            self.assertNotIn("no-pty", line)
        for host in ("spark", "spark2"):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as directory:
                script, files = render(host)
                self.assertEqual(files[key_path], ("0644", canonical))
                subprocess.run(["bash", "-n"], input=script, text=True, check=True)
                temp = Path(directory)
                host_key = temp / "host_key"
                subprocess.run(
                    ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(host_key)],
                    check=True,
                )
                dropins = temp / "sshd_config.d"
                dropins.mkdir()
                for path, (_, text) in files.items():
                    if path.startswith("/etc/ssh/sshd_config.d/"):
                        (dropins / Path(path).name).write_text(text)
                config = temp / "sshd_config"
                # Global-only directives after Include catch Match context leaks.
                config.write_text(f"Include {dropins}/*.conf\nUsePAM yes\n")
                for user, port, expected in (
                    ("joost", 2222, True), ("joost", 22, False),
                    ("root", 2222, False), ("someone", 2222, False),
                ):
                    output = subprocess.check_output([
                        "/usr/sbin/sshd", "-T", "-f", str(config), "-h", str(host_key),
                        "-C", f"user={user},addr=100.64.0.1,laddr=100.64.0.2,lport={port}",
                    ], text=True)
                    settings = dict(line.split(" ", 1) for line in output.splitlines())
                    self.assertEqual(key_path in settings["authorizedkeysfile"], expected)
                    self.assertIn(".ssh/authorized_keys", settings["authorizedkeysfile"])
                    self.assertEqual(settings["permittty"], "yes")
                    self.assertEqual(settings["passwordauthentication"], "no")
                    self.assertEqual(settings["permitrootlogin"], "no")

    def test_other_hosts_do_not_install_spark_root_files(self):
        for host in ("bali", "fu137", "j9", "radon"):
            with self.subTest(host=host):
                self.assertEqual(render(host), (None, {}))


if __name__ == "__main__":
    unittest.main()
