#include "chromeimport.h"
#include "library.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

ChromeImport::ChromeImport(Library *library, QObject *parent) : QObject(parent), m_lib(library) {
    loadRules();
}

QString ChromeImport::profileDir() const {
    return QDir::homePath() + "/.config/google-chrome/Default";
}

void ChromeImport::loadRules() {
    const QString cfg = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    const QString mine = cfg + "/workspace-rules.json";
    if (!QFile::exists(mine)) {
        QDir().mkpath(cfg);
        for (const QString &d : {QStringLiteral(UB_DATADIR), QCoreApplication::applicationDirPath() + "/../data"})
            if (QFile::copy(d + "/workspace-rules.json", mine)) { QFile(mine).setPermissions(QFile::ReadOwner | QFile::WriteOwner); break; }
    }
    QFile f(mine);
    if (!f.open(QIODevice::ReadOnly)) return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    m_default = o.value("default").toString("Personal");
    m_order = {};
    for (auto it = o.begin(); it != o.end(); ++it) {
        if (it.key().startsWith('_') || it.key() == "default") continue;
        QStringList pats;
        for (const auto &v : it.value().toArray()) pats << v.toString().toLower();
        m_rules.insert(it.key(), pats);
        m_order << it.key();
    }
    if (!m_order.contains(m_default)) m_order.prepend(m_default);
}

QString ChromeImport::wsFor(const QString &host) const {
    const QString h = host.toLower();
    QHostAddress addr(h);
    for (const QString &ws : m_order) {
        for (const QString &p : m_rules.value(ws)) {
            if (p.contains('/')) {
                if (!addr.isNull() && addr.isInSubnet(QHostAddress::parseSubnet(p))) return ws;
            } else if (h == p || h.endsWith('.' + p)) {
                return ws;
            }
        }
    }
    return m_default;
}

QString ChromeImport::findExport() const {
    QFileInfo best;
    for (auto loc : {QStandardPaths::DocumentsLocation, QStandardPaths::DownloadLocation}) {
        const QDir d(QStandardPaths::writableLocation(loc));
        for (const QFileInfo &f : d.entryInfoList({"*assword*.csv"}, QDir::Files))
            if (!best.exists() || f.lastModified() > best.lastModified()) best = f;
    }
    return best.exists() ? best.absoluteFilePath() : QString();
}

static qint64 chromeTime(qint64 us) {          // microseconds since 1601 -> unix seconds
    return us > 0 ? us / 1000000 - 11644473600LL : 0;
}

// RFC 4180-ish CSV: quoted fields, doubled quotes, newlines inside quotes.
static QList<QStringList> parseCsv(const QString &text) {
    QList<QStringList> rows;
    QStringList row;
    QString field;
    bool quoted = false;
    for (int i = 0; i < text.size(); ++i) {
        const QChar c = text[i];
        if (quoted) {
            if (c == '"' && i + 1 < text.size() && text[i + 1] == '"') { field += '"'; ++i; }
            else if (c == '"') quoted = false;
            else field += c;
        } else if (c == '"') quoted = true;
        else if (c == ',') { row << field; field.clear(); }
        else if (c == '\n' || c == '\r') {
            if (c == '\r' && i + 1 < text.size() && text[i + 1] == '\n') ++i;
            row << field; field.clear();
            if (!(row.size() == 1 && row[0].isEmpty())) rows << row;
            row.clear();
        } else field += c;
    }
    if (!field.isEmpty() || !row.isEmpty()) { row << field; rows << row; }
    return rows;
}

