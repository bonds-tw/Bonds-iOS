#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/clean/zkID" >&2
  exit 64
fi

overlay_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
zkid_dir="$1"
expected_commit="b395e09c225ff45b003f0087c28e2e208e22f944"

# CMake is installed through the user's Python tool directory on the build
# machine. It is needed by the host-side Cargo build as well as both iOS slices.
export PATH="${HOME}/Library/Python/3.9/bin:${PATH}"

actual_commit="$(git -C "$zkid_dir" rev-parse HEAD)"
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "refusing unreviewed zkID revision: $actual_commit" >&2
  exit 65
fi
if ! git -C "$zkid_dir" diff --quiet || ! git -C "$zkid_dir" diff --cached --quiet; then
  echo "zkID checkout must be clean before applying the overlay" >&2
  exit 65
fi

git -C "$zkid_dir" apply "$overlay_dir/zkid-mobile.patch"
git -C "$zkid_dir" apply "$overlay_dir/utf8-name-circuit.patch"
install -m 0644 "$overlay_dir/predicate.rs" \
  "$zkid_dir/wallet-unit-poc/mobile/src/predicate.rs"
install -m 0644 "$overlay_dir/age_assets.rs" \
  "$zkid_dir/wallet-unit-poc/mobile/src/bin/age_assets.rs"
mkdir -p "$zkid_dir/wallet-unit-poc/mobile/.cargo"
install -m 0644 "$overlay_dir/cargo-config.toml" \
  "$zkid_dir/wallet-unit-poc/mobile/.cargo/config.toml"

mobile_dir="$zkid_dir/wallet-unit-poc/mobile"
circuit_dir="$zkid_dir/wallet-unit-poc/circom"
(
  cd "$circuit_dir"
  npm install --ignore-scripts --no-audit --no-fund
  bash scripts/compile.sh jwt_2k
  bash scripts/compile.sh show
)
cargo fetch --manifest-path "$mobile_dir/Cargo.toml"
adapter_dir="$(find "${CARGO_HOME:-$HOME/.cargo}/git/checkouts" \
  -path '*/witnesscalc_adapter-*/e5a82bc' -type d -print -quit)"
if [ -z "$adapter_dir" ]; then
  echo "reviewed witnesscalc_adapter checkout e5a82bc was not fetched" >&2
  exit 66
fi
if git -C "$adapter_dir" apply --check "$overlay_dir/witnesscalc-adapter.patch"; then
  git -C "$adapter_dir" apply "$overlay_dir/witnesscalc-adapter.patch"
elif ! git -C "$adapter_dir" apply --reverse --check "$overlay_dir/witnesscalc-adapter.patch"; then
  echo "witnesscalc_adapter overlay no longer applies cleanly" >&2
  exit 66
fi

# Cargo fingerprints git dependencies by their pinned revision. Because this
# reviewed build patches that checkout in place, remove only the adapter and
# its native consumer so neither the host tool nor an iOS slice can reuse a
# build-script binary from an earlier overlay revision.
cargo clean --manifest-path "$mobile_dir/Cargo.toml" --release \
  -p witnesscalc-adapter -p ecdsa-spartan2
if [ -d "$mobile_dir/build" ] && [ ! -f "$mobile_dir/build/CACHEDIR.TAG" ]; then
  printf '%s\n' 'Signature: 8a477f597d28d172789f06886806bc55' > "$mobile_dir/build/CACHEDIR.TAG"
fi
cargo clean --manifest-path "$mobile_dir/Cargo.toml" --target-dir "$mobile_dir/build" --release \
  -p witnesscalc-adapter -p ecdsa-spartan2

for artifact in \
  "$zkid_dir/wallet-unit-poc/circom/build/cpp/jwt_2k.cpp" \
  "$zkid_dir/wallet-unit-poc/circom/build/cpp/show.cpp" \
  "$zkid_dir/wallet-unit-poc/circom/build/jwt_2k/jwt_2k_js/jwt_2k.r1cs" \
  "$zkid_dir/wallet-unit-poc/circom/build/show/show_js/show.r1cs"
do
  if [ ! -f "$artifact" ]; then
    echo "missing compiled circuit: $artifact" >&2
    exit 66
  fi
done

cd "$mobile_dir"
cargo build --release --bin ios

# The generated 2K witness calculator is large. Building both slices in one
# Mopro invocation keeps every target directory alive at once and can consume
# more than 8 GB, even though the finished static libraries are only a fraction
# of that. Preserve each finished slice, discard only its rebuildable Cargo
# output, then combine the two libraries ourselves.
artifact_root="$(mktemp -d "${TMPDIR:-/tmp}/openac-age-ios.XXXXXX")"
cleanup_artifacts()
{
  if [ -d "$artifact_root" ]; then
    find "$artifact_root" -depth -delete
  fi
}
trap cleanup_artifacts EXIT

build_slice()
{
  local target="$1"
  local label="$2"
  CONFIGURATION=release \
    IOS_ARCHS="$target" \
    IPHONEOS_DEPLOYMENT_TARGET=16.0 \
    ./target/release/ios
  mv MoproiOSBindings "$artifact_root/$label"
  find "$mobile_dir/build" -depth -delete
}

build_slice aarch64-apple-ios device
build_slice aarch64-apple-ios-sim simulator

mkdir -p MoproiOSBindings
install -m 0644 "$artifact_root/device/mopro.swift" MoproiOSBindings/mopro.swift
xcodebuild -create-xcframework \
  -library "$artifact_root/device/MoproBindings.xcframework/ios-arm64/libopenac_age_mobile_app.a" \
  -headers "$artifact_root/device/MoproBindings.xcframework/ios-arm64/Headers" \
  -library "$artifact_root/simulator/MoproBindings.xcframework/ios-arm64-simulator/libopenac_age_mobile_app.a" \
  -headers "$artifact_root/simulator/MoproBindings.xcframework/ios-arm64-simulator/Headers" \
  -output MoproiOSBindings/MoproBindings.xcframework

echo "built $mobile_dir/MoproiOSBindings"
