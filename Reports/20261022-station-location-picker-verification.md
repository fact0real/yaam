# Station location and precise grid picker — 2026-10-22

Shared board: https://github.com/fact0real/yaam-lab599-shared-board/issues/385

## Delivered workflow

Settings → Stations → Location → Choose location on map opens a native picker with:

- Explicit, on-demand macOS device location; best available fresh fix and reported horizontal accuracy, a bounded acquisition window, Stop, and recovery text for denied/unavailable access.
- Decimal coordinate entry with range/finite validation, Persian digits and decimal separators, plus strict complete 4/6/8/10-character grid entry.
- Native MapKit world map, click-to-select, zoom/pan, satellite imagery, selected-location annotation and cell outline, world and selected-pin navigation.
- Live grid, saved-coordinate and approximate cell-dimension previews; 4/6/8/10-character precision controls. An existing or entered grid is explicitly described as a cell center, not a measured station position.
- Unapplied manual edits block confirmation and can be restored. Validation feedback is next to the manual entry. Header and footer stay fixed while content scrolls.
- Apply edits only the current station draft's grid/latitude/longitude. Existing profile Save owns persistence; Cancel does not invoke the apply callback. No historical QSO rewrite.

The shared Maidenhead bounding-box reader now uses the same strict geometry and honors valid 8/10-character locators instead of reducing them to six-character subsquares. Two-character field geometry remains supported for existing map consumers. Saved coordinate rounding and grid encoding use the same values, including at cell boundaries and the poles/dateline.

macOS location usage descriptions are configured for Debug and Release and the sandbox location entitlement is present. Authorization is requested only by Locate me. No always-on tracking or IP-location fallback was added. Automatic updates stop on explicit cancellation, dismissal, a sufficiently accurate fix, or timeout.

## Verification

`bash Tests/run-station-location-regressions.sh` passed:

1. PreciseGridLocatorRegression: 25,025 coordinate/grid round trips across 2/4/6/8/10 characters, valid known locations, polar/dateline endpoints, deterministic random global samples, strict malformed locator rejection, invalid/nonfinite coordinates, Persian digits and decimal commas, precise shared-engine centers, persisted-coordinate/grid consistency, geometry resolution, stale/future/invalid fix rejection, profile-draft identity/metadata preservation and JSON round trip. Checks also confirm existing four/six-character transmission/weather truncation remains compatible with a ten-character profile grid.
2. StationPrivacyRegression: existing weather privacy defaults and request coordinates, locator validation, rover refresh, cancellation, persisted settings and actual QSL PNG/PDF export regressions.

Debug YAAM scheme build passed with signing disabled. Entitlements XML validation and `git diff --check` passed. Final Release/build installation results are recorded on the board at completion.

`python3 Tests/render-station-location.py` renders the production picker with real MapKit tiles and an inert location-service fixture; it never requests a device position or constructs AppState. Inspected light/dark, compact/normal, initial world/no selection, selected location, expanded manual entry, invalid entry with blocked confirmation, denied access, and acquisition/loading states. Images are generated at `/tmp/yaam-station-location-visual`. Native MapKit hosted annotation/control layers may not be fully represented by NSView bitmap capture; real tiles, cell outlines and position labels were visible.

## Limits

Actual macOS location authorization, hardware fix reception, interactive native map clicks, satellite tile availability and pointer hover were not exercised end to end. Location freshness/accuracy rules were tested independently; denied/loading interfaces use inert fixtures. Device accuracy is displayed rather than inferred from grid length. An entered grid supplies its cell center, and map clicks have unmeasured positional accuracy. The map projection has polar display limits; validated polar coordinates remain stored exactly.

No production station profile/logbook or system location authorization was changed by the regression fixtures.

Platform references: [Apple location authorization and usage descriptions](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services), [MapReader](https://developer.apple.com/documentation/mapkit/mapreader), [MapProxy coordinate conversion](https://developer.apple.com/documentation/mapkit/mapproxy/convert(_:from:)).
