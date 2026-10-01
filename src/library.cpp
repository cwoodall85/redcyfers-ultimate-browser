#include "library.h"

#include <QDateTime>
#include <QDir>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUrl>
#include <QSet>
#include <QVariantMap>
#include <qt6keychain/keychain.h>

// Tests set UB_KEYCHAIN_SERVICE so a throwaway profile can never touch the
// real profile's keyring entries (login ids would collide).
static QString keychainService() {
    const QByteArray s = qgetenv("UB_KEYCHAIN_SERVICE");
    return s.isEmpty() ? QStringLiteral("ultimate-browser") : QString::fromUtf8(s);
}
#define KEYCHAIN_SERVICE keychainService()

Library::Library(QObject *parent) : QObject(parent) {}

bool Library::open() {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    m_db = QSqlDatabase::addDatabase("QSQLITE", "library");
    m_db.setDatabaseName(dir + "/library.db");
    if (!m_db.open()) {
        qWarning("library: %s", qPrintable(m_db.lastError().text()));
        return false;
    }
    QSqlQuery q(m_db);
    q.exec("PRAGMA journal_mode=WAL");
    q.exec("CREATE TABLE IF NOT EXISTS bookmarks (id INTEGER PRIMARY KEY, ws TEXT NOT NULL, title TEXT, url TEXT NOT NULL,"
           " folder TEXT DEFAULT '', position INTEGER DEFAULT 0, added INTEGER)");
    q.exec("CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, ws TEXT NOT NULL, url TEXT NOT NULL, title TEXT,"
           " visits INTEGER DEFAULT 1, last_visit INTEGER, UNIQUE(ws, url))");
    q.exec("CREATE INDEX IF NOT EXISTS history_rank ON history (ws, visits DESC)");
    q.exec("CREATE TABLE IF NOT EXISTS logins (id INTEGER PRIMARY KEY, ws TEXT NOT NULL, origin TEXT NOT NULL,"
           " username TEXT, created INTEGER, last_used INTEGER, UNIQUE(ws, origin, username))");
    return true;
}

static QString originOf(const QString &url) {
    const QUrl u(url);
    return u.scheme().isEmpty() ? url : u.scheme() + "://" + u.host() + (u.port() > 0 ? ":" + QString::number(u.port()) : QString());
}

// ---- bookmarks ---------------------------------------------------------------

QVariantList Library::bookmarks(const QString &ws) const {
    QVariantList out;
    QSqlQuery q(m_db);
    q.prepare("SELECT id, title, url, folder FROM bookmarks WHERE ws = ? ORDER BY position, id");
    q.addBindValue(ws);
    q.exec();
    while (q.next())
        out << QVariantMap{{"id", q.value(0)}, {"title", q.value(1)}, {"url", q.value(2)}, {"folder", q.value(3)}};
    return out;
}

int Library::importBookmark(const QString &ws, const QString &title, const QString &url, const QString &folder, qint64 added) {
    if (bookmarkId(ws, url)) return bookmarkId(ws, url);
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO bookmarks (ws, title, url, folder, position, added)"
              " VALUES (?, ?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM bookmarks WHERE ws = ?), ?)");
    q.addBindValue(ws); q.addBindValue(title); q.addBindValue(url); q.addBindValue(folder); q.addBindValue(ws); q.addBindValue(added);
    q.exec();
    return q.lastInsertId().toInt();
}

int Library::addBookmark(const QString &ws, const QString &title, const QString &url, const QString &folder) {
    const int id = importBookmark(ws, title, url, folder, QDateTime::currentSecsSinceEpoch());
    emit bookmarksChanged(ws);
    return id;
}

void Library::removeBookmark(int id) {
    QSqlQuery q(m_db);
    q.prepare("SELECT ws FROM bookmarks WHERE id = ?"); q.addBindValue(id); q.exec();
    const QString ws = q.next() ? q.value(0).toString() : QString();
    q.prepare("DELETE FROM bookmarks WHERE id = ?"); q.addBindValue(id); q.exec();
    emit bookmarksChanged(ws);
}

