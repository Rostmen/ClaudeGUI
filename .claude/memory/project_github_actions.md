---
name: GitHub Actions release workflow
description: How the CI release pipeline works — runner, signing, notarization, known gotchas
type: project
---

Release workflow at `.github/workflows/release.yml` — triggers on `v*` tags.

**Runner**: `macos-26` (required — project targets macOS 26.2, needs macOS 26 SDK)

**Xcode selection**: Picks latest non-beta Xcode dynamically:
```bash
ls -d /Applications/Xcode*.app | grep -iv "beta" | sort -V | tail -1
```

**Metal Toolchain**: Must be installed explicitly on CI — `sudo xcodebuild -downloadComponent MetalToolchain`

**Signing approach** (why it's done this way):
- `xcodebuild -exportArchive` uses `IDEDistribution` which ignores user keychains — unusable in CI
- Archive is built with `CODE_SIGNING_ALLOWED=NO` to skip xcodebuild's cert validation
- App is signed manually with `codesign` after archive (frameworks first, then app bundle)
- `echo -n` must be used when base64-decoding the certificate (trailing newline corrupts .p12)
- Keychain must be re-unlocked in each step that needs it (each step = new shell)

**Required GitHub Secrets**:
- `APPLE_CERTIFICATE` — base64 of Developer ID Application .p12 (must include private key)
- `APPLE_CERTIFICATE_PASSWORD` — .p12 export password
- `KEYCHAIN_PASSWORD` — any random string
- `APPLE_ID` — Apple ID email
- `APPLE_APP_PASSWORD` — app-specific password from appleid.apple.com
- `APPLE_TEAM_ID` — 10-char team ID (AWKHNRR4U2)

**To release**: `git tag v1.x.x && git push origin v1.x.x`

**Why:** macOS 26 SDK is required so the app renders with modern SwiftUI look. macOS 15 SDK produces legacy UI appearance even when running on macOS 26.
**How to apply:** When updating the workflow, always keep macos-26 runner and the manual codesign approach.
