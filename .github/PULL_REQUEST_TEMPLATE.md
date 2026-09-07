## What / 做了什麼

<!-- One paragraph. Link the issue if there is one. -->

## Why / 為什麼

<!-- The reason, not the diff. Which user or verifier is affected? -->

## How it was verified / 怎麼驗證的

- [ ] `backupTWTests` pass locally (`xcodebuild test -scheme backupTW -only-testing:backupTWTests`)
- [ ] Ran on a real device, if the change touches Keychain, Secure Enclave, App Attest, BLE, camera, or the signing broker
- [ ] New user-facing strings added to `Localizable.xcstrings` in both `en` and `zh-Hant`
- [ ] Docs updated if behaviour, trust gates, or caveats changed

## Privacy and secrets checklist / 隱私與機密檢查

- [ ] No real ID number, certificate, MyData file, or TW FidO round trip in the diff or fixtures
- [ ] Nothing new reads TW FidO SP credentials outside `#if DEBUG`
- [ ] Any new stored file is in Application Support, `completeUnlessOpen`, excluded from backup
