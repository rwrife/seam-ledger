import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ContractGateTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        for dirname in ("App", "UITests", "Packages", "scripts"):
            (self.root / dirname).mkdir()
        for name in ("check_zero_network.sh", "check_native_only.sh", "check_dependencies.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)

    def run_gate(self, name):
        return subprocess.run(["bash", str(self.root / "scripts" / name)],
                              cwd=self.root, capture_output=True, text=True)

    def test_missing_network_scan_root_fails(self):
        (self.root / "UITests").rmdir()
        self.assertNotEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_remote_data_load_fails(self):
        (self.root / "App" / "Fetch.swift").write_text(
            'let payload = try Data(contentsOf: URL(string: "https://example.com")!)\n'
        )
        self.assertNotEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_exact_grdb_dependency_passes(self):
        store = self.root / "Packages" / "SeamLedgerStore"
        store.mkdir()
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.swift", store)
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.resolved", store)
        self.assertEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_changed_grdb_pin_and_other_dependencies_fail(self):
        store = self.root / "Packages" / "SeamLedgerStore"
        store.mkdir()
        manifest = store / "Package.swift"
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.resolved", store)
        original = (ROOT / "Packages/SeamLedgerStore/Package.swift").read_text()
        for changed in (original.replace('exact: "7.8.0"', 'from: "7.8.0"'),
                        original.replace('exact: "7.8.0"', 'exact: "7.9.0"'),
                        original.replace('groue/GRDB.swift', 'other/GRDB.swift')):
            manifest.write_text(changed)
            self.assertNotEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_changed_lock_revision_fails(self):
        store = self.root / "Packages" / "SeamLedgerStore"
        store.mkdir()
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.swift", store)
        lock = store / "Package.resolved"
        lock.write_text((ROOT / "Packages/SeamLedgerStore/Package.resolved").read_text().replace(
            "18497b68fdbb3a09528d260a0a0e1e7e61c8c53d", "0" * 40))
        self.assertNotEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_runtime_network_api_still_fails_with_grdb(self):
        store = self.root / "Packages" / "SeamLedgerStore"
        store.mkdir()
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.swift", store)
        shutil.copy2(ROOT / "Packages/SeamLedgerStore/Package.resolved", store)
        (self.root / "App" / "Fetch.swift").write_text('import Foundation\nlet client = URLSession.shared\n')
        self.assertNotEqual(self.run_gate("check_zero_network.sh").returncode, 0)

    def test_maui_property_fails(self):
        (self.root / "Sketch.csproj").write_text("<Project><UseMaui>true</UseMaui></Project>")
        self.assertNotEqual(self.run_gate("check_native_only.sh").returncode, 0)

    def test_groovy_kmp_fails(self):
        (self.root / "build.gradle").write_text("plugins { id 'org.jetbrains.kotlin.multiplatform' }")
        self.assertNotEqual(self.run_gate("check_native_only.sh").returncode, 0)


if __name__ == "__main__":
    unittest.main()
