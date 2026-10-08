#include "helmsmanlog.h"

#include "appsettings.h"

#include <QCoreApplication>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMetaMethod>
#include <QMouseEvent>
#include <QMutex>
#include <QMutexLocker>
#include <QPointer>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSettings>
#include <QStandardPaths>
#include <QStringList>
#include <QTextStream>
#include <QTimer>
#include <QTouchEvent>
#include <QVariant>
#include <QVector>
#include <QWheelEvent>
#include <QElapsedTimer>
#include <cstdio>

namespace {

const int kHeartbeatMs = 60 * 1000;
const int kKeepDays = 14;

enum TraceKind {
    TraceIgnore,
    TraceStart,
    TraceMove,
    TraceEnd
};

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

QString typeName(QObject *object)
{
    if (!object)
        return QString();
    QString name = QString::fromLatin1(object->metaObject()->className());
    const int colon = name.lastIndexOf(QLatin1String("::"));
    if (colon >= 0)
        name = name.mid(colon + 2);
    int cut = name.indexOf(QLatin1String("_QMLTYPE_"));
    if (cut < 0)
        cut = name.indexOf(QLatin1String("_QML_"));
    if (cut > 0)
        name.truncate(cut);
    if (name.startsWith(QLatin1String("QQuick")))
        name = name.mid(6);
    return name;
}

QString sanitize(const QString &value, int limit)
{
    QString text = value;
    text.replace(QLatin1Char('\n'), QLatin1Char(' '));
    text.replace(QLatin1Char('"'), QLatin1Char('\''));
    text = text.simplified();
    if (text.size() > limit)
        text = text.left(limit - 3) + QStringLiteral("...");
    return text;
}

QString formatNumber(double value)
{
    const int rounded = qRound(value);
    if (qAbs(value - rounded) < 0.05)
        return QString::number(rounded);
    return QString::number(value, 'f', 2);
}

QString formatPos(const QPointF &pos)
{
    return QString::number(qRound(pos.x())) + QLatin1Char(',')
            + QString::number(qRound(pos.y()));
}

bool isSecret(QObject *object)
{
    if (!object)
        return false;
    if (typeName(object) == QLatin1String("PasswordField"))
        return true;
    const QVariant echo = object->property("echoMode");
    return echo.isValid() && echo.toInt() != 0;
}

bool isSkippable(const QString &type)
{
    return type == QLatin1String("Item")
            || type == QLatin1String("Column")
            || type == QLatin1String("Row")
            || type == QLatin1String("Grid")
            || type == QLatin1String("Flow")
            || type == QLatin1String("Flickable")
            || type == QLatin1String("SilicaFlickable")
            || type == QLatin1String("Loader")
            || type == QLatin1String("FocusScope")
            || type == QLatin1String("Rectangle")
            || type == QLatin1String("Image")
            || type == QLatin1String("Label")
            || type == QLatin1String("Icon")
            || type == QLatin1String("MdiIcon")
            || type == QLatin1String("Text");
}

QObject *visualParent(QObject *object)
{
    QQuickItem *item = qobject_cast<QQuickItem *>(object);
    if (item)
        return item->parentItem();
    return object ? object->parent() : 0;
}

QString headerTitle(QQuickItem *item, int depth)
{
    if (!item || depth > 6)
        return QString();
    const QString type = typeName(item);
    if (type == QLatin1String("PageHeader") || type == QLatin1String("DialogHeader")) {
        const QString title = sanitize(item->property("title").toString(), 80);
        if (!title.isEmpty())
            return title;
    }
    const QList<QQuickItem *> kids = item->childItems();
    for (int i = 0; i < kids.size(); ++i) {
        const QString title = headerTitle(kids.at(i), depth + 1);
        if (!title.isEmpty())
            return title;
    }
    return QString();
}

QString describePage(QObject *page)
{
    if (!page)
        return QStringLiteral("(none)");
    QString text = typeName(page);
    const QString name = page->objectName();
    if (!name.isEmpty())
        text += QLatin1Char(' ') + name;
    QQuickItem *item = qobject_cast<QQuickItem *>(page);
    const QString title = headerTitle(item, 0);
    if (!title.isEmpty())
        text += QStringLiteral(" \"") + title + QLatin1Char('"');
    return text;
}

QString entityOf(QObject *object)
{
    QString entity = object->property("entityId").toString();
    if (entity.isEmpty())
        entity = object->property("trackedEntityId").toString();
    if (entity.isEmpty()) {
        const QVariant card = object->property("card");
        if (card.type() == QVariant::Map)
            entity = card.toMap().value(QStringLiteral("entity")).toString();
    }
    return sanitize(entity, 80);
}

QString captionOf(QObject *object)
{
    if (isSecret(object))
        return QString();
    QString caption = object->property("text").toString();
    if (caption.isEmpty())
        caption = object->property("label").toString();
    if (caption.isEmpty())
        caption = object->property("currentText").toString();
    if (caption.isEmpty()) {
        const QVariant card = object->property("card");
        if (card.type() == QVariant::Map)
            caption = card.toMap().value(QStringLiteral("name")).toString();
    }
    return sanitize(caption, 60);
}

QString describeOne(QObject *object)
{
    if (!object)
        return QStringLiteral("(none)");
    const QString type = typeName(object);
    if (type == QLatin1String("Page") || type == QLatin1String("Dialog"))
        return describePage(object);

    QStringList bits;
    bits << type;
    const QString name = object->objectName();
    if (!name.isEmpty())
        bits << name;
    if (isSecret(object)) {
        bits << QStringLiteral("(hidden)");
        return bits.join(QLatin1Char(' '));
    }
    const QString caption = captionOf(object);
    if (!caption.isEmpty())
        bits << QStringLiteral("\"%1\"").arg(caption);
    const QString entity = entityOf(object);
    if (!entity.isEmpty())
        bits << QStringLiteral("entity=%1").arg(entity);
    return bits.join(QLatin1Char(' '));
}

bool keepInChain(QObject *object, bool receiver)
{
    if (receiver)
        return true;
    const QString type = typeName(object);
    if (type == QLatin1String("Page") || type == QLatin1String("Dialog"))
        return true;
    if (!isSkippable(type))
        return true;
    if (!object->objectName().isEmpty())
        return true;
    if (!entityOf(object).isEmpty() || !captionOf(object).isEmpty())
        return true;
    return false;
}

QString describeChain(QObject *object)
{
    if (!object)
        return QStringLiteral("(none)");
    if (qobject_cast<QQuickWindow *>(object))
        return QStringLiteral("Window");

    QStringList parts;
    QObject *cursor = object;
    for (int i = 0; cursor && parts.size() < 8 && i < 24; ++i) {
        const QString type = typeName(cursor);
        if (type == QLatin1String("ApplicationWindow") || type == QLatin1String("Window"))
            break;
        if (keepInChain(cursor, cursor == object))
            parts << describeOne(cursor);
        if (type == QLatin1String("Page") || type == QLatin1String("Dialog"))
            break;
        cursor = visualParent(cursor);
    }
    if (parts.isEmpty())
        return describeOne(object);
    return parts.join(QStringLiteral(" < "));
}

bool secretChain(QObject *object)
{
    QObject *cursor = object;
    for (int i = 0; cursor && i < 24; ++i) {
        if (isSecret(cursor))
            return true;
        cursor = visualParent(cursor);
    }
    return false;
}

QString grabberSuffix(QObject *watched)
{
    QQuickItem *item = qobject_cast<QQuickItem *>(watched);
    QQuickWindow *window = item ? item->window() : qobject_cast<QQuickWindow *>(watched);
    if (!window)
        return QString();
    QQuickItem *grabber = window->mouseGrabberItem();
    if (!grabber || grabber == item)
        return QString();
    return QStringLiteral(" grabber=%1").arg(describeOne(grabber));
}

QString buttonLabel(Qt::MouseButton button)
{
    switch (button) {
    case Qt::LeftButton:
        return QStringLiteral("left");
    case Qt::RightButton:
        return QStringLiteral("right");
    case Qt::MiddleButton:
        return QStringLiteral("middle");
    default:
        return QString::number(int(button));
    }
}

bool isNumber(const QVariant &value)
{
    switch (value.type()) {
    case QVariant::Int:
    case QVariant::UInt:
    case QVariant::LongLong:
    case QVariant::ULongLong:
    case QVariant::Double:
        return true;
    default:
        return false;
    }
}

bool tracksValue(const QString &type)
{
    return type.contains(QLatin1String("Slider"));
}

bool tracksIndex(const QString &type)
{
    return type == QLatin1String("ComboBox")
            || type == QLatin1String("Tumbler")
            || type.contains(QLatin1String("Picker"));
}

struct PropSnap {
    QPointer<QObject> object;
    bool hasChecked;
    bool checked;
    bool hasValue;
    double value;
    bool hasIndex;
    int index;
};

bool fillSnap(QObject *object, PropSnap *snap)
{
    const QString type = typeName(object);
    const QVariant checked = object->property("checked");
    const QVariant value = object->property("value");
    const QVariant index = object->property("currentIndex");
    snap->object = object;
    snap->hasChecked = checked.type() == QVariant::Bool;
    snap->checked = checked.toBool();
    snap->hasValue = tracksValue(type) && isNumber(value);
    snap->value = value.toDouble();
    snap->hasIndex = tracksIndex(type) && isNumber(index);
    snap->index = index.toInt();
    return snap->hasChecked || snap->hasValue || snap->hasIndex;
}

TraceKind traceKind(QEvent *event)
{
    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonDblClick:
    case QEvent::TouchBegin:
    case QEvent::Wheel:
        return TraceStart;
    case QEvent::KeyPress: {
        QKeyEvent *key = static_cast<QKeyEvent *>(event);
        return key->isAutoRepeat() ? TraceIgnore : TraceStart;
    }
    case QEvent::MouseButtonRelease:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel:
        return TraceEnd;
    case QEvent::MouseMove: {
        QMouseEvent *mouse = static_cast<QMouseEvent *>(event);
        return mouse->buttons() == Qt::NoButton ? TraceIgnore : TraceMove;
    }
    case QEvent::TouchUpdate:
        return TraceMove;
    default:
        return TraceIgnore;
    }
}

