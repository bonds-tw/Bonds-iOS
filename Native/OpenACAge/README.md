# OpenAC field-predicate native binding

This directory is the reproducible source overlay for the field-level age proof
used by 有備而來. It is based on Ethereum Privacy and Scaling Explorations'
`ethereum/zkID` commit `b395e09c225ff45b003f0087c28e2e208e22f944` and Mopro 0.3.5.

The overlay exposes two application profiles over the same linked proof:

- verify an ES256 SD-JWT issuer signature and its committed birth-date disclosure;
- bind the credential's `cnf.jwk` key to a fresh verifier nonce;
- prove that the hidden ISO or Taiwan ROC birth date is not later than the
  verifier-supplied cutoff;
- link the Prepare and Show proofs and compare all public inputs against values
  supplied independently by the verifier.
- prove equality between a signed full-name disclosure and a verifier-supplied
  UTF-8 name of up to 31 bytes. The circuit hashes the complete bytes and their
  length with Poseidon before `EQ`; it does not truncate the name into OpenAC's
  eight-byte legacy string slot.

`predicate.rs` is copied into the upstream mobile crate. `zkid-mobile.patch`
adds its UniFFI exports and pinned dependencies, and runs each native prover on
a dedicated 64 MB stack. `witnesscalc-adapter.patch` moves loader scratch
arrays to heap storage, keeps the iOS 16 deployment floor consistent, and
prevents an Apple Silicon build from silently compiling the unnecessary Intel
simulator slice.
`utf8-name-circuit.patch` adds the full UTF-8 equality profile while preserving
the existing numeric age predicate.

Run `./build-ios.sh /path/to/clean/zkID` after compiling the upstream Circom
`jwt_2k` and `show` circuits. The script refuses any upstream revision other
than the reviewed commit. The resulting XCFramework must be zipped and its
SwiftPM checksum and SHA-256 recorded before publication; runtime circuit/key
files are separately pinned by `AgePredicateCircuitAssets.swift`.

`age_assets.rs` is the release gate for those runtime files. It creates fresh
circuit keys and then signs a fixed ES256 SD-JWT, proves an exact hidden UTF-8
name, reblinds both linked proofs, checks the expected verifier statement, and
rejects the same proof for a different target name. A release whose positive or
negative vector fails is not publishable.

Do not treat the self-issued MyData digital-ID derivative as a government
assertion. The same proof mechanics hide its name, but the verifier result must
keep the source label `selfIssued` visible.

Upstream licenses remain Apache-2.0/MIT as declared by zkID and Mopro.
