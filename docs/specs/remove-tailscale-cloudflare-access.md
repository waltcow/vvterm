# Remove Tailscale and Cloudflare Access Connection Modes

## Summary

Remove VVTerm's Tailscale SSH and Cloudflare Access connection modes while preserving Mosh support and the standard SSH flow.

After this change, the server form should expose only:
- SSH
- Mosh

Existing saved servers that use `tailscale` or `cloudflare` should remain loadable and should be treated as standard SSH after migration or decode fallback. Existing Mosh servers must continue to behave as they do today.

Spec date: 2026-07-05

## Problem

VVTerm currently supports four connection modes:
- standard SSH
- Tailscale SSH
- Mosh
- Cloudflare Access

The extra Tailscale and Cloudflare modes add product and maintenance surface that is no longer needed:
- server form branching
- saved `connectionMode` values in local storage and CloudKit
- Cloudflare OAuth and service-token state
- Cloudflare URL scheme registration
- extra SwiftPM dependency on `swift-cloudflared`
- extra tests and marketing copy

Mosh remains useful and is out of scope for removal.

## Goals

- Remove Tailscale SSH as a selectable connection mode.
- Remove Cloudflare Access as a selectable connection mode.
- Preserve standard SSH behavior.
- Preserve Mosh behavior, Mosh fallback, and remote `mosh-server` install prompts.
- Keep old `tailscale` and `cloudflare` server records readable.
- Convert or interpret old `tailscale` and `cloudflare` records as standard SSH.
- Remove Cloudflare runtime code and the `swift-cloudflared` package dependency.
- Remove Cloudflare service-token UI and storage paths.
- Remove Cloudflare fields, enums, credential fields, and Keychain helpers from the active model.
- Remove Tailscale-specific auth behavior and no-credential form behavior.
- Update tests, README, website copy, and localization strings that advertise removed modes.

## Non-Goals

- Removing Mosh.
- Redesigning the server form.
- Changing standard SSH authentication behavior.
- Changing tmux behavior.
- Changing Remote Files or Stats behavior except where they refer to removed transports.
- Migrating user-entered Cloudflare service tokens into another format.
- Auto-discovering replacement direct SSH hosts for old Cloudflare servers.
- Adding a separate migration UI.

## Current State

### Server Model

`Server.connectionMode` is stored locally and in CloudKit using `SSHConnectionMode`.

Current enum cases:
- `standard`
- `tailscale`
- `mosh`
- `cloudflare`

Cloudflare also stores mode-specific metadata:
- `cloudflareAccessMode`
- `cloudflareTeamDomainOverride`
- `cloudflareAppDomainOverride`

Cloudflare service-token credentials are stored in Keychain through server-specific keys.

### Server Form

`ServerTransportSelection` exposes SSH, Tailscale, Mosh, and Cloudflare.

Tailscale skips the auth-method picker and credential fields because it relies on server-side Tailscale SSH policy.

Cloudflare adds:
- OAuth vs service token picker
- optional Team Domain override
- service-token client ID and secret fields
- Cloudflare-specific connection-test error handling

### SSH Runtime

Tailscale does not use a separate network stack. It connects directly to the configured host and checks whether libssh2 already sees the session as authenticated by server policy. If not, it throws `tailscaleAuthenticationNotAccepted`.

Cloudflare uses `CloudflareTransportManager` to establish a local tunnel endpoint, then `SSHClient` dials `127.0.0.1:<localPort>`.

Mosh uses `RemoteMoshManager`, `MoshCore`, and `MoshBootstrap`. This path remains in place.

### Project and App Metadata

Cloudflare adds:
- `Cloudflared` SwiftPM product dependency
- `swift-cloudflared` package reference
- `vvterm-cfaccess` URL scheme in iOS and macOS Info.plist files

Tailscale adds no package dependency and no URL scheme.

## Proposed Design

### Supported Modes

After the change, `SSHConnectionMode` should support only:
- `standard`
- `mosh`

The UI should show only:
- `SSH`
- `Mosh`

Internal decode compatibility must still recognize old raw values:
- `tailscale` -> `standard`
- `cloudflare` -> `standard`
- unknown future value -> `standard`

This keeps old records readable while avoiding continued product support for removed modes.

### Data Compatibility

