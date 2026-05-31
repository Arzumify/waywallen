module;
#include "waywallen/ui_settings.moc.h"
#include <QSettings>

module waywallen;
import :ui_settings;
import :app;

using namespace Qt::Literals::StringLiterals;

namespace waywallen
{

UiSettings* UiSettings::instance() {
    static UiSettings* the = new UiSettings(App::instance());
    return the;
}

UiSettings* UiSettings::create(QQmlEngine*, QJSEngine*) {
    auto t = instance();
    QJSEngine::setObjectOwnership(t, QJSEngine::CppOwnership);
    return t;
}

UiSettings::UiSettings(QObject* parent): QObject(parent), m_store() {}
UiSettings::~UiSettings() = default;

bool UiSettings::saveWindowSize() const {
    return m_store.value(u"window/save"_s, true).toBool();
}

void UiSettings::setSaveWindowSize(bool v) {
    if (v == saveWindowSize()) return;
    m_store.setValue(u"window/save"_s, v);
    Q_EMIT saveWindowSizeChanged();
}

int UiSettings::windowWidth() const {
    return m_store.value(u"window/width"_s, 0).toInt();
}

void UiSettings::setWindowWidth(int v) {
    if (v == windowWidth()) return;
    m_store.setValue(u"window/width"_s, v);
    Q_EMIT windowWidthChanged();
}

int UiSettings::windowHeight() const {
    return m_store.value(u"window/height"_s, 0).toInt();
}

void UiSettings::setWindowHeight(int v) {
    if (v == windowHeight()) return;
    m_store.setValue(u"window/height"_s, v);
    Q_EMIT windowHeightChanged();
}

bool UiSettings::sidebarAutoExpand() const {
    return m_store.value(u"sidebar/autoExpand"_s, true).toBool();
}

void UiSettings::setSidebarAutoExpand(bool v) {
    if (v == sidebarAutoExpand()) return;
    m_store.setValue(u"sidebar/autoExpand"_s, v);
    Q_EMIT sidebarAutoExpandChanged();
}

bool UiSettings::sidebarExpanded() const {
    return m_store.value(u"sidebar/expanded"_s, true).toBool();
}

void UiSettings::setSidebarExpanded(bool v) {
    if (v == sidebarExpanded()) return;
    m_store.setValue(u"sidebar/expanded"_s, v);
    Q_EMIT sidebarExpandedChanged();
}

} // namespace waywallen

#include "waywallen/ui_settings.moc.cpp"
