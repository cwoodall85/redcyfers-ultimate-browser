cmake_minimum_required(VERSION 3.21)
project(ultimate-browser VERSION 0.3.7 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Widgets Network Qml Quick QuickControls2 Sql WebChannel WebChannelQuick WebEngineCore WebEngineQuick)
find_package(Qt6Keychain REQUIRED)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(ultimate-browser
    src/main.cpp
    src/blocker.cpp src/blocker.h
    src/control.cpp src/control.h
    src/process.cpp src/process.h
    src/library.cpp src/library.h
    src/chromeimport.cpp src/chromeimport.h
    src/opener.cpp src/opener.h
)
# must come before qt_add_qml_module, or Theme isn't a singleton
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# imported by path from Main.qml, not a module-wide script
set_source_files_properties(qml/Page.js PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY TRUE)
qt_add_qml_module(ultimate-browser
    URI UltimateBrowser
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/TabList.qml
        qml/AddressBar.qml
        qml/ClaudePanel.qml
        qml/FindBar.qml
        qml/Downloads.qml
        qml/Theme.qml
        qml/BookmarksBar.qml
        qml/Suggestions.qml
        qml/HistoryPanel.qml
        qml/PasswordsPanel.qml
        qml/ImportDialog.qml
        qml/LoginBar.qml
        qml/Page.js
)

# page scripts run in the browser's own isolated world (autofill)
qt_add_resources(ultimate-browser "scripts" PREFIX "/ub" FILES scripts/autofill.js scripts/select.js)

target_compile_definitions(ultimate-browser PRIVATE
    UB_VERSION="${PROJECT_VERSION}"
    UB_DATADIR="${CMAKE_INSTALL_PREFIX}/share/ultimate-browser")
target_link_libraries(ultimate-browser PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2
    Qt6::Sql Qt6::WebChannel Qt6::WebChannelQuick Qt6::WebEngineCore Qt6::WebEngineQuick qt6keychain)

include(GNUInstallDirs)
install(TARGETS ultimate-browser RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(DIRECTORY data/blocklists DESTINATION ${CMAKE_INSTALL_DATADIR}/ultimate-browser)
install(FILES data/workspace-rules.json DESTINATION ${CMAKE_INSTALL_DATADIR}/ultimate-browser)
install(FILES data/org.ultimatelinux.browser.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/ultimate-browser.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES mcp/ultimate_browser.py DESTINATION lib/ultimate/mcp.d)
