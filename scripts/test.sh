#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ -f work/build/TranslationCore.swiftmodule ]] || ./scripts/build.sh
export CLANG_MODULE_CACHE_PATH="$PWD/work/clang-cache"
swiftc -vfsoverlay "$PWD/work/toolchain-overlay.json" -I work/build work/build/libTranslationCore.a Tests/Smoke/main.swift -o work/build/pipeline-tests
work/build/pipeline-tests
