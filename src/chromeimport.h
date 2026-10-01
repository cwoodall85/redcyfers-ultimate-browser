// "Import from Chrome": bookmarks and history read straight from Chrome's
// profile (copies; Chrome is never changed), passwords from the CSV Chrome
// exports (Google Password Manager -> Settings -> Export passwords). Every
// site is sorted into a workspace by the rules (workspace-rules.json); the
// review screen gets sites and usernames only -- passwords stay in this
// object until apply() writes them to the keyring, then the CSV is
// overwritten and deleted.
#pragma once
#include <QHash>
#include <QObject>
#include <QVariantMap>
#include <QVector>

class Library;

class ChromeImport : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString profileDir READ profileDir CONSTANT)
public:
    ChromeImport(Library *library, QObject *parent = nullptr);
    QString profileDir() const;

    // Read everything; returns {sites: [{host, ws, bookmarks, pages, logins}],
    // totals: {...}, csv: path or "", errors: [...]}. No passwords.
    Q_INVOKABLE QVariantMap scan(const QString &passwordsCsv);
    // Import, with any per-site workspace changes from the review: {host: ws}.
    Q_INVOKABLE QVariantMap apply(const QVariantMap &overrides);
    // Forget what was scanned (and the passwords) without importing.
    Q_INVOKABLE void cancel();

    // Chrome's password export, if it's in Documents or Downloads (newest).
    Q_INVOKABLE QString findExport() const;
    Q_INVOKABLE QString wsFor(const QString &host) const;
    Q_INVOKABLE QStringList workspaces() const { return m_order; }

private:
    void loadRules();
    struct Bookmark { QString title, url, folder; qint64 added; };
    struct Page { QString url, title; int visits; qint64 last; };
    struct Login { QString origin, username, password; };
    Library *m_lib;
    QString m_csv;
    QVector<Bookmark> m_bookmarks;
    QVector<Page> m_pages;
    QVector<Login> m_logins;
    QHash<QString, QStringList> m_rules;   // ws -> host patterns
    QStringList m_order;                   // workspaces in rule order
    QString m_default = "Personal";
};
