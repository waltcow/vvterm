# SSH Exec Stream Binary Echo Fixture

This opt-in integration test verifies VVTerm's long-lived, no-PTY SSH Exec Stream against a real SSH server before Herdr protocol code is introduced.

The test starts an inline Python bridge on the remote host. The bridge reads 4-byte big-endian length-prefixed binary frames from stdin, echoes the frames unchanged to stdout, and sends fixed diagnostics only to stderr. No fixture files are installed on the remote host.

## Requirements

- A POSIX SSH server reachable from the test machine.
- Password or private-key authentication.
- Python 3 on the remote host.
- A disposable test account is recommended.

## Environment

Required:

```sh
export VVTERM_SSH_FIXTURE_HOST=127.0.0.1
export VVTERM_SSH_FIXTURE_USER=fixture
```

Authentication, choose one:

```sh
export VVTERM_SSH_FIXTURE_PASSWORD='fixture-password'
```

```sh
export VVTERM_SSH_FIXTURE_PRIVATE_KEY_PATH="$HOME/.ssh/vvterm-fixture"
export VVTERM_SSH_FIXTURE_KEY_PASSPHRASE='optional-passphrase'
```

Optional:

```sh
export VVTERM_SSH_FIXTURE_PORT=22
export VVTERM_SSH_FIXTURE_PYTHON=python3
```

## Run

Run `SSHExecStreamIntegrationTests` from Xcode with the environment variables added to the test action, or use:

```sh
xcodebuild test \
  -project VVTerm.xcodeproj \
  -scheme VVTerm \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:VVTermTests/SSHExecStreamIntegrationTests
```

If the host and user variables are absent, the real SSH test is skipped. Frame codec and command-construction tests remain part of the default unit-test suite.

## Coverage

- zero-length payload
- one byte
- NUL, CR, LF, ESC, and `0xff`
- 32 KiB boundary payload
- 1 MiB payload
- 256 rapidly queued small payloads
- stdout/stderr separation
- stdin half-close
- remote EOF and exit
- concurrent one-shot Exec fairness on the same SSH connection

Cancellation, queue limits, partial writes, terminal error delivery, and read-side backpressure are covered by `SSHExecStreamTests` without requiring a remote host.