QObject *findPageStack(QObject *root)
{
    if (!root)
        return 0;
    QObject *stack = root->property("pageStack").value<QObject *>();
    if (stack)
        return stack;
    const QObjectList kids = root->findChildren<QObject *>();
    for (int i = 0; i < kids.size(); ++i) {
        const QString type = typeName(kids.at(i));
        if (type == QLatin1String("PageStack") || type.endsWith(QLatin1String("PageStack")))
            return kids.at(i);
    }
    return 0;
}

QString actionLine(QObject *watched, QEvent *event)
{
    QString verb;
    QString where;
    QString extra;
    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease:
    case QEvent::MouseButtonDblClick: {
        QMouseEvent *mouse = static_cast<QMouseEvent *>(event);
        if (event->type() == QEvent::MouseButtonDblClick)
            verb = QStringLiteral("double-click");
        else if (event->type() == QEvent::MouseButtonRelease)
            verb = QStringLiteral("release");
        else
            verb = QStringLiteral("press");
        where = buttonLabel(mouse->button()) + QLatin1Char(' ')
                + formatPos(mouse->windowPos());
#if QT_VERSION >= QT_VERSION_CHECK(5, 3, 0)
        if (mouse->source() != Qt::MouseEventNotSynthesized)
            extra = QStringLiteral(" synth");
#endif
        break;
    }
    case QEvent::TouchBegin:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel:
    case QEvent::TouchUpdate: {
        QTouchEvent *touch = static_cast<QTouchEvent *>(event);
        if (event->type() == QEvent::TouchBegin)
            verb = QStringLiteral("touch-begin");
        else if (event->type() == QEvent::TouchEnd)
            verb = QStringLiteral("touch-end");
        else if (event->type() == QEvent::TouchCancel)
            verb = QStringLiteral("touch-cancel");
        else
            verb = QStringLiteral("touch-move");
        const QList<QTouchEvent::TouchPoint> points = touch->touchPoints();
        if (!points.isEmpty())
            where = formatPos(points.first().scenePos());
        if (points.size() > 1)
            extra = QStringLiteral(" points=%1").arg(points.size());
        break;
    }
    case QEvent::KeyPress: {
        QKeyEvent *key = static_cast<QKeyEvent *>(event);
        verb = QStringLiteral("key");
        if (secretChain(watched))
            where = QStringLiteral("(hidden)");
        else {
            const int combo = int(key->modifiers()) | key->key();
            where = QKeySequence(combo).toString(QKeySequence::PortableText);
            if (where.isEmpty())
                where = QString::number(key->key());
        }
        break;
    }
    case QEvent::Wheel: {
        QWheelEvent *wheel = static_cast<QWheelEvent *>(event);
        verb = QStringLiteral("wheel");
        where = formatPos(QPointF(wheel->globalPos()))
                + QStringLiteral(" delta=%1").arg(wheel->angleDelta().y());
        break;
    }
    default:
        verb = QStringLiteral("event");
        where = QString::number(int(event->type()));
        break;
    }
    QString line = verb + QLatin1Char(' ') + where + extra
            + QStringLiteral(" | ") + describeChain(watched) + grabberSuffix(watched);
    const QVariant enabled = watched ? watched->property("enabled") : QVariant();
    if (enabled.type() == QVariant::Bool && !enabled.toBool())
        line += QStringLiteral(" disabled");
    return line;
}

