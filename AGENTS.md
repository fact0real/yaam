# YAAM development context

For work in this repository, use the local project skills in `.codex/skills/` when present. They are intentionally Git-ignored. Read only the skill relevant to the request:

- `yaam-feature`: architecture, navigation, feature changes, and verification.
- `yaam-visual`: SwiftUI layout, graphics, maps, assets, and visual review.
- `yaam-logbook`: ADIF, QSO identity, SQLite, profiles, and export.
- `yaam-connectivity`: radios, digital modes, network services, sync, and credentials.

For cross-cutting changes, read `yaam-feature` first and then the relevant specialist skill. If the local skills are absent, inspect the current source before relying on `DEVELOPER_DOCUMENTATION.md`; some details in that guide are older than the project settings.
