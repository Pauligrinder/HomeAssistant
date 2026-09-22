#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QtQml>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QLocale>
#include <QStringList>
#include <QTranslator>

#include "appsettings.h"
#include "helmsmanlog.h"
#include "hasscamerastream.h"
#include "hassclient.h"
#include "lovelacecoordinator.h"
#include "mdiiconrenderer.h"
#include "sensorcoordinator.h"
#include "widgetcoordinator.h"

// Loads harbour-helmsman_<lang>.qm for the preferred Settings override,
// else Home Assistant profile language (cached), else system locale.
// Full locale first (e.g. fi_FI), then bare language (fi). English
// ("en") and missing catalogs keep the English source strings.
// See docs/translations.md.
static void installAppTranslator(QGuiApplication *app)
{
    const QString preferred = HassClient::preferredUiLanguage();
    if (preferred == QLatin1String("en"))
        return;

    const QString dir = SailfishApp::pathTo(QStringLiteral("translations")).toLocalFile();
    QStringList candidates;
    if (!preferred.isEmpty()) {
        candidates << preferred;
        const int sep = preferred.indexOf(QLatin1Char('_'));
        if (sep > 0)
            candidates << preferred.left(sep);
    } else {
        const QString locale = QLocale::system().name();
        candidates << locale;
        const int sep = locale.indexOf(QLatin1Char('_'));
        if (sep > 0)
            candidates << locale.left(sep);
    }

    for (int i = 0; i < candidates.size(); ++i) {
        const QString &tag = candidates.at(i);
        if (tag.isEmpty() || tag == QLatin1String("en"))
            continue;
        QTranslator *translator = new QTranslator(app);
        if (translator->load(QStringLiteral("harbour-helmsman_%1").arg(tag), dir)) {
            app->installTranslator(translator);
            return;
        }
        delete translator;
    }
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
    installAppTranslator(app);
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
