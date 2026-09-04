Name:       harbour-helmsman
Summary:    Semi-native Home Assistant client
Version:    0.2.23
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
Semi-native Home Assistant client. Connect to a Home Assistant instance
by IP or hostname, then log in with username/password and optional TOTP
two-step verification. Receives companion notifications over a WebSocket
push channel after mobile_app registration, and reports battery, Wi-Fi, and
location sensors via the mobile_app webhook. Selected lights, switches,
scripts, and ACs can be shown on the app cover and as a third-party
Events View widget.

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
%{_datadir}/lipstick/eventswidgets/%{name}.json

%changelog
* Fri Sep 04 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.23-1
- Fix the native dashboard: switching dashboards and view tabs now works,
  cards receive their config before they load so images and content appear,
  and entity state changes reach the UI live instead of freezing at the
  first value. Entities-card rows for toggleable entities show a switch.

* Fri Sep 04 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.22-1
- Load native Lovelace dashboards that have no saved config (auto-gen
  Overview) instead of showing "No config found." Selecting a listed
  dashboard now requests that dashboard's url_path.

* Fri Sep 04 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.21-1
- Optional native Lovelace dashboard renderer (Settings → Dashboard), off
  by default. The Home Assistant web UI remains the home screen until it
  is turned on. Custom cards, energy, and the map still open in the web
  view.

* Thu Sep 03 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.20-1
- Keep each stale location acquisition active for up to 45 seconds so a
  cached or coarse first result can be replaced by a current GPS fix.
- Preserve the provider timestamp when scheduling the next acquisition.

* Thu Sep 03 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.19-1
- Ping the Home Assistant notification websocket every two minutes and
  reconnect if pong is missing, so a half-open socket no longer reports
  Client is not connected.

* Wed Sep 02 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.18-1
- Recognize Nordpool-style series on data and prices_by_date attributes,
  not only raw_today/today/prices, and ignore timestamp sensor states
  when showing the current graph value.
- Draw min and max values on Events View graph and history watermarks.

* Wed Sep 02 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.16-1
- Move Events View reorder and remove (drag onto the bin) from the
  widget into Events View favorites settings.
- Draw Events View graph and sensor history watermarks in the app and
  show them as cached images, so the widget no longer freezes or flashes
  while painting Canvas graphs.
- Add search on cover and Events View favorites that filters every
  entity list, and keep long sensor lists collapsed until you type.

* Tue Sep 01 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.15-1
- Keep reporting home on the internal connection so Home Assistant does
  not time the device tracker out to away.
- Add Update location now in settings.
- Events View AC long-press now sets target temperature, fan Auto, and
  vane Auto/Swing when the climate entity supports them.
- When the Helmsman Events View widget is enabled, Home Assistant
  notifications appear as colored cards there instead of in the system
  notification list.
- Add a setting to disable notification tints on the app cover.
- Events View cards can be reordered by dragging, or dropped on a bin to
  remove them.
- Events View can show graphs of sensors that already publish a
  today/tomorrow series, such as Nordpool electricity prices.
- Events View can also show any sensor: the current value, with the last
  24 hours as a watermark graph on the card.

* Mon Aug 31 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.14-1
- Tell Events View when Helmsman is not running, and offer Choose
  favorites when nothing is selected.
- Add a Settings → Events view description for the Helmsman widget.
- Cover and Events View favorites can include switches, scripts, and ACs.
  Scripts have no on/off state: the cover runs them; Events View shows
  Run and Cancel. ACs toggle on the cover; Events View also offers mode,
  fan speed, and vane positions.
- Events View long-press on a light also offers color temperature and
  common-color swatches when the bulb supports them.

* Mon Aug 31 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.13-1
- Fix launch showing a blank white screen: LocationReporter bound
  PositionSource.updateTimeout, which is not in the QtPositioning 5.2
  import, so the main window failed to load.
- Instantiate GeoClue D-Bus listeners only after location reporting is
  enabled, so GPS activation cannot block the first frame.

* Mon Aug 31 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.12-1
- Add native switches to disable individual mobile_app sensors from settings.
- Add location settings: update mode, optional home-on-internal, and a stale
  timeout (default 15 minutes) before Helmsman requests GPS itself.
- Stop continuous GPS: reuse other apps' GeoClue fixes, and never fetch GPS
  on an internal connection.

* Sun Aug 30 2026 Pauli Kettunen <pauli.kettunen@sarkain.fi> - 0.2.11-1
- Add a third-party Events View widget for selected lights, registered via
  lipstick eventswidgets JSON without overriding system files.
- Keep cover and Events View favorites as separate lists; existing cover
  favorites stay on the cover, Events View starts empty.
- Event cards use the cover tint, rounded corners, and MDI watermarks.
  Tap toggles a light; long-press on dimmable lights opens brightness.
- Refresh the widget only while the Events View is visible.

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
