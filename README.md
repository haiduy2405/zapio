# Zapio – TV & AC Remote

Universal remote for Android (iOS later): **Wi-Fi** control for smart TVs plus
**infrared** for TVs, air conditioners and fans on phones with an IR blaster.

Author: duyluma

## Stack
- Flutter (Dart) UI + Wi-Fi protocols
- Kotlin bridge `zapio/ir` → Android `ConsumerIrManager` (`MainActivity.kt`)
- IR code DB: `assets/irdb/<Category>.json.gz`, built from flipperdevices/irdb
  (MIT) with `python3 tools/build_irdb.py <checkout>` — see NOTICE.md
- Wi-Fi: Samsung Tizen (WebSocket), LG webOS (SSAP), Roku (ECP); discovery via
  SSDP + /24 sweep

## Build
Every push to `main` runs GitHub Actions: analyze → test → build release APK →
publishes a pre-release `build-N` with the APK attached.

## Milestone P0 – feasibility test (current)
Checklist to run on a real phone (vivo X100s):

| # | Test | Pass when |
|---|------|-----------|
| 1 | IR tab shows "Máy có cổng hồng ngoại" + frequency range | Card is green |
| 2 | TV → Samsung → Dò mã nhanh → POWER | Samsung TV turns on/off |
| 3 | TV → Sony → Dò mã nhanh → POWER | Sony TV turns on/off |
| 4 | Điều hòa → Hisense → try each model's POWER | Hisense AC beeps / turns on |
| 5 | Điều hòa → Midea / Gree → POWER (for the Casper AC) | Casper AC reacts (Casper often reuses OEM protocols) |
| 6 | Wi-Fi → Quét mạng | Samsung TV found |
| 7 | Open TV → allow on TV → Vol +/−, OK, Home | TV reacts; reconnect needs no prompt |

## Roadmap
- **P1 MVP**: LG webOS, Android/Google TV, Roku over Wi-Fi; AC state encoders
  (Gree, Midea, Daikin…); proper code DB (SQLite) + licence vetting; device
  list/home screen; English + Vietnamese UI.
- **P2**: AdMob + Play Billing (Premium).
- **P3**: Play Store closed test (12 testers × 14 days) → production.
- **P4**: Sony Bravia, Fire TV, iOS (Wi-Fi only).
