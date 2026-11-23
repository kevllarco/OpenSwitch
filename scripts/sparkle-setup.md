# Sparkle update signing — one-time setup

OpenDisplay updates itself with [Sparkle 2](https://sparkle-project.org). Every update is verified
twice before it runs: against the project's EdDSA (ed25519) signing key, and against the Developer ID
code signature of the app that is already installed. This file covers the key half — the part that
lives outside the repository and can't be regenerated from it.

## What is already wired up

| Piece | Where | Value |
|---|---|---|
| Feed | `Apps/OpenDisplay/Resources/Info.plist` → `SUFeedURL` | `https://raw.githubusercontent.com/kevllarco/OpenSwitch/main/appcast.xml` |
| Public key | `Apps/OpenDisplay/Resources/Info.plist` → `SUPublicEDKey` | `GOnMLLE932dHyUBXxIG2qdyRS0wfzcHn0tzV3HatjSs=` |
| Private key | maintainer's **login keychain** (account `ed25519`) | never on disk, never in the repo |
| Framework | `project.yml` → `packages.Sparkle` | resolved by SwiftPM, embedded in the app |
| Appcast | produced by `scripts/release-signed.sh`, uploaded beside `OpenDisplay.zip` | one item, signed |

The appcast is committed to the OpenSwitch repository so prerelease builds can receive later updates
without changing their feed URL. Every release must update this file and attach the matching appcast
asset to the release.

## Generating the key (only on a new machine, or to rotate)

The key exists in the release Mac's login keychain. Running `generate_keys` again will print the
existing public key instead of replacing it. You only need this section to set up a second release
machine or deliberately rotate the key.

```sh
# The tools travel inside the resolved Sparkle package, so they always match the embedded framework.
DD=$(ls -dt ~/Library/Developer/Xcode/DerivedData/OpenDisplay-* | head -1)
SPARKLE_BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"

"$SPARKLE_BIN/generate_keys"        # creates the keypair, stores the private half in the keychain
"$SPARKLE_BIN/generate_keys" -p     # prints just the public key, for checking against Info.plist
```

`generate_keys` prints the `SUPublicEDKey` value to paste into
`Apps/OpenDisplay/Resources/Info.plist`. Confirm the embedded key matches the machine you release
from before cutting a release:

```sh
diff <("$SPARKLE_BIN/generate_keys" -p) \
     <(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Apps/OpenDisplay/Resources/Info.plist)
```

To move the key to another machine, export and import it — never commit the exported file, and delete
it once imported:

```sh
"$SPARKLE_BIN/generate_keys" -x sparkle-private-key.txt   # on the machine that has the key
"$SPARKLE_BIN/generate_keys" -f sparkle-private-key.txt   # on the machine that needs it
rm -P sparkle-private-key.txt
```

## Cutting a release

```sh
./scripts/release-signed.sh                 # build → sign → notarize → staple → zip → appcast
gh release create v0.9.1 dist/OpenDisplay.zip dist/appcast.xml --title "…" --notes-file …
```

or, against a release that already exists:

```sh
PUBLISH=1 ./scripts/release-signed.sh       # uploads both assets with gh
```

The script derives the version from the built app's `CFBundleShortVersionString`, uses `v<version>`
as the release tag (override with `RELEASE_TAG=`), and lifts that version's section out of
`CHANGELOG.md` as the release notes Sparkle shows in its update window.

## Things that will bite you

* **Every release needs its appcast.** `SUFeedURL` points at `main/appcast.xml`. Publish the matching
  release asset and commit the generated appcast so installed copies can find the update.
* **The first Sparkle-enabled release still has to be installed by hand.** Sparkle only updates *from*
  a build that already contains it. Copies built before 0.12.0 have no update feed, so install this
  release once; later releases can arrive through the in-app updater.
* **Appcast generation must come after stapling.** The signature and length cover the exact bytes
  users download, and `xcrun stapler` rewrites the zip. The script already orders it that way.
* **Losing the private key means users can't update.** An app in the field only installs what its
  embedded public key verifies. Recovering means generating a new key, shipping an app with the new
  `SUPublicEDKey`… which nobody can auto-update to. Keep the login keychain backed up.
* **A build running from DerivedData will happily update itself** into the released app. That is
  Sparkle working as designed on a debug build; quit the dev copy before testing an update, or turn
  the automatic check off in Settings while developing.
