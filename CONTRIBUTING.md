# Contributing

Issues and pull requests are welcome. Please describe the visible problem, expected behavior, macOS version, chip, model name/quantization, selected capture mode, and dialogue timing mode.

Before submitting a change:

```sh
./scripts/build.sh
./scripts/test.sh
```

The core checks require no model or screen-recording permission. Native end-to-end checks need a compatible local GGUF model; capture checks also need an interactive macOS desktop and permission granted through the system picker. They do not run in CI.

Do not commit model weights, screen recordings, private dialogue logs, keys, tokens, or personal preferences. Use short text-only reproductions where possible. Share recordings only if you have the right to publish their contents and they contain no personal information.

Keep changes focused. Include relevant validation and any known limitations. Contributions are accepted under Apache-2.0, the same license as the project.
