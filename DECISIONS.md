# Decisions

Product decisions belong to the owner (BUILD_PROTOCOL D2). An item marked **OPEN** has not
been decided, and code that depends on it does not get written.

| ID | Decision | Status | Notes |
|---|---|---|---|
| D-LICENSE | License for this repository | **OPEN. Blocks M3 (radio).** | `meshtastic/protobufs` is GPL-3.0 (checked 2026-11-08, `LICENSE` file on `master`: GNU GPL v3, 29 June 2007, 674 lines). No LICENSE file is added until the owner decides. No code is generated from the Meshtastic protobufs until then. |
| D-NAME | Final app name | OPEN | "Hurricane Mesh" is a codename. |
| D-A4-SHARED | `/shared` copies are an accepted exception to gate A4 | **Decided by the owner, 2026-11-08** (Going Public checklist, item 6) | See `SHARED_SOURCES.md`. |
| D-PUBLIC | Repository visibility | **Decided: private until the Going Public checklist passes. The owner switches it to public.** | |
| D-TWIN | Plain-text twin on by default | OPEN | Doubles airtime. |
| D-RATE | Rate limit N per X minutes | OPEN | Suggested start: 6 per 10 minutes. |
| D-MAPHOST | Where to host the offline map, and what it costs | OPEN | A 100–500 MB file; bandwidth cost grows with downloads. |
| D-PRODUCTS | Name specific radio products on "Get a radio" | OPEN | |
| D-HISTORY | Local history retention | OPEN | Plan suggests 7 days. |
| D-PRICE | Price | OPEN | |
