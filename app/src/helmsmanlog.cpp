#include "helmsmanlog.h"

#include <QCoreApplication>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlEngine>
#include <QQmlError>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QElapsedTimer>
#include <cstdio>

namespace {

const int kHeartbeatMs = 60 * 1000;
const int kLagTickMs = 2000;
const int kLagWarnMs = 5000;
const int kKeepDays = 14;

QString typeLabel(QtMsgType type)
{
    switch (type) {
    case QtDebugMsg:
        return QStringLiteral("DEBUG");
    case QtWarningMsg:
        return QStringLiteral("WARN");
    case QtCriticalMsg:
        return QStringLiteral("ERROR");
    case QtFatalMsg:
        return QStringLiteral("FATAL");
#if QT_VERSION >= QT_VERSION_CHECK(5, 5, 0)
    case QtInfoMsg:
        return QStringLiteral("INFO");
#endif
    default:
        return QStringLiteral("LOG");
    }
}

bool shouldCapture(QtMsgType type, const QString &message)
{
    if (type == QtWarningMsg || type == QtCriticalMsg || type == QtFatalMsg)
        return true;
#if QT_VERSION >= QT_VERSION_CHECK(5, 5, 0)
    if (type == QtInfoMsg)
        return true;
#endif
    return message.startsWith(QLatin1String("Helmsman"));
}

QString processRssKb()
{
    QFile file(QStringLiteral("/proc/self/status"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringLiteral("?");
    while (!file.atEnd()) {
        const QByteArray line = file.readLine();
        if (!line.startsWith("VmRSS:"))
            continue;
        return QString::fromLatin1(line.mid(6).trimmed());
    }
    return QStringLiteral("?");
}

class HelmsmanLogger : public QObject
{
public:
    explicit HelmsmanLogger(QObject *parent = 0)
        : QObject(parent)
        , m_previous(0)
        , m_lastLagMs(0)
    {
        m_started.start();
        m_lagClock.start();
    }

    QString directoryPath() const { return m_directory; }

    void start()
    {
        m_directory = resolveDirectory();
        pruneOldFiles();
        openToday();

        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman log: writing to %1").arg(m_file.fileName()));
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman log: version=%1 pid=%2")
                 .arg(QStringLiteral(APP_VERSION))
                 .arg(QCoreApplication::applicationPid()));

        m_heartbeat.setInterval(kHeartbeatMs);
        connect(&m_heartbeat, &QTimer::timeout, this, [this]() { onHeartbeat(); });
        m_heartbeat.start();

        m_lagTimer.setInterval(kLagTickMs);
        connect(&m_lagTimer, &QTimer::timeout, this, [this]() { onLagTick(); });
        m_lagTimer.start();

        if (qApp) {
            connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() { onAboutToQuit(); });
            QGuiApplication *gui = qobject_cast<QGuiApplication *>(qApp);
            if (gui) {
                connect(gui, &QGuiApplication::applicationStateChanged,
                        this, [this](Qt::ApplicationState state) { onAppStateChanged(state); });
            }
        }
    }

    void setPreviousHandler(QtMessageHandler previous)
    {
        m_previous = previous;
    }

    void handleMessage(QtMsgType type, const QMessageLogContext &context, const QString &message)
    {
        if (shouldCapture(type, message))
            writeRaw(type, message);

        if (m_previous)
            m_previous(type, context, message);
        else
            fprintf(stderr, "%s\n", qPrintable(message));
    }

    void info(const QString &tag, const QString &message)
    {
        writeRaw(QtInfoMsg, QStringLiteral("Helmsman %1: %2").arg(tag, message));
    }

    void logQmlWarnings(const QList<QQmlError> &errors)
    {
        for (int i = 0; i < errors.size(); ++i) {
            const QQmlError error = errors.at(i);
            writeRaw(QtWarningMsg,
                     QStringLiteral("Helmsman qml: %1:%2 %3")
                     .arg(error.url().toString())
                     .arg(error.line())
                     .arg(error.toString()));
        }
    }

private:
    static QString resolveDirectory()
    {
        const QString documents =
                QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        if (!documents.isEmpty()) {
            const QString dir = documents + QStringLiteral("/Helmsman");
            if (QDir().mkpath(dir))
                return dir;
        }
        const QString fallback =
                QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                + QStringLiteral("/logs");
        QDir().mkpath(fallback);
        return fallback;
    }

    void pruneOldFiles()
    {
        QDir dir(m_directory);
        const QFileInfoList files = dir.entryInfoList(
                    QStringList() << QStringLiteral("helmsman-*.log"),
                    QDir::Files, QDir::Name);
        const QDate cutoff = QDate::currentDate().addDays(-kKeepDays);
        for (int i = 0; i < files.size(); ++i) {
            const QString name = files.at(i).fileName();
            const QString stamp = name.mid(9, 10);
            const QDate date = QDate::fromString(stamp, QStringLiteral("yyyy-MM-dd"));
            if (date.isValid() && date < cutoff)
                QFile::remove(files.at(i).absoluteFilePath());
        }
    }

    void openToday()
    {
        const QString today = QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"));
        if (m_date == today && m_file.isOpen())
            return;

        if (m_file.isOpen()) {
            m_stream.flush();
            m_file.close();
        }

        m_date = today;
        const QString path = m_directory + QStringLiteral("/helmsman-") + today
                + QStringLiteral(".log");
        m_file.setFileName(path);
        if (!m_file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            fprintf(stderr, "Helmsman log: cannot open %s\n", qPrintable(path));
            return;
        }
        m_stream.setDevice(&m_file);
    }

    void writeRaw(QtMsgType type, const QString &message)
    {
        QMutexLocker locker(&m_mutex);
        openToday();
        if (!m_file.isOpen())
            return;

        const QString line = QStringLiteral("%1 %2 %3")
                .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss.zzz")))
                .arg(typeLabel(type), -5)
                .arg(message);
        m_stream << line << '\n';
        m_stream.flush();
        m_file.flush();
    }

    void onHeartbeat()
    {
        const QGuiApplication *gui = qobject_cast<QGuiApplication *>(qApp);
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman heartbeat: uptime=%1s rss=%2 active=%3 lastLag=%4ms")
                 .arg(m_started.elapsed() / 1000)
                 .arg(processRssKb())
                 .arg(gui ? int(gui->applicationState()) : -1)
                 .arg(m_lastLagMs));
    }

