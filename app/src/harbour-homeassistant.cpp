#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QtQml>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QLocale>
#include <QStringList>

#include "appsettings.h"
#include "helmsmani18n.h"
#include "helmsmanlog.h"
#include "hasscamerastream.h"
#include "hassclient.h"
#include "lovelacecoordinator.h"
#include "mdiiconrenderer.h"
#include "sensorcoordinator.h"
#include "widgetcoordinator.h"

// Loads translations/en.json, then the first matching <lang>.json for the
// preferred Settings override, else the Home Assistant profile language,
// else the phone locale. Full locale first (fi_FI), then the language (fi).
// English and missing keys stay on the English text. See docs/translations.md.
static void loadTranslations()
{
    const QString preferred = HassClient::preferredUiLanguage();
    const QString dir = SailfishApp::pathTo(QStringLiteral("translations")).toLocalFile();
    QStringList candidates;
    if (!preferred.isEmpty() && preferred != QLatin1String("en")) {
        candidates << preferred;
        const int sep = preferred.indexOf(QLatin1Char('_'));
        if (sep > 0)
            candidates << preferred.left(sep);
    } else if (preferred.isEmpty()) {
        const QString locale = QLocale::system().name();
        candidates << locale;
        const int sep = locale.indexOf(QLatin1Char('_'));
        if (sep > 0)
            candidates << locale.left(sep);
    }
    HelmsmanI18n::instance()->load(dir, candidates);
}

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
    loadTranslations();
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
    view->rootContext()->setContextProperty(QStringLiteral("i18n"), HelmsmanI18n::instance());
    view->rootContext()->setContextProperty(QStringLiteral("debugSettings"), HelmsmanDebug::instance());
    HelmsmanLog::watchEngine(view->engine());
    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-homeassistant.qml")));
    HelmsmanLog::watchWindow(view->rootObject());
    view->show();

    return app->exec();
}
