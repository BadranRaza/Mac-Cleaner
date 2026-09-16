# Reclaim

<img src="Resources/AppIcon.png" width="96" align="right" alt="Reclaim icon">

A small, native macOS app that finds caches, logs and build leftovers you can safely remove.

## What it cleans

Only fixed, well-known locations in your home folder, in plain language, with the owning app's name and icon where possible.
Every item is tagged, and only **Safe** items are selected by default:

- **Safe**: comes back by itself.
- **Takes time**: comes back, but rebuilding or downloading it takes a while.
- **Check first**: may be your only copy.

| Group | What it is | Tag |
|---|---|---|
| Temporary App Files | `~/Library/Caches/*`, App Store apps' caches | Safe |
| Activity Logs | `~/Library/Logs` | Safe |
| Trash | `~/.Trash` | Check first |
| Email Attachments | Mail Downloads (moved to the Trash) | Check first |
| Leftovers from Deleted Apps | Containers of apps that are no longer installed; login items whose program is gone (turned off, moved to the Trash) | Check first |
| Duplicate Files | Real extra copies (not APFS clones) of files over 50 MB in Desktop, Documents, Downloads; the oldest copy is kept | Check first |
| Developer Downloads | Homebrew, CocoaPods, pip, Yarn, Go, npm, Cargo, unused Codex installs, old Claude Code plugin versions; `~/.cache` and Gradle | Safe; `~/.cache` and Gradle take time |
| Xcode | Simulator files (safe); build files, iPhone debugging files (take time); archived builds (check first, moved to the Trash) | Mixed |
| Unity Projects | `Library`, `Temp`, `Obj`, `Logs` (take time); `Build`/`Builds` (check first, moved to the Trash) | Mixed |
| JavaScript Packages, iOS Libraries | Each project's `node_modules` / `Pods` | Takes time |

**Quick Clean** scans and shows how much Safe space it found, grouped, with one Clean Now button. **Scan & Review** shows everything with full control.

**Uninstall Apps** removes an app together with the files it created (settings, caches, containers, login items), found by bundle ID. Folders that only match the app's name are marked Check first. The app is quit first and everything goes to the Trash.

**Also taking space** explains big things Reclaim leaves alone, like Docker virtual machines, AI chat history, browser profiles and other accounts, and how to shrink them yourself.

Safety rules:
- Removes what is *inside* cache and log locations, never the location itself; `node_modules`, `Pods` and Unity folders are removed whole.
- Skips app data in `~/Library/Application Support`, caches that hold state (CloudKit, Spotlight, FontRegistry, Finder, iCloud) or are costly to rebuild (JetBrains, Playwright), and caches of running apps.
- Sizes are allocated bytes on disk with hard links counted once. APFS clones can make them an upper bound.

Grant **Full Disk Access** (System Settings → Privacy & Security) to include Trash, Mail and sandboxed app caches. Reclaim works without it and tells you what it skipped.

## Development

```bash
swift test                          # core tests
Scripts/run-gui-app.sh              # build .build/Reclaim.app and open it
Scripts/run-gui-app.sh release      # release build
swift run reclaim-cli               # read-only list of what would be cleaned
swift Scripts/make-icon.swift       # regenerate Resources/AppIcon.icns
```

Each app build records its git commit in `Info.plist` under `ReclaimGitCommit`.

## License

MIT
