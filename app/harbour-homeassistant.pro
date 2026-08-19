TARGET = harbour-helmsman

CONFIG += sailfishapp
QT += network
PKGCONFIG += qt5embedwidget

VERSION = 0.1.3
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/harbour-homeassistant.cpp \
    src/hassclient.cpp

HEADERS += \
    src/hassclient.h

DISTFILES += \
    rpm/harbour-homeassistant.spec \
    harbour-helmsman.desktop \
    qml/harbour-homeassistant.qml \
    qml/cover/CoverPage.qml \
    qml/pages/*.qml
