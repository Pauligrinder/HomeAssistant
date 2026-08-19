TARGET = harbour-homeassistant

CONFIG += sailfishapp
QT += network

VERSION = 0.1.0
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/harbour-homeassistant.cpp \
    src/hassclient.cpp

HEADERS += \
    src/hassclient.h

DISTFILES += \
    rpm/harbour-homeassistant.spec \
    harbour-homeassistant.desktop \
    qml/harbour-homeassistant.qml \
    qml/cover/CoverPage.qml \
    qml/pages/*.qml

icon86.files = icons/86x86/harbour-homeassistant.png
icon86.path = /usr/share/icons/hicolor/86x86/apps
icon108.files = icons/108x108/harbour-homeassistant.png
icon108.path = /usr/share/icons/hicolor/108x108/apps
icon128.files = icons/128x128/harbour-homeassistant.png
icon128.path = /usr/share/icons/hicolor/128x128/apps
icon172.files = icons/172x172/harbour-homeassistant.png
icon172.path = /usr/share/icons/hicolor/172x172/apps

INSTALLS += icon86 icon108 icon128 icon172
