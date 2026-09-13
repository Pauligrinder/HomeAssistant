#ifndef HELMSMANLOG_H
#define HELMSMANLOG_H

#include <QObject>
#include <QString>

class QQmlEngine;

// Persistent diagnostics under Documents/Helmsman, one file per day.
// Installed as the Qt message handler so existing qWarning() lines and
// Helmsman-prefixed QML console.log also land in the file.
namespace HelmsmanLog {

void install();
void watchEngine(QQmlEngine *engine);
QString directory();
void info(const QString &tag, const QString &message);

}

#endif
