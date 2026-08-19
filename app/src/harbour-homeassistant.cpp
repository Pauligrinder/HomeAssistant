#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QtQml>

#include "hassclient.h"

int main(int argc, char *argv[])
{
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setOrganizationName(QStringLiteral("org.homeassistant"));
    app->setApplicationName(QStringLiteral("harbour-homeassistant"));

    QQuickView *view = SailfishApp::createView();

    qmlRegisterType<HassClient>("harbour.homeassistant", 1, 0, "HassClient");

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-homeassistant.qml")));
    view->show();

    return app->exec();
}
