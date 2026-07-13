# Herdr Workspace Integration Fixture

This opt-in XCTest validates the real no-PTY path through VVTerm's own stack:

```text
SSHClient/libssh2 -> HerdrWorkspaceConnection -> HerdrClientKit
```

It requires a disposable, already-running Herdr 0.7.3 named session. The test
verifies protocol 16 Welcome, the initial full ANSI redraw, resize, input, and
detach. It stops the named server during cleanup, so never point it at a user
session that must remain running.

A second real test uses a short random session name with no running server and
verifies that structured preflight returns `runtimeUnavailable` before opening
the private bridge or sending a protocol Hello.

## Environment

```sh
export VVTERM_SSH_FIXTURE_HOST=example.com
export VVTERM_SSH_FIXTURE_USER=user
export VVTERM_SSH_FIXTURE_PASSWORD='password'
export VVTERM_HERDR_EXECUTABLE=/absolute/path/to/herdr
export VVTERM_HERDR_SESSION_NAME=vvterm-libssh2-smoke
```

Private-key authentication uses the same `VVTERM_SSH_FIXTURE_PRIVATE_KEY_PATH`
and optional `VVTERM_SSH_FIXTURE_KEY_PASSPHRASE` variables documented in
`ssh-exec-stream-fixture.md`.

Run only the integration test:

```sh
xcodebuild test \
  -project VVTerm.xcodeproj \
  -scheme VVTerm \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:VVTermTests/HerdrWorkspaceIntegrationTests/testRealWorkspaceBridgeOverVVTermSSHClient
```

## Known startup boundary

On the macOS Herdr 0.7.3 integration fixture, invoking
`remote-client-bridge` over VVTerm's no-PTY libssh2 channel while the named
server is stopped does not successfully keep the implicitly spawned headless
server alive. Its startup pane receives `SIGHUP` before the client socket is
ready. The same VVTerm/libssh2 bridge works once the named server is already
running.

This fixture intentionally separates validation of the native protocol path
from the unresolved remote server bootstrap lifecycle. A production entry must
not assume that Herdr 0.7.3 auto-start is reliable over every no-PTY SSH client.

Use short session names for disposable fixtures. Long names combined with the
Herdr config directory can exceed macOS `sockaddr_un.sun_path` capacity; Herdr
then exits before emitting structured status JSON.