class HelmsmanLogger : public QObject
{
public:
    explicit HelmsmanLogger(QObject *parent = 0)
        : QObject(parent)
        , m_previous(0)
        , m_fileLogging(false)
        , m_touchSetting(false)
        , m_touchActive(false)
        , m_hooksInstalled(false)
        , m_navConnected(false)
        , m_navFailed(false)
        , m_navWarned(false)
        , m_navAttempts(0)
        , m_lastDepth(-1)
        , m_diffQueued(false)
        , m_clearAfterDiff(false)
        , m_inTouchLog(false)
    {
        m_started.start();
        m_diffTimer.setSingleShot(true);
        m_diffTimer.setInterval(0);
        connect(&m_diffTimer, &QTimer::timeout, this, [this]() {
            m_diffQueued = false;
            diffGesture();
        });
        m_navRetry.setSingleShot(true);
        m_navRetry.setInterval(0);
        connect(&m_navRetry, &QTimer::timeout, this, [this]() {
            QObject *root = m_navRoot.data();
            if (root)
                watchNavigation(root);
        });
    }

    QString directoryPath() const { return m_directory; }

    void setPreviousHandler(QtMessageHandler previous)
    {
        m_previous = previous;
    }

    void setFileLogging(bool enabled)
    {
        if (enabled == m_fileLogging)
            return;
        if (!enabled) {
            if (m_touchActive) {
                qApp->removeEventFilter(this);
                m_touchActive = false;
                finishGesture();
                writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: touch logging disabled"));
            }
            stopFileLogging();
            return;
        }
        startFileLogging();
        syncTouchFilter();
    }

