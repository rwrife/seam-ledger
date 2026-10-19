#!/usr/bin/env bash
# Zero-network gate (issue #1, binding project contract).
#
# SeamLedger is zero-network BY CONSTRUCTION: the app, the UI tests, and the
# domain package must never use network APIs. Only the exact GRDB build-time
# dependency declaration below is exempt from the URL scan; runtime APIs are not.
#
# Scanned roots: App/ and UITests/ (app sources) and Packages/*/Sources/.
# SwiftPM .build directories are skipped so vendored checkouts never trip
# the first-party scan.
set -euo pipefail

cd "$(dirname "$0")/.."

ROOTS=("App" "UITests" "Packages")
ALLOWLIST=()   # runtime allowlist remains empty

python3 scripts/check_dependencies.py

PATTERNS=(
  '\bURLSession\b'
  '\bNWConnection\b'
  '\bNWListener\b'
  '\bNWConnectionGroup\b'
  '\bNWBrowser\b'
  '\bNetService\b'
  '\bCFNetwork\b'
  '\bimport[[:space:]]+Network\b'
  '\bCFStream\b'
  '\bCFSocket\b'
  '\bCocoaHTTPServer\b'
  '\bWebSocket\b'
  '\bgetaddrinfo\b'
  '\bsocket[[:space:]]*\('
  '\bconnect[[:space:]]*\('
  '\blisten[[:space:]]*\('
  '\bbind[[:space:]]*\('
  '\baccept[[:space:]]*\('
  '\bNSURLSession\b'
  '\bCF(Read|Write)StreamCreatePairWithSocketToHost\b'
  '\bimport[[:space:]]+(CloudKit|WebKit)\b'
  '\b(Data|NSData|String|NSString|NSArray|NSDictionary)[[:space:]]*\([[:space:]]*contentsOf(URL)?[[:space:]]*:'
  'https?://'
)
# Remote-capable contentsOf initializers are deliberately prohibited here.
# Future local imports must use a reviewed file-only adapter before relaxing this gate.

matches=""
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { echo "ZERO-NETWORK GATE FAILED — missing source root: $root" >&2; exit 1; }
  for pat in "${PATTERNS[@]}"; do
    if hits=$(grep -RnE --include='*.swift' --include='*.h' --include='*.m' --include='*.c' \
      --exclude-dir=.build --exclude-dir=.swiftpm \
      "$pat" "$root"); then
      # Exempt only this entire reviewed declaration at this exact manifest path.
      hits=$(printf '%s\n' "$hits" | sed '\|^Packages/SeamLedgerStore/Package.swift:[0-9][0-9]*:        \.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),$|d')
      matches+="$hits"$'\n'
    else
      code=$?
      [ "$code" -eq 1 ] || { echo "ZERO-NETWORK GATE FAILED — grep error: $code" >&2; exit "$code"; }
    fi
  done
done

# Filter allowlisted lines (exact substring match against allowlist entries)
if [ -n "$matches" ]; then
  filtered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    skip=0
    for a in ${ALLOWLIST[@]+"${ALLOWLIST[@]}"}; do
      [[ "$line" == *"$a"* ]] && { skip=1; break; }
    done
    [ "$skip" -eq 0 ] && filtered+="$line"$'\n'
  done <<< "$matches"
  if [ -n "$filtered" ]; then
    echo "ZERO-NETWORK GATE FAILED — network API usage found (allowlist is empty):"
    printf '%s' "$filtered"
    exit 1
  fi
fi

echo "Zero-network gate: PASS (empty allowlist, no network API usage found)"
