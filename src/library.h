// The browser's own records, per workspace: bookmarks, history and saved
// logins. One SQLite file (~/.local/share/ultimate-browser/library.db).
// Passwords are NOT in it: each lives in the desktop keyring (KWallet's
// Secret Service, via QtKeychain), under service "ultimate-browser", key
// "login-<id>"; the database keeps only the site and the username.
#pragma once
#include <QObject>
#include <QSqlDatabase>
#include <QVariantList>

class Library : public QObject {
    Q_OBJECT
public:
    explicit Library(QObject *parent = nullptr);
    bool open();

    // bookmarks
    Q_INVOKABLE QVariantList bookmarks(const QString &ws) const;
    Q_INVOKABLE int addBookmark(const QString &ws, const QString &title, const QString &url, const QString &folder = {});
    Q_INVOKABLE void removeBookmark(int id);
    Q_INVOKABLE int bookmarkId(const QString &ws, const QString &url) const;   // 0 = not bookmarked

    // history
    Q_INVOKABLE void recordVisit(const QString &ws, const QString &url, const QString &title);
    Q_INVOKABLE QVariantList suggest(const QString &ws, const QString &text, int limit = 8) const;
    Q_INVOKABLE QVariantList history(const QString &ws, const QString &query, int limit = 300) const;
    Q_INVOKABLE void forget(const QString &ws, const QString &url);
    Q_INVOKABLE void clearHistory(const QString &ws);

    // logins: the site and username here, the password in the keyring
    Q_INVOKABLE QVariantList logins(const QString &ws, const QString &origin = {}) const;
    Q_INVOKABLE void saveLogin(const QString &ws, const QString &origin, const QString &username, const QString &password);
    Q_INVOKABLE void removeLogin(int id);
    // Fetch a password; answered by passwordReady(request, password).
    Q_INVOKABLE int fetchPassword(int loginId);

    // for the Chrome import (one transaction for thousands of rows)
    void begin();
    void commit();
    void importHistory(const QString &ws, const QString &url, const QString &title, int visits, qint64 lastVisitSecs);
    int importBookmark(const QString &ws, const QString &title, const QString &url, const QString &folder, qint64 added);

signals:
    void bookmarksChanged(const QString &ws);
    void loginsChanged(const QString &ws);
    void passwordReady(int request, const QString &password, const QString &error);

private:
    void storePassword(int loginId, const QString &password);
    QSqlDatabase m_db;
    int m_nextRequest = 1;
};
