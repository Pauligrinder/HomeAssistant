#include "appsettings.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>

namespace {

QString legacyFilePath()
{
    const QString base =
            QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (base.isEmpty())
        return QString();
    return base + QLatin1Char('/') + QCoreApplication::organizationName()
            + QLatin1Char('/') + QCoreApplication::applicationName()
            + QStringLiteral(".conf");
}

} // namespace

namespace AppSettings {

QString filePath()
{
    const QString dir =
            QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    return dir + QStringLiteral("/settings.conf");
}

void migrateLegacyFile()
{
    const QString target = filePath();
    if (QFile::exists(target))
        return;

    const QString legacy = legacyFilePath();
    if (legacy.isEmpty() || !QFile::exists(legacy))
        return;

    QDir().mkpath(QFileInfo(target).absolutePath());
    if (QFile::copy(legacy, target))
        qWarning() << "Helmsman: migrated settings from" << legacy << "to" << target;
    else
        qWarning() << "Helmsman: could not migrate settings from" << legacy;
}

} // namespace AppSettings
