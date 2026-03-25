# Reclaim

Reclaim is an open-source macOS cleanup tool built natively in Swift. The app uses a general cleanup architecture where multiple specialized scanners can identify and safely remove unnecessary data, caches, build artifacts, and system trash to reclaim precious disk space.

## Features

- **SwiftUI Interface**: Beautiful, responsive native UI built for macOS 13+.
- **Universal Binaries**: Native support for both Apple Silicon (M-series) and Intel architectures.
- **System-Wide Scan Mode**: Scans every user profile under `/Users` after you grant Full Disk Access once in macOS.
- **Specialized Scanners**:
  - **Xcode**: Reclaim space occupied by stale `DerivedData`, outdated simulators, and iOS device logs.
  - **Unity**: Automatically detects cached builds and unnecessary library artifacts across all Unity projects.
  - *More scanners can easily be added using the modular `MacCleanerCore` framework.*

## Installation

### Pre-built Application (Recommended)

1. Navigate to the [Releases](https://github.com/BadranRaza/Mac-Cleaner/releases) section of this repository.
2. Download the latest `Reclaim-vX.Y.Z.zip`.
3. Unzip the file and drag the provided `Reclaim.app` to your `/Applications` folder.
4. If macOS warns that Apple cannot verify the app, right-click `Reclaim.app`, choose `Open`, and confirm once.
5. After launch, optionally grant `Reclaim.app` access in `System Settings > Privacy & Security > Full Disk Access` for the broadest scan coverage.

> Note: The GUI performs a system-wide scan across `/Users`. Without Full Disk Access, Reclaim still runs in a best-effort mode, but protected folders such as Mail, Safari, Desktop, Documents, and Downloads may be skipped.

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

The project relies on GitHub Actions to auto-release the Reclaim GUI natively. A `.github/workflows/release.yml` triggers when pushing new git tags (e.g., `v1.2.0`) to automatically bind the version natively and export universally compiled applications ready for download.

The current release workflow builds the universal binaries, bundles `Reclaim.app` plus the CLI tools into one ZIP, and uploads that archive to GitHub Releases. The release is unsigned, so Gatekeeper may require the manual `Open` confirmation described above on first launch.

To launch the GUI locally during development with an auto-generated App bundle scaffold:

```bash
./Scripts/run-gui-app.sh debug
```

## Contributing

Pull requests are actively welcomed! Please follow common conventions and write unit tests for any new scanner added to the `MacCleanerCore` architecture.

## License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