int Library::bookmarkId(const QString &ws, const QString &url) const {
    QSqlQuery q(m_db);
    q.prepare("SELECT id FROM bookmarks WHERE ws = ? AND url = ?");
    q.addBindValue(ws); q.addBindValue(url); q.exec();
    return q.next() ? q.value(0).toInt() : 0;
}

// ---- history -----------------------------------------------------------------

void Library::recordVisit(const QString &ws, const QString &url, const QString &title) {
    if (!url.startsWith("http")) return;
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO history (ws, url, title, visits, last_visit) VALUES (?, ?, ?, 1, ?)"
              " ON CONFLICT(ws, url) DO UPDATE SET visits = visits + 1, last_visit = excluded.last_visit,"
              " title = CASE WHEN excluded.title != '' THEN excluded.title ELSE title END");
    q.addBindValue(ws); q.addBindValue(url); q.addBindValue(title); q.addBindValue(QDateTime::currentSecsSinceEpoch());
    q.exec();
}

void Library::importHistory(const QString &ws, const QString &url, const QString &title, int visits, qint64 last) {
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO history (ws, url, title, visits, last_visit) VALUES (?, ?, ?, ?, ?)"
              " ON CONFLICT(ws, url) DO UPDATE SET visits = MAX(visits, excluded.visits),"
              " last_visit = MAX(last_visit, excluded.last_visit)");
    q.addBindValue(ws); q.addBindValue(url); q.addBindValue(title); q.addBindValue(qMax(1, visits)); q.addBindValue(last);
    q.exec();
}

// Typed text -> the best matches from bookmarks and history: the host or
// title starting with it ranks first, then anything containing it; ties by
// how often it's visited.
QVariantList Library::suggest(const QString &ws, const QString &text, int limit) const {
    QVariantList out;
    const QString t = text.trimmed();
    if (t.isEmpty()) return out;
    QSqlQuery q(m_db);
    q.prepare("SELECT url, title, visits, 0 AS starred FROM history WHERE ws = :ws AND (url LIKE :any OR title LIKE :any)"
              " UNION ALL SELECT url, title, 1000000, 1 FROM bookmarks WHERE ws = :ws AND (url LIKE :any OR title LIKE :any)"
              " ORDER BY (CASE WHEN url LIKE :host1 OR url LIKE :host2 OR title LIKE :start THEN 0 ELSE 1 END), 3 DESC LIMIT :lim");
    q.bindValue(":ws", ws);
    q.bindValue(":any", "%" + t + "%");
    q.bindValue(":host1", "%://" + t + "%");
    q.bindValue(":host2", "%://www." + t + "%");
    q.bindValue(":start", t + "%");
    q.bindValue(":lim", limit * 2);
    q.exec();
    QSet<QString> seen;
    while (q.next() && out.size() < limit) {
        const QString url = q.value(0).toString();
        if (seen.contains(url)) continue;
        seen.insert(url);
        out << QVariantMap{{"url", url}, {"title", q.value(1)}, {"starred", q.value(3).toInt() == 1}};
    }
    return out;
}

QVariantList Library::history(const QString &ws, const QString &query, int limit) const {
    QVariantList out;
    QSqlQuery q(m_db);
    q.prepare("SELECT url, title, visits, last_visit FROM history WHERE ws = ? AND (url LIKE ? OR title LIKE ?)"
              " ORDER BY last_visit DESC LIMIT ?");
    q.addBindValue(ws); q.addBindValue("%" + query + "%"); q.addBindValue("%" + query + "%"); q.addBindValue(limit);
    q.exec();
    while (q.next())
        out << QVariantMap{{"url", q.value(0)}, {"title", q.value(1)}, {"visits", q.value(2)},
                           {"when", QDateTime::fromSecsSinceEpoch(q.value(3).toLongLong()).toString("ddd d MMM yyyy, HH:mm")}};
    return out;
}