The implementation should keep decoding tolerant:
- Local JSON records with `connectionMode: "tailscale"` decode as `.standard`.
- Local JSON records with `connectionMode: "cloudflare"` decode as `.standard`.
- CloudKit records with `connectionMode` set to `tailscale` or `cloudflare` decode as `.standard`.
- Local JSON writes through `Server.encode(to:)` must not write Cloudflare fields.
- CloudKit writes should omit `connectionMode` for standard SSH, matching current behavior.
- CloudKit writes should still write `connectionMode: "mosh"` for Mosh.

Do not keep `tailscale` or `cloudflare` enum cases for compatibility. `SSHConnectionMode` should have active cases for `standard` and `mosh` only. Its JSON decoder must still treat legacy raw strings as `.standard`; this may be implemented by an explicit legacy switch or by the post-removal raw-value fallback, but tests must lock the behavior. The CloudKit path in `Server+CloudKit.swift` must produce the same result as the JSON path.

Cloudflare-specific fields should not block decoding old records. They should be ignored on decode and must not be written for standard or Mosh records.

When a user edits an old Tailscale or Cloudflare server after the change, saving it should persist as standard SSH unless the user explicitly selects Mosh.

### Legacy Field Removal

Remove Cloudflare fields from the active model instead of keeping decode-only dead fields.

Remove:
- `CloudflareAccessMode`
- `Server.cloudflareAccessMode`
- `Server.cloudflareTeamDomainOverride`
- `Server.cloudflareAppDomainOverride`
- `ServerCredentials.cloudflareClientID`
- `ServerCredentials.cloudflareClientSecret`
- `KeychainManager.storeCloudflareServiceToken`
- `KeychainManager.getCloudflareServiceToken`
- `KeychainManager.deleteCloudflareServiceToken`
- Cloudflare-specific key helper methods except any literal legacy cleanup needed inside `deleteCredentials`

`Server` custom `Codable` should tolerate old Cloudflare keys by ignoring them. `Server.toRecord()` must never write Cloudflare-specific fields.

`ServerManager` must stop copying or storing Cloudflare fields when adding, updating, repairing, or syncing servers. It should not retain Cloudflare-specific constructor arguments through model rebuilds.

### CloudKit Lazy Migration

This spec uses lazy migration by decode fallback, not a one-time CloudKit cleanup job.

Accepted behavior:
- Old CloudKit records may keep `connectionMode: "tailscale"` or `connectionMode: "cloudflare"` until the user saves that server.
- Every device running the new build decodes those records as standard SSH.
- Saving the server rewrites it without legacy mode values or Cloudflare fields.
- No background job scans and rewrites every CloudKit record only to remove legacy fields.

### Credentials

Tailscale removal changes old Tailscale servers materially:
- old Tailscale records likely have no saved password or SSH key
- after decode fallback, they become standard SSH records
- users may need to add credentials before the server can connect

Cloudflare removal changes old Cloudflare servers materially:
- old Cloudflare hosts may not be directly reachable by standard SSH
- Cloudflare service-token credentials should no longer be loaded into `ServerCredentials`
- users may need to replace the host and credentials with a direct SSH endpoint

Expected behavior:
- The server form should require standard SSH credentials for old Tailscale/Cloudflare records after they are edited.
- Connection attempts should use normal standard SSH validation and errors, not Tailscale or Cloudflare-specific errors.
- Deleting a server should continue deleting legacy server-specific Cloudflare service-token keys if the implementation can do so without keeping public Cloudflare Keychain APIs alive. This cleanup should use the old literal key shapes only inside `deleteCredentials`: `server.<UUID>.cloudflare.clientid` and `server.<UUID>.cloudflare.clientsecret`.

### UI

The server form should remove:
- Tailscale transport option
- Tailscale explanatory text
- Tailscale credential-skip behavior
- Cloudflare transport option
- Cloudflare Access picker
- Cloudflare OAuth explanatory text
- Team Domain override field
- service-token client ID and secret fields
- Cloudflare-specific connection-test recovery that opens overrides

`ServerTransportSelection` should be reduced to active cases for `standard` and `mosh` only. Remove `tailscale` and `cloudflare` cases, labels, icons, connection-mode mapping, and `init(server:)` branches instead of only hiding them from the picker.

The form should keep:
- SSH password auth
- SSH key auth
- SSH key plus passphrase auth
- Mosh selection
- Mosh connection test bootstrap

No layout redesign is required.

### SSH Runtime

Remove Tailscale-specific auth handling:
- `tailscaleAuthenticationNotAccepted`
- Tailscale auth accepted/not accepted logging
- direct-tailnet reminder text

