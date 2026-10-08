#ifndef HELMSMANLOG_H
#define HELMSMANLOG_H

#include <QObject>
#include <QString>

class QQmlEngine;

// Settings → Debug. File logging is on until the user turns it off, matching
// the previous always-on diagnostics. Touch logging stays off until enabled,
// and writes only while file logging is on.
class HelmsmanDebug : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool fileLoggingEnabled READ fileLoggingEnabled WRITE setFileLoggingEnabled NOTIFY fileLoggingEnabledChanged)
    Q_PROPERTY(bool touchLoggingEnabled READ touchLoggingEnabled WRITE setTouchLoggingEnabled NOTIFY touchLoggingEnabledChanged)

public:
    static HelmsmanDebug *instance();

    bool fileLoggingEnabled() const;
    void setFileLoggingEnabled(bool enabled);
    bool touchLoggingEnabled() const;
    void setTouchLoggingEnabled(bool enabled);

signals:
    void fileLoggingEnabledChanged();
    void touchLoggingEnabledChanged();

private slots:
    void onPageStackChanged();

private:
    explicit HelmsmanDebug(QObject *parent = 0);
    void writeSettings();

    bool m_fileLoggingEnabled;
    bool m_touchLoggingEnabled;
};

// Persistent diagnostics under Documents/Helmsman, one file per day.
// Installed as the Qt message handler so existing qWarning() lines and
// Helmsman-prefixed QML console.log also land in the file when file logging
// is on. Touch actions are separate lines prefixed "Helmsman touch:".
namespace HelmsmanLog {

void install();
void watchEngine(QQmlEngine *engine);
void watchWindow(QObject *root);
QString directory();
void info(const QString &tag, const QString &message);

}

#endif
