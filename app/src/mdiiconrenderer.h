#ifndef MDIICONRENDERER_H
#define MDIICONRENDERER_H

#include <QObject>
#include <QString>
#include <QImage>
#include <QColor>
#include <QHash>

class MdiIconRenderer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)

public:
    explicit MdiIconRenderer(QObject *parent = nullptr);

    bool ready() const;

    // Renders mdi:name (or bare name) into a square ARGB image.
    Q_INVOKABLE QImage renderIcon(const QString &mdiName,
                                  const QString &colorSpec = QString(),
                                  int pixelSize = 128) const;

    // Writes a PNG under the app cache and returns an absolute file path
    // suitable for Notification.icon (lipstick cannot use app image providers).
    Q_INVOKABLE QString renderIconFile(const QString &mdiName,
                                       const QString &colorSpec = QString(),
                                       int pixelSize = 128) const;

    Q_INVOKABLE bool hasIcon(const QString &mdiName) const;

signals:
    void readyChanged();

private:
    bool loadResources();
    QString normalizeName(const QString &mdiName) const;
    QColor parseColor(const QString &colorSpec) const;
    uint codepointFor(const QString &name) const;

    bool m_ready;
    QString m_fontFamily;
    QHash<QString, uint> m_codepoints;
};

#endif