Remove Cloudflare runtime handling:
- `CloudflareTransportManager`
- `CloudflareOAuthFlow`
- `CloudflareTokenStoreAdapter`
- Cloudflare local tunnel setup in `SSHClient.connect`
- Cloudflare cleanup on connect failure, pre-connect cleanup, and disconnect
- Cloudflare-specific SSH handshake error mapping
- Cloudflare error cases in `SSHError`
- Cloudflare-specific fields from the `SSHClient.connect` cache key; the key should include only fields still active for standard SSH and Mosh.

Remove Cloudflare storage code from active runtime:
- OAuth token store service: `app.vivy.vvterm.cloudflare.tokens`
- OAuth token key prefix: `oauth.`
- metadata cache service: `app.vivy.vvterm.cloudflare.metadata`
- metadata cache key: `cache.v1`

Do not keep Cloudflare runtime or token-store types only to perform cleanup. Server-specific service-token key deletion may remain as a private legacy cleanup detail inside `deleteCredentials`; OAuth token and metadata leftovers are accepted as orphaned Keychain data if there is no simple static cleanup path.

Keep Mosh runtime handling unchanged:
- imports and package products for `MoshCore` and `MoshBootstrap`
- `RemoteMoshManager`
- `ShellTransport.mosh`
- Mosh fallback reasons
- Mosh install prompts
- Stats and Remote Files behavior that treats active Mosh sessions specially

### Package and Metadata Cleanup

Remove from Xcode project:
- `Cloudflared` framework build file
- `Cloudflared` package product dependency
- `swift-cloudflared` package reference

Remove from `Package.resolved`:
- `swift-cloudflared`

Remove from Info.plist files:
- Cloudflare callback URL type
- `vvterm-cfaccess`

Do not remove:
- `swift-mosh`
- `MoshCore`
- `MoshBootstrap`

### Documentation and Marketing

Update project and website copy to stop advertising removed modes.

Required copy direction:
- describe VVTerm as supporting standard SSH and Mosh
- remove references to Tailscale SSH
- remove references to Cloudflare Tunnel SSH or Cloudflare Access
- remove Cloudflare service-token wording from README
- remove Cloudflared from the README dependency acknowledgements
- remove Tailscale/Cloudflare wording embedded in decorative website assets or background SVGs

Terms or privacy copy that generically mentions third-party remote services should be reviewed. If the wording is broad and still accurate, it may stay. If it explicitly promises Tailscale or Cloudflare support, update it.

### Localization

Remove or stop using localized strings that are only for:
- Tailscale SSH auth failure
- direct tailnet reminder
- Tailscale form copy
- Cloudflare Access labels
- Cloudflare OAuth/service-token UI
- Cloudflare tunnel/config/auth errors

Mosh strings must stay.

The implementation does not need to manually prune every unused localized key in the same change if the project tolerates unused strings, but user-visible copy must not reference removed modes.

## Implementation Scope