void Library::forget(const QString &ws, const QString &url) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM history WHERE ws = ? AND url = ?"); q.addBindValue(ws); q.addBindValue(url); q.exec();
}

void Library::clearHistory(const QString &ws) {
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM history WHERE ws = ?"); q.addBindValue(ws); q.exec();
}

void Library::begin() { m_db.transaction(); }
void Library::commit() { m_db.commit(); }

// ---- logins --------------------------------------------------------------------

QVariantList Library::logins(const QString &ws, const QString &origin) const {
    QVariantList out;
    QSqlQuery q(m_db);
    if (origin.isEmpty()) {
        q.prepare("SELECT id, origin, username, last_used FROM logins WHERE ws = ? ORDER BY origin, username");
        q.addBindValue(ws);
    } else {
        // the same site (exact origin), or the same host on either http/https
        const QUrl u(origin);
        q.prepare("SELECT id, origin, username, last_used FROM logins WHERE ws = ? AND (origin = ? OR origin LIKE ?)"
                  " ORDER BY last_used DESC");
        q.addBindValue(ws); q.addBindValue(originOf(origin)); q.addBindValue("%://" + u.host());
    }
    q.exec();
    while (q.next())
        out << QVariantMap{{"id", q.value(0)}, {"origin", q.value(1)}, {"username", q.value(2)}};
    return out;
}

void Library::saveLogin(const QString &ws, const QString &origin, const QString &username, const QString &password) {
    const QString o = originOf(origin);
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO logins (ws, origin, username, created, last_used) VALUES (?, ?, ?, ?, ?)"
              " ON CONFLICT(ws, origin, username) DO UPDATE SET last_used = excluded.last_used");
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    q.addBindValue(ws); q.addBindValue(o); q.addBindValue(username); q.addBindValue(now); q.addBindValue(now);
    q.exec();
    q.prepare("SELECT id FROM logins WHERE ws = ? AND origin = ? AND username = ?");
    q.addBindValue(ws); q.addBindValue(o); q.addBindValue(username); q.exec();
    if (q.next()) storePassword(q.value(0).toInt(), password);
    emit loginsChanged(ws);
}

void Library::storePassword(int loginId, const QString &password) {
    auto *job = new QKeychain::WritePasswordJob(KEYCHAIN_SERVICE, this);
    job->setKey(QStringLiteral("login-%1").arg(loginId));
    job->setTextData(password);
    connect(job, &QKeychain::Job::finished, this, [](QKeychain::Job *j) {
        if (j->error()) qWarning("keyring: could not save a password: %s", qPrintable(j->errorString()));
    });
    job->start();
}

void Library::removeLogin(int id) {
    QSqlQuery q(m_db);
    q.prepare("SELECT ws FROM logins WHERE id = ?"); q.addBindValue(id); q.exec();
    const QString ws = q.next() ? q.value(0).toString() : QString();
    q.prepare("DELETE FROM logins WHERE id = ?"); q.addBindValue(id); q.exec();
    auto *job = new QKeychain::DeletePasswordJob(KEYCHAIN_SERVICE, this);
    job->setKey(QStringLiteral("login-%1").arg(id));
    job->start();
    emit loginsChanged(ws);
}

int Library::fetchPassword(int loginId) {
    const int request = m_nextRequest++;
    auto *job = new QKeychain::ReadPasswordJob(KEYCHAIN_SERVICE, this);
    job->setKey(QStringLiteral("login-%1").arg(loginId));
    connect(job, &QKeychain::Job::finished, this, [this, request, loginId](QKeychain::Job *j) {
        auto *r = static_cast<QKeychain::ReadPasswordJob *>(j);
        emit passwordReady(request, r->error() ? QString() : r->textData(), r->error() ? r->errorString() : QString());
        if (!r->error()) {
            QSqlQuery q(m_db);
            q.prepare("UPDATE logins SET last_used = ? WHERE id = ?");
            q.addBindValue(QDateTime::currentSecsSinceEpoch()); q.addBindValue(loginId); q.exec();
        }
    });
    job->start();
    return request;
}
