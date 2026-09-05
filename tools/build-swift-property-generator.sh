#!/usr/bin/env bash
set -euo pipefail
swift_compiler="$1"
output="$2"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
host_libraries="$(cd -- "$(dirname -- "${swift_compiler}")/../lib/swift/host" && pwd)"
options=(-parse-as-library -O -I "${host_libraries}" -L "${host_libraries}"
         -Xlinker -rpath -Xlinker "${host_libraries}")
if [[ "$(uname -s)" == Darwin ]]; then
    options+=(-sdk "$(xcrun --sdk macosx --show-sdk-path)")
fi
mkdir -p "$(dirname -- "${output}")"
"${swift_compiler}" "${options[@]}" \
    "${repo_root}/tools/GenerateDynamicProperties.swift" -o "${output}"
