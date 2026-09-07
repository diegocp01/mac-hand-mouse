# Keeping permission through source updates

Starting with v1.3.1, normal builds and source installs use a persistent, per-user code-signing identity. The same identity is reused across builds and cloned checkouts, so a changed binary can satisfy the requirement macOS saved when Accessibility was approved. A signing mismatch stops replacement of the installed app.

## Why the old checkbox stopped working

Earlier builds used `codesign --sign -` (ad-hoc signing). Their identity was a hash of that particular binary. Changing the code changed the hash; System Settings could continue showing an enabled entry for the previous version while the new app failed `AXIsProcessTrusted()`.

Apple documents this relationship in [TN3127: code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/). Its [code-signing guide](https://developer.apple.com/library/archive/technotes/tn2206/) also describes self-signed identities. A real signature with a stable signer is different from weakening a requirement to accept any app with the same name.

## Install and update

Use the usual command from a checkout:

```sh
bash "Install Hand Mouse.command"
```

The first build creates a local signing key. Later builds reuse it; no Apple developer membership, root certificate installation, or change to system trust settings is needed. Its dedicated Keychain is added to the user's lookup list, preserving other keychains and the default keychain. This makes the identity discoverable by older macOS signing tools; it does not mark the certificate as trusted. The certificate is used only for code signing, and its private key is imported as non-extractable with `/usr/bin/codesign` as the allowed signing tool. Temporary PEM/PKCS#12 files are removed immediately after import. This certificate does not make a downloaded app notarized or Developer ID signed.

Signing state lives outside the repository and build folder:

```text
~/Library/Application Support/Hand Mouse/Signing/
```

That directory is accessible only to its owner. It contains an encrypted, dedicated Keychain, its local unlock secret, and the public certificate fingerprint. Keep the whole directory with your private backups; do not publish it, copy it into the repository, or remove it during an update. The keychain is locked after signing. An incomplete identity stops the build instead of silently creating a different signer. An interrupted process can leave `.lock`; remove that empty lock directory only after confirming no other Hand Mouse build/install is running.

**Upgrading from v1.3.0 or earlier:** the old ad-hoc approval cannot authenticate the new signer. One final repair is required: quit the old app, install the new build, remove the old Hand Mouse entry in Accessibility, and add the exact new app using **Show in Finder**. Enable it, reopen Hand Mouse if necessary, then start the camera. The installer never resets privacy approvals automatically.

Normal updates should retain approval while the identity and installation are retained. No app can guarantee permission forever: user revocation, macOS/management policy, a lost signing identity, or moving to a different signer may require approval again. The local certificate lasts ten years; the installer will not silently replace it when renewal or recovery is needed.

## Developer and release modes

| Mode | Purpose |
| --- | --- |
| `local` (build/install default) | Persistent local identity for source-built installs. |
| `identity` | An explicitly chosen certificate, such as your Developer ID Application identity. |
| `adhoc` (package/CI default) | Disposable build artifacts; permission persistence is not supported. |

For an existing signing certificate:

```sh
HAND_MOUSE_SIGNING_MODE=identity \
HAND_MOUSE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
bash scripts/package.sh
```

`HAND_MOUSE_SIGNING_KEYCHAIN` optionally selects its keychain. A broadly distributed binary release should use Developer ID signing and notarization; the command above signs but does not notarize. Changing from a local certificate to a Developer ID identity is a deliberate migration, not a compatible local update. The installer refuses the mismatch and leaves the previous app in place.

`HAND_MOUSE_SIGNING_DIR` selects an isolated state directory for tests. Production builds should use the default consistently, including after cloning again. No private signing material is embedded in an app or included in a package. Only the public certificate accompanies a signature.

## Verify the contract

```sh
bash Tests/signing.sh
codesign --display -r- "build/Hand Mouse.app"
```

The local app's requirement contains its identifier and a certificate fingerprint, rather than `cdhash`. The regression suite signs different compiled binaries from separate directories with one identity, verifies that the update satisfies the old requirement, rejects another identity with the same certificate name, and rejects downgrading a stable install to ad-hoc signing. It also exercises legacy migration, missing state, file permissions, and the signing lock. These checks do not grant TCC permissions; the actual Accessibility approval still belongs to the user and macOS.