QVariantMap ChromeImport::scan(const QString &passwordsCsv) {
    cancel();
    QStringList errors;
    const QString dir = profileDir();

    // bookmarks: the signed-in account's file and the local one
    std::function<void(const QJsonObject &, const QString &)> walk = [&](const QJsonObject &n, const QString &folder) {
        if (n.value("type").toString() == "url") {
            const QString url = n.value("url").toString();
            if (url.startsWith("http"))
                m_bookmarks.push_back({n.value("name").toString(), url, folder, chromeTime(n.value("date_added").toString().toLongLong())});
            return;
        }
        const QString name = n.value("name").toString();
        const QString sub = folder.isEmpty() || folder == "Bookmarks bar" ? (name == "Bookmarks bar" ? QString() : name) : folder + "/" + name;
        for (const auto &c : n.value("children").toArray()) walk(c.toObject(), sub);
    };
    for (const QString &file : {QStringLiteral("AccountBookmarks"), QStringLiteral("Bookmarks")}) {
        QFile f(dir + "/" + file);
        if (!f.open(QIODevice::ReadOnly)) continue;
        const QJsonObject roots = QJsonDocument::fromJson(f.readAll()).object().value("roots").toObject();
        for (auto it = roots.begin(); it != roots.end(); ++it)
            if (it.value().isObject()) walk(it.value().toObject(), QString());
    }

    // history: from a copy (Chrome keeps its database locked while running)
    QTemporaryDir tmp;
    if (QFile::copy(dir + "/History", tmp.filePath("History"))) {
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "chrome-history");
            db.setDatabaseName(tmp.filePath("History"));
            if (db.open()) {
                QSqlQuery q("SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0", db);
                while (q.next()) {
                    const QString url = q.value(0).toString();
                    if (url.startsWith("http"))
                        m_pages.push_back({url, q.value(1).toString(), q.value(2).toInt(), chromeTime(q.value(3).toLongLong())});
                }
            } else errors << "couldn't open Chrome's history";
        }
        QSqlDatabase::removeDatabase("chrome-history");
    } else errors << "no Chrome history found";

    // passwords: Chrome's export (name,url,username,password,note)
    if (!passwordsCsv.isEmpty()) {
        QFile f(QUrl(passwordsCsv).isLocalFile() ? QUrl(passwordsCsv).toLocalFile() : passwordsCsv);
        if (f.open(QIODevice::ReadOnly)) {
            m_csv = f.fileName();
            const auto rows = parseCsv(QString::fromUtf8(f.readAll()));
            int iu = 1, iuser = 2, ipass = 3;
            if (!rows.isEmpty()) {
                const QStringList h = rows.first();
                iu = h.indexOf("url"); iuser = h.indexOf("username"); ipass = h.indexOf("password");
            }
            if (iu < 0 || ipass < 0) errors << "that file doesn't look like Chrome's password export";
            else for (int r = 1; r < rows.size(); ++r) {
                const QStringList &row = rows[r];
                if (row.size() <= qMax(iu, ipass)) continue;
                const QUrl u(row[iu]);
                if (!u.scheme().startsWith("http") || row[ipass].isEmpty()) continue;
                m_logins.push_back({u.scheme() + "://" + u.host() + (u.port() > 0 ? ":" + QString::number(u.port()) : QString()),
                                    iuser >= 0 ? row[iuser] : QString(), row[ipass]});
            }
        } else errors << "couldn't read " + passwordsCsv;
    }

    // per-site summary for the review
    struct Site { int b = 0, p = 0, l = 0; };
    QHash<QString, Site> sites;
    for (const auto &b : m_bookmarks) sites[QUrl(b.url).host()].b++;
    for (const auto &p : m_pages) sites[QUrl(p.url).host()].p++;
    for (const auto &l : m_logins) sites[QUrl(l.origin).host()].l++;
    QVariantList list;
    QVariantMap totals;
    for (auto it = sites.begin(); it != sites.end(); ++it) {
        const QString ws = wsFor(it.key());
        list << QVariantMap{{"host", it.key()}, {"ws", ws}, {"bookmarks", it->b}, {"pages", it->p}, {"logins", it->l}};
        QVariantMap t = totals.value(ws).toMap();
        t["bookmarks"] = t.value("bookmarks").toInt() + it->b;
        t["pages"] = t.value("pages").toInt() + it->p;
        t["logins"] = t.value("logins").toInt() + it->l;
        totals[ws] = t;
    }
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        const auto x = a.toMap(), y = b.toMap();
        const int wx = x["bookmarks"].toInt() * 1000 + x["logins"].toInt() * 100 + x["pages"].toInt();
        const int wy = y["bookmarks"].toInt() * 1000 + y["logins"].toInt() * 100 + y["pages"].toInt();
        return wx > wy;
    });
    return {{"sites", list}, {"totals", totals}, {"csv", m_csv}, {"errors", errors},
            {"bookmarks", m_bookmarks.size()}, {"pages", m_pages.size()}, {"logins", m_logins.size()}};
}

QVariantMap ChromeImport::apply(const QVariantMap &overrides) {
    auto ws = [&](const QString &host) { return overrides.contains(host) ? overrides.value(host).toString() : wsFor(host); };
    int b = 0, p = 0, l = 0;
    m_lib->begin();
    for (const auto &x : m_bookmarks) { m_lib->importBookmark(ws(QUrl(x.url).host()), x.title, x.url, x.folder, x.added); b++; }
    for (const auto &x : m_pages) { m_lib->importHistory(ws(QUrl(x.url).host()), x.url, x.title, x.visits, x.last); p++; }
    m_lib->commit();
    for (const auto &x : m_logins) { m_lib->saveLogin(ws(QUrl(x.origin).host()), x.origin, x.username, x.password); l++; }
    // The export is every password in plain text: overwrite it, then delete it.
    bool removed = false;
    if (!m_csv.isEmpty()) {
        QFile f(m_csv);
        if (f.open(QIODevice::ReadWrite)) {
            f.write(QByteArray(f.size(), '\0'));
            f.flush();
            f.close();
        }
        removed = QFile::remove(m_csv);
    }
    const QString csv = m_csv;
    cancel();
    for (const QString &w : m_order) emit m_lib->bookmarksChanged(w);
    return {{"bookmarks", b}, {"pages", p}, {"logins", l}, {"csvRemoved", removed}, {"csv", csv}};
}

void ChromeImport::cancel() {
    for (auto &x : m_logins) x.password.fill(QChar(0));
    m_logins.clear();
    m_bookmarks.clear();
    m_pages.clear();
    m_csv.clear();
}