    void setTouchLogging(bool enabled)
    {
        m_touchSetting = enabled;
        if (!m_fileLogging) {
            if (m_touchActive) {
                qApp->removeEventFilter(this);
                m_touchActive = false;
                m_gesture.clear();
            }
            return;
        }
        syncTouchFilter();
    }

    void watchNavigation(QObject *root)
    {
        if (m_navConnected || !root)
            return;
        QObject *stack = findPageStack(root);
        if (!stack) {
            if (m_navAttempts < 8) {
                ++m_navAttempts;
                m_navRoot = root;
                if (!m_navRetry.isActive())
                    m_navRetry.start();
                return;
            }
            m_navFailed = true;
            warnNavigation();
            return;
        }
        m_stack = stack;
        m_navConnected = connectCurrentPage(stack);
        if (!m_navConnected) {
            m_navFailed = true;
            warnNavigation();
            return;
        }
        m_lastPage = describePage(stack->property("currentPage").value<QObject *>());
        m_lastDepth = stack->property("depth").toInt();
    }

    void handlePageChanged()
    {
        if (!m_touchActive || !m_stack)
            return;
        QObject *page = m_stack->property("currentPage").value<QObject *>();
        const int depth = m_stack->property("depth").toInt();
        const QString next = describePage(page);
        if (next == m_lastPage && depth == m_lastDepth)
            return;
        QString verb = QStringLiteral("navigate");
        if (m_lastDepth >= 0) {
            if (depth > m_lastDepth)
                verb = QStringLiteral("push");
            else if (depth < m_lastDepth)
                verb = QStringLiteral("pop");
            else
                verb = QStringLiteral("replace");
        }
        const QString from = m_lastPage.isEmpty() ? QStringLiteral("(none)") : m_lastPage;
        logTouch(verb + QLatin1Char(' ') + from + QStringLiteral(" -> ")
                 + next + QStringLiteral(" depth=") + QString::number(depth));
        m_lastPage = next;
        m_lastDepth = depth;
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

    bool eventFilter(QObject *watched, QEvent *event)
    {
        if (!m_touchActive || m_inTouchLog)
            return false;
        const TraceKind kind = traceKind(event);
        if (kind == TraceIgnore)
            return false;
        if (kind == TraceMove && m_gesture.isEmpty())
            return false;

        TouchGuard guard(m_inTouchLog);
        if (kind != TraceMove)
            logTouch(actionLine(watched, event));
        if (kind == TraceStart) {
            captureGesture(watched);
            const QEvent::Type type = event->type();
            m_clearAfterDiff = type == QEvent::KeyPress || type == QEvent::Wheel;
        } else if (kind == TraceEnd) {
            m_clearAfterDiff = true;
        }
        if (!m_gesture.isEmpty())
            scheduleDiff();
        return false;
    }

private:
    struct TouchGuard {
        bool &flag;
        explicit TouchGuard(bool &flag) : flag(flag) { flag = true; }
        ~TouchGuard() { flag = false; }
    };

    void ensureHooks()
    {
        if (m_hooksInstalled)
            return;
        m_hooksInstalled = true;
        m_heartbeat.setInterval(kHeartbeatMs);
        connect(&m_heartbeat, &QTimer::timeout, this, [this]() { onHeartbeat(); });
        if (!qApp)
            return;
        connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() { onAboutToQuit(); });
        QGuiApplication *gui = qobject_cast<QGuiApplication *>(qApp);
        if (gui) {
            connect(gui, &QGuiApplication::applicationStateChanged,
                    this, [this](Qt::ApplicationState state) { onAppStateChanged(state); });
        }
    }

