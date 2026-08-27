# Helmsman for Sailfish OS

A native Silica client for [Home Assistant](https://www.home-assistant.io/).
Built as a Harbour app (Qt 5 / QML + C++) the same way most SFOS apps are,
and tested against Platform SDK target `SailfishOS-5.2.0.15-aarch64`.

This first cut covers connecting to an instance and signing in, including
TOTP two-step verification, dashboards (webview-wrapped), notifications, and
mobile_app sensors (battery, Wi‑Fi, location).

## Layout

```
app/
  harbour-homeassistant.pro
  src/hassclient.{h,cpp}           HA HTTP auth + session
  src/sensorcoordinator.{h,cpp}    mobile_app sensor webhooks
  qml/pages/                       Connection, login, OTP, home, settings
  qml/components/                  WifiChecker, BatteryMonitor, LocationReporter
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
5. **Sensors** — After mobile_app registration, Helmsman reports battery level/
   state, charger type, Wi‑Fi SSID, OS version, and (while foregrounded) GPS
   location. On the internal URL it can mark the device as `home`. Enable or
   disable each entity under HA → Settings → Devices → Helmsman.
6. **Cover favorites** — Pick lights in settings to show on the app cover.
   Cover actions toggle them (and page when there are more than two).
7. **URLs** — Internal and external addresses with Wi‑Fi switching. If you only
   have one address, put it in External URL and leave Internal URL empty. If
   the internal address does not respond, Helmsman falls back to the external
   URL. A failed restore shows an error and a Settings button instead of hanging.

## Build

Docker Platform SDK flow:

```sh
docker pull coderus/sailfishos-platform-sdk-aarch64
chmod +x build.sh
./build.sh
```

Install on the phone:

```sh
scp app/RPMS/harbour-helmsman-0.2.7-1.aarch64.rpm defaultuser@<phone-ip>:~/
ssh defaultuser@<phone-ip>
devel-su pkcon install-local ~/harbour-helmsman-0.2.7-1.aarch64.rpm
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
