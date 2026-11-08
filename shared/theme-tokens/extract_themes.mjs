// Extract the four Hurricane Mesh themes from twentyseven's theme.jsx, values unchanged.
import fs from "node:fs";
const [, , srcDir, out] = process.argv;
const sm = await import(srcDir + "/soulMark.js");
const src = fs.readFileSync(srcDir + "/theme.jsx", "utf8");
const start = src.indexOf("export const THEMES = {");
const end = src.indexOf("\n};\n", start);
const body = src.slice(start + "export const THEMES = ".length, end + 2);
const THEMES = new Function("composeSoulMark", "SOUL_MARK_STARTER", "return (" + body + ");")(sm.composeSoulMark, sm.SOUL_MARK_STARTER);
const map = { light: "daylight", night: "night", neon: "neon-deep", soulmark: "soulmark" };
const res = { _source: "Luminous-Enigma/twentyseven mobile/src/theme.jsx (THEMES) + soulMark.js composeSoulMark(SOUL_MARK_STARTER)", themes: {} };
for (const [k, v] of Object.entries(map)) res.themes[k] = { sourceId: v, ...THEMES[v] };
res.soulMarkStarterSeeds = sm.SOUL_MARK_STARTER;
fs.writeFileSync(out, JSON.stringify(res, null, 2) + "\n");
console.log(Object.keys(res.themes).map(k => k + "=" + res.themes[k].label).join(", "));