    void startFileLogging()
    {
        ensureHooks();
        QString path;
        {
            QMutexLocker locker(&m_mutex);
            if (m_directory.isEmpty())
                m_directory = resolveDirectory();
            m_fileLogging = true;
            path = m_directory + QStringLiteral("/helmsman-")
                    + QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"))
                    + QStringLiteral(".log");
        }
        pruneOldFiles();
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman log: writing to %1").arg(path));
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman log: version=%1 pid=%2")
                 .arg(QStringLiteral(APP_VERSION))
                 .arg(QCoreApplication::applicationPid()));
        if (!m_heartbeat.isActive())
            m_heartbeat.start();
    }

    void stopFileLogging()
    {
        if (!m_fileLogging)
            return;
        writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: file logging disabled"));
        m_heartbeat.stop();
        QMutexLocker locker(&m_mutex);
        m_fileLogging = false;
        flushUnlocked();
        if (m_file.isOpen())
            m_file.close();
        m_date.clear();
    }

    void syncTouchFilter()
    {
        const bool active = m_touchSetting && m_fileLogging;
        if (active == m_touchActive)
            return;
        m_touchActive = active;
        if (active) {
            qApp->installEventFilter(this);
            writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: touch logging enabled"));
            warnNavigation();
            return;
        }
        qApp->removeEventFilter(this);
        finishGesture();
        if (m_fileLogging)
            writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: touch logging disabled"));
    }

    bool connectNamed(QObject *stack, const char *signalName)
    {
        HelmsmanDebug *debug = HelmsmanDebug::instance();
        const int slotIndex = debug->metaObject()->indexOfSlot("onPageStackChanged()");
        if (slotIndex < 0)
            return false;
        const QMetaMethod slot = debug->metaObject()->method(slotIndex);
        const QMetaObject *meta = stack->metaObject();
        for (int i = 0; i < meta->methodCount(); ++i) {
            const QMetaMethod method = meta->method(i);
            if (method.methodType() != QMetaMethod::Signal)
                continue;
            if (method.name() != signalName)
                continue;
            if (QObject::connect(stack, method, debug, slot))
                return true;
        }
        return false;
    }

    bool connectCurrentPage(QObject *stack)
    {
        // Prefer the page signal. depthChanged is only a fallback, so a push
        // is not logged twice when both signals exist.
        return connectNamed(stack, "currentPageChanged")
                || connectNamed(stack, "depthChanged");
    }

    void warnNavigation()
    {
        if (!m_touchActive || !m_navFailed || m_navWarned)
            return;
        m_navWarned = true;
        logTouch(QStringLiteral("navigation watch unavailable"));
    }

    void finishGesture()
    {
        m_diffTimer.stop();
        m_diffQueued = false;
        m_clearAfterDiff = true;
        diffGesture();
    }

    void captureGesture(QObject *watched)
    {
        m_gesture.clear();
        QObject *cursor = watched;
        for (int i = 0; cursor && i < 24; ++i) {
            PropSnap snap;
            if (fillSnap(cursor, &snap))
                m_gesture.append(snap);
            const QString type = typeName(cursor);
            if (type == QLatin1String("Page") || type == QLatin1String("Dialog"))
                break;
            cursor = visualParent(cursor);
        }
    }

    void scheduleDiff()
    {
        if (m_diffQueued)
            return;
        m_diffQueued = true;
        m_diffTimer.start();
    }

    void diffGesture()
    {
        if (!m_fileLogging) {
            m_gesture.clear();
            m_clearAfterDiff = false;
            return;
        }
        for (int i = 0; i < m_gesture.size(); ++i) {
            PropSnap &snap = m_gesture[i];
            QObject *object = snap.object;
            if (!object)
                continue;
            QStringList changes;
            if (snap.hasChecked) {
                const bool checked = object->property("checked").toBool();
                if (checked != snap.checked) {
                    changes << QStringLiteral("checked %1 -> %2")
                               .arg(snap.checked ? QStringLiteral("on") : QStringLiteral("off"),
                                    checked ? QStringLiteral("on") : QStringLiteral("off"));
                    snap.checked = checked;
                }
            }
            if (snap.hasValue) {
                const double value = object->property("value").toDouble();
                if (qAbs(value - snap.value) >= 0.001) {
                    QString change = QStringLiteral("value ")
                            + formatNumber(snap.value)
                            + QStringLiteral(" -> ")
                            + formatNumber(value);
                    const QString shown = sanitize(object->property("valueText").toString(), 40);
                    if (!shown.isEmpty())
                        change += QStringLiteral(" (") + shown + QLatin1Char(')');
                    changes << change;
                    snap.value = value;
                }
            }
            if (snap.hasIndex) {
                const int index = object->property("currentIndex").toInt();
                if (index != snap.index) {
                    QString change = QStringLiteral("index ")
                            + QString::number(snap.index)
                            + QStringLiteral(" -> ")
                            + QString::number(index);
                    const QString shown = sanitize(object->property("currentText").toString(), 40);
                    if (!shown.isEmpty())
                        change += QStringLiteral(" (") + shown + QLatin1Char(')');
                    changes << change;
                    snap.index = index;
                }
            }
            if (!changes.isEmpty()) {
                logTouch(QStringLiteral("state ") + describeChain(object)
                         + QStringLiteral(" | ") + changes.join(QStringLiteral(", ")));
            }
        }
        if (m_clearAfterDiff) {
            m_gesture.clear();
            m_clearAfterDiff = false;
        }
    }

    void logTouch(const QString &message)
    {
        if (!m_fileLogging)
            return;
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman touch: %1").arg(message),
                 true);
    }

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

    void writeRaw(QtMsgType type, const QString &message, bool flushNow = false)
    {
        QMutexLocker locker(&m_mutex);
        if (!m_fileLogging)
            return;
        openToday();
        if (!m_file.isOpen())
            return;

        const QString line = QStringLiteral("%1 %2 %3")
                .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss.zzz")))
                .arg(typeLabel(type), -5)
                .arg(message);
        m_stream << line << '\n';
        if (flushNow)
            flushUnlocked();
    }

    void flushUnlocked()
    {
        if (m_file.isOpen()) {
            m_stream.flush();
            m_file.flush();
        }
    }

    void onHeartbeat()
    {
        const QGuiApplication *gui = qobject_cast<QGuiApplication *>(qApp);
        writeRaw(QtInfoMsg,
                 QStringLiteral("Helmsman heartbeat: uptime=%1s rss=%2 active=%3")
                 .arg(m_started.elapsed() / 1000)
                 .arg(processRssKb())
                 .arg(gui ? int(gui->applicationState()) : -1));
        QMutexLocker locker(&m_mutex);
        flushUnlocked();
    }

    void onAboutToQuit()
    {
        writeRaw(QtInfoMsg, QStringLiteral("Helmsman log: aboutToQuit"));
        QMutexLocker locker(&m_mutex);
        flushUnlocked();
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
    QTimer m_diffTimer;
    QTimer m_navRetry;
    QElapsedTimer m_started;
    bool m_fileLogging;
    bool m_touchSetting;
    bool m_touchActive;
    bool m_hooksInstalled;
    bool m_navConnected;
    bool m_navFailed;
    bool m_navWarned;
    int m_navAttempts;
    QPointer<QObject> m_navRoot;
    QPointer<QObject> m_stack;
    QString m_lastPage;
    int m_lastDepth;
    QVector<PropSnap> m_gesture;
    bool m_diffQueued;
    bool m_clearAfterDiff;
    bool m_inTouchLog;
};