    void onLagTick()
    {
        const qint64 gap = m_lagClock.restart();
        m_lastLagMs = gap - kLagTickMs;
        if (gap >= kLagWarnMs) {
            writeRaw(QtWarningMsg,
                     QStringLiteral("Helmsman hang: event loop stalled %1ms (timer was %2ms)")
                     .arg(gap)
                     .arg(kLagTickMs));
        }
    }

    void onAboutToQuit()
    {
        writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: aboutToQuit"));
        QMutexLocker locker(&m_mutex);
        if (m_file.isOpen()) {
            m_stream.flush();
            m_file.flush();
        }
    }

    void onAppStateChanged(Qt::ApplicationState state)
    {
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman app: state=%1").arg(int(state)));
    }

    QMutex m_mutex;
    QFile m_file;
    QTextStream m_stream;
    QString m_directory;
    QString m_date;
    QtMessageHandler m_previous;
    QTimer m_heartbeat;
    QTimer m_lagTimer;
    QElapsedTimer m_started;
    QElapsedTimer m_lagClock;
    qint64 m_lastLagMs;
};

HelmsmanLogger *g_logger = 0;

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (g_logger)
        g_logger->handleMessage(type, context, message);
}

} // namespace

void HelmsmanLog::install()
{
    if (g_logger)
        return;
    g_logger = new HelmsmanLogger(qApp);
    g_logger->start();
    g_logger->setPreviousHandler(qInstallMessageHandler(messageHandler));
}

void HelmsmanLog::watchEngine(QQmlEngine *engine)
{
    if (!g_logger || !engine)
        return;
    connect(engine, &QQmlEngine::warnings, g_logger,
            [engine](const QList<QQmlError> &errors) {
        Q_UNUSED(engine);
        if (g_logger)
            g_logger->logQmlWarnings(errors);
    });
}

QString HelmsmanLog::directory()
{
    return g_logger ? g_logger->directoryPath() : QString();
}

void HelmsmanLog::info(const QString &tag, const QString &message)
{
    if (g_logger)
        g_logger->info(tag, message);
}
