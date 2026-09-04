# Helmsman for Sailfish OS

A semi-native Silica client for [Home Assistant](https://www.home-assistant.io/).
Built as a Harbour app (Qt 5 / QML + C++) the same way most SFOS apps are,
and tested against Platform SDK target `SailfishOS-5.2.0.15-aarch64`.

This first cut covers connecting to an instance and signing in, including
TOTP two-step verification, dashboards (webview-wrapped by default, with an
optional native Silica renderer), notifications, and
mobile_app sensors (battery, Wi‑Fi, location).

## Layout

```
app/
  harbour-homeassistant.pro
  src/hassclient.{h,cpp}           HA HTTP auth + session
  src/hasswebsocket.{h,cpp}        shared HA websocket
  src/lovelacecoordinator.{h,cpp}  native Lovelace config + states
  src/sensorcoordinator.{h,cpp}    mobile_app sensor webhooks
  src/widgetcoordinator.{h,cpp}    cover + Events View favorites
  qml/pages/                       Connection, login, OTP, home, settings
  qml/dashboard/                   Native Lovelace layouts and cards
  qml/components/                  WifiChecker, BatteryMonitor, LocationReporter
  eventsview/                      Lipstick Events View widget + JSON
  rpm/harbour-homeassistant.spec
```

## What works

1. **Connect** — IP, hostname, or full `http(s)://` URL. Optional HTTPS and
   ignore-certificate-errors for self-signed TLS. Default port is 80 (HTTP) or 443 (HTTPS).
2. **Login** — Home Assistant username/password via `/auth/login_flow`.
3. **OTP** — If the user has MFA enabled, a second page collects the TOTP
   (or other MFA) code, then exchanges the auth code for tokens.
4. **Session** — Refresh token is stored in the sandboxed app settings and
   restored on launch.
5. **Dashboards** — The Home Assistant frontend in a WebView is the default
   home screen. Settings → Dashboard can enable an experimental native Silica
   renderer of Lovelace JSON. Custom cards, energy, and the map still open
   in the web view. The native renderer is off by default.
6. **Sensors** — After mobile_app registration, Helmsman reports battery level/
   state, charger type, Wi‑Fi SSID, OS version, and (while foregrounded) GPS
   location. Native settings can disable individual sensors and select a
   battery-saving, balanced, or accurate location mode. GPS is not kept
   running: Helmsman reuses other apps’ location fixes and only requests its
   own when the last fix is older than a configurable stale time (default 15
   minutes). On the internal URL, GPS stays off; Helmsman can optionally
   report the device as `home` from the connection alone, and repeats that
   report about once a minute so Home Assistant does not time out to away.
   Settings include **Update location now**. Sensors start a few
   seconds after the dashboard has loaded so their webhook calls cannot stall
   the UI.
7. **Cover favorites** — Pick lights, switches, scripts, ACs, and sensors in
   settings to show on the app cover. Cover actions toggle lights, switches, and
   ACs, or run a script (no on/off state). Sensors show their current value and
   have no action, keeping an empty slot so the paging arrow stays put. Arrows
   page when there are more than two.
8. **Events View widget** — A separate favorites list drives a third-party
   Events View widget (`/usr/share/lipstick/eventswidgets/`). Cards use the
   cover tint and watermark. Tap toggles a light, switch, or AC; long-press a
   dimmable light to set brightness, color, or temperature; long-press an AC
   for mode, temperature, fan speed, and vanes; tap a script for **Run** and **Cancel**.
   Vanes offer **Auto**, **Swing**, and **Manual**, with the five angle cells
   only shown while Manual is picked so the card stays short.
   Sensors that already publish a today/tomorrow series (for example Nordpool
   electricity prices in `raw_today`/`today`, `data`, or `prices_by_date`)
   can be added as graph cards, with min/max values marked on the watermark.
   Other sensors show the
   current value with the last 24 hours drawn as the card watermark, like the
   Home Assistant sensor dialog. Home Assistant notifications
   appear as colored cards at the top of the widget
   when it is enabled in Settings → Events view; otherwise they go to the
   system notification list. Cover notification tints can be turned off in
   Helmsman settings. The widget only refreshes while Events View is visible.
   If Helmsman is not running the widget says so; if no favorites are selected
   it offers **Choose favorites**. Drag a preview card on the Events View
   favorites settings page to reorder it, or drop it on the bin to remove it.
   Search on the cover and Events View favorites pages filters every entity
   list. Sensor graphs are drawn in the app and shown as a cached image in
   Events View so the widget does not redraw them every refresh.
   Settings → Events view shows a short description next to
   the Helmsman toggle.
9. **URLs** — Internal and external addresses with Wi‑Fi switching. If you only
   have one address, put it in External URL and leave Internal URL empty.

## Build

Docker Platform SDK flow:

```sh
docker pull coderus/sailfishos-platform-sdk-aarch64
chmod +x build.sh
./build.sh
```

Install on the phone:

```sh
scp app/RPMS/harbour-helmsman-0.2.21-1.aarch64.rpm defaultuser@<phone-ip>:~/
ssh defaultuser@<phone-ip>
devel-su pkcon install-local ~/harbour-helmsman-0.2.20-1.aarch64.rpm
```

Sailjail permissions used: `Internet`, `Notifications`, `Location`.

## Releases (GitHub Actions)

CI builds Sailfish RPMs with the Platform SDK Docker image (`5.2.0.15`)
for `aarch64`, `armv7hl`, and `i486`.

**Automatic release:** bump `VERSION` in `app/harbour-homeassistant.pro`,
merge to `main`. If no GitHub release exists for that version yet, the
Release workflow builds the RPMs and publishes a GitHub Release. Rebuild
tags count too, so a `v0.2.4-2` release stops `main` from republishing
`v0.2.4` as build 1.

**Manual tag:** after bumping `VERSION`, you can also tag explicitly:

```sh
git tag v0.2.0
git push origin v0.2.0
```

Optional RPM release counter in the tag: `v0.2.0-2`.

Pull requests and pushes to `main` also run a CI build (aarch64 only)
without publishing a release.
