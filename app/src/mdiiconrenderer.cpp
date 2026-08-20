#include "mdiiconrenderer.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFontDatabase>
#include <QFont>
#include <QPainter>
#include <QStandardPaths>
#include <QDir>
#include <QCryptographicHash>
#include <QDebug>
#include <QRegularExpression>

namespace {

const QColor kDefaultIconColor(0x03, 0xa9, 0xf4); // Helmsman blue

QImage colorizeAlpha(const QImage &src, const QColor &tint)
{
    QImage image = src.convertToFormat(QImage::Format_ARGB32);
    const int r = tint.red();
    const int g = tint.green();
    const int b = tint.blue();
    for (int y = 0; y < image.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const int a = qAlpha(line[x]);
            if (a == 0)
                line[x] = 0;
            else
                line[x] = qRgba(r, g, b, a);
        }
    }
    return image;
}

} // namespace

MdiIconRenderer::MdiIconRenderer(QObject *parent)
    : QObject(parent)
    , m_ready(false)
{
    loadResources();
}

bool MdiIconRenderer::ready() const
{
    return m_ready;
}

bool MdiIconRenderer::loadResources()
{
    QFile fontFile(QStringLiteral(":/mdi/materialdesignicons-webfont.ttf"));
    if (!fontFile.open(QIODevice::ReadOnly)) {
        qWarning() << "Helmsman mdi: cannot open font resource";
        return false;
    }
    const int fontId = QFontDatabase::addApplicationFontFromData(fontFile.readAll());
    fontFile.close();
    if (fontId < 0) {
        qWarning() << "Helmsman mdi: failed to register font";
        return false;
    }
    const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
    if (families.isEmpty()) {
        qWarning() << "Helmsman mdi: font has no families";
        return false;
    }
    m_fontFamily = families.at(0);

    QFile mapFile(QStringLiteral(":/mdi/codepoints.json"));
    if (!mapFile.open(QIODevice::ReadOnly)) {
        qWarning() << "Helmsman mdi: cannot open codepoints resource";
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(mapFile.readAll());
    mapFile.close();
    if (!doc.isObject()) {
        qWarning() << "Helmsman mdi: codepoints JSON invalid";
        return false;
    }

    m_codepoints.clear();
    const QJsonObject obj = doc.object();
    for (auto it = obj.begin(); it != obj.end(); ++it)
        m_codepoints.insert(it.key(), static_cast<uint>(it.value().toInt()));

    m_ready = !m_codepoints.isEmpty() && !m_fontFamily.isEmpty();
    qWarning() << "Helmsman mdi: ready=" << m_ready
               << "family=" << m_fontFamily
               << "icons=" << m_codepoints.size();
    emit readyChanged();
    return m_ready;
}

QString MdiIconRenderer::normalizeName(const QString &mdiName) const
{
    QString name = mdiName.trimmed().toLower();
    if (name.startsWith(QStringLiteral("mdi:")))
        name = name.mid(4);
    // Some payloads use mdi-bell instead of mdi:bell
    if (name.startsWith(QStringLiteral("mdi-")))
        name = name.mid(4);
    return name;
}

QColor MdiIconRenderer::parseColor(const QString &colorSpec) const
{
    QString s = colorSpec.trimmed();
    if (s.isEmpty())
        return kDefaultIconColor;

    // Strip quotes if a YAML/JSON quirk leaked through.
    if ((s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"')))
            || (s.startsWith(QLatin1Char('\'')) && s.endsWith(QLatin1Char('\'')))) {
        s = s.mid(1, s.size() - 2).trimmed();
    }

    if (s.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive))
        s = QLatin1Char('#') + s.mid(2);

    // Bare hex: "2DF56D", "FFF", "FF2DF56D"
    static const QRegularExpression bareHex(QStringLiteral("^[0-9A-Fa-f]{3}([0-9A-Fa-f]{3}([0-9A-Fa-f]{2})?)?$"));
    if (!s.startsWith(QLatin1Char('#')) && bareHex.match(s).hasMatch())
        s.prepend(QLatin1Char('#'));

    QColor color(s);
    if (color.isValid() && color.alpha() > 0)
        return color;

    // Last resort: named colors with spaces removed ("light blue" -> "lightblue")
    color = QColor(QString(s).remove(QLatin1Char(' ')));
    if (color.isValid() && color.alpha() > 0)
        return color;

    qWarning() << "Helmsman mdi: unrecognised color" << colorSpec << "- using default";
    return kDefaultIconColor;
}

uint MdiIconRenderer::codepointFor(const QString &name) const
{
    return m_codepoints.value(name, 0);
}

bool MdiIconRenderer::hasIcon(const QString &mdiName) const
{
    return codepointFor(normalizeName(mdiName)) != 0;
}

QImage MdiIconRenderer::renderIcon(const QString &mdiName,
                                   const QString &colorSpec,
                                   int pixelSize) const
{
    if (!m_ready || pixelSize <= 0)
        return QImage();

    const QString name = normalizeName(mdiName);
    const uint code = codepointFor(name);
    if (code == 0) {
        qWarning() << "Helmsman mdi: unknown icon" << mdiName;
        return QImage();
    }

    // Draw glyph in opaque white, then recolor by alpha. Pen-colored drawText
    // on icon fonts is unreliable across Qt builds (often stays black/white).
    QImage mask(pixelSize, pixelSize, QImage::Format_ARGB32);
    mask.fill(Qt::transparent);

    QFont font(m_fontFamily);
    font.setPixelSize(qMax(8, int(pixelSize * 0.88)));
    font.setStyleStrategy(QFont::PreferAntialias);

    QPainter painter(&mask);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::TextAntialiasing, true);
    painter.setFont(font);
    painter.setPen(Qt::white);
    painter.setBrush(Qt::white);
    const QString glyph = QString::fromUcs4(&code, 1);
    painter.drawText(QRect(0, 0, pixelSize, pixelSize),
                     Qt::AlignCenter,
                     glyph);
    painter.end();

    const QColor tint = parseColor(colorSpec);
    qWarning() << "Helmsman mdi: render" << name << "tint=" << tint.name();
    return colorizeAlpha(mask, tint);
}

QString MdiIconRenderer::renderIconFile(const QString &mdiName,
                                        const QString &colorSpec,
                                        int pixelSize) const
{
    const QImage image = renderIcon(mdiName, colorSpec, pixelSize);
    if (image.isNull())
        return QString();

    const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
            + QStringLiteral("/mdi-icons");
    QDir().mkpath(cacheRoot);

    // v2: colorize-by-alpha renderer (busts old black/default caches).
    const QString key = QStringLiteral("v2|") + normalizeName(mdiName) + QLatin1Char('|')
            + parseColor(colorSpec).name() + QLatin1Char('|')
            + QString::number(pixelSize);
    const QByteArray hash = QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex();
    const QString path = cacheRoot + QLatin1Char('/') + QString::fromLatin1(hash) + QStringLiteral(".png");

    if (!QFile::exists(path)) {
        if (!image.save(path, "PNG")) {
            qWarning() << "Helmsman mdi: failed to save" << path;
            return QString();
        }
    }
    return path;
}
