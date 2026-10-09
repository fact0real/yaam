# FT8 Station 1.37.33 (183) verification

## Automated checks

```sh
swiftc -O -parse-as-library YAAM/FT8AudioDecimator.swift Tests/FT8AudioDecimatorRegression.swift -o /tmp/yaam-decimator
/tmp/yaam-decimator
swiftc -O -parse-as-library YAAM/FT8OperatingSupport.swift YAAM/DXCCDatabase.swift YAAM/CountryNameNormalizer.swift YAAM/CountryFlagEngine.swift Tests/FT8OperatingSupportRegression.swift -o /tmp/yaam-operating-check
/tmp/yaam-operating-check
```

Both passed: packet continuity, filter passband/alias rejection, sender parsing,
SV2AOB/Greece, Mount Athos exception, fresh/distinct SWR readings, threshold,
disabled protection, stale/nonfinite telemetry, and occupied/noisy spectrum.

`FT8ExpandedDecodeRegression.swift` was run in a temporary Swift package with
the project's pinned FT8Codec dependency and `FT8StationDecoder.swift`.
Six deterministic noisy trials produced four standard and four expanded
decodes, with zero noise-only decodes. Expanded decoding retained all standard
results without duplicates. This does **not** establish improved sensitivity
or parity with WSJT-X; no real comparative recording was available.

Debug and universal macOS Release builds passed. The installed Release is
ad-hoc signed and its signature was verified.

## Remaining live checks

- IC-7300MK2 TX audio level versus measured ALC, and PTT release on high SWR.
- Long receive session CPU measurements against the same signal/source.
- Live Club Log/DX Cluster freshness and current-band filtering.
- Compact/normal windows in light/dark appearance: macOS screen capture failed
  during verification, so visual acceptance is pending.

SWR protection is opt-in and requires two distinct fresh readings above 2.5
under RF load. TX audio changes apply at the next transmission. Quiet-frequency
suggestions only set an offset on explicit selection and cannot guarantee an
unoccupied channel at a remote receiver. State/province is shown when present
in the station's existing log; unresolved callsign hashes remain unknown.
