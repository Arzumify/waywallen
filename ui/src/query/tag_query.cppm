module;
#include "QExtra/macro_qt.hpp"

#ifdef Q_MOC_RUN
#    include "waywallen/query/tag_query.moc"
#endif

export module waywallen:query.tag;
export import :query.query;

namespace waywallen
{

// All distinct tag names in the library DB. Feeds the tag-filter picker.
export class TagListQuery : public Query,
                            public QueryExtra<control::v1::Response, TagListQuery> {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QStringList tags READ tags NOTIFY tagsChanged FINAL)

public:
    TagListQuery(QObject* parent = nullptr);

    auto tags() const -> const QStringList&;

    void reload() override;

    Q_SIGNAL void tagsChanged();

private:
    QStringList m_tags;
};

} // namespace waywallen
