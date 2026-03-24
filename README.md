# Mac Cleaner

Mac Cleaner is a macOS cleanup tool built in Swift. The app is moving toward a general cleanup architecture where multiple scanners can contribute findings under the same permission model.

Current scanners:
- Unity project scanner

Available products:
- `mac-cleaner`: general cleanup CLI that emits generic cleanup findings
- `unity-detector`: specialized Unity scanner CLI
- `MacCleanerGUI`: SwiftUI macOS app
- `MacCleanerCore`: shared scanning and reporting core

## Project direction

The long-term product is a general cleaner, not a Unity-only tool. Unity support remains useful, but it now sits behind a generic cleanup engine so future scanners can be added for areas like Xcode artifacts, caches, logs, and other developer-generated files.

## Development

Build everything:

```bash
swift build
```

Run tests:

```bash
swift test
```

Run the general CLI against the current directory:

```bash
swift run mac-cleaner --root=. --json
```

Run the specialized Unity scanner:

```bash
swift run unity-detector --root=. --json
```
