# YAAM website

Public URL: https://yaam.asis.sh/

Original, buildless English product website. System-font stack and #18A4D1 / #F9A229 / #0E262E / #34270E palette follow the requested Audio Hijack reference. Artwork is YAAM's; illustrations and globe are original. No analytics, cookies, CDN scripts, runtime packages or third-party browser requests are required.

## Preview

From this directory, run `python3 -m http.server 4317 --bind 127.0.0.1`, then open http://127.0.0.1:4317/. The production download archive lives on the server and is intentionally not copied into this repository.

## Source

- `index.html`: semantic, searchable feature directory and product copy; useful without scripting.
- `features.json`: editable capability content. Run `python3 ops/render_features.py` to refresh its HTML.
- `style.css`: responsive layouts, reference palette/system typography, reduced-motion support.
- `app.js`: local globe, gallery/dialog, feature search, deep links, mobile navigation, motion control.
- `assets/`: compressed app artwork, bundled-guide screenshots, Natural Earth public-domain land data; see attribution.
- `ops/nginx.conf`: dedicated server configuration; includes the generated JSON-LD CSP hash.

Feature descriptions were checked against local source v1.37.55 on November 5, 2026. Digital-mode limitations are explicit. The latest published release at creation was GitHub's **v1.37.37 pre-release**, October 18, 2026, build 187, Apple Silicon, macOS 15.6+. It is intentionally not represented as a v1.37.55 binary. The older `ep2aes.asis.sh` ZIP was v1.0.0 and is not used.

Published archive: `/releases/YAAM-1.37.37-macOS.zip` (29,954,922 bytes).

SHA-256: `b97aec2bbd84662487974bff90cbb464549460117bbea8ec4e9d3d47eeea5a09` (matched to the official GitHub release asset).

## Hosting and updates

- Host: `root@65.109.192.152`; nginx site: `/etc/nginx/sites-available/yaam.asis.sh`.
- Site root: `/var/www/yaam/current`, a symlink to a timestamped immutable web directory.
- Archives: `/var/www/yaam/releases/` (separate from website versions).
- Certificate: `/etc/letsencrypt/live/yaam.asis.sh/`; renews with the existing certbot timer and webroot `/var/www/yaam/acme`.
- Upload only `index.html`, `404.html`, `style.css`, `app.js`, `robots.txt`, `sitemap.xml` and `assets/` into a new version directory. Verify it, then atomically repoint `current`. Keep previous versions for rollback.
- Download updates: verify the official archive hash, version, architecture and minimum OS; update all version/size/hash references together. Do not substitute a local development build without an intentional application release.
- When editing the structured-data script, update its SHA-256 in nginx before reloading. Run `nginx -t` first. No other virtual hosts need changing.

## Verification

JavaScript syntax, HTML IDs/anchors/assets, local HTTP responses, responsive browser layouts, gallery and modal, feature search/empty state/expansion, deep links and motion control were checked. Production checks cover TLS, HTTP redirect, page/assets/404, official binary SHA-256 and partial-content download support.


## November 5 update: comparison and updater bootstrap

The site now includes a 23-row comparison with MacLoggerDX, RUMlogNG and Wavelog, a seven-row integrated-advantage filter, explicit unknown/companion distinctions, dated official sources and competitor strengths. It introduces the website preview v1.37.56 (206), its corresponding source ZIP and first-install guidance for the signed Sparkle updater. See `Docs/Software-Updates.md` for the trust/signing/release workflow and actual validation.

Previous download: `/releases/YAAM-1.37.56-macOS.zip`, 32,393,072 bytes, SHA-256 `b23edf2138694787b23546bd942be3cc26bee949d14ac33aa053d6dcf0d35767`. This is explicitly a non-notarized developer preview. The historical v1.37.37 archive remains available. `/updates/` is separately mapped to `/var/www/yaam/updates/`; signed appcast bytes must be uploaded unchanged. No private key is deployed.


## 1.37.57 (207) — reviewed sync and radio evidence

