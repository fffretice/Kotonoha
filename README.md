# Kotonoha

Local Japanese-to-Simplified-Chinese screen translation for visual novels on macOS. Select a game window, a screen region, or an entire display, and read translated text over the original dialogue.

Kotonoha uses Apple Vision for OCR and llama.cpp for local GGUF inference. **Model weights are not included: bring your own compatible model.**

Current preview: **0.8.1** · Apple Silicon · macOS 14 or later

## Download and get started

1. Download `Kotonoha-0.8.1-AppleSilicon.dmg` from [Releases](https://github.com/fffretice/Kotonoha/releases) and drag the app into Applications.
2. Open the app, choose a local GGUF model, and load it.
3. Select a display, draw a region, or choose a window. Confirm the shared content in the macOS system picker.
4. Check the preview and start translation.

The current app interface is in Simplified Chinese. This repository's documentation is in English.

Release builds currently use an ad-hoc development signature. **They are not Developer ID signed or notarized**, so Gatekeeper may block the first launch on another Mac. Verify the source and follow macOS's own prompts. The project does not provide scripts that disable system security checks.

## Features

- Full-display, region, and window capture.
- Existing translations remain visible while the same dialogue page adds characters or lines. Completed continuations replace them without first clearing the overlay; a new dialogue page clears the old content.
- A growing dialogue cover keeps its top-left anchor and background color to reduce visual jumps.
- Automatic, subtitle, and typewriter timing modes.
- Sampled background colors, dark or light covers, and a consistent font size.
- A terminology glossary, in-memory conversation history, and shortcuts to reveal the source.

Background blending uses sampled-color covers, **not generative inpainting**. Complex artwork, decorative fonts, and low-resolution text can still affect OCR and appearance.

## Models and memory

The app has been tested with Qwen3 in non-thinking mode, including 8B Q4_K_M and 30B-A3B Q4_K_M. The app also recognizes Sakura, GalTransl and HY-MT filenames and uses specialized plain-text prompts rather than forcing their output into JSON. Keep the family name when renaming files. Prior dialogue for Sakura/GalTransl uses separate conversation turns, and context is scoped to nearby regions. Recognized speaker labels and fixed playback controls retain the game appearance. Rejected native replies get one history-free retry before a region backs off. Quality and latency depend on the model, quantization, context, and competing GPU workloads. Parameter count alone does not predict performance.

- The current backend loads local GGUF files. It does not connect directly to Ollama servers, cloud APIs, or ChatGPT accounts.
- The model-file limit is 20 GiB. Context and compute buffers require additional memory; this is not a process-memory cap.
- Unloading terminates the model process. macOS releases its resources after the process exits, while the model file stays on disk. Reclaimable file caches may remain.
- Follow the license of each model you choose.

## Shortcuts and usage tips

| Shortcut | Action |
| --- | --- |
| Control + Option + T | Start or pause translation |
| Control + Option + R | Select a region again |
| Control + Option + H | Reveal the source or restore the overlay |

Automatic mode can start a high-confidence, punctuated complete sentence after the first OCR observation. Incomplete typing still waits for a quiet interval; an explicitly longer stability delay is respected. Use typewriter mode when you prefer a quiet interval even on first-seen complete sentences. Completed prefixes stay visible while the same dialogue page grows; replaced dialogue cancels obsolete work. New dialogue is prioritized over static captions, and a failed region temporarily backs off without blocking other bubbles. Keep paragraph grouping enabled for wrapped dialogue. After a window moves, resizes, or changes resolution, select it again and verify the preview. Closing the main window leaves the menu-bar controls active; quit the app to stop sharing and unload the model.

## Privacy

During normal use, OCR and translation run on your Mac. Screen images and source text are not uploaded. The model subprocess listens only on a random loopback port and uses a fresh access key for each launch. Conversation history stays in memory unless you explicitly export it. The engine keeps a runtime log in the system temporary directory, accessible from preferences. Optional diagnostic commands write test reports and test images.

Downloading the inference runtime or a model requires network access. This repository, source archives, and release DMGs contain no personal preferences, screen recordings, or model weights.

## Build from source

Requirements: an Apple Silicon Mac, macOS 14 or later, Swift command-line tools, and Python 3. Full Xcode is not required.

```sh
xcode-select --install  # Skip this if command-line tools are already installed.
./scripts/setup-runtime.sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-dmg.sh
```

Builds are written to `outputs/`. The runtime download is pinned to llama.cpp `b12428` and verified with SHA256. You can set `KOTONOHA_PROXY` to use an existing proxy for downloads; the script does not change system network settings.

`./scripts/setup-runtime.sh --model` is optional. It downloads Qwen3-8B GGUF into the local `outputs/Models/` directory, without embedding it in the app. Alternatively, obtain your own model and select it in the app.

Source builds use an ad-hoc signature. A Developer ID signed and notarized distribution requires the developer to configure an Apple distribution identity separately.

## Tests

`./scripts/test.sh` runs 63 core checks without a model or screen-recording permission. `python3 scripts/check-comments.py` checks source comments for CJK ideographs. GitHub Actions builds the Apple Silicon app and runs both checks without downloading a model.

The app executable also accepts these native diagnostic flags. They need an interactive macOS desktop; inference checks need a local GGUF model configured in the app:

- `--diagnose`: local OCR and translation.
- `--typewriter-test`: growing text, full-sentence translation, and prefix-cache regression checks.
- `--pipeline-test --fast-test`: rapid dialogue changes in the bundled fixture window.
- `--pipeline-test --jitter-test`: overlay continuity under OCR variation.
- `--screen-test --display-filter` and `--resize-test`: capture mapping, overlay exclusion, and reselection.

`--dialogue-append-test`, `--presentation-test`, `--visual-text-test`, and `--recording-replay-test` are optional development checks that require separately supplied local recording fixtures. Those private frames are not distributed.

`--continuous-dialogue-test` runs a Sakura session across twelve complete and typewriter pages without resetting dialogue memory, including speaker labels and a persistent playback control. It checks actual painted position and obstruction, oversized covers and same-source dropouts. The synthetic replay is not a real-game coverage benchmark.

`--profile-timing-test` is an optional local-model check for Sakura, GalTransl and Hy-MT2, with Qwen3-8B as a structured-output control. It covers completed dialogue, typewriter append retention, independent/scrolling chat bubbles, obsolete-request cancellation and per-region failure isolation. Set `KOTONOHA_MODELS_DIR` to the directory containing the tested GGUF filenames (see `ProfileDiagnostics.swift`); the default is `~/Documents/Codex/model`. A local recording frame is used when available. Models and recording frames are not distributed.

Set `KOTONOHA_DIAGNOSTICS_DIR` to choose a diagnostic output directory. Model quality, permission flows, and actual game behavior still require manual testing and are not covered by unattended CI.

## Limitations and contributing

Only Apple Silicon is supported; no Intel build is provided. OCR errors, mistranslations, complex layouts, and other GPU workloads can affect results. Very fast subtitle changes may leave insufficient time to translate every line. Report reproducible problems in [Issues](https://github.com/fffretice/Kotonoha/issues), without private data. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.

## License

The project's source code is licensed under [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution. llama.cpp uses the MIT License; see [THIRD_PARTY.md](THIRD_PARTY.md). Model weights and external game assets are not covered by this project's license.
