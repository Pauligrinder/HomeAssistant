TARGET = harbour-helmsman

CONFIG += sailfishapp
QT += network websockets gui positioning dbus qml
LIBS += -ldl

VERSION = 0.4.8
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/appsettings.cpp \
    src/harbour-homeassistant.cpp \
    src/helmsmani18n.cpp \
    src/helmsmanlog.cpp \
    src/hasscamerastream.cpp \
    src/hassclient.cpp \
    src/hasspushchannel.cpp \
    src/hasswebsocket.cpp \
    src/lovelacecoordinator.cpp \
    src/mdiiconrenderer.cpp \
    src/sensorcoordinator.cpp \
    src/widgetcoordinator.cpp

HEADERS += \
    src/appsettings.h \
    src/helmsmani18n.h \
    src/helmsmanlog.h \
    src/hasscamerastream.h \
    src/hassclient.h \
    src/hasspushchannel.h \
    src/hasswebsocket.h \
    src/lovelacecoordinator.h \
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
    qml/dashboard/*.qml \
    qml/dashboard/cards/*.qml \
    qml/dashboard/features/*.qml \
    qml/eventsview/*.qml \
    eventsview/*.qml \
    eventsview/*.json \
    eventsview/*.ts \
    data/mdi/LICENSE.txt \
    sailjail/harbour-helmsman.profile \
    translations/*.json \
    translations/README.md \
    eventsview/i18n.js

# i18n (see docs/translations.md): i18n.translation("key") looks up
# translations/<lang>.json. English is en.json. Installed beside qml/.
transjson.files = $$files(translations/*.json)
transjson.path = /usr/share/$${TARGET}/translations

icon86.files = icons/86x86/harbour-helmsman.png
icon86.path = /usr/share/icons/hicolor/86x86/apps
icon108.files = icons/108x108/harbour-helmsman.png
icon108.path = /usr/share/icons/hicolor/108x108/apps
icon128.files = icons/128x128/harbour-helmsman.png
icon128.path = /usr/share/icons/hicolor/128x128/apps
icon172.files = icons/172x172/harbour-helmsman.png
icon172.path = /usr/share/icons/hicolor/172x172/apps

eventsWidgetQml.files = eventsview/HelmsmanEventsWidget.qml eventsview/i18n.js
eventsWidgetQml.path = /usr/share/harbour-helmsman/eventsview

eventsWidgetJson.files = eventsview/harbour-helmsman.json
eventsWidgetJson.path = /usr/share/lipstick/eventswidgets

# Settings → Events view shows model.description only when qtTrId()
# resolves description_id. The id must differ from the visible sentence,
# and the catalog is /usr/share/translations/harbour-helmsman_eng_en.qm.
EVENT_WIDGET_TS = $$PWD/eventsview/harbour-helmsman.ts
EVENT_WIDGET_QM = $$OUT_PWD/harbour-helmsman_eng_en.qm
eventswidget_qm.target = $$EVENT_WIDGET_QM
eventswidget_qm.depends = $$EVENT_WIDGET_TS
eventswidget_qm.commands = $$[QT_INSTALL_BINS]/lrelease -idbased $$EVENT_WIDGET_TS -qm $$EVENT_WIDGET_QM
QMAKE_EXTRA_TARGETS += eventswidget_qm
PRE_TARGETDEPS += $$EVENT_WIDGET_QM

eventsWidgetQm.files = $$EVENT_WIDGET_QM
eventsWidgetQm.path = /usr/share/translations
eventsWidgetQm.CONFIG += no_check_exist

sailjailProfile.files = sailjail/harbour-helmsman.profile
sailjailProfile.path = /etc/sailjail/permissions

INSTALLS += icon86 icon108 icon128 icon172 eventsWidgetQml eventsWidgetJson eventsWidgetQm sailjailProfile transjson