Expected code areas:
- `VVTerm/Features/Servers/Domain/Server.swift`
- `VVTerm/Features/Servers/Domain/Server+CloudKit.swift`
- `VVTerm/Features/Servers/UI/ServerDetail/ServerFormSheet.swift`
- `VVTerm/Features/Servers/Application/ServerManager.swift`
- `VVTerm/Core/Security/KeychainManager.swift`
- `VVTerm/Core/SSH/SSHClient.swift`
- `VVTerm/Core/Network/Cloudflare/`
- `VVTerm/Features/TerminalSessions/UI/Terminal/SSHTerminalWrapper.swift`
- `VVTerm/Features/TerminalSessions/UI/Splits/TerminalView.swift`
- `VVTermTests/ServerConnectionModeTests.swift`
- `VVTermTests/ConnectionLifecycleIntegrationTests.swift`
- `VVTerm.xcodeproj/project.pbxproj`
- `VVTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `VVTerm-iOS/Info.plist`
- `VVTerm-macOS/Info.plist`
- `README.md`
- `web/src/lib/site.ts`
- `web/src/i18n/translations/*.json`
- `web/src/pages/terms.astro`
- `web/src/layouts/BaseLayout.astro`
- relevant `VVTerm/Resources/*.lproj/Localizable.strings`
- `AGENTS.md`
- `CLAUDE.md`

## Testing Requirements

Unit tests should cover:
- Decoding missing `connectionMode` defaults to `.standard`.
- Decoding unknown `connectionMode` defaults to `.standard`.
- Decoding old `tailscale` raw value defaults to `.standard`.
- Decoding old `cloudflare` raw value defaults to `.standard`.
- Decoding `mosh` still produces `.mosh`.
- CloudKit `Server(from:)` with `connectionMode: "tailscale"` decodes to `.standard`.
- CloudKit `Server(from:)` with `connectionMode: "cloudflare"` decodes to `.standard`.
- `Server.toRecord()` omits Cloudflare fields for all servers.
- `Server.encode(to:)` omits Cloudflare fields for local persistence.
- `ServerTransportSelection(server:)` maps standard and Mosh correctly.
- Credential builder no longer has Tailscale or Cloudflare special cases.
- Mosh credential behavior still preserves SSH password and key credentials.
- `KeychainManager.getCredentials(for:)` no longer injects Cloudflare service-token credentials.
- Remove or replace tests asserting Tailscale credential skipping.
- Remove or replace tests asserting Cloudflare service-token preservation.
- `ConnectionLifecycleIntegrationTests` fixtures no longer depend on Cloudflare credential fields or `.cloudflare` defaults.

Build verification should cover:
- App target compiles without `Cloudflared`.
- Tests compile without Cloudflare error cases.
- `RemoteMoshManagerTests` still compile and pass.

Manual smoke checks:
- Add standard SSH server with password.
- Add standard SSH server with key.
- Add Mosh server.
- Edit an old Tailscale record and confirm it appears as SSH.
- Edit an old Cloudflare record and confirm it appears as SSH.
- Connect an old Tailscale or Cloudflare record without editing and confirm it uses standard SSH errors.
- Confirm no Tailscale or Cloudflare options appear in the server form.

## Risks

### Existing Tailscale Servers May Need Credentials

Old Tailscale records likely do not have saved SSH credentials. After fallback to standard SSH, those records may fail until the user adds credentials.

This is expected and should be accepted as part of removing the feature.

### Existing Cloudflare Servers May Not Be Directly Reachable

Old Cloudflare hosts may be Access-protected endpoints rather than direct SSH hosts. After fallback to standard SSH, those records may fail until the user replaces the host with a reachable SSH endpoint.

This is expected and should be accepted as part of removing the feature.

### Cloudflare Keychain Data Becomes Orphaned

Existing Cloudflare OAuth tokens and service-token credentials may remain in Keychain if the app no longer references their storage services.

Acceptable options:
- keep deletion of legacy server-specific Cloudflare service-token keys inside `deleteCredentials`
- delete the static metadata cache key if doing so does not require keeping Cloudflare runtime types
- leave OAuth token cleanup as best-effort or orphaned data because token keys are dynamic

Do not add complex migration UI only to clean removed Cloudflare credentials.

### Product Copy Drift

The app, README, and website must not continue advertising Tailscale or Cloudflare support after runtime removal.

## Rollout

This should ship as one coherent removal PR, split into atomic commits that can be reviewed and reverted independently.

Recommended order:
1. Spec/docs update.
2. Domain decode compatibility and legacy field removal.
3. Server form UI removal.
4. Runtime removal and Cloudflare directory deletion.
5. Package, Info.plist, and metadata cleanup.
6. Test updates.
7. README, website copy, architecture instructions (`AGENTS.md` / `CLAUDE.md`), and visible localization string updates.
8. Build and targeted test verification.

## Acceptance Criteria

- Server creation UI offers SSH and Mosh only.
- Standard SSH connections still use password/key/key+passphrase authentication.
- Mosh connections still bootstrap and fall back exactly as before.
- Old `tailscale` server records load as standard SSH.
- Old `cloudflare` server records load as standard SSH.
- Old `tailscale` and `cloudflare` records connect through the standard SSH path and surface standard SSH errors.
- Active `Server`, `ServerCredentials`, and `KeychainManager` APIs no longer expose Cloudflare-specific fields or token helpers.
- `ServerTransportSelection` exposes only `standard` and `mosh`.
- Local JSON writes omit legacy Cloudflare fields.
- CloudKit writes omit legacy Cloudflare fields.
- `SSHClient.connect` cache key no longer references removed Cloudflare fields.
- No Cloudflare tunnel or OAuth code remains in the app target.
- `swift-cloudflared` is no longer referenced by the Xcode project or package resolution.
- iOS and macOS apps no longer register `vvterm-cfaccess`.
- Tests compile and cover legacy decode behavior.
- README and website copy no longer claim Tailscale or Cloudflare support.
