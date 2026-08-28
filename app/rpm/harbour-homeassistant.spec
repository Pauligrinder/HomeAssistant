Name:       harbour-helmsman
Summary:    Native Home Assistant client
Version:    0.2.10
Release:    1
License:    ASL 2.0
URL:        https://github.com
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtcore
Requires:   qt5-qtdeclarative
Requires:   qt5-qtnetwork
Requires:   qt5-qtwebsockets
Requires:   qt5-qtpositioning
Requires:   qt5-qtdbus
Requires:   sailfish-components-webview-qt5
Requires:   nemo-qml-plugin-dbus-qt5
Requires:   nemo-qml-plugin-notifications-qt5
Requires:   nemo-qml-plugin-contextkit-qt5
Requires:   nemo-qml-plugin-configuration-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5WebSockets)
BuildRequires:  pkgconfig(Qt5Positioning)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  pkgconfig(qt5embedwidget)
BuildRequires:  desktop-file-utils

%description
Sailfish-native Home Assistant client. Connect to a Home Assistant instance
by IP or hostname, then log in with username/password and optional TOTP
two-step verification. Receives companion notifications over a WebSocket
push channel after mobile_app registration, and reports battery, Wi-Fi, and
location sensors via the mobile_app webhook. Selected lights can be shown
on the app cover, with paging arrows when they do not all fit.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
%qmake5_install

desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
  %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Sat Aug 29 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.10-1
- Fix cover favorites freezing the app the same way sensors did: the cover
  poller no longer fetches states from inside the login reply handler or
  immediately on an internal/external switch.

* Fri Aug 28 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.9-1
- Fix the app freezing on launch and on internal/external switches: mobile_app
  sensors now start after the dashboard has loaded, and their first webhook
  calls are spaced out instead of all firing at once.
- Delay GPS start until sensors are running, so Geoclue cannot block the UI.
- Store settings inside the Sailjail-visible config directory so sensor and
  connection preferences survive launches from the app grid.
- Revert the 0.2.8 endpoint changes (request timeouts, internal-to-external
  fallback, splash error screen) that were chasing the wrong root cause.

* Thu Aug 27 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.8-1
- Treat Wi-Fi as connected only when it is ConnMan's default route (online).
- If the internal URL times out, fall back to the external address.
- Show a connection-failed error with Settings on the splash instead of hanging.
- Report Wi-Fi as null in Home Assistant when it is not connected.

* Thu Aug 27 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.7-1
- Fix external connections freezing the app after sign-in (cover poller
  no longer downloads every Home Assistant state on the UI thread).
- Load the dashboard via /lovelace and then switch to the default panel,
  so Nabu Casa no longer gets stuck on a root-URL auth bounce.

* Thu Aug 27 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.6-1
- Show selected lights on the app cover, with paging when there are many.
- Leave Internal URL empty when there is only one address; skip switching.
- Open Home Assistant's default dashboard; Companion app opens Helmsman settings.
- Refresh access tokens before they expire so cover and push stay authenticated.

* Wed Aug 26 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.5-1
- Report battery, Wi-Fi, OS version, and location via the mobile_app webhook.
- Mark the device as home when using the internal URL (configurable).
- Improve location seeking with Wi-Fi/GPS hybrid fixes and ConnMan GPS power.

* Mon Aug 24 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.4-2
- Switch to the external URL on mobile data instead of staying on the LAN address.
- Renew the access token before it expires so the push channel stops causing
  invalid-authentication warnings in Home Assistant.

* Mon Aug 24 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.4-1
- Keep the live dashboard on resume instead of showing the loading overlay.

* Fri Aug 21 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.2-1
- Internal/external URL configuration with WiFi-based endpoint selection.
- Theme-aware dashboard loading overlay; larger cover watermarks.

* Thu Aug 20 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.0-1
- Fix app cover when notifications include tag or group data.

* Thu Aug 20 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.1.9-1
- Register as mobile_app and receive notifications over WebSocket.

* Wed Aug 19 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.1.3-1
- Rename app/package to Helmsman (harbour-helmsman).

* Wed Aug 19 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.1.2-1
- Launch directly on connection screen; restore session in background.

* Wed Aug 19 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.1.1-1
- Fix startup routing to connection/login screens.
- Embed Lovelace dashboard via WebView with token handoff.

* Wed Aug 19 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.1.0-1
- Initial packaging: instance connection and login with OTP.
