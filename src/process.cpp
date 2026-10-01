#include "process.h"

#include <QProcess>
#include <QTimer>

void Process::run(const QString &tag, const QStringList &argv, int timeoutMs) {
    if (argv.isEmpty()) return;
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::SeparateChannels);
    connect(p, &QProcess::finished, this, [this, p, tag](int code, QProcess::ExitStatus) {
        emit finished(tag, code, QString::fromUtf8(p->readAllStandardOutput()),
                      QString::fromUtf8(p->readAllStandardError()));
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, tag](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            emit finished(tag, -1, QString(), p->errorString());
            p->deleteLater();
        }
    });
    QTimer::singleShot(timeoutMs, p, [p] { if (p->state() != QProcess::NotRunning) p->kill(); });
    p->start(argv.first(), argv.mid(1));
}
