# YAAM software-update delivery

YAAM uses **Sparkle 2.10.1**, pinned exactly in the Xcode project and Package.resolved. It does not execute a server-provided shell command, remove quarantine, force-kill the radio application or replace a running bundle from the application process.

## Trust and sandbox boundary

- Feed: `https://yaam.asis.sh/updates/appcast.xml`, pinned by `YAAMUpdater` as well as Info.plist.
- Archive: exact `https://yaam.asis.sh/releases/YAAM-<major.minor.patch>-macOS.zip`; credentials, query/fragment, alternate hosts/ports, encoded alternatives and product mismatches are rejected.
- Public Ed25519 key: `SUPublicEDKey` in AppInfo.plist. Private key: login Keychain, Sparkle account **ASIS.YAAM.updates**, generated with Sparkle's official `generate_keys` utility. No private key is in Git, an archive, a command-line argument or the web server.
- `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are true; `SUSignedFeedFailureExpirationInterval` is zero. Maintain an independently protected backup of the signing key through the publisher's normal secure process; losing it can prevent future updates.
- Sparkle's sandbox installer service is enabled. Only the two app-specific `ASIS.YAAM-spks` / `ASIS.YAAM-spki` Mach lookups are added. The existing sandbox, logbook paths and credential vault remain in place.
- Increasing CFBundleVersion, a canonical three-component displayed version, bounded nonzero size and Sparkle's OS/hardware/signature checks are required. Appcast replay cannot install an older/equal build.

Daily checking is enabled by default; automatic downloads and install-on-quit are opt-in. System profiling and JavaScript release notes start disabled. Requests contain ordinary HTTP metadata and app/framework versions, not a callsign, location, credential or QSO payload. Check/download settings are owned by Sparkle's persisted preferences.

Requested relaunch can be postponed while registered transmit or CW Auto-CQ is active. AppKit's normal application termination path remains responsible for releasing hardware and allowing queued CAT/PTT requests to drain. This does not confirm physical RX. Tests must not key real hardware.

## Publish a build

1. Increment marketing version and build, run the focused regression and Debug/Release builds. Keep the Sparkle pin current through intentional, reviewed dependency updates.
2. Produce a **Developer ID signed and notarized** app for a production release when that signing identity is available. Exporting an Xcode archive with Developer ID is the preferred Sparkle signing workflow. The current available website build is explicitly a non-notarized developer preview; do not label its ad-hoc signature as Apple distribution approval.
3. Preserve nested helper/framework signatures and their individual entitlements. Do not sign the entire Sparkle tree with the host application's entitlement plist or use `--deep` for signing. `--deep` is appropriate for verification.
4. Place release notes as `YAAM-<version>-macOS.html` in a fresh release directory. Use an HTML fragment if you want embedded notes.
5. Run `Tools/package-software-update.sh` with the app and release directory, setting `SPARKLE_TOOLS` to `build/SourcePackages/artifacts/sparkle/Sparkle/bin` (or the same pinned official distribution). The helper signs the archives/feed through Keychain, verifies the feed, and prints the public archive hash.
6. Verify archive and feed signatures; modify copies and ensure verification fails. Check the embedded version, public key, sandbox entitlements and architecture. Publish the corresponding GPL source, including new files and the pinned dependency references/licenses.
7. Upload immutable, versioned ZIPs to `/var/www/yaam/releases/`. Upload the signed appcast byte-for-byte to `/var/www/yaam/updates/appcast.xml` using an atomic rename after assets exist. Do not rewrite XML/HTML with a CDN optimizer; any edit needs a new signature. Keep old archives for recovery/manual installation.
8. Update the website download version/size/hash/source links together. The updater's `/updates/` root is separate from timestamped website deployments.

The current nginx virtual host must map `/updates/` to `/var/www/yaam/updates/`, serve fresh metadata and retain HTTPS. Only public artifacts are uploaded; signing tools and keys remain on the Mac.

## Bootstrap and verification limits

An installed app without Sparkle cannot retroactively update itself through the new feed. Users install the updater-enabled build once, then future signed releases use the in-app flow. A native “up to date” test proves feed delivery and validation, not a real replacement/relaunch. Exercise replacement only with disposable test bundles and synthetic settings; do not replace a user's running station during verification.

Official references: [setup](https://sparkle-project.org/documentation/), [sandbox integration](https://sparkle-project.org/documentation/sandboxing/), [security options](https://sparkle-project.org/documentation/customization/).

## Verification performed for 1.37.56

- Debug and Release builds on macOS/arm64 with Sparkle 2.10.1 resolved by its pinned checksum.
- `SoftwareUpdateRegression`: wrong-origin/product URLs, userinfo/query/fragment/port/encoding alternatives, equal/older/invalid builds, size bounds, TX/CW restart eligibility and signed-feed configuration.
- `ReleaseEntitlementsRegression`: source inventory and effective staged Release entitlements; sandbox on, no debugger privilege.
- Existing `QuitReleasesTransmitRegression`: idle exit, active transmit release, delayed quit/drain and repeated quit.
- Official Sparkle signing tools: authentic payload/feed accepted, modified payload/feed rejected.
- Native update-settings preview under a separate bundle ID: toggles, dependent automatic-download state and native UI.
- **Real sandboxed installation and relaunch**: disposable `ASIS.YAAM.UpdaterSmoke` apps (build 1 → 2), a separate signed HTTPS test feed, full download/verification/Install and Relaunch, then visible build 2. `Tests/SoftwareUpdateSmokeApp.swift` is the fixture application, not part of the YAAM target. No station code, logbook, credential vault or physical radio was used. The temporary public test feed is removed after verification.

The publisher currently has an Apple Development identity, not a Developer ID distribution identity. This is why the downloadable build is clearly a non-notarized developer preview; neither the website nor updater claims Apple notarization. Future production releases should use Developer ID/archive export and notarization, without changing the public Ed25519 key accidentally.


## 1.37.57 (207) publication

The first update after the 1.37.56 website bootstrap uses the same pinned public key and an increasing build number (207 > 206). Debug/Release builds, focused regressions, effective sandbox/no-debugger entitlements and official Sparkle feed/archive signature verification passed; modified feed/archive copies were rejected. Both website and GitHub publish the same immutable binary ZIP and corresponding tagged GPL source. See `Docs/Release/1.37.57-release-notes.md` for changes and remaining limitations. This remains an explicitly non-notarized developer preview. A fresh physical-radio/live-provider acceptance or another real-app replacement test was not performed for this patch.


## 1.37.59 (209) publication

QRZ Incoming follow-up fixes and the multi-file ADIF Live Sync work from local 1.37.58 use build 209 and the unchanged publisher public key. The release includes a corresponding source snapshot with a file-hash manifest; unrelated untracked analysis reports are excluded. Validation covers focused QRZ regressions, update-policy and Release-entitlement regressions, the optimized Release build, effective sandbox/no-debugger privileges, and authentic feed/archive acceptance with corrupted-copy rejection. Live UI and real QRZ/SMTP delivery were not completed. The website retains prior downloads; publication changes the versioned assets, signed feed and current-site symlink.


## 1.37.60 (210) publication

Shared ADIF entity identities reconcile worked/confirmed counting and Russia display labels. Debug/Release builds, 53 focused counting/identity checks, Russian grouping/ADIF round-trip checks, 42 portable-callsign checks, update-policy and effective entitlement checks passed. Authentic archives/feeds were accepted and corrupted copies rejected with the unchanged publisher key. Live visual review and live QRZ synchronization were not performed. Publication includes the corresponding source snapshot and retains prior archives for rollback.

## 1.37.61 (211) publication

Logbook scrolling now constructs pinned/visible columns with exact offscreen spacing and represents the complete filtered log without incremental footer loading. Build 211 retains the publisher public key. Validation covers 2,800 geometry checks, the production row/viewport fixture with 100,000 invented contacts, Debug/Release builds, update policy and staged sandbox/no-debugger entitlements. Official Sparkle tools verify authentic archive/feed signatures and reject modified copies. The website and GitHub distribute identical immutable binaries and corresponding GPL source. This remains a non-notarized developer preview; no real station/logbook is used by the scroll fixture.
