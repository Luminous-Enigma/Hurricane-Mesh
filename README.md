# Hurricane Mesh

> Codename. The final name is undecided.

**Hurricane Mesh is not 911.** If you can reach 911, call 911. Messages in this app come
from neighbors. Nobody has checked them, and emergency services do not watch them.

## What it does

Hurricane Mesh is an Android app for a neighborhood board that keeps working when the
power grid and cell towers are down. People post short, structured messages:

| Type | Example |
|---|---|
| **NEED** | "need insulin kept cold", "need a ride to the shelter" |
| **HAVE** | "have generator power for charging", "have water" |
| **HAZARD** | "power line down", "road flooded" |
| **SAFE** | "I'm OK" check-ins for family and neighbors |
| **ASK** | "any news on the bridge?" |

Messages travel two ways:

- **LoRa radios running [Meshtastic](https://meshtastic.org)**, paired over Bluetooth.
  Range is measured in miles, and messages hop from radio to radio.
- **Phone to phone** (Google Nearby Connections). Short range, no radio needed.

The app sorts the traffic into a board, a map, and a family check-in list.

**What it is not:** it is not 911, it is not an official emergency channel, and it is not
a chat app for everyday talk. All posts are **unverified**.

## Status

Pre-alpha. This repository contains only the setup for now: repository rules, workflows,
and the shared theme tokens. No app code exists yet. See `STUBS.md` for what is unfinished
and `DECISIONS.md` for what still needs the owner's decision.

## Building

The Android project arrives in milestone M1. When it does:

- **Requirements:** JDK 17 and the Android SDK (Android Studio works).
- **Debug build:** `./gradlew assembleDebug`
- **Release build:** runs only on GitHub Actions (`release` workflow). The owner starts it
  by hand from `main`. The signing key exists only in GitHub Actions secrets, never in this
  repository. A local `./gradlew bundleRelease` without those secrets does not produce a
  signed build.
- **Checks:** `./gates.sh` runs the repository gates (workflow policy, `.gitignore`, and a
  secret scan if `gitleaks` is installed).

Large files are never committed. The offline map (`.pmtiles`) and any on-device model are
downloaded by the app.

## Repository rules

- Pull request workflows use `pull_request` only, never `pull_request_target`. Pull
  requests from forks never get access to secrets.
- Do not post real personal data, addresses, or photos in issues or pull requests. See
  [SECURITY.md](SECURITY.md).
- Test data is synthetic only.
- Code copied from the owner's private repositories is listed in
  [SHARED_SOURCES.md](SHARED_SOURCES.md).

## Copyright

© November 2026 Luminous Enigma

License: **not yet chosen**. Until a LICENSE file is added, all rights are reserved.
(Pending decision. See `DECISIONS.md`, D-LICENSE.)
