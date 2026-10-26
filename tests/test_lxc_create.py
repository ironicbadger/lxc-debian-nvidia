"""Exercise helper behavior without a Proxmox host or network access."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "proxmox/lxc-create.sh"
# Load the functions without running the command-line entry point.
FUNCTIONS = SCRIPT.read_text().split('while [[ "$#" -gt 0 ]]; do', 1)[0]


class CreateHelperTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def run_functions(self, commands):
        return subprocess.run(
            ["bash", "-c", FUNCTIONS + '\nDEFAULT_TEMPLATE_CACHE_DIR="$1"\n' + commands,
             "test", str(self.root)],
            text=True, capture_output=True,
        )

    def test_first_download_returns_only_existing_filename(self):
        result = self.run_functions('''
curl() {
    while [[ "$1" != -o ]]; do shift; done
    printf 'template contents' > "$2"
}
TEMPLATE=$(download_template 123)
[[ -s "$TEMPLATE" ]]
printf '%s' "$TEMPLATE"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.root / "nvidia-template-debian13-123.tar.gz"))
        self.assertIn("Downloading template", result.stderr)

    def test_cached_template_skips_download(self):
        template = self.root / "nvidia-template-debian13-123.tar.gz"
        template.write_text("cached template")
        result = self.run_functions('curl() { return 99; }; download_template 123')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(template))
        self.assertEqual(template.read_text(), "cached template")

    def test_failed_download_does_not_poison_cache(self):
        result = self.run_functions('''
curl() {
    while [[ "$1" != -o ]]; do shift; done
    printf 'partial contents' > "$2"
    return 22
}
TEMPLATE=$(download_template 123)
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertEqual(result.stdout, "")

    def test_empty_download_is_rejected(self):
        result = self.run_functions('curl() { return 0; }; download_template 123')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.root.iterdir()), [])

    def storage_result(self, rows):
        (self.root / "storage").write_text("Name Type Status Total Used Available %\n" + rows)
        return self.run_functions('''
pvesm() {
    [[ "$*" == "status --content rootdir --enabled 1" ]] || return 99
    cat "$DEFAULT_TEMPLATE_CACHE_DIR/storage"
}
detect_storage
''')

    def test_storage_preference_does_not_depend_on_listing_order(self):
        result = self.storage_result(
            "local dir active 100 1 99 1\n"
            "local-zfs zfspool active 100 1 99 1\n"
            "local-lvm lvmthin active 100 1 99 1\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "local-lvm")

    def test_storage_skips_inactive_and_uses_custom_pool(self):
        result = self.storage_result(
            "local-lvm lvmthin inactive 0 0 0 0\n"
            "custom zfspool active 100 1 99 1\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "custom")

    def test_no_eligible_storage_fails_without_stdout(self):
        result = self.storage_result("local-lvm lvmthin inactive 0 0 0 0\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("rootdir", result.stderr)

    def test_storage_command_failure_propagates(self):
        result = self.run_functions('pvesm() { return 1; }; detect_storage')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_local_template_reaches_create_without_network(self):
        template = self.root / "local template.tar.gz"
        template.write_text("local template")
        environment = os.environ.copy()
        environment.pop("DRIVER_VERSION", None)
        environment.pop("TEMPLATE", None)
        environment["TEST_DIRECTORY"] = str(self.root)
        result = subprocess.run(
            ["bash", "-c", '''
pct() {
    printf '%s\\n' "$@" > "$TEST_DIRECTORY/pct-args"
    # Stop before the script writes any host configuration.
    return 73
}
pvesm() { return 99; }
curl() { touch "$TEST_DIRECTORY/network-called"; return 22; }
export -f pct pvesm curl
bash "$1" --id 999999998 --storage local-lvm --password test --template "$2"
''', "test", str(SCRIPT), str(template)],
            env=environment, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 73, result.stderr)
        self.assertFalse((self.root / "network-called").exists())
        args = (self.root / "pct-args").read_text().splitlines()
        self.assertEqual(args[:3], ["create", "999999998", str(template)])


if __name__ == "__main__":
    unittest.main()
