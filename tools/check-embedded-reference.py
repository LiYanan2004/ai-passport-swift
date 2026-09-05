#!/usr/bin/env python3
"""Verify the imported Embedded source baseline and its documented adaptations."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", type=Path, help="Reference EmbeddedSwiftUICore/Embedded directory")
arguments = parser.parse_args()
package = Path(__file__).resolve().parents[1] / "main/EmbeddedSwiftUI"
manifest = json.loads((package / "UPSTREAM.json").read_text())
entries = manifest["embedded_source_alignment"]
errors = []
for name, entry in entries.items():
    if "omitted" not in entry:
        local_path = entry.get("local_path")
        if local_path is None:
            local_path = f"Sources/EmbeddedSwiftUI/{entry['local_file']}"
        local = package / local_path
        expected = entry.get("local_sha256", entry["reference_sha256"])
        if not local.is_file() or hashlib.sha256(local.read_bytes()).hexdigest() != expected:
            errors.append(f"{name}: differs from the recorded source baseline")
    if arguments.reference:
        reference = arguments.reference / name
        if not reference.is_file() or hashlib.sha256(reference.read_bytes()).hexdigest() != entry["reference_sha256"]:
            errors.append(f"{name}: reference differs from the recorded import")
if arguments.reference:
    extra = {path.name for path in arguments.reference.glob("*.swift")} - entries.keys()
    errors.extend(f"{name}: reference file has no local mapping" for name in sorted(extra))
for relative_path in manifest.get("embedded_adaptation_comments", []):
    local = package / relative_path
    if not local.is_file():
        errors.append(f"{relative_path}: documented embedded adaptation is missing")
    elif "Embedded adaptation:" not in local.read_text():
        errors.append(f"{relative_path}: embedded adaptation comment is missing")
if errors:
    raise SystemExit("\n".join(errors))
adapted = sum(
    "local_sha256" in entry or "omitted" in entry
    for entry in entries.values()
)
print(f"Embedded reference: PASS ({len(entries) - adapted} identical, {adapted} documented adaptations)")
