module;
#include <QSettings>
#include "QExtra/macro_qt.hpp"

#ifdef Q_MOC_RUN
#    include "waywallen/ui_settings.moc"
#endif

export module waywallen:ui_settings;
export import qextra;

namespace waywallen
{

export class UiSettings : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool saveWindowSize READ saveWindowSize WRITE setSaveWindowSize NOTIFY saveWindowSizeChanged FINAL)
    Q_PROPERTY(int windowWidth READ windowWidth WRITE setWindowWidth NOTIFY windowWidthChanged FINAL)
    Q_PROPERTY(int windowHeight READ windowHeight WRITE setWindowHeight NOTIFY windowHeightChanged FINAL)
    Q_PROPERTY(bool sidebarAutoExpand READ sidebarAutoExpand WRITE setSidebarAutoExpand NOTIFY sidebarAutoExpandChanged FINAL)
    Q_PROPERTY(bool sidebarExpanded READ sidebarExpanded WRITE setSidebarExpanded NOTIFY sidebarExpandedChanged FINAL)

public:
    explicit UiSettings(QObject* parent);
    ~UiSettings() override;
    UiSettings() = delete;

    static UiSettings* instance();
    static UiSettings* create(QQmlEngine*, QJSEngine*);

    bool saveWindowSize() const;
    void setSaveWindowSize(bool v);
    int  windowWidth() const;
    void setWindowWidth(int v);
    int  windowHeight() const;
    void setWindowHeight(int v);
    bool sidebarAutoExpand() const;
    void setSidebarAutoExpand(bool v);
    bool sidebarExpanded() const;
    void setSidebarExpanded(bool v);

    Q_SIGNAL void saveWindowSizeChanged();
    Q_SIGNAL void windowWidthChanged();
    Q_SIGNAL void windowHeightChanged();
    Q_SIGNAL void sidebarAutoExpandChanged();
    Q_SIGNAL void sidebarExpandedChanged();

private:
    QSettings m_store;
};

} // namespace waywallen
