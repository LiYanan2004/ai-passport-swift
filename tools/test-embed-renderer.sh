#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="${EMBEDDED_TEST_BUILD_DIR:-$(mktemp -d /tmp/ai-passport-embed-tests.XXXXXX)}"
mkdir -p "${test_dir}"
if [[ -z "${EMBEDDED_TEST_BUILD_DIR:-}" ]]; then
    trap 'rm -rf -- "${test_dir}"' EXIT
fi
python3 "${repo_root}/tools/check-embedded-reference.py"
default_toolchain="/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a.xctoolchain"
if [[ -x "${default_toolchain}/usr/bin/swiftc" ]]; then
    default_swift_compiler="${default_toolchain}/usr/bin/swiftc"
else
    default_swift_compiler="swiftc"
fi
swift_compiler="${SWIFTC:-${default_swift_compiler}}"
source_root="${repo_root}/main/EmbeddedSwiftUI/Sources"
compiler_options=(-enable-experimental-feature Embedded -package-name EmbeddedSwiftUI -wmo -parse-as-library -Osize
                  -module-cache-path "${test_dir}/module-cache")
linker_options=()
if [[ "$(uname -s)" == Darwin ]]; then
    compiler_options+=(-sdk "$(xcrun --sdk macosx --show-sdk-path)")
    unicode_library_dir="$(cd -- "$(dirname -- "${swift_compiler}")/../lib/swift/embedded/$(uname -m)-apple-macos" 2>/dev/null && pwd || true)"
    if [[ -f "${unicode_library_dir}/libswiftUnicodeDataTables.a" ]]; then
        linker_options+=(-L "${unicode_library_dir}" -lswiftUnicodeDataTables)
    fi
fi

bash "${repo_root}/tools/build-swift-property-generator.sh" \
    "${swift_compiler}" "${test_dir}/generate-dynamic-properties"
"${test_dir}/generate-dynamic-properties" \
    "${repo_root}/tests/TestEmbedRenderer.swift" "${test_dir}/TestEmbedRenderer.swift"

