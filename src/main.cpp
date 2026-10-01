// Ultimate Browser: Chromium (QtWebEngine) in a QML shell, with Claude built
// in, workspaces, tracker blocking and a line to Chris's phone.
// See docs/DESIGN.md.
#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QUrl>
#include <QtWebEngineQuick>

#include "blocker.h"
#include "chromeimport.h"
#include "library.h"
#include "opener.h"
#include "control.h"
#include "process.h"

int main(int argc, char *argv[]) {
    QCoreApplication::setOrganizationName("Ultimate Linux");
    QCoreApplication::setOrganizationDomain("ultimatelinux.org");
    QCoreApplication::setApplicationName("ultimate-browser");
    QCoreApplication::setApplicationVersion(UB_VERSION);
    // Chromium flags. Things this browser never does: phone home, pre-fetch
    // pages it guesses you'll visit, or report domain reliability.
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS",
            qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") +
            " --disable-domain-reliability --no-pings --disable-breakpad"
            " --enable-features=ParallelDownloading,WebRTCPipeWireCapturer"
            " --disable-features=NetworkPrediction,InterestFeedContentSuggestions");
    QtWebEngineQuick::initialize();
    QApplication app(argc, argv);
    QApplication::setApplicationDisplayName("Ultimate Browser");
    QApplication::setDesktopFileName("org.ultimatelinux.browser");
    app.setWindowIcon(QIcon::fromTheme("ultimate-browser", QIcon::fromTheme("web-browser")));
    QQuickStyle::setStyle("Basic");

    QCommandLineParser cli;
    cli.setApplicationDescription("Ultimate Browser");
    cli.addHelpOption();
    cli.addVersionOption();
    cli.addPositionalArgument("urls", "Pages to open", "[url...]");
    cli.process(app);

    // One browser: if it's already running, hand it the pages (links clicked
    // in other apps) over its control socket and stop. Two copies would fight
    // over the same profiles.
    {
        QString base = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
        QLocalSocket other;
        other.connectToServer(base + "/ultimate/browser.sock");
        if (other.waitForConnected(500)) {
            QStringList urls = cli.positionalArguments();
            int id = 1;
            auto send = [&](const QJsonObject &o) {
                other.write(QJsonDocument(o).toJson(QJsonDocument::Compact) + '\n');
                other.flush();
                other.waitForReadyRead(3000);
                other.readAll();
            };
            for (const QString &u : urls)
                send({{"id", id++}, {"cmd", "open"}, {"url", QUrl::fromUserInput(u).toString()}});
            send({{"id", id++}, {"cmd", "activate"}});
            return 0;
        }
    }

    Blocker blocker;
    const QString userLists = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/blocklists";
    QDir().mkpath(userLists);
    blocker.loadLists({QStringLiteral(UB_DATADIR "/blocklists"), userLists,
                       QCoreApplication::applicationDirPath() + "/../data/blocklists"});   // run from a build dir

    Control control;
    if (!control.start())
        qWarning("control socket unavailable: Claude can't see the browser");
    Process process;
    Opener opener;
    Library library;
    if (!library.open())
        qWarning("library unavailable: no bookmarks, history or saved logins this run");
    ChromeImport importer(&library);

    QQmlApplicationEngine engine;
    auto *ctx = engine.rootContext();
    ctx->setContextProperty("Blocker", &blocker);
    ctx->setContextProperty("BrowserControl", &control);
    ctx->setContextProperty("Proc", &process);
    ctx->setContextProperty("Library", &library);
    ctx->setContextProperty("Importer", &importer);
    ctx->setContextProperty("Opener", &opener);
    ctx->setContextProperty("StartUrls", cli.positionalArguments());
    ctx->setContextProperty("AppVersion", QStringLiteral(UB_VERSION));
    // Developer testing only: UB_DEBUG_EVAL=1 lets the control socket run a
    // script in a page ("eval"). Never set in normal use.
    ctx->setContextProperty("DebugEval", qgetenv("UB_DEBUG_EVAL") == "1");
    engine.loadFromModule("UltimateBrowser", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}
