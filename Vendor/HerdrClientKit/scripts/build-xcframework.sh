#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CRATE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=${1:-"$CRATE_DIR/build"}
XCFRAMEWORK="$OUTPUT_DIR/HerdrClientKit.xcframework"

RUSTC_BIN=$(rustup which rustc --toolchain stable)
CARGO_BIN=$(rustup which cargo --toolchain stable)

for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
    if ! rustup target list --installed --toolchain stable | grep -qx "$target"; then
        rustup target add --toolchain stable "$target"
    fi
    env RUSTC="$RUSTC_BIN" "$CARGO_BIN" build \
        --manifest-path "$CRATE_DIR/Cargo.toml" \
        --release \
        --locked \
        --target "$target"
done

rm -rf "$XCFRAMEWORK"
mkdir -p "$OUTPUT_DIR"

xcodebuild -create-xcframework \
    -library "$CRATE_DIR/target/aarch64-apple-darwin/release/libherdr_client_kit.a" \
    -headers "$CRATE_DIR/include" \
    -library "$CRATE_DIR/target/aarch64-apple-ios/release/libherdr_client_kit.a" \
    -headers "$CRATE_DIR/include" \
    -library "$CRATE_DIR/target/aarch64-apple-ios-sim/release/libherdr_client_kit.a" \
    -headers "$CRATE_DIR/include" \
    -output "$XCFRAMEWORK"

echo "$XCFRAMEWORK"
