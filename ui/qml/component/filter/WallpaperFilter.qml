pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import waywallen.control as WC
import waywallen.ui as W
import Qcm.Material as MD

MD.ItemDelegate {
    id: root
    required property var model
    required property int index
    property WC.wallpaperStringFilter emptyStringFilter
    property WC.wallpaperIntFilter emptyIntFilter
    property WC.wallpaperAspectFilter emptyAspectFilter

    font.capitalization: Font.MixedCase

    readonly property var typeOptions: [
        { name: qsTr("Name"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_NAME, kind: "string" },
        { name: qsTr("Wallpaper type"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_WP_TYPE, kind: "string" },
        { name: qsTr("Library"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_LIBRARY, kind: "string" },
        { name: qsTr("Format"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_FORMAT, kind: "string" },
        { name: qsTr("Width"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_WIDTH, kind: "int" },
        { name: qsTr("Height"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_HEIGHT, kind: "int" },
        { name: qsTr("Size"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_SIZE, kind: "int" },
        { name: qsTr("Aspect"), value: WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_ASPECT, kind: "aspect" }
    ]

    function optionForType(type) {
        return typeOptions.find(e => e.value === type);
    }

    function applyType(option) {
        root.model.type = option.value;
        switch (option.kind) {
        case "string":
            root.model.stringFilter = emptyStringFilter;
            break;
        case "int":
            root.model.intFilter = emptyIntFilter;
            break;
        case "aspect":
            root.model.aspectFilter = emptyAspectFilter;
            break;
        }
    }

    function openMenu() {
        typeMenu.open();
    }

    Component.onCompleted: {
        emptyAspectFilter.value = WC.WallpaperAspect.WALLPAPER_ASPECT_LANDSCAPE;
    }

    contentItem: RowLayout {
        Row {
            Layout.fillWidth: true
            spacing: 0

            Loader {
                id: filterLoader
                width: parent.width

                sourceComponent: {
                    switch (root.model.type) {
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_NAME:
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_WP_TYPE:
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_LIBRARY:
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_FORMAT:
                        return stringFilterComponent;
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_WIDTH:
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_HEIGHT:
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_SIZE:
                        return intFilterComponent;
                    case WC.WallpaperFilterType.WALLPAPER_FILTER_TYPE_ASPECT:
                        return aspectFilterComponent;
                    default:
                        return emptyFilterComponent;
                    }
                }

                onLoaded: {
                    if (!item)
                        return;
                    const option = root.optionForType(root.model.type);
                    if (option)
                        item.name = option.name;
                }

                Connections {
                    target: filterLoader.item
                    ignoreUnknownSignals: true
                    function onClicked() {
                        root.openMenu();
                    }
                }
            }
        }

        MD.SmallIconButton {
            icon.name: MD.Token.icon.close
            onClicked: ListView.view.model.removeRow(root.index)
        }
    }

    background: MD.Rectangle {
        corners: {
            const view = root.ListView.view;
            const model = view.model;
            void(view.count);
            return MD.Util.listCorners(model.rowIndexInGroup(root.index),
                                       model.rowCountInGroupOf(root.index), 12);
        }
        color: root.MD.MProp.color.surface
    }

    MD.Menu {
        id: typeMenu
        parent: root
        y: root.contentItem.y + root.contentItem.height
        model: root.typeOptions
        contentDelegate: MD.MenuItem {
            required property var modelData
            text: modelData.name
            onClicked: {
                root.applyType(modelData);
                typeMenu.close();
            }
        }
    }

    Component {
        id: stringFilterComponent
        W.StringFilter {
            filter: root.model
        }
    }

    Component {
        id: intFilterComponent
        W.IntFilter {
            filter: root.model
        }
    }

    Component {
        id: aspectFilterComponent
        W.AspectFilter {
            filter: root.model
        }
    }

    Component {
        id: emptyFilterComponent
        W.EmptyFilter {
            name: qsTr("Filter")
        }
    }
}
