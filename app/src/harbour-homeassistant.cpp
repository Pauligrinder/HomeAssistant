#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QtQml>

#include "appsettings.h"
#include "hassclient.h"
#include "mdiiconrenderer.h"
#include "sensorcoordinator.h"
#include "widgetcoordinator.h"

int main(int argc, char *argv[])
{
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setOrganizationName(QStringLiteral("org.helmsman"));
    app->setApplicationName(QStringLiteral("harbour-helmsman"));

    AppSettings::migrateLegacyFile();

    qmlRegisterType<HassClient>("harbour.helmsman", 1, 0, "HassClient");
    qmlRegisterType<MdiIconRenderer>("harbour.helmsman", 1, 0, "MdiIconRenderer");
    qmlRegisterUncreatableType<SensorCoordinator>(
                "harbour.helmsman", 1, 0, "SensorCoordinator",
                QStringLiteral("Use HassClient.sensors"));
    qmlRegisterUncreatableType<WidgetCoordinator>(
                "harbour.helmsman", 1, 0, "WidgetCoordinator",
                QStringLiteral("Use HassClient.widget"));

    QQuickView *view = SailfishApp::createView();
    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-homeassistant.qml")));
    view->show();

    return app->exec();
}
