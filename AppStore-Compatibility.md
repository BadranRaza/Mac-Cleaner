# Reclaim App — App Store compatibility checklist

The current GitHub release is a non-sandboxed desktop app that performs a system-wide `/Users` scan and expects Full Disk Access.

This document is only for a future Mac App Store variant. Shipping on the Mac App Store would require a separate folder-scoped build that scans only user-selected locations and runs under the App Sandbox permission model.

1. Build as a macOS app target (not a SwiftPM CLI distribution) and sign with an App Store Distribution certificate.
2. Enable App Sandbox in the Xcode target entitlements.
3. Set at least these entitlement keys:
   - `com.apple.security.app-sandbox = true`
   - `com.apple.security.files.user-selected.read-write = true`
   - `com.apple.security.files.user-selected.read-only = true` (if write flow is not used yet)
4. Keep filesystem operations under granted scoped URLs only.
   - In app, folders are added via `NSOpenPanel`.
   - Scans are executed after `startAccessingSecurityScopedResource()`.
5. Keep any hidden root scan path removed or gated behind explicit user consent.
6. Add privacy messaging in UI before scanning (“We only scan user-approved folders”).
7. Add a visible stop/pause flow for long scans and allow cancellation.
8. Confirm crash-safe behavior for denied/revoked access.
9. Provide a lightweight preview step before cleanup (default action must be non-destructive).
10. Run Apple's `xcrun altool`/Validation checks for final package.

Current implementation status:
- ❌ Current desktop build is not App Store compatible because it performs a system-wide `/Users` scan.
- ⚠️ A separate App Store variant would need folder pickers, security-scoped access, and sandbox-constrained scanning restored.
- ⚠️ The existing entitlements plist is dormant and not wired into the SwiftPM desktop release build.
- ⚠️ Remaining work: create a real Xcode app target for the App Store variant. The current GitHub desktop release path remains an unsigned direct download.
