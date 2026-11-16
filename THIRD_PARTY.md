# Third-party components

Kotonoha's own source code is licensed under Apache-2.0. Third-party licenses remain unchanged.

## llama.cpp

- Project: https://github.com/ggml-org/llama.cpp
- Pinned runtime: official Apple Silicon build `b12428`, commit `b4c0e00a4`.
- License: MIT; full text in [licenses/llama.cpp-LICENSE](licenses/llama.cpp-LICENSE).
- Runtime archive SHA256: `7d72477a2a375cc1d93e308b34e26fb9a608c2f93750517d2bafc59af578d3e2`.
- Release DMGs bundle the runtime and its original license. Source checkouts download it separately with `scripts/setup-runtime.sh`.

## Model weights

No model weights are included in this repository, source archives, app bundle, or release DMGs. Users must obtain their own compatible GGUF model and follow its license.

The optional `scripts/setup-runtime.sh --model` command downloads Qwen3-8B Q4_K_M from https://huggingface.co/Qwen/Qwen3-8B-GGUF, under Apache-2.0. Its SHA256 is `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`.

## Apple frameworks and media

AppKit, SwiftUI, Vision and ScreenCaptureKit are system frameworks supplied by macOS. No Apple framework or font files are redistributed.

The repository includes no game artwork, game audio, videos, or private recording fixtures. Optional local recording regression commands require files supplied separately by the developer; those files are not covered by this project's license.
