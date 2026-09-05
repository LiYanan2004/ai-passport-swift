#!/usr/bin/env bash
set -euo pipefail

mode="${1:---all}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "Usage: $0 [--all|--static|--firmware]" >&2
}

run_static_checks() {
    local actionlint_bin
    local test_dir

    python3 tools/check_repo.py

    actionlint_bin="${ACTIONLINT_BIN:-}"
    if [[ -z "${actionlint_bin}" ]]; then
        actionlint_bin="$(command -v actionlint || true)"
    fi
    if [[ -z "${actionlint_bin}" || ! -x "${actionlint_bin}" ]]; then
        actionlint_bin="$(./tools/install-actionlint.sh)"
    fi
    "${actionlint_bin}" -color .github/workflows/*.yml

    test_dir="$(mktemp -d /tmp/ai-passport-host-tests.XXXXXX)"
    swiftc tests/TestUIPixelMath.swift main/legacy/ui/UIPixelAnimation.swift \
        -o "${test_dir}/test_ui_pixel_math"
    "${test_dir}/test_ui_pixel_math"
    swiftc tests/TestWiFiCandidateSelector.swift main/models/wifi/WiFiCandidateSelector.swift \
        -o "${test_dir}/test_wifi_candidate_selector"
    "${test_dir}/test_wifi_candidate_selector"
    swiftc tests/TestWiFiReconnectTimer.swift main/models/wifi/WiFiReconnectTimer.swift \
        -o "${test_dir}/test_wifi_reconnect_timer"
    "${test_dir}/test_wifi_reconnect_timer"
    swiftc tests/TestKnownWiFiScanFormatter.swift main/models/wifi/KnownWiFiScanFormatter.swift \
        -o "${test_dir}/test_known_wifi_scan_formatter"
    "${test_dir}/test_known_wifi_scan_formatter"
    swiftc tests/TestAgentMonitorState.swift main/legacy/agentmonitor/AgentMonitorState.swift \
        -o "${test_dir}/test_agent_monitor_state"
    "${test_dir}/test_agent_monitor_state"
    swiftc tests/TestAgentMonitorUsageState.swift main/legacy/agentmonitor/AgentMonitorUsageState.swift \
        -o "${test_dir}/test_agent_monitor_usage_state"
    "${test_dir}/test_agent_monitor_usage_state"
    swiftc tests/TestCodexResetQueryStatus.swift \
        main/models/tibo/CodexResetQuery.swift main/models/tibo/TiboResetDate.swift \
        -o "${test_dir}/test_codex_reset_query_status"
    "${test_dir}/test_codex_reset_query_status"
    swiftc tests/TestMirrorStreamDecoder.swift \
        "PassportMirroring/PassportMirroring/Mirroring Models/MirrorStreamDecoder.swift" \
        -o "${test_dir}/test_mirror_stream_decoder"
    "${test_dir}/test_mirror_stream_decoder"
    if [[ "$(uname -s)" == Darwin ]]; then
        swiftc tests/TestUSBMirrorReceiver.swift \
            "PassportMirroring/PassportMirroring/Mirroring Models/USBMirrorReceiver.swift" \
            "PassportMirroring/PassportMirroring/Mirroring Models/MirrorStreamDecoder.swift" \
            -o "${test_dir}/test_usb_mirror_receiver"
        "${test_dir}/test_usb_mirror_receiver"
    fi
    python3 tests/test_verify_firmware.py
    bash tools/test-embed-renderer.sh
    rm -rf "${test_dir}"
    echo "Host tests: PASS"
}

run_firmware_checks() (
    local validation_build_dir

    if ! command -v idf.py >/dev/null 2>&1; then
        echo "ERROR: idf.py is not available; activate ESP-IDF 5.5.3 first." >&2
        return 1
    fi

    validation_build_dir="$(mktemp -d /tmp/ai-passport-firmware.XXXXXX)"
    trap 'case "${validation_build_dir}" in /tmp/ai-passport-firmware.*) rm -rf -- "${validation_build_dir}" ;; esac' EXIT

    SDKCONFIG_DEFAULTS="${repo_root}/sdkconfig.defaults" \
        idf.py -G Ninja -B "${validation_build_dir}" \
        -D "SDKCONFIG=${validation_build_dir}/sdkconfig" build
    idf.py -B "${validation_build_dir}" merge-bin \
        -o "${validation_build_dir}/FoloToy-AI-Passport-full.bin"
    python3 tools/verify_firmware.py "${validation_build_dir}"
    mkdir -p "${repo_root}/build"
    install -m 0644 \
        "${validation_build_dir}/FoloToy-AI-Passport-full.bin" \
        "${repo_root}/build/FoloToy-AI-Passport-full.bin"
    echo "Firmware build: PASS"
)

cd "${repo_root}"
case "${mode}" in
    --all)
        run_static_checks
        run_firmware_checks
        ;;
    --static)
        run_static_checks
        ;;
    --firmware)
        run_firmware_checks
        ;;
    *)
        usage
        exit 2
        ;;
esac
