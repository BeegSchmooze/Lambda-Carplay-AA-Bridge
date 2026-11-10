# G70 & Stinger CarPlay / AA Bridge

Repository: Lambda-Carplay-AA-Bridge (formerly G70-Carplay-AA-Bridge; old links redirect here),
named after the Lambda V6 shared by the cars it supports.

Wireless Android Auto and wireless CarPlay, with turn-by-turn from both on the
cluster/HUD, for the **Genesis G70** head unit, and turn-by-turn on the HUD and
cluster for the **Kia Stinger** (see [Kia Stinger](#kia-stinger-turn-by-turn-on-the-hud-and-cluster)), as a reversible
[NEMESIS](https://github.com/xwtk/hmg_nemesis) package. It started from
[HMG Leafia Plus](https://github.com/VysseCodes/HMG-Leafia-Plus), which had no
patch set for this car's firmware, so every patch here was ported to it. Since
v1.1 it is **standalone**: HMG Leafia Plus does not need to be installed.

> Unofficial. Not affiliated with Hyundai, Kia, Genesis, Google, Apple, the
> NEMESIS project or HMG Leafia Plus. You use it at your own risk.

## Status (v1.4)

v1.4 makes the **approach bar on the HUD** empty as you near the turn (it stood still
before) and clears the old app's turns when you **switch nav apps on the iPhone**.
v1.3 brought **wireless CarPlay back by itself** after a drop (engine off and on, or
walking away and coming back), **CarPlay lane guidance** on the cluster and HUD, and the
drawn CarPlay turns on the 260507 firmware. Since v1.2 it is **one package for several
firmwares**. It carries a separate build for
each supported G70 firmware and uses the one made for exactly your head unit's
files (see [Compatibility](#compatibility)):

| Firmware | Status |
|---|---|
| `IKFL.USA.0000.V014.011.251120` | the original build, tested on a car |
| `IKFL.USA.0000.V014.010.250818` | port, tested on a car |
| `IKFL.USA.0000.V015.012.260507` (2026.07 update) | port (v1.2), tested on a car |

What matters is the firmware, not the model year: any head unit whose files match one of
these builds byte for byte can install it.

Speed-camera alerts are no longer part of the bridge: they will come back as a
separate add-on package, so only people who want them install them. v1.1 made
the package standalone (no HMG Leafia Plus needed); v1.0 brought Apple Maps
turn-by-turn and the now-playing track to the cluster and HUD.

| Feature | State |
|---|---|
| Wireless Android Auto | Works |
| Wireless CarPlay (Bluetooth iAP2 bridge, Wi-Fi session, audio, volume) | Works |
| iPhone saved in the car's projection device list / Device Connections | Works (new in v0.95) |
| Android Auto turn-by-turn on the cluster and HUD | Works: turns, exits and forks drawn the way the car's own navigation draws them (arrow at the real angle), with the distance |
| Street name above the arrow on the HUD (Android Auto) | Works for turns, exits and forks; like the car's own navigation, icon steps (straight, merge, U-turn, roundabout) show no name |
| Distance count-down | Smooth: counts down from the car's speed between the phone's updates |
| First instruction from a standstill | Shows the first real turn instead of Google's "head toward …" step |
| Android Auto reconnect after walking away with the car running | Fix included (a stale session for the same phone is ended so it can reconnect); not yet confirmed on the car |
| Car navigation's own turn frames muted while the phone guides | Works; its speed-camera / trap frames still pass |
| Side roads drawn behind the arrow (Android Auto) | **Not yet**: the phone doesn't send them; planned from the car's map data |
| CarPlay turn-by-turn on the cluster and HUD | Works (new in v1.0): Apple Maps turns with the distance. Tested parked and on short routes; rerouting not yet tested on the car |
| CarPlay now playing on the cluster and HUD | Works (new in v1.0): track title and changes |
| CarPlay call state on the cluster | Requested from the iPhone; not yet tested on the car |
| CarPlay lane guidance on the cluster and HUD | New in v1.3: the iPhone's lanes as the car's own lane strip (up to 8 lanes, the lanes to use highlighted); not yet confirmed on the car |
| HUD approach bar (beside the turn distance) | New in v1.4: full until about 1000 ft / 300 m before the turn, then empties to the turn, for Android Auto and CarPlay (both used to send a fixed value). Not yet confirmed on the car |
| Switching nav apps on the iPhone | New in v1.4: the old app's turns are cleared at once and the car's navigation gets the cluster back (it used to wait 90 s) |
| Wireless CarPlay reconnects by itself | New in v1.3. Engine off and on: confirmed on the car. Walking away and coming back: the car looks for the iPhone again every 30 s for 10 minutes; not yet confirmed on the car |
| Speed / red-light camera alerts on the HUD | Moved out of the bridge in v1.2; coming back as a separate add-on |
| Standalone wireless setup (no HMG Leafia Plus) | New in v1.1; tested in the mock head unit on factory files and confirmed on a second G70 |

Joining another Wi-Fi network from the car's settings turns off the hotspot that
wireless Android Auto and CarPlay use; restart the head unit to get it back.

Work on the open items continues; see [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Kia Stinger: turn-by-turn on the HUD and cluster

A separate package for the Kia Stinger (2022, firmware `CKPE23.USA`): the phone's turn-by-turn on
the head-up display and cluster with **wired** CarPlay and Android Auto (or a wireless dongle),
the same as the G70 bridge's turn-by-turn part. It does not add wireless CarPlay / Android Auto.
Release asset: `Stinger-TurnByTurn-v1.1.zip` (v1.1 adds the moving HUD approach bar). The package id is
`stinger.tbt`; v1.0 and the test builds were `g70.tbt` (a leftover from the G70), so uninstall
that first: v1.1 refuses while it is installed.

| Firmware | Status |
|---|---|
| `CKPE23.USA.0000.V015.012.260507` | Reported working on a Stinger by its owner |
| `CKPE23.USA.0000.V014.011.251120` | Built the same way from the same code; not yet run on a Stinger |

Like the bridge, it is one package with a build per firmware and picks the one whose stock files
the head unit has; on anything else it refuses and changes nothing. The Stinger's apps are the
G70's code: on 251120 identical to the G70's 250818 build, on 260507 to the G70's 260507 build
(one navigation class differs, which is not patched), so the patches are those in
`src/patches/250818` and `src/patches/260507` (turn-by-turn classes only) plus update 24's DiPO
hook (`src/hooks/hooks24_dipo.py`: switching nav apps on the iPhone clears the old app's turns)
and update 25's approach bar (`src/hooks/hooks25_bar.py`, `src/java/LeafiaBar.java.in`).
Install: unzip onto the root of a USB drive, plug it in with the head unit on and confirm; the head
unit restarts. Uninstall: NEMESIS Manager → Packages → `stinger.tbt`. Not together with the G70 bridge
(`g70.carplay.bt`), which the package refuses to install alongside.

## Requirements

- A head unit whose stock files match one of the package's firmware builds
  (the table above). Other firmwares and closely related cars install only if
  every file the package changes is byte-identical to one of them. Run the
  compatibility check first (below).
- NEMESIS 1.15 or newer on the head unit.
- A FAT32 USB drive.

HMG Leafia Plus is **not** needed. If its `wireless.carplay.aa` is already
installed, the bridge leaves the settings it made alone and works alongside it.
To keep things simple, uninstall it first (NEMESIS Manager → Packages) and
restart the head unit; the bridge then turns everything on itself.

## Compatibility

`G70-Compat-Check.zip` (in the release, source in `tools/compat/`) is a
read-only NEMESIS script: unzip it onto the USB drive, plug it in, and it writes
`G70COMPAT-<n>/report.txt`. It checks your files against every firmware build in
the package and reports the one that matches (or the closest), one line per file
(MATCH or DIFFERENT), whether the wireless features are already on, and a result:

- **COMPATIBLE**: the package will install on your car, and the report names
  the firmware build it will use.
- **NOT COMPATIBLE YET**: the report lists which files differ and which feature
  each one belongs to. A port for your firmware is possible: open an issue with
  the report, and send a run of the probe (`tools/probe`) privately. A port adds
  one more firmware build to the same package.

The installer does the same check itself and refuses before changing anything
if no firmware build matches, so trying an install on an unmatched car is safe.
It just won't install. Every change is still built from the car's own stock
files and must match the tested build's checksum.

## Install

1. Download the release zip (`G70-Bridge-v1.4.zip`) and unzip it onto the root
   of the USB drive. You should have `NEMESIS.data` and
   `packages/g70.carplay.bt.zip` at the top level. Do not unzip
   `g70.carplay.bt.zip` itself.
2. Plug the drive into the car with the head unit on.
3. If an earlier build of this package is installed, NEMESIS first offers
   **uninstall**: accept it. Then accept **install**. (v1.4 can also install
   straight over v1.3, update 24, v1.2, v1.1 and the earlier builds for the
   other two firmwares.)
4. The head unit restarts. The first start after an install can take a few
   minutes, and Bluetooth may show "initializing" for a while; that is the apps
   being optimised once.

The bare packages `g70.carplay.bt-1.4.zip` and `stinger.tbt-1.1.zip` on the releases are
the same packages for the NEMESIS Package Store and `nemesis install`. They use the
store descriptor format (1.1), with compatibility set to the supported firmwares.

## Uninstall

NEMESIS Manager → Packages → `g70.carplay.bt` → Uninstall, then restart the head
unit. Every changed file, property and library goes back to stock byte for byte,
including the wireless settings, if the bridge was the one that turned them on.

## Camera alerts

Speed / red-light camera alerts were part of v1.1. From v1.2 they are not in the
bridge: they will be a separate add-on package, so the bridge itself stays the
same for everyone. Installing v1.2 over v1.1 removes them; a camera list already
on the head unit is simply no longer read.

## How it is built

Nothing modified from Hyundai, Google or Apple is shipped. The package carries
only patch deltas (`package/firmware/<firmware>/*.lpd`, one set per supported
firmware). During install, Leafia's `lpatch`
rebuilds each app on the head unit from that unit's own stock files: it refuses
unless the stock `.odex` is exactly the expected original, and the rebuilt APK
must match the tested build's checksum. Native libraries are patched the same
way. The changes themselves are in [`src/patches/<firmware>/`](src/patches) as
smali diffs against each firmware's stock apps.

| Part | Change |
|---|---|
| `HKMC_DiPO` (CarPlay) | Bluetooth→iAP2 bridge, starts the CarPlay engine for wireless, audio source and focus, iAP2 notifications let through for wireless sessions, iPhone in the device list, iAP2 handover into the CarPlay session, now playing and call state requested over wireless, drawn turns, lane guidance, the iPhone reported to the car's Bluetooth manager as its wireless CarPlay phone (so it reconnects) and a reconnect retry after a dropped session; stock bugs fixed: iAP send length, maneuver index |
| `Iap2ServerApp` | Starts/ends the iAP2 session on the Bluetooth transport; advertises route guidance |
| `HKMC_GPM` (Android Auto) | Stuck-session, USB-drive and same-phone reconnect fixes; turn-by-turn sent straight to the cluster (port of HMG-API's AaTurns) with drawn turns, street name, lanes, smooth count-down |
| `HKMC_Navi_ExSL` (car navigation) | Skips its turn frames while the phone guides; logs what it sends to the cluster (diagnostics) |
| Wireless settings | Wireless CarPlay / Android Auto and Wi-Fi feature files added, `featurexml.cfg`'s removal of them and of the hotspot commented out, `persist.ium.support=carplay`; each left alone when already in place |
| `libautoreceiver_infobank.so` | Leafia/NEMESIS `projection.tbt` navigation bridge, ported to this car's library build |
| `libCarPlayCore.so` | Leafia recipe: accept Wi-Fi CarPlay sessions |
| Leafia audio part | Unchanged (`package/comp/4_audio`) |

## Repository layout

```
package/          the NEMESIS package source (zip its contents to make g70.carplay.bt.zip);
                  package/firmware/<firmware>/ holds each firmware's checksums and deltas
stinger/package/  the Kia Stinger turn-by-turn package source (stinger.tbt, formerly g70.tbt; firmware/<firmware>/ sets)
src/patches/      smali diffs per firmware: stock app -> this build (new classes included)
src/java/         Java source of the bridge classes compiled into the apps
src/hooks/        the scripts that insert the calls into the apps' smali
tools/aa-lib-port library port scripts (see docs/TECHNICAL.md)
tools/port/       porting to another firmware: deodex, 3-way merge, rename and field
                  checks, builds, and the multi-firmware package and its mock tests
tools/checks/     reference/register checkers and the mock head-unit tests
tools/probe/      read-only diagnostic probe (NEMESIS execute script)
tools/compat/     read-only compatibility check (generated from the installer's checksums)
docs/             technical notes
```

## Diagnostics

`tools/probe` is a read-only NEMESIS script that writes logs to the USB drive.
Its output contains your phone names, Bluetooth addresses and vehicle data:
**don't post it publicly**.

By default it collects logs only, gzipped (a few MB). A file named
`G70PROBE-FULL` on the drive root makes it also copy the stock apps and
libraries a port needs (about 70 MB). Its first run after a head-unit restart
starts a background logger that records until the next restart. To capture a
test, run the probe once before it and again afterwards.

## Licence and credits

GPL-3.0 (see `LICENSE`), with parts under AGPL-3.0; see [NOTICE.md](NOTICE.md).
Built on HMG Leafia Plus by VysseCodes and contributors, and on NEMESIS and
its community packages by xwtk and contributors.
