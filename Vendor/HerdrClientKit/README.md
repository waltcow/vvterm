# HerdrClientKit

`HerdrClientKit` is VVTerm's transport-independent client core for the Herdr
private workspace protocol. It is pinned to:

- Herdr tag: `v0.7.4`
- Herdr revision: `50aaa2ec046ee26ff407c20f49de496f522512a8`
- Protocol version: `16`
- Wire format: `u32` little-endian length followed by a bincode 2 standard
  configuration payload

The crate owns protocol framing, the client handshake, sequence validation,
bounded event buffering, and outbound input/resize/scroll/detach messages. It does not
own SSH, credentials, rendering, or application lifecycle.

## Build

From the repository root:

```sh
./scripts/build.sh herdr-client-kit
```

This installs missing Rust Apple targets through `rustup`, builds arm64 slices
for macOS, iOS device, and iOS Simulator, and creates:

```text
Vendor/HerdrClientKit/build/HerdrClientKit.xcframework
```

The generated framework and Cargo target directory are intentionally ignored.
Run the command before opening or building the Xcode project on a fresh clone.

## C ABI ownership

- `herdr_client_create` returns an opaque client owned by the caller.
- `herdr_client_free` releases the client and accepts null.
- Functions returning `HerdrBuffer` or `HerdrEvent` transfer ownership to the
  caller.
- Release buffers with `herdr_buffer_free` and events with `herdr_event_free`.
- All exported calls contain Rust panics and convert them into status errors.
- `herdr_client_take_error` consumes the most recent diagnostic message.

See `include/herdr_client_kit.h` for the complete interface.

## Validation

```sh
cd Vendor/HerdrClientKit
cargo fmt --check
cargo clippy --offline --all-targets -- -D warnings
cargo test --offline
```

The ignored real-bridge smoke test can use either a local Herdr binary or an
already-authenticated SSH control socket:

```sh
cargo test installed_bridge_completes_real_handshake_and_full_redraw -- --ignored

HERDR_BRIDGE_SSH_SOCKET=/tmp/herdr.sock \
HERDR_BRIDGE_SSH_TARGET=user@example.com \
HERDR_REMOTE_BIN=/absolute/path/to/herdr \
cargo test installed_bridge_completes_real_handshake_and_full_redraw -- --ignored
```

The test creates a unique named session, validates the real protocol 16
Welcome and initial full ANSI redraw, sends resize/input/scroll/detach, and stops the
temporary server before returning.
