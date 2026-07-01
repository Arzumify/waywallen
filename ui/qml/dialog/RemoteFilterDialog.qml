pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Qcm.Material as MD

MD.Dialog {
    id: root
    title: qsTr("Filters")
    horizontalPadding: 16
    implicitWidth: Math.min(760, parent ? parent.width - 48 : 760)
    standardButtons: T.Dialog.Cancel | T.Dialog.Reset | T.Dialog.Apply

    property var availableTags: []
    property var selectedTags: []
    property var working: ({})

    signal apply(var tags)

    readonly property var filterTags: sanitizeTags(availableTags).filter(t => t !== "Mature")
    readonly property bool hasMatureFilter: sanitizeTags(availableTags).indexOf("Mature") >= 0

    function sanitizeTags(tags) {
        let out = [];
        let seen = {};
        for (const value of tags ?? []) {
            const tag = String(value);
            if (tag.length === 0 || seen[tag] === true)
                continue;
            seen[tag] = true;
            out.push(tag);
        }
        return out;
    }
    function selectedMap(tags) {
        const allowed = {};
        for (const tag of sanitizeTags(availableTags))
            allowed[tag] = true;
        let out = {};
        for (const tag of sanitizeTags(tags)) {
            if (allowed[tag] === true)
                out[tag] = true;
        }
        return out;
    }
    function setSelectedTags(tags) {
        working = selectedMap(tags);
    }
    function has(tag) {
        return working[tag] === true;
    }
    function toggle(tag, on) {
        let w = {};
        for (const k in working)
            w[k] = working[k];
        if (on)
            w[tag] = true;
        else
            delete w[tag];
        working = w;
    }
    function collect() {
        let out = [];
        for (const tag of sanitizeTags(availableTags)) {
            if (working[tag] === true)
                out.push(tag);
        }
        return out;
    }

    onAboutToShow: setSelectedTags(selectedTags)
    onApplied: {
        root.apply(collect());
        accept();
    }
    onReset: setSelectedTags([])

    contentItem: ColumnLayout {
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.filterTags.length > 0

            MD.Label {
                text: qsTr("Tags")
                typescale: MD.Token.typescale.title_small
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.filterTags
                    delegate: MD.FilterChip {
                        required property string modelData
                        text: modelData
                        checked: root.has(modelData)
                        onClicked: root.toggle(modelData, checked)
                    }
                }
            }
        }

        MD.Divider {
            Layout.fillWidth: true
            visible: root.hasMatureFilter
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: root.hasMatureFilter

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                MD.Label {
                    text: qsTr("Mature content (NSFW)")
                    typescale: MD.Token.typescale.title_small
                }
                MD.Label {
                    text: qsTr("18+ only. Shows mature-tagged wallpapers.")
                    typescale: MD.Token.typescale.body_small
                    color: MD.Token.color.on_surface_variant
                }
            }

            MD.Switch {
                id: m_nsfw
                checked: root.has("Mature")
                onClicked: {
                    if (!root.has("Mature"))
                        m_confirm.open();
                    else
                        root.toggle("Mature", false);
                }
            }
        }
    }

    MD.Dialog {
        id: m_confirm
        title: qsTr("Mature content")
        modal: true
        anchors.centerIn: T.Overlay.overlay
        standardButtons: T.Dialog.Cancel | T.Dialog.Ok
        onAccepted: root.toggle("Mature", true)
        onRejected: m_nsfw.checked = Qt.binding(() => root.has("Mature"))

        contentItem: MD.Label {
            text: qsTr("This shows wallpapers tagged as mature / NSFW. You must be 18 or older to enable this. Continue?")
            wrapMode: Text.WordWrap
        }
    }
}
