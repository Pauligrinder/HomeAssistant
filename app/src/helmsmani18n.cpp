#include "helmsmani18n.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

HelmsmanI18n::HelmsmanI18n(QObject *parent)
    : QObject(parent)
{
}

HelmsmanI18n *HelmsmanI18n::instance()
{
    static HelmsmanI18n *self = 0;
    if (!self)
        self = new HelmsmanI18n(qApp);
    return self;
}

QHash<QString, QString> HelmsmanI18n::readCatalog(const QString &path)
{
    QHash<QString, QString> out;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "Helmsman i18n: cannot read" << path;
        return out;
    }
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "Helmsman i18n: bad catalog" << path << error.errorString();
        return out;
    }
    const QJsonObject obj = doc.object();
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
        if (it.value().isString())
            out.insert(it.key(), it.value().toString());
    }
    return out;
}

void HelmsmanI18n::load(const QString &directory, const QStringList &candidates)
{
    m_strings = readCatalog(directory + QStringLiteral("/en.json"));
    for (int i = 0; i < candidates.size(); ++i) {
        const QString code = candidates.at(i);
        if (code.isEmpty() || code == QLatin1String("en"))
            continue;
        const QString path = directory + QLatin1Char('/') + code + QStringLiteral(".json");
        if (!QFile::exists(path))
            continue;
        const QHash<QString, QString> over = readCatalog(path);
        for (auto it = over.constBegin(); it != over.constEnd(); ++it) {
            if (!it.value().isEmpty())
                m_strings.insert(it.key(), it.value());
        }
        break;
    }
}

QString HelmsmanI18n::translation(const QString &key) const
{
    return m_strings.value(key, key);
}

QString HelmsmanI18n::translation(const QString &key, const QVariant &a1) const
{
    return translation(key).arg(a1.toString());
}

QString HelmsmanI18n::translation(const QString &key, const QVariant &a1,
                                  const QVariant &a2) const
{
    return translation(key).arg(a1.toString()).arg(a2.toString());
}

QString HelmsmanI18n::translation(const QString &key, const QVariant &a1,
                                  const QVariant &a2, const QVariant &a3) const
{
    return translation(key).arg(a1.toString()).arg(a2.toString()).arg(a3.toString());
}
