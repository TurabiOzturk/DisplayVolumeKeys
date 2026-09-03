# Contributing

Contributions are welcome through GitHub issues and pull requests.

## Development setup

Requirements:

- macOS 13 or later on Apple Silicon
- Swift 5.10 or later
- A DDC/CI-capable external monitor for hardware testing

Build the app:

```bash
./Scripts/build-app.sh
```

Install and launch the local build:

```bash
./Scripts/install-app.sh
```

## Guidelines

- Keep the app narrowly focused and lightweight.
- Do not add analytics or network services.
- Perform DDC communication away from the main thread.
- Preserve normal macOS media-key behavior when no compatible monitor is available.
- Document monitor-specific workarounds.
- Test volume up, volume down, mute, held-key repeat, wake, and reconnect behavior.
