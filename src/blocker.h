// Ad and tracker blocking: every request the page makes passes through
// interceptRequest(); requests to a listed host (or any subdomain of one)
// from a different site are blocked. Lists are plain hosts files, loaded
// from the system data dir and the user's (updatable) copy.
#pragma once
#include <QHash>
#include <QObject>
#include <QReadWriteLock>
#include <QSet>
#include <QWebEngineUrlRequestInterceptor>

class Blocker : public QWebEngineUrlRequestInterceptor {
    Q_OBJECT
    Q_PROPERTY(int listed READ listed NOTIFY listsChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
public:
    explicit Blocker(QObject *parent = nullptr);
    void loadLists(const QStringList &dirs);
    void interceptRequest(QWebEngineUrlRequestInfo &info) override;

    int listed() const { return m_hosts.size(); }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);

    // Blocked requests on a page, by the page's host (the address bar shows it).
    Q_INVOKABLE int blockedOn(const QString &host) const;
    // Turn blocking off for one site (it breaks something there), or back on.
    Q_INVOKABLE void allowSite(const QString &host, bool allow);
    Q_INVOKABLE bool siteAllowed(const QString &host) const;
    // Attach to a WebEngineProfile created in QML.
    Q_INVOKABLE void attach(QObject *profile);

signals:
    void listsChanged();
    void enabledChanged();
    void blocked(const QString &pageHost, int count);

private:
    bool listedHost(const QString &host) const;
    static QString site(const QString &host);   // last two labels: tracking.example.com -> example.com
    mutable QReadWriteLock m_lock;
    QSet<QString> m_hosts;
    QSet<QString> m_allowSites;
    QHash<QString, int> m_counts;
    bool m_enabled = true;
};
