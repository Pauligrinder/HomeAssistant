Name:       harbour-helmsman
Summary:    Native Home Assistant client
Version:    0.1.9
Release:    1
License:    ASL 2.0
URL:        https://github.com
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtcore
Requires:   qt5-qtdeclarative
Requires:   qt5-qtnetwork
Requires:   qt5-qtwebsockets
Requires:   sailfish-components-webview-qt5
Requires:   nemo-qml-plugin-dbus-qt5
Requires:   nemo-qml-plugin-notifications-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5WebSockets)
BuildRequires:  pkgconfig(qt5embedwidget)
BuildRequires:  desktop-file-utils

%description
Sailfish-native Home Assistant client. Connect to a Home Assistant instance
by IP or hostname, then log in with username/password and optional TOTP
two-step verification. Receives companion notifications over a WebSocket
push channel after mobile_app registration.

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
