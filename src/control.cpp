#include "control.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QStandardPaths>
#include <QTimer>

Control::Control(QObject *parent) : QObject(parent) {
    connect(&m_server, &QLocalServer::newConnection, this, &Control::onConnection);
}

bool Control::start() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (base.isEmpty()) base = QDir::tempPath();
    QDir().mkpath(base + "/ultimate");
    QFile::setPermissions(base + "/ultimate", QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    m_path = base + "/ultimate/browser.sock";
    QLocalServer::removeServer(m_path);          // a stale socket from a crashed run
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    return m_server.listen(m_path);
}

void Control::onConnection() {
    while (auto *s = m_server.nextPendingConnection()) {
        connect(s, &QLocalSocket::readyRead, this, [this, s] { onData(s); });
        connect(s, &QLocalSocket::disconnected, s, &QObject::deleteLater);
    }
}

void Control::onData(QLocalSocket *s) {
    while (s->canReadLine()) {
        const QByteArray line = s->readLine().trimmed();
        if (line.isEmpty()) continue;
        QJsonParseError err;
        const auto doc = QJsonDocument::fromJson(line, &err);
        const int request = m_next++;
        if (!doc.isObject()) {
            m_pending.insert(request, {s, QJsonValue()});
            fail(request, "not JSON: " + err.errorString());
            continue;
        }
        const QJsonObject o = doc.object();
        m_pending.insert(request, {s, o.value("id")});
        // Nothing waits for ever: an unanswered command fails after 30 s.
        QTimer::singleShot(30000, this, [this, request] {
            if (m_pending.contains(request)) fail(request, "timed out");
        });
        emit command(request, o.value("cmd").toString(), o.toVariantMap());
    }
}

void Control::send(int request, const QJsonObject &o) {
    const auto p = m_pending.take(request);
    if (!p.first) return;
    QJsonObject out = o;
    out.insert("id", p.second);
    p.first->write(QJsonDocument(out).toJson(QJsonDocument::Compact) + '\n');
    p.first->flush();
}

void Control::reply(int request, const QJsonValue &result) {
    send(request, {{"ok", true}, {"result", result}});
}

void Control::fail(int request, const QString &error) {
    send(request, {{"ok", false}, {"error", error}});
}
