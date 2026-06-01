module;
#include "waywallen/query/tag_query.moc.h"
#undef assert
#include <rstd/macro.hpp>

module waywallen;
import :query.tag;
import :app;

using namespace qextra::prelude;

namespace proto = waywallen::control::v1;

namespace waywallen
{

TagListQuery::TagListQuery(QObject* parent): Query(parent) {}

auto TagListQuery::tags() const -> const QStringList& { return m_tags; }

void TagListQuery::reload() {
    setStatus(Status::Querying);
    auto backend = App::instance()->backend();

    auto req = proto::Request {};
    req.setTagList(proto::TagListRequest {});

    auto self = QWatcher { this };
    spawn([self, backend, req = std::move(req)]() mutable -> task<void> {
        auto result = co_await backend->send(std::move(req));
        co_await asio::post(asio::bind_executor(self->get_executor(), use_task));
        if (! self) co_return;

        self->inspect_set(result, [self](const proto::Response& rsp) {
            QStringList tags;
            for (const auto& t : rsp.tagList().tags()) {
                tags.append(t);
            }
            self->m_tags = std::move(tags);
            Q_EMIT self->tagsChanged();
        });
        co_return;
    });
}

} // namespace waywallen

#include "waywallen/query/tag_query.moc.cpp"
