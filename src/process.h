// Run a program for QML and hand back what it printed: the Claude panel
// drives the Claude bar's backend (ultimate-claude-bar) this way, and "send
// to phone" posts through `ultimate-mail chat post`. argv, never a shell.
#pragma once
#include <QObject>
#include <QStringList>

class Process : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    // tag comes back with the result, so one Process can serve many callers.
    Q_INVOKABLE void run(const QString &tag, const QStringList &argv, int timeoutMs = 30000);
signals:
    void finished(const QString &tag, int code, const QString &out, const QString &err);
};