HelmsmanLogger *g_logger = 0;
HelmsmanDebug *g_debug = 0;

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (g_logger)
        g_logger->handleMessage(type, context, message);
}

} // namespace

HelmsmanDebug::HelmsmanDebug(QObject *parent)
    : QObject(parent)
    , m_fileLoggingEnabled(true)
    , m_touchLoggingEnabled(false)
{
    QSettings ui(AppSettings::filePath(), QSettings::IniFormat);
    if (ui.contains(QStringLiteral("debugFileLogging")))
        m_fileLoggingEnabled = ui.value(QStringLiteral("debugFileLogging")).toBool();
    if (ui.contains(QStringLiteral("debugTouchLogging")))
        m_touchLoggingEnabled = ui.value(QStringLiteral("debugTouchLogging")).toBool();
}

HelmsmanDebug *HelmsmanDebug::instance()
{
    if (!g_debug)
        g_debug = new HelmsmanDebug(qApp);
    return g_debug;
}

bool HelmsmanDebug::fileLoggingEnabled() const
{
    return m_fileLoggingEnabled;
}

bool HelmsmanDebug::touchLoggingEnabled() const
{
    return m_touchLoggingEnabled;
}

void HelmsmanDebug::writeSettings()
{
    const QString path = AppSettings::filePath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSettings ui(path, QSettings::IniFormat);
    ui.setValue(QStringLiteral("debugFileLogging"), m_fileLoggingEnabled);
    ui.setValue(QStringLiteral("debugTouchLogging"), m_touchLoggingEnabled);
}

