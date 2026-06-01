pragma ComponentBehavior: Bound
import QtQml
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import waywallen.control as WC
import waywallen.ui as W
import Qcm.Material as MD

// Tag membership rule. The value is a set of tags (multi-select). The
// daemon matches "has any" (IS) / "has none" (IS_NOT) against item tags.
QtObject {
    id: root
    property var filter: null
    property var values: []
    property int condition: WC.StringCondition.STRING_CONDITION_UNSPECIFIED
    // All DB tag names, supplied by the host for the picker dialog.
    property var allTags: []
    // Width the inline tag flow may use before wrapping (rule row width).
    property int availableWidth: 0
    property WC.wallpaperTagFilter subfilter
    property bool _syncing: false

    readonly property var conditionModel: [
        { name: qsTr("has any"),  value: WC.StringCondition.STRING_CONDITION_IS },
        { name: qsTr("has none"), value: WC.StringCondition.STRING_CONDITION_IS_NOT },
        { name: qsTr("any"),      value: WC.StringCondition.STRING_CONDITION_UNSPECIFIED }
    ]

    function toggleValue(tag) {
        const next = (root.values || []).slice();
        const i = next.indexOf(tag);
        if (i >= 0)
            next.splice(i, 1);
        else
            next.push(tag);
        root.values = next;
    }

    readonly property Component valueDelegate: Component {
        Flow {
            id: valueFlow
            visible: root.condition !== WC.StringCondition.STRING_CONDITION_UNSPECIFIED
            width: root.availableWidth > 0 ? root.availableWidth : implicitWidth
            spacing: 6

            Repeater {
                model: root.values
                delegate: W.Tag {
                    required property var modelData
                    text: modelData
                }
            }

            MD.SmallIconButton {
                icon.name: MD.Token.icon.edit
                onClicked: tagDialog.open()
            }

            MD.Dialog {
                id: tagDialog
                parent: T.Overlay.overlay
                title: qsTr("Select tags")
                horizontalPadding: 16
                implicitWidth: Math.min(330, parent ? parent.width - 48 : 330)
                standardButtons: T.Dialog.Cancel | T.Dialog.Reset | T.Dialog.Apply

                // Pending selection — only pushed to the rule on Apply.
                property var pending: []
                function togglePending(tag) {
                    const next = (tagDialog.pending || []).slice();
                    const i = next.indexOf(tag);
                    if (i >= 0)
                        next.splice(i, 1);
                    else
                        next.push(tag);
                    tagDialog.pending = next;
                }

                onAboutToShow: tagDialog.pending = (root.values || []).slice()
                onApplied: {
                    root.values = tagDialog.pending;
                    tagDialog.accept();
                }
                onReset: tagDialog.pending = (root.values || []).slice()

                contentItem: MD.VerticalFlickable {
                    id: tagFlick
                    contentWidth: width
                    contentHeight: m_col.implicitHeight
                    implicitHeight: Math.min(m_col.implicitHeight, 360)

                    ColumnLayout {
                        id: m_col
                        width: tagFlick.contentWidth
                        spacing: 8

                        MD.Text {
                            Layout.fillWidth: true
                            visible: !root.allTags || root.allTags.length === 0
                            text: qsTr("No tags in library")
                            typescale: MD.Token.typescale.body_medium
                            color: MD.Token.color.on_surface_variant
                            wrapMode: Text.WordWrap
                        }

                        Flow {
                            Layout.fillWidth: true
                            visible: root.allTags && root.allTags.length > 0
                            spacing: 8
                            Repeater {
                                model: root.allTags
                                delegate: MD.FilterChip {
                                    required property var modelData
                                    checkable: false
                                    text: modelData
                                    checked: (tagDialog.pending || []).indexOf(modelData) >= 0
                                    onClicked: tagDialog.togglePending(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function syncFromFilter() {
        if (!filter)
            return;
        if (!filter.hasTagFilter)
            filter.tagFilter = subfilter;
        const active = filter.hasTagFilter ? filter.tagFilter : subfilter;
        _syncing = true;
        condition = active.condition;
        values = active.values;
        _syncing = false;
    }

    function commitToFilter() {
        if (!filter || _syncing)
            return;
        subfilter.condition = condition;
        subfilter.values = root.values;
        filter.tagFilter = subfilter;
    }

    onFilterChanged: syncFromFilter()
    onConditionChanged: commitToFilter()
    onValuesChanged: commitToFilter()
}
