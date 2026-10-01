// Links that aren't web pages (mailto:, tel:, zoommtg:, ...). Chromium hands
// them to QDesktopServices::openUrl(), which on KDE goes through KIO -- and KIO
// fails on them ("Unable to create KIO worker. Unknown protocol 'mailto'").
// Registered as Qt's URL handler for those schemes, this launches the right
// app directly: Ultimate Mail for mailto:, the desktop's registered handler
// (gio open, which reads mimeapps.list) for the rest.
#pragma once
#include <QObject>
#include <QUrl>

class Opener : public QObject {
    Q_OBJECT
public:
    explicit Opener(QObject *parent = nullptr);
    Q_INVOKABLE bool isWeb(const QString &url) const;
public slots:
    void openUrl(const QUrl &url);
signals:
    void opened(const QString &url, const QString &app, bool ok);
};
