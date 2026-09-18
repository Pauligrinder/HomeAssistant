#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QtQml>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>

#include "appsettings.h"
#include "helmsmanlog.h"
#include "hasscamerastream.h"
#include "hassclient.h"
#include "lovelacecoordinator.h"
#include "mdiiconrenderer.h"
#include "sensorcoordinator.h"
#include "widgetcoordinator.h"

int main(int argc, char *argv[])
{
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setOrganizationName(QStringLiteral("org.helmsman"));
    app->setApplicationName(QStringLiteral("harbour-helmsman"));

    // ConnMan's system proxy lookup blocks the GUI for a long time when
    // Wi-Fi vanishes. Helmsman never needs an HTTP proxy to reach HA.
    QNetworkProxyFactory::setUseSystemConfiguration(false);
    QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);

    HelmsmanLog::install();
    AppSettings::migrateLegacyFile();
    // Prepare exactly one web engine before any QML import. Gecko stacks
    // share libxul.so; Atlantic is WPE WebKit. Mixing them in-process crashes.
    HassClient::preloadWebViewEmbed();

    qmlRegisterType<HassClient>("harbour.helmsman", 1, 0, "HassClient");
    qmlRegisterType<MdiIconRenderer>("harbour.helmsman", 1, 0, "MdiIconRenderer");
    qmlRegisterUncreatableType<SensorCoordinator>(
                "harbour.helmsman", 1, 0, "SensorCoordinator",
                QStringLiteral("Use HassClient.sensors"));
    qmlRegisterUncreatableType<WidgetCoordinator>(
                "harbour.helmsman", 1, 0, "WidgetCoordinator",
                QStringLiteral("Use HassClient.widget"));
    qmlRegisterUncreatableType<LovelaceCoordinator>(
                "harbour.helmsman", 1, 0, "LovelaceCoordinator",
                QStringLiteral("Use HassClient.lovelace"));
    qmlRegisterUncreatableType<HassCameraStream>(
                "harbour.helmsman", 1, 0, "HassCameraStream",
                QStringLiteral("Use HassClient.lovelace.cameraStream"));

    QQuickView *view = SailfishApp::createView();
    HelmsmanLog::watchEngine(view->engine());
    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-homeassistant.qml")));
    view->show();

    return app->exec();
}
