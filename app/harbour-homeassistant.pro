TARGET = harbour-helmsman

CONFIG += sailfishapp
QT += network websockets gui positioning dbus
PKGCONFIG += qt5embedwidget

VERSION = 0.2.19
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/appsettings.cpp \
    src/harbour-homeassistant.cpp \
    src/hassclient.cpp \
    src/hasspushchannel.cpp \
    src/mdiiconrenderer.cpp \
    src/sensorcoordinator.cpp \
    src/widgetcoordinator.cpp

HEADERS += \
    src/appsettings.h \
    src/hassclient.h \
    src/hasspushchannel.h \
    src/mdiiconrenderer.h \
    src/sensorcoordinator.h \
    src/widgetcoordinator.h

RESOURCES += mdi.qrc

DISTFILES += \
    rpm/harbour-homeassistant.spec \
    harbour-helmsman.desktop \
    qml/harbour-homeassistant.qml \
    qml/cover/CoverPage.qml \
    qml/pages/*.qml \
    qml/components/*.qml \
    qml/eventsview/*.qml \
    eventsview/*.qml \
    eventsview/*.json \
    data/mdi/LICENSE.txt

icon86.files = icons/86x86/harbour-helmsman.png
icon86.path = /usr/share/icons/hicolor/86x86/apps
icon108.files = icons/108x108/harbour-helmsman.png
icon108.path = /usr/share/icons/hicolor/108x108/apps
icon128.files = icons/128x128/harbour-helmsman.png
icon128.path = /usr/share/icons/hicolor/128x128/apps
icon172.files = icons/172x172/harbour-helmsman.png
icon172.path = /usr/share/icons/hicolor/172x172/apps

eventsWidgetQml.files = eventsview/HelmsmanEventsWidget.qml
eventsWidgetQml.path = /usr/share/harbour-helmsman/eventsview

eventsWidgetJson.files = eventsview/harbour-helmsman.json
eventsWidgetJson.path = /usr/share/lipstick/eventswidgets

INSTALLS += icon86 icon108 icon128 icon172 eventsWidgetQml eventsWidgetJson
