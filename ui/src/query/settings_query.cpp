module;
#include "waywallen/query/settings_query.moc.h"
#undef assert
#include <rstd/macro.hpp>

module waywallen;
import :query.settings;
import :app;

using namespace Qt::Literals::StringLiterals;
using namespace qextra::prelude;

namespace proto = waywallen::control::v1;

namespace waywallen
{

namespace
{

auto global_to_map(const proto::GlobalSettings& g) -> QVariantMap {
    QVariantMap m;
    m[u"defaultWidth"_s]  = g.defaultWidth();
    m[u"defaultHeight"_s] = g.defaultHeight();
    return m;
}

auto plugins_to_map(const proto::SettingsGetResponse::PluginsEntry& src) -> QVariantMap {
    QVariantMap out;
    for (auto it = src.constBegin(); it != src.constEnd(); ++it) {
        QVariantMap inner;
        const auto& values = it.value().values();
        for (auto vit = values.constBegin(); vit != values.constEnd(); ++vit) {
            inner[vit.key()] = vit.value();
        }
        out[it.key()] = inner;
    }
    return out;
}

auto map_to_global(const QVariantMap& m) -> proto::GlobalSettings {
    proto::GlobalSettings g;
    g.setDefaultWidth(m.value(u"defaultWidth"_s).toUInt());
    g.setDefaultHeight(m.value(u"defaultHeight"_s).toUInt());
    return g;
}

auto map_to_plugins(const QVariantMap& m) -> QHash<QString, proto::PluginSettings> {
    QHash<QString, proto::PluginSettings> out;
    for (auto it = m.constBegin(); it != m.constEnd(); ++it) {
        proto::PluginSettings ps;
        proto::PluginSettings::ValuesEntry values;
        const auto inner = it.value().toMap();
        for (auto vit = inner.constBegin(); vit != inner.constEnd(); ++vit) {
            values.insert(vit.key(), vit.value().toString());
        }
        ps.setValues(values);
        out.insert(it.key(), ps);
    }
    return out;
}

} // namespace

// ---------------------------------------------------------------------------
// SettingsGetQuery
// ---------------------------------------------------------------------------

SettingsGetQuery::SettingsGetQuery(QObject* parent): Query(parent) {}

auto SettingsGetQuery::global() const -> const QVariantMap& { return m_global; }
auto SettingsGetQuery::plugins() const -> const QVariantMap& { return m_plugins; }

void SettingsGetQuery::reload() {
    setStatus(Status::Querying);
    auto backend = App::instance()->backend();

    auto req = proto::Request {};
    req.setSettingsGet(proto::SettingsGetRequest {});

    auto self = QWatcher { this };
    spawn([self, backend, req = std::move(req)]() mutable -> task<void> {
        auto result = co_await backend->send(std::move(req));
        co_await asio::post(asio::bind_executor(self->get_executor(), use_task));

        self->inspect_set(result, [self](const proto::Response& rsp) {
            const auto& get_rsp = rsp.settingsGet();
            self->m_global  = global_to_map(get_rsp.global());
            self->m_plugins = plugins_to_map(get_rsp.plugins());
            Q_EMIT self->globalChanged();
            Q_EMIT self->pluginsChanged();
        });
        co_return;
    });
}

// ---------------------------------------------------------------------------
// SettingsSetQuery
// ---------------------------------------------------------------------------

SettingsSetQuery::SettingsSetQuery(QObject* parent): Query(parent) {}

auto SettingsSetQuery::global() const -> const QVariantMap& { return m_global; }
void SettingsSetQuery::setGlobal(const QVariantMap& v) {
    if (m_global != v) {
        m_global = v;
        Q_EMIT globalChanged();
    }
}

auto SettingsSetQuery::plugins() const -> const QVariantMap& { return m_plugins; }
void SettingsSetQuery::setPlugins(const QVariantMap& v) {
    if (m_plugins != v) {
        m_plugins = v;
        Q_EMIT pluginsChanged();
    }
}

void SettingsSetQuery::reload() {
    setStatus(Status::Querying);
    auto backend = App::instance()->backend();

    auto req   = proto::Request {};
    auto inner = proto::SettingsSetRequest {};
    inner.setGlobal(map_to_global(m_global));
    inner.setPlugins(map_to_plugins(m_plugins));
    req.setSettingsSet(std::move(inner));

    auto self = QWatcher { this };
    spawn([self, backend, req = std::move(req)]() mutable -> task<void> {
        auto result = co_await backend->send(std::move(req));
        co_await asio::post(asio::bind_executor(self->get_executor(), use_task));

        self->inspect_set(result, [](const proto::Response&) {});
        co_return;
    });
}

} // namespace waywallen

#include "waywallen/query/settings_query.moc.cpp"
