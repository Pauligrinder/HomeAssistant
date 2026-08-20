TARGET = harbour-helmsman

CONFIG += sailfishapp
QT += network websockets gui
PKGCONFIG += qt5embedwidget

VERSION = 0.2.0
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/harbour-homeassistant.cpp \
    src/hassclient.cpp \
    src/hasspushchannel.cpp \
    src/mdiiconrenderer.cpp

HEADERS += \
    src/hassclient.h \
    src/hasspushchannel.h \
    src/mdiiconrenderer.h

RESOURCES += mdi.qrc

DISTFILES += \
    rpm/harbour-homeassistant.spec \
    harbour-helmsman.desktop \
    qml/harbour-homeassistant.qml \
    qml/cover/CoverPage.qml \
    qml/pages/*.qml \
    qml/components/*.qml \
    data/mdi/LICENSE.txt

icon86.files = icons/86x86/harbour-helmsman.png
icon86.path = /usr/share/icons/hicolor/86x86/apps
icon108.files = icons/108x108/harbour-helmsman.png
icon108.path = /usr/share/icons/hicolor/108x108/apps
icon128.files = icons/128x128/harbour-helmsman.png
icon128.path = /usr/share/icons/hicolor/128x128/apps
icon172.files = icons/172x172/harbour-helmsman.png
icon172.path = /usr/share/icons/hicolor/172x172/apps

INSTALLS += icon86 icon108 icon128 icon172
