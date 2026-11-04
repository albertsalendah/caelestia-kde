# Standalone build of KDE's XEmbed-to-StatusNotifier proxy (xembed-sni-proxy), which turns the
# tray icons of old X11 apps (Java, Compose, GTK2, ...) into StatusNotifierItems the shell shows.
# KDE ships it only inside plasma-workspace; a Plasma-free install builds this copy instead.
# See NOTICE.md for where the sources come from.

cmake_minimum_required(VERSION 3.16)
project(caelestia-xembedsniproxy VERSION 6.8.2 LANGUAGES CXX)

find_package(ECM REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(GNUInstallDirs)
include(ECMQtDeclareLoggingCategory)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui DBus)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6DBusAddons REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Crash REQUIRED)
find_package(X11 REQUIRED)
find_package(XCB REQUIRED COMPONENTS XCB XFIXES DAMAGE COMPOSITE RANDR SHM UTIL IMAGE ICCCM)

if(NOT TARGET X11::Xtst)
    message(FATAL_ERROR "libXtst (X11::Xtst) was not found")
endif()

configure_file(config-workspace.h.in config-workspace.h @ONLY)

set(XEMBED_SNI_PROXY_SOURCES
    main.cpp
    fdoselectionmanager.cpp fdoselectionmanager.h
    snidbus.cpp snidbus.h
    sniproxy.cpp
    xtestsender.cpp xtestsender.h
)

qt_add_dbus_adaptor(XEMBED_SNI_PROXY_SOURCES org.kde.StatusNotifierItem.xml
                    sniproxy.h SNIProxy)

qt_add_dbus_interface(XEMBED_SNI_PROXY_SOURCES org.kde.StatusNotifierWatcher.xml
                      statusnotifierwatcher_interface)

ecm_qt_declare_logging_category(XEMBED_SNI_PROXY_SOURCES
    HEADER debug.h
    IDENTIFIER SNIPROXY
    CATEGORY_NAME kde.xembedsniproxy
    DEFAULT_SEVERITY Info
    DESCRIPTION "xembed sni proxy"
)

add_executable(xembedsniproxy ${XEMBED_SNI_PROXY_SOURCES})
set_target_properties(xembedsniproxy PROPERTIES OUTPUT_NAME caelestia-xembedsniproxy)
target_include_directories(xembedsniproxy PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(xembedsniproxy
    Qt6::Core
    Qt6::Gui
    Qt6::DBus
    KF6::DBusAddons
    KF6::WindowSystem
    KF6::CoreAddons
    KF6::Crash
    XCB::XCB
    XCB::XFIXES
    XCB::DAMAGE
    XCB::COMPOSITE
    XCB::RANDR
    XCB::SHM
    XCB::UTIL
    XCB::IMAGE
    XCB::ICCCM
    X11::Xtst
)

install(TARGETS xembedsniproxy RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
