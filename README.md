# Mac Cleaner

Mac Cleaner is an open-source macOS cleanup tool built natively in Swift. The app uses a general cleanup architecture where multiple specialized scanners can identify and safely remove unnecessary data, caches, build artifacts, and system trash to reclaim precious disk space.

## Features

- **SwiftUI Interface**: Beautiful, responsive native UI built for macOS 13+.
- **Universal Binaries**: Native support for both Apple Silicon (M-series) and Intel architectures.
- **Safety First**: Implements App Sandbox access controls, ensuring scans stay strictly within user-granted directories.
- **Specialized Scanners**:
  - **Xcode**: Reclaim space occupied by stale `DerivedData`, outdated simulators, and iOS device logs.
  - **Unity**: Automatically detects cached builds and unnecessary library artifacts across all Unity projects.
  - *More scanners can easily be added using the modular `MacCleanerCore` framework.*

## Installation

### Pre-built Application (Recommended)

1. Navigate to the [Releases](https://github.com/BadranRaza/Mac-Cleaner/releases) section of this repository.
2. Download the latest `MacCleaner-vX.Y.Z.zip`.
3. Unzip the file and drag the provided `MacCleaner.app` to your `/Applications` folder.

> Note: The zip file also conveniently contains the standalone `mac-cleaner` and `unity-detector` command-line utilities inside the same extracted folder, ready to be used from your terminal if preferred.

### Command-Line Arguments

The Command-Line interface utilities (`mac-cleaner` and `unity-detector`) support flags such as:
- `--version` : Print the installed version payload.
- `--root=<path>` : Designate exactly which directory to scan.
- `--json` : Output machine-readable JSON payloads instead of human-readable text.
- `--max-depth=<depth>` : Set a limit on how deep to traverse.
- `--minimum-confidence=<1-10>` : Set minimum strictness regarding what should be deleted.

## Development

Build the entire project via SwiftPM:

```bash
swift build
```

Run unit tests:

```bash
swift test
```

### Local CLI Execution

Run the general cleanup CLI targeting the current directory:

```bash
swift run mac-cleaner --root=. --json
```

Run the specialized Unity scanner:

```bash
swift run unity-detector --root=. --json
```

### GUI Application Packaging

The project relies on GitHub Actions to auto-release `MacCleanerGUI` natively. A `.github/workflows/release.yml` triggers when pushing new git tags (e.g., `v1.2.0`) to automatically bind the version natively and export universally compiled applications ready for download.

To launch the GUI locally during development with an auto-generated App bundle scaffold:

```bash
./Scripts/run-gui-app.sh debug
```

## Contributing

Pull requests are actively welcomed! Please follow common conventions and write unit tests for any new scanner added to the `MacCleanerCore` architecture.

## License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
