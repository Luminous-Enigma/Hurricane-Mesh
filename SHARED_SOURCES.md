# Shared sources

The owner keeps some code and design values in private repositories. This repository
will become public, so it cannot depend on them. The pieces this app needs are **copied**
into `/shared`, and every copy is listed here.

**If the owner later makes a source module public, delete the copy and depend on the
module instead.** Then remove its row here and its A4 exception.

## Copied pieces

| # | Piece | Copied to | Source repository | Source path | Source commit | Copied on | How |
|---|---|---|---|---|---|---|---|
| 1 | Soul Mark colour engine (WCAG measuring, seed → theme) | `shared/theme-tokens/soulMark.js` | `Luminous-Enigma/twentyseven` (private, "27 app" / Wisdom Collections) | `mobile/src/soulMark.js` | `a6b4b05be4cdf075856628a585ea99ebe2265479` (2026-10-26) | 2026-11-08 | Byte-for-byte copy. sha256 `3f85c122cb70044752be834fc887eecb4908fa3962fea567eb60cc25d4644aa6` |
| 2 | Theme tokens for the four Hurricane Mesh themes: Light (`daylight`), Night (`night`), Neon (`neon-deep`), Soul Mark (`soulmark`, starter seeds) | `shared/theme-tokens/hurricane-mesh-themes.json` | `Luminous-Enigma/twentyseven` | `mobile/src/theme.jsx` (`THEMES`), plus `composeSoulMark(SOUL_MARK_STARTER)` from `soulMark.js` | `a6b4b05be4cdf075856628a585ea99ebe2265479` (source `theme.jsx` sha256 `c046a9eae6deb773cae09985adf76c277e1653e6bb8ff11fc556ba5ba5395fcf`) | 2026-11-08 | Values extracted by script, unchanged: `node shared/theme-tokens/extract_themes.mjs <twentyseven>/mobile/src out.json`. Other 27-app themes (Supercar, Outer Space, Earth, Petal, Confection) are left out. |
| 3 | Extraction script for row 2 | `shared/theme-tokens/extract_themes.mjs` | Written for this repo | n/a | n/a | 2026-11-08 | Original (not a copy). Listed so the provenance of row 2 can be reproduced. |

### Theme name mapping

The plan names four themes. The 27 app uses different ids:

| Hurricane Mesh | 27 app id | 27 app label |
|---|---|---|
| Light | `daylight` | Type 7 — Daylight |
| Night (Dark) | `night` | Type 8 — Night |
| Neon | `neon-deep` | Type 1 — Neon Deep |
| Soul Mark | `soulmark` | Type 9 — Soul Mark |

`twentyseven/mobile/src/themes.json` also exists. It is the older spec file: it has no
Soul Mark entry and fewer keys per theme. `theme.jsx` is what the 27 app actually runs, so
the values here come from `theme.jsx`. For these four themes the shared keys in both files
agree.

## Not copied (yet)

| Piece | Why not |
|---|---|
| Shared Kotlin theme module (Drive Right / Letter Explainer) | Not found. `Letter-Explainer` is an empty repository; `Drive-Right` was not checked in this pass. The Kotlin `ThemeTokens` port happens in M1 from the values above. |
| Navy & Gold PDF layout | Letter Explainer only. Hurricane Mesh does not use it. |
| Agent kit | Does not exist yet (`Luminous-Enigma/Agent-Ready-Standard` is an empty repository). `AGENT_READY_PLAN.md` was not found. |

## Gate A4 (duplication): documented exception

`BUILD_PROTOCOL.md` gate A4 fails on copy-paste that replaces reuse. Everything under
`/shared` is a **deliberate copy**, so it is an accepted exception, for this reason only:
the source repositories are private and this one will be public, so depending on them is
impossible.

Rules for the exception:

1. A4 skips `/shared` (add `shared` to the duplication gate's skip list when it is ported).
2. Nothing outside `/shared` may duplicate code inside `/shared`. App code **imports** the
   shared copy; it never copies it a second time. A4 still checks this.
3. Files in `/shared` are not edited by hand. To update one, copy it again from the source
   and update this table (commit and date).
4. The exception ends for a piece when its source becomes public (see the top of this file).
