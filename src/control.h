// The browser's control socket: how Claude (and anything else of Chris's)
// sees and drives the browser. $XDG_RUNTIME_DIR/ultimate/browser.sock,
// user-only. One JSON object per line in, one per line out:
//   {"id": 1, "cmd": "tabs"}                 -> {"id": 1, "ok": true, "result": [...]}
//   {"id": 2, "cmd": "read", "tab": 7}       -> page title, address and text
//   {"id": 3, "cmd": "click", "tab": 7, "element": 12}
// The work is done in QML (it owns the tabs): C++ passes each command on
// as command(), and QML answers with reply().
#pragma once
#include <QHash>
#include <QJsonValue>
#include <QLocalServer>
#include <QObject>
#include <QPointer>

class QLocalSocket;

class Control : public QObject {
    Q_OBJECT
public:
    explicit Control(QObject *parent = nullptr);
    bool start();
    QString path() const { return m_path; }

    Q_INVOKABLE void reply(int request, const QJsonValue &result);
    Q_INVOKABLE void fail(int request, const QString &error);

signals:
    // request: this socket request; cmd + args as sent
    void command(int request, const QString &cmd, const QVariantMap &args);

private:
    void onConnection();
    void onData(QLocalSocket *s);
    void send(int request, const QJsonObject &o);
    QLocalServer m_server;
    QString m_path;
    int m_next = 1;
    QHash<int, QPair<QPointer<QLocalSocket>, QJsonValue>> m_pending;   // our id -> (socket, caller's id)
};
