# OpenAC field assets v2

Reproducible inputs:

- ethereum/zkID: `b395e09c225ff45b003f0087c28e2e208e22f944`
- witnesscalc_adapter: `e5a82bcb7d54a4694fc0662c51b01d99134e686c`
- Mopro: `0.3.5`
- iOS deployment target: `16.0`
- architectures: `arm64-apple-ios`, `arm64-apple-ios-simulator`
- SwiftPM XCFramework checksum: `7bd13bc83621d87e7a5f866518f3513f5fe5ed2fe03e4c46e6f9e9f51bff4776`

The release gate generated fresh circuit keys, signed a fixed ES256 SD-JWT
whose selectively disclosed UTF-8 name is `黃彥霖`, created and reblinded the
linked Prepare and Show proofs, and accepted the exact-name verifier statement.
The same proof was then checked against `王小明` and rejected. The build-Mac
gate measured 10,031 ms for Prepare and 131 ms for Show. These are release-gate
measurements, not the iPhone/iPad QR-to-judgment results.

The UTF-8 name profile is format 5. It hashes all name bytes plus their length
with Poseidon before applying OpenAC `EQ`; the target name is a verifier public
input and the name itself is not included in the proof package. The reviewed
profile accepts 1–31 UTF-8 bytes and a 128-bit SD-JWT disclosure salt.

| Asset | gzip bytes | gzip SHA-256 | installed bytes | installed SHA-256 |
|---|---:|---|---:|---|
| `jwt_2k.r1cs.gz` | 28,373,678 | `e60d73921d1935789a6d237949be72500cda0b3b39e196ae87016be26e68de3b` | 374,893,516 | `1ef44eb4889b19c71f6cec0f9cf91da04588346b2a262fb67739ff2ab691f0ad` |
| `show.r1cs.gz` | 590,996 | `0e537a97c34eea829fc945f5287853eaf576fc1963c51c607209f71eef1e010c` | 4,025,780 | `683162facd8636e062835cad414775fe2569f4e946493d1d55bfa56589858fba` |
| `prepare_proving.key.gz` | 23,772,560 | `6518606f1f6ae38bfbda1a19727748902c2c0b51aa545adef251a129701fb3df` | 432,432,554 | `167eb76c59505bd50b8a061bc5005960011e0877a4f663d6ddd395c0502119f4` |
| `prepare_verifying.key.gz` | 23,772,504 | `8fe4867ea95094b06c484862f3af8b0271f41088482bf495ae76b76c7da8fbe5` | 432,432,522 | `81f29f3a11e45a2e1b728c290f8af87ac8c8548fd049ac176897a583d83f5347` |
| `show_proving.key.gz` | 576,612 | `cf74a3e8f58be86d0e6faf68786e5b28952d4548485e394843b8e0340039d32d` | 4,871,018 | `8008c16e150736e595e0a3f9ebe31e57a56c7603e3348efa09618f696e275c61` |
| `show_verifying.key.gz` | 576,575 | `ae9df7e79ae7cabd8c87cfc7b27d39117618a6aeec459d1bb5c985f4bc0ff988` | 4,870,986 | `f112a4953b4af7f1aca5c561671cff6f11860b0d727b47418f30ed45f0e10258` |

The app independently checks the compressed transport and installed bytes. The
iPhone downloads both R1CS files and both key pairs; the iPad downloads only
the two public verifying keys. Downloads are excluded from proof and verifier
timing. The field release also moves witnesscalc loader scratch arrays to heap
storage so the 2K JWT circuit does not exhaust an iOS worker stack.
