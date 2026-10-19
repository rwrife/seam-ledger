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
        for name in ("check_zero_network.sh", "check_native_only.sh"):
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

    def test_maui_property_fails(self):
        (self.root / "Sketch.csproj").write_text("<Project><UseMaui>true</UseMaui></Project>")
        self.assertNotEqual(self.run_gate("check_native_only.sh").returncode, 0)

    def test_groovy_kmp_fails(self):
        (self.root / "build.gradle").write_text("plugins { id 'org.jetbrains.kotlin.multiplatform' }")
        self.assertNotEqual(self.run_gate("check_native_only.sh").returncode, 0)


if __name__ == "__main__":
    unittest.main()
