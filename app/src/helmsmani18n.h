#ifndef HELMSMANI18N_H
#define HELMSMANI18N_H

#include <QObject>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariant>

// Flat JSON catalogs: translations/en.json is the full list of keys, and
// translations/<lang>.json overrides whichever keys it contains. Missing
// keys stay in English. Call i18n.translation("save") from QML.
class HelmsmanI18n : public QObject
{
    Q_OBJECT
public:
    static HelmsmanI18n *instance();

    // directory holds en.json and optional <lang>.json files.
    // candidates are tried in order (fi_FI, then fi); the first file wins.
    void load(const QString &directory, const QStringList &candidates);

    Q_INVOKABLE QString translation(const QString &key) const;
    Q_INVOKABLE QString translation(const QString &key, const QVariant &a1) const;
    Q_INVOKABLE QString translation(const QString &key, const QVariant &a1,
                                    const QVariant &a2) const;
    Q_INVOKABLE QString translation(const QString &key, const QVariant &a1,
                                    const QVariant &a2, const QVariant &a3) const;

private:
    explicit HelmsmanI18n(QObject *parent = 0);
    static QHash<QString, QString> readCatalog(const QString &path);

    QHash<QString, QString> m_strings;
};

#endif // HELMSMANI18N_H
