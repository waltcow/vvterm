# Remove Tailscale and Cloudflare Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Tailscale SSH and Cloudflare Access while preserving standard SSH and Mosh.

**Architecture:** Keep `SSHConnectionMode` as the compatibility boundary: active modes are standard SSH and Mosh, while legacy raw values decode to standard SSH. Delete Cloudflare runtime, model fields, package metadata, URL scheme, and visible product copy instead of keeping unused shims.

**Tech Stack:** Swift, Swift Testing, CloudKit serialization, Xcode project SwiftPM references, Astro website copy.

---

### Task 1: Lock Legacy Decode and Model Cleanup Tests

**Files:**
- Modify: `VVTermTests/ServerConnectionModeTests.swift`
- Modify: `VVTermTests/ConnectionLifecycleIntegrationTests.swift`

- [ ] Add tests that old JSON `connectionMode` values `tailscale` and `cloudflare` decode as `.standard`.
- [ ] Add tests that old Cloudflare JSON keys are ignored and are not emitted by `Server.encode(to:)`.
- [ ] Add CloudKit tests that old `connectionMode` values decode as `.standard` and `toRecord()` omits Cloudflare fields.
- [ ] Update credential-builder tests so only SSH and Mosh remain.
- [ ] Update integration fixtures to avoid Cloudflare-only `ServerCredentials` fields.
- [ ] Run targeted tests and verify the new tests fail before production changes.

Run:
```bash
xcodebuild test -project VVTerm.xcodeproj -scheme VVTerm -destination 'platform=macOS' -only-testing:VVTermTests/ServerConnectionModeTests
```

### Task 2: Remove Tailscale and Cloudflare From Active Domain Model

**Files:**
- Modify: `VVTerm/Features/Servers/Domain/Server.swift`
- Modify: `VVTerm/Features/Servers/Domain/Server+CloudKit.swift`
- Modify: `VVTerm/Features/Servers/Application/ServerManager.swift`
- Modify: `VVTerm/Core/Security/KeychainManager.swift`

- [ ] Remove `.tailscale`, `.cloudflare`, `CloudflareAccessMode`, Cloudflare `Server` fields, and Cloudflare credential fields.
- [ ] Keep JSON and CloudKit decode tolerant of old raw values and old Cloudflare keys.
- [ ] Ensure local JSON and CloudKit writes do not emit Cloudflare fields.
- [ ] Remove Cloudflare token helper APIs while preserving private deletion of legacy server-specific keys in `deleteCredentials`.
- [ ] Remove ServerManager copying/storing of Cloudflare fields and service tokens.

### Task 3: Remove UI Transport Branches

**Files:**
- Modify: `VVTerm/Features/Servers/UI/ServerDetail/ServerFormSheet.swift`

- [ ] Reduce `ServerTransportSelection` to `standard` and `mosh`.
- [ ] Remove Tailscale no-credentials flow.
- [ ] Remove Cloudflare access-mode fields, validation, connection-test override behavior, and save-time token storage.
- [ ] Preserve SSH auth methods and Mosh connection test bootstrap.

### Task 4: Remove Runtime and Package Metadata

**Files:**
- Modify: `VVTerm/Core/SSH/SSHClient.swift`
- Delete: `VVTerm/Core/Network/Cloudflare/CloudflareTransportManager.swift`
- Delete: `VVTerm/Core/Network/Cloudflare/CloudflareOAuthFlow.swift`
- Delete: `VVTerm/Core/Network/Cloudflare/CloudflareTokenStoreAdapter.swift`
- Modify: `VVTerm/Features/TerminalSessions/UI/Terminal/SSHTerminalWrapper.swift`
- Modify: `VVTerm/Features/TerminalSessions/UI/Splits/TerminalView.swift`
- Modify: `VVTerm.xcodeproj/project.pbxproj`
- Modify: `VVTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Modify: `VVTerm-iOS/Info.plist`
- Modify: `VVTerm-macOS/Info.plist`

- [ ] Remove Cloudflare tunnel setup/cleanup and Tailscale auth handling from `SSHClient`.
- [ ] Simplify the connection cache key to active fields.
- [ ] Remove Cloudflare/Tailscale error cases from terminal wrapper reset switches.
- [ ] Remove `Cloudflared` package/product references and URL scheme.
- [ ] Preserve `swift-mosh`, `MoshCore`, `MoshBootstrap`, and `RemoteMoshManager`.

### Task 5: Update Docs, Website, and Architecture Copy

**Files:**
- Modify: `README.md`
- Modify: `web/src/lib/site.ts`
- Modify: `web/src/i18n/translations/en.json`
- Modify: `web/src/i18n/translations/zh.json`
- Modify: `web/src/pages/terms.astro`
- Modify: `web/src/layouts/BaseLayout.astro`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify as needed: `VVTerm/Resources/*.lproj/Localizable.strings`

- [ ] Remove user-visible Tailscale and Cloudflare support claims.
- [ ] Remove Cloudflared dependency acknowledgement.
- [ ] Update architecture instructions so `Core/Network` no longer owns Cloudflare transport.
- [ ] Keep Mosh references.

### Task 6: Verify

**Files:**
- Inspect all modified files.

- [ ] Run targeted Swift tests for connection mode and Mosh manager.
- [ ] Run a compile/build check for the app target if available in this environment.
- [ ] Search for remaining `tailscale`, `cloudflare`, `Cloudflared`, `CloudflareAccessMode`, and `vvterm-cfaccess` references; keep only intentional historical references in the spec/plan if any.
- [ ] Confirm package metadata no longer references `swift-cloudflared`.
- [ ] Confirm Mosh references remain.
