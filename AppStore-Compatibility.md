# Mac Cleaner App — App Store compatibility checklist

This SwiftUI app scans only user-selected folders and is structured so multiple cleanup scanners can run under the same permission model. To ship on the Mac App Store, complete the following checklist:

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
- ✅ No default `/` scan path in the GUI.
- ✅ Folder scope is user-driven via picker.
- ✅ Security-scoped access is requested before scanning.
- ✅ Entitlements plist exists for sandboxed file access.
- ⚠️ Remaining work: wire the entitlements into a real Xcode app target and finish signing/notarization.
