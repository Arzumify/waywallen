pragma ComponentBehavior: Bound
import QtQuick
import waywallen.control as WC
import waywallen.ui as W
import Qcm.Material as MD

W.BaseFilter {
    id: root
    required property var filter
    property int value: WC.WallpaperAspect.WALLPAPER_ASPECT_LANDSCAPE
    property WC.wallpaperAspectFilter subfilter

    function syncFromFilter() {
        if (!filter.hasAspectFilter)
            filter.aspectFilter = subfilter;
        const active = filter.hasAspectFilter ? filter.aspectFilter : subfilter;
        condition = active.condition;
        value = active.value;
    }

    function commitToFilter() {
        subfilter.condition = condition;
        subfilter.value = value;
        filter.aspectFilter = subfilter;
    }

    function aspectLabel(v) {
        switch (v) {
        case WC.WallpaperAspect.WALLPAPER_ASPECT_PORTRAIT:
            return qsTr("portrait");
        case WC.WallpaperAspect.WALLPAPER_ASPECT_SQUARE:
            return qsTr("square");
        default:
            return qsTr("landscape");
        }
    }

    Component.onCompleted: {
        subfilter.value = WC.WallpaperAspect.WALLPAPER_ASPECT_LANDSCAPE;
        syncFromFilter();
        commit.connect(commitToFilter);
    }

    conditionModel: [
        { name: qsTr("is"), value: WC.TypeCondition.TYPE_CONDITION_IS },
        { name: qsTr("is not"), value: WC.TypeCondition.TYPE_CONDITION_IS_NOT },
        { name: qsTr("any"), value: WC.TypeCondition.TYPE_CONDITION_UNSPECIFIED }
    ]

    MD.InputChip {
        id: valueChip
        visible: root.condition !== WC.TypeCondition.TYPE_CONDITION_UNSPECIFIED
        text: root.aspectLabel(root.value)
        onClicked: valueMenu.open()

        MD.Menu {
            id: valueMenu
            parent: valueChip
            y: parent.height
            model: [
                { name: qsTr("landscape"), value: WC.WallpaperAspect.WALLPAPER_ASPECT_LANDSCAPE },
                { name: qsTr("portrait"), value: WC.WallpaperAspect.WALLPAPER_ASPECT_PORTRAIT },
                { name: qsTr("square"), value: WC.WallpaperAspect.WALLPAPER_ASPECT_SQUARE }
            ]
            contentDelegate: MD.MenuItem {
                required property var modelData
                text: modelData.name
                onClicked: {
                    root.value = modelData.value;
                    valueMenu.close();
                }
            }
        }
    }
}
