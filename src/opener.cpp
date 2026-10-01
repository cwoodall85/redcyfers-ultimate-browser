#include "opener.h"

#include <QDesktopServices>
#include <QProcess>
#include <QStandardPaths>

static const QStringList kSchemes = {
    "mailto", "tel", "sms", "callto", "sip", "facetime", "zoommtg", "zoomus", "msteams",
    "slack", "discord", "spotify", "magnet", "webcal", "irc", "ircs", "xmpp", "geo",
    "maps", "itms-apps", "market", "steam", "vscode", "ssh", "sftp", "smb", "news"};

Opener::Opener(QObject *parent) : QObject(parent) {
    for (const QString &s : kSchemes)
        QDesktopServices::setUrlHandler(s, this, "openUrl");
}

bool Opener::isWeb(const QString &url) const {
    const QString s = QUrl(url).scheme().toLower();
    return !kSchemes.contains(s);
}

void Opener::openUrl(const QUrl &url) {
    const QString u = url.toString();
    bool ok;
    QString app;
    if (url.scheme().compare("mailto", Qt::CaseInsensitive) == 0
            && !QStandardPaths::findExecutable("ultimate-mail-gtk").isEmpty()) {
        app = "Ultimate Mail";
        ok = QProcess::startDetached("ultimate-mail-gtk", {u});
    } else {
        app = "the app for " + url.scheme() + ": links";
        ok = QProcess::startDetached("gio", {"open", u});
    }
    emit opened(u, app, ok);
}