void HelmsmanDebug::setFileLoggingEnabled(bool enabled)
{
    if (m_fileLoggingEnabled == enabled)
        return;
    m_fileLoggingEnabled = enabled;
    writeSettings();
    if (g_logger)
        g_logger->setFileLogging(enabled);
    emit fileLoggingEnabledChanged();
}

void HelmsmanDebug::setTouchLoggingEnabled(bool enabled)
{
    if (m_touchLoggingEnabled == enabled)
        return;
    m_touchLoggingEnabled = enabled;
    writeSettings();
    if (g_logger)
        g_logger->setTouchLogging(enabled);
    emit touchLoggingEnabledChanged();
}

void HelmsmanDebug::onPageStackChanged()
{
    if (g_logger)
        g_logger->handlePageChanged();
}

void HelmsmanLog::install()
{
    if (g_logger)
        return;
    HelmsmanDebug *debug = HelmsmanDebug::instance();
    g_logger = new HelmsmanLogger(qApp);
    g_logger->setPreviousHandler(qInstallMessageHandler(messageHandler));
    g_logger->setTouchLogging(debug->touchLoggingEnabled());
    g_logger->setFileLogging(debug->fileLoggingEnabled());
}

void HelmsmanLog::watchEngine(QQmlEngine *engine)
{
    if (!g_logger || !engine)
        return;
    QObject::connect(engine, &QQmlEngine::warnings, g_logger,
            [engine](const QList<QQmlError> &errors) {
        Q_UNUSED(engine);
        if (g_logger)
            g_logger->logQmlWarnings(errors);
    });
}

void HelmsmanLog::watchWindow(QObject *root)
{
    if (g_logger)
        g_logger->watchNavigation(root);
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
