"""Build-time dependency exception; runtime source scanning stays strict."""
import json
from pathlib import Path
import re

REMOTE = '.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0")'
STORE = Path("Packages/SeamLedgerStore/Package.swift")
if STORE.exists() and not STORE.with_name("Package.resolved").is_file():
    raise SystemExit("Store requires the reviewed GRDB Package.resolved")
for manifest in Path("Packages").glob("*/Package.swift"):
    text = manifest.read_text()
    declarations = re.findall(r"\.package\s*\([^)]*\)", text)
    for declaration in declarations:
        if declaration == REMOTE and manifest == STORE:
            continue
        if re.fullmatch(r'\.package\(path: "\.\./SeamLedgerKit"\)', declaration):
            continue
        raise SystemExit(f"Unapproved package dependency in {manifest}: {declaration}")
    if manifest == STORE and declarations.count(REMOTE) != 1:
        raise SystemExit("Store must declare exactly pinned GRDB 7.8.0")

for lock in Path("Packages").glob("*/Package.resolved"):
    pins = json.loads(lock.read_text())["pins"]
    if len(pins) != 1 or pins[0] != {
        "identity": "grdb.swift",
        "kind": "remoteSourceControl",
        "location": "https://github.com/groue/GRDB.swift.git",
        "state": {"revision": "18497b68fdbb3a09528d260a0a0e1e7e61c8c53d", "version": "7.8.0"},
    }:
        raise SystemExit(f"Unapproved resolved dependency in {lock}")
