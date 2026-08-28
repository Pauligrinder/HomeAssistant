#ifndef APPSETTINGS_H
#define APPSETTINGS_H

#include <QString>

// QSettings' default location is ~/.config/<org>/<app>.conf, which sits next
// to — not inside — the ~/.config/<org>/<app>/ directory Sailjail whitelists.
// Launched from the app grid the sandbox hides that file, so every setting
// silently fell back to its compiled default on each start. Keep the INI file
// inside the private config directory instead.
namespace AppSettings {

// Absolute path of the settings INI, inside the Sailjail-visible directory.
QString filePath();

// Best-effort one-time copy of the pre-sandbox settings file. Only ever finds
// anything when running outside the sandbox, which is enough to carry existing
// installs over.
void migrateLegacyFile();

} // namespace AppSettings

#endif // APPSETTINGS_H
