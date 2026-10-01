#include "blocker.h"

#include <QDir>
#include <QFile>
#include <QMetaObject>
#include <QQuickWebEngineProfile>
#include <QSettings>
#include <QRegularExpression>
#include <QTextStream>

Blocker::Blocker(QObject *parent) : QWebEngineUrlRequestInterceptor(parent) {
    QSettings s;
    m_enabled = s.value("privacy/blocking", true).toBool();
    for (const auto &h : s.value("privacy/allowSites").toStringList())
        m_allowSites.insert(h);
}

void Blocker::loadLists(const QStringList &dirs) {
    QSet<QString> hosts;
    for (const auto &d : dirs) {
        const QDir dir(d);
        for (const auto &f : dir.entryList({"*.txt", "*.hosts"}, QDir::Files)) {
            QFile file(dir.filePath(f));
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
                continue;
            QTextStream in(&file);
            while (!in.atEnd()) {
                // "0.0.0.0 host", "127.0.0.1 host" or a bare "host"; # comments
                QString line = in.readLine();
                const int hash = line.indexOf('#');
                if (hash >= 0) line.truncate(hash);
                const auto parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                if (parts.isEmpty()) continue;
                const QString host = (parts.size() > 1 ? parts[1] : parts[0]).toLower();
                if (host.contains('.') && host != "localhost" && !host.startsWith("0.0.0.0"))
                    hosts.insert(host);
            }
        }
    }
    {
        QWriteLocker w(&m_lock);
        m_hosts = std::move(hosts);
    }
    emit listsChanged();
}

QString Blocker::site(const QString &host) {
    const auto labels = host.split('.');
    if (labels.size() <= 2) return host;
    // co.uk-style second-level domains: keep three labels
    const QString sl = labels[labels.size() - 2];
    const int keep = (sl.size() <= 3 && labels.last().size() == 2) ? 3 : 2;
    return labels.mid(labels.size() - keep).join('.');
}

bool Blocker::listedHost(const QString &host) const {
    // tracker.ads.example.com -> check it, ads.example.com, example.com
    QString h = host;
    while (true) {
        if (m_hosts.contains(h)) return true;
        const int dot = h.indexOf('.');
        if (dot < 0 || h.indexOf('.', dot + 1) < 0) return false;
        h = h.mid(dot + 1);
    }
}

void Blocker::interceptRequest(QWebEngineUrlRequestInfo &info) {
    if (!m_enabled) return;
    const QString host = info.requestUrl().host().toLower();
    const QString page = info.firstPartyUrl().host().toLower();
    if (host.isEmpty()) return;
    // Never block the page itself, or its own site's requests.
    if (info.resourceType() == QWebEngineUrlRequestInfo::ResourceTypeMainFrame) return;
    if (!page.isEmpty() && site(host) == site(page)) return;
    {
        QReadLocker r(&m_lock);
        if (m_allowSites.contains(site(page)) || !listedHost(host)) return;
    }
    info.block(true);
    int n;
    {
        QWriteLocker w(&m_lock);
        n = ++m_counts[page];
    }
    QMetaObject::invokeMethod(this, [this, page, n] { emit blocked(page, n); }, Qt::QueuedConnection);
}

int Blocker::blockedOn(const QString &host) const {
    QReadLocker r(&m_lock);
    return m_counts.value(host.toLower());
}

void Blocker::setEnabled(bool on) {
    if (on == m_enabled) return;
    m_enabled = on;
    QSettings().setValue("privacy/blocking", on);
    emit enabledChanged();
}

void Blocker::allowSite(const QString &host, bool allow) {
    const QString s = site(host.toLower());
    {
        QWriteLocker w(&m_lock);
        if (allow) m_allowSites.insert(s); else m_allowSites.remove(s);
        QSettings().setValue("privacy/allowSites", QStringList(m_allowSites.begin(), m_allowSites.end()));
    }
    emit listsChanged();
}

bool Blocker::siteAllowed(const QString &host) const {
    QReadLocker r(&m_lock);
    return m_allowSites.contains(site(host.toLower()));
}

void Blocker::attach(QObject *profile) {
    if (auto *p = qobject_cast<QQuickWebEngineProfile *>(profile))
        p->setUrlRequestInterceptor(this);
}
