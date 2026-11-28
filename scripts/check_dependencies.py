"""Reviewed build-time dependency pins; runtime source scanning stays strict.

Guarantees hold textually on the manifest, before SwiftPM evaluation:
every ``.package`` mention must match one approved exact declaration (the
Store's GRDB and Swift Crypto pins or a Packages/-internal local path). Extra
declarations hidden by comments or spacing (e.g. ``.package/*c*/(path:
"../../Vendor")``) fail closed. Local paths must resolve inside Packages/
so runtime source scanning covers them.
"""
import json
from pathlib import Path
import re

REMOTE = '.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0")'
CRYPTO = '.package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1")'
LOCAL = re.compile(r'\.package\(path: "([^"]+)"\)')
STORE = Path("Packages/SeamLedgerStore/Package.swift")
if STORE.exists() and not STORE.with_name("Package.resolved").is_file():
    raise SystemExit("Store requires the reviewed GRDB Package.resolved")

# Fail closed: supported declarations are intentionally exact textual forms.
# A future manifest rewrite must update this allowlist and its regression tests.
DECLARATION = re.compile(r'\.package\(\s*(?:url: "https://github\.com/(?:groue/GRDB\.swift|apple/swift-crypto)\.git", exact: "(?:7\.8\.0|3\.15\.1)"|path: "[^"]+")\s*\)')

manifests = sorted(Path("Packages").glob("*/Package.swift"))
for manifest in manifests:
    text = manifest.read_text()
    declarations = DECLARATION.findall(text)
    if text.count(".package") != len(declarations):
        raise SystemExit(f"Unparseable/extra .package mention in {manifest}")
    remote_count = 0
    crypto_count = 0
    for declaration in declarations:
        if declaration == REMOTE and manifest == STORE:
            remote_count += 1
            continue
        if declaration == CRYPTO and manifest == STORE:
            crypto_count += 1
            continue
        match = LOCAL.fullmatch(declaration)
        if match:
            target = (manifest.parent / match.group(1)).resolve()
            packages_root = Path("Packages").resolve()
            if packages_root not in target.parents or not target.is_dir():
                raise SystemExit(f"Local dependency escapes Packages/ in {manifest}: {declaration}")
            if not (target / "Package.swift").is_file():
                raise SystemExit(f"Local dependency has no manifest in {manifest}: {declaration}")
            continue
        raise SystemExit(f"Unapproved package dependency in {manifest}: {declaration}")
    if manifest == STORE and (remote_count != 1 or crypto_count != 1):
        raise SystemExit("Store must declare exactly pinned GRDB 7.8.0 and Swift Crypto 3.15.1")

for lock in Path("Packages").glob("*/Package.resolved"):
    pins = json.loads(lock.read_text())["pins"]
    expected = {
        "grdb.swift": ("https://github.com/groue/GRDB.swift.git", "18497b68fdbb3a09528d260a0a0e1e7e61c8c53d", "7.8.0"),
        "swift-asn1": ("https://github.com/apple/swift-asn1.git", "97fd57437fc94cfa6b62f2b8f84c50f433534e17", "1.7.5"),
        "swift-crypto": ("https://github.com/apple/swift-crypto.git", "95ba0316a9b733e92bb6b071255ff46263bbe7dc", "3.15.1"),
    }
    observed = {
        pin["identity"]: (pin["location"], pin["state"]["revision"], pin["state"]["version"])
        for pin in pins
        if pin["kind"] == "remoteSourceControl"
    }
    if len(pins) != len(expected) or observed != expected:
        raise SystemExit(f"Unapproved resolved dependency in {lock}")