"${swift_compiler}" "${compiler_options[@]}" -emit-module -emit-library -static \
    -module-name EmbeddedSwiftUI -emit-module-path "${test_dir}/EmbeddedSwiftUI.swiftmodule" \
    "${source_root}"/EmbeddedSwiftUI/*.swift -o "${test_dir}/libEmbeddedSwiftUI.a"
"${swift_compiler}" "${compiler_options[@]}" -I "${test_dir}" -L "${test_dir}" \
    -lEmbeddedSwiftUI "${test_dir}/TestEmbedRenderer.swift" \
    "${linker_options[@]}" \
    -o "${test_dir}/test_embed_renderer"
"${test_dir}/test_embed_renderer"

"${swift_compiler}" "${compiler_options[@]}" -I "${test_dir}" -L "${test_dir}" \
    -lEmbeddedSwiftUI "${repo_root}/tests/TestViewStorage.swift" \
    "${linker_options[@]}" -o "${test_dir}/test_view_storage"
"${test_dir}/test_view_storage"

"${test_dir}/generate-dynamic-properties" \
    "${repo_root}/tests/TestViewAlignment.swift" "${test_dir}/TestViewAlignment.swift"
"${swift_compiler}" "${compiler_options[@]}" -I "${test_dir}" -L "${test_dir}" \
    -lEmbeddedSwiftUI "${test_dir}/TestViewAlignment.swift" \
    "${linker_options[@]}" -o "${test_dir}/test_view_alignment"
"${test_dir}/test_view_alignment"

"${test_dir}/generate-dynamic-properties" \
    "${repo_root}/tests/TestViewP1.swift" "${test_dir}/TestViewP1.swift"
"${swift_compiler}" "${compiler_options[@]}" -I "${test_dir}" -L "${test_dir}" \
    -lEmbeddedSwiftUI "${test_dir}/TestViewP1.swift" \
    "${linker_options[@]}" -o "${test_dir}/test_view_p1"
"${test_dir}/test_view_p1"

if [[ "${1:-}" == --lvgl ]]; then
    lvgl_root="${repo_root}/managed_components/lvgl__lvgl"
    lvgl_build_dir="${LVGL_HOST_BUILD_DIR:-${test_dir}/lvgl}"
    if [[ ! -f "${lvgl_root}/CMakeLists.txt" ]]; then
        echo "Initialize ESP-IDF dependencies before running --lvgl." >&2
        exit 1
    fi
    cmake -G Ninja -S "${lvgl_root}" -B "${lvgl_build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLV_BUILD_CONF_PATH="${repo_root}/tests/lvgl/lv_conf.h" \
        -DCONFIG_LV_BUILD_DEMOS=OFF -DCONFIG_LV_BUILD_EXAMPLES=OFF \
        -DCONFIG_LV_USE_THORVG_INTERNAL=OFF
    cmake --build "${lvgl_build_dir}" --target lvgl --parallel 8
    configuration_define="-DLV_CONF_PATH=\"${repo_root}/tests/lvgl/lv_conf.h\""
    cc -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" "${configuration_define}" \
        -c "${repo_root}/tests/lvgl/TestScreenSnapshotBridge.c" \
        -o "${test_dir}/snapshot_test_support.o"
    "${test_dir}/generate-dynamic-properties" \
        "${repo_root}/main/EmbeddedSwiftUIDemoView.swift" "${test_dir}/EmbeddedSwiftUIDemoView.swift"
    "${test_dir}/generate-dynamic-properties" \
        "${repo_root}/tests/TestLVEmbedRenderer.swift" "${test_dir}/TestLVEmbedRenderer.swift"
    "${swift_compiler}" "${compiler_options[@]}" -emit-module -emit-library -static \
        -module-name LVGLRendererAdaptor \
        -emit-module-path "${test_dir}/LVGLRendererAdaptor.swiftmodule" \
        -I "${test_dir}" -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" -Xcc "${configuration_define}" \
        -import-bridging-header \
        "${repo_root}/main/HeaderBridge.h" \
        "${source_root}"/LVGLRendererAdaptor/*.swift \
        -o "${test_dir}/libLVGLRendererAdaptor.a"
    "${swift_compiler}" "${compiler_options[@]}" \
        -I "${test_dir}" -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" \
        -Xcc "${configuration_define}" \
        -import-bridging-header "${repo_root}/main/HeaderBridge.h" \
        -L "${test_dir}" -lLVGLRendererAdaptor -lEmbeddedSwiftUI \
        "${repo_root}/tests/TestLVGLAnimationTiming.swift" \
        "${test_dir}/snapshot_test_support.o" "${lvgl_build_dir}/lib/liblvgl.a" \
        "${linker_options[@]}" -o "${test_dir}/test_lvgl_animation_timing"
    "${test_dir}/test_lvgl_animation_timing"
    "${test_dir}/generate-dynamic-properties" \
        "${repo_root}/main/Main.swift" "${test_dir}/Main.swift"
    "${test_dir}/generate-dynamic-properties" \
        "${repo_root}/main/ConnectivityStatusView.swift" \
        "${test_dir}/ConnectivityStatusView.swift"
    allocation_linker_options=("${linker_options[@]}")
    if [[ "$(uname -s)" == Darwin ]]; then
        cc -O2 -dynamiclib "${repo_root}/tests/lvgl/TestAllocationBudgetBridge.c" \
            -o "${test_dir}/libAllocationBudgetSupport.dylib"
        allocation_linker_options+=(-lAllocationBudgetSupport)
    else
        cc -O2 -c "${repo_root}/tests/lvgl/TestAllocationBudgetBridge.c" \
            -o "${test_dir}/allocation_budget_support.o"
        allocation_linker_options+=("${test_dir}/allocation_budget_support.o")
        allocation_linker_options+=(-Xlinker --wrap=posix_memalign)
    fi
    "${swift_compiler}" "${compiler_options[@]}" \
        -I "${test_dir}" -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" \
        -Xcc "${configuration_define}" \
        -import-bridging-header "${repo_root}/main/HeaderBridge.h" \
        -L "${test_dir}" -lLVGLRendererAdaptor -lEmbeddedSwiftUI \
        "${test_dir}/Main.swift" "${test_dir}/ConnectivityStatusView.swift" \
        "${test_dir}/EmbeddedSwiftUIDemoView.swift" \
        "${repo_root}/tests/TestLVGLMemoryBudget.swift" \
        "${test_dir}/snapshot_test_support.o" \
        "${lvgl_build_dir}/lib/liblvgl.a" \
        "${allocation_linker_options[@]}" -o "${test_dir}/test_lvgl_memory_budget"
    "${test_dir}/test_lvgl_memory_budget"
    "${swift_compiler}" "${compiler_options[@]}" -I "${test_dir}" -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" \
        -Xcc "${configuration_define}" \
        -import-bridging-header \
        "${repo_root}/main/HeaderBridge.h" \
        -L "${test_dir}" -lLVGLRendererAdaptor -lEmbeddedSwiftUI \
        "${test_dir}/EmbeddedSwiftUIDemoView.swift" \
        "${test_dir}/TestLVEmbedRenderer.swift" \
        "${test_dir}/snapshot_test_support.o" "${lvgl_build_dir}/lib/liblvgl.a" \
        "${linker_options[@]}" \
        -o "${test_dir}/test_lvgl_renderer"
    "${test_dir}/test_lvgl_renderer"

    cc -O2 -pthread -c "${repo_root}/tests/lvgl/TestStackBudgetBridge.c" \
        -o "${test_dir}/stack_budget_support.o"
    "${swift_compiler}" "${compiler_options[@]}" \
        -I "${test_dir}" -I "${lvgl_root}" -I "${repo_root}/tests/lvgl" \
        -Xcc "${configuration_define}" \
        -import-bridging-header "${repo_root}/main/HeaderBridge.h" \
        -L "${test_dir}" -lLVGLRendererAdaptor -lEmbeddedSwiftUI \
        "${test_dir}/EmbeddedSwiftUIDemoView.swift" \
        "${repo_root}/tests/TestLVGLStackBudget.swift" \
        "${test_dir}/snapshot_test_support.o" "${test_dir}/stack_budget_support.o" \
        "${lvgl_build_dir}/lib/liblvgl.a" "${linker_options[@]}" \
        -o "${test_dir}/test_lvgl_stack_budget"
    "${test_dir}/test_lvgl_stack_budget"
fi