Current download: `/releases/YAAM-1.37.57-macOS.zip`, 32,436,009 bytes, SHA-256 `c9078e6b1e56982a649e5154e53a631fe7489f4456d3f6f6a006de0be0f25141`. Corresponding source: `/releases/YAAM-1.37.57-source.zip`; GitHub release: https://github.com/fact0real/yaam/releases/tag/v1.37.57 .

The website feature reference matches this build. Sync All reviews per-provider counts before queueing, Digital Suite logging requires fresh radio frequency evidence, and Olivia/Contestia is explicitly a tone prototype without native interoperable text coding. Relative FT8 DT does not diagnose the local clock; independent reference acquisition remains unimplemented. Russia grouping preserves ADIF entity distinctions. This remains a non-notarized developer preview. Existing 1.37.56 users can update through the signed feed; older builds need a manual bootstrap installation.


## 1.37.59 (209) — QRZ Incoming follow-up

Current download: `/releases/YAAM-1.37.59-macOS.zip`, 32,475,322 bytes, SHA-256 `e16028c4b3ed406075d11ec18555b521156774d6d0c994461a57fa61ad60c7a0`. Corresponding source: `/releases/YAAM-1.37.59-source.zip`. Release notes: `/updates/release-1.37.59.html`.

QRZ profile emails are checked automatically; only requests needing details with a published usable email can be selected. Bulk drafts receive their recipients atomically and combine request dates per callsign. Failed checks remain distinct from missing published emails; current no-email requests offer a prefilled rejection. The build also includes multi-file ADIF Live Sync from local 1.37.58. This remains a non-notarized developer preview with publisher-signed feed and archive.


## 1.37.60 (210) — consistent DXCC identities

Current download: `/releases/YAAM-1.37.60-macOS.zip`, 32,521,038 bytes, SHA-256 `7dd7421e1c54d0533a7ef4ff4419e6dd6104b24523cea6ce878875611b8f24ac`. Corresponding source: `/releases/YAAM-1.37.60-source.zip`. Release notes: `/updates/release-1.37.60.html`. Worked/confirmed counts and country/band views share an ADIF identity, missing codes use unambiguous country/operating-call evidence, and Russia entities remain distinct. Local QRZ confirmations are separate from all-source confirmations. Invalid/unresolved identities have a review list; original ADIF fields remain unchanged. Non-notarized preview, signed publisher feed/archive.


## 1.37.61 (211) — logbook scrolling

Current download: `/releases/YAAM-1.37.61-macOS.zip`, 32,518,447 bytes, SHA-256 `eda312df1e75c266cc37d5b1acba85228b35564b151fcc9ac1a1d55668e695ef`. Corresponding source: `/releases/YAAM-1.37.61-source.zip`; release notes: `/updates/release-1.37.61.html`; GitHub: https://github.com/fact0real/yaam/releases/tag/v1.37.61 .

The table constructs pinned and nearby horizontal cells, retains exact column positions, and exposes the complete filtered log without the 1,000-row loading boundary. Includes the complete 1.37.60 DXCC/Russia corrections and 1.37.59 QRZ follow-up changes. A 100,000-row/30-column production-rendering fixture, 2,800 geometry checks, DXCC regressions and Debug/Release builds cover the change. Measurements are fixture-specific; see the release notes. Non-notarized developer preview with signed publisher feed/archive. Activation is guarded against the prior 1.37.60 site and build 210; previous downloads/site directories remain available.


## 1.37.62 (212) — security hardening for HamClock kiosk remote control

Current download: `/releases/YAAM-1.37.62-macOS.zip`, 32,501,983 bytes, SHA-256 `cf42d16e1ec01cf70e381a9842c2a607db3aee30fdf84e31558eba38346d2d57`. Corresponding source: `/releases/YAAM-1.37.62-source.zip`; release notes: `/updates/release-1.37.62.html`; GitHub: https://github.com/fact0real/yaam/releases/tag/v1.37.62 .

The HamClock Remote Web Server enforces token authentication on all telemetry and rotator control endpoints, eliminates wildcard CORS, validates azimuth bearings, and repairs connection lifecycle state handling to prevent socket leaks. Non-notarized developer preview with signed publisher feed/archive.
