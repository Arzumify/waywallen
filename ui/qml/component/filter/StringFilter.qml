pragma ComponentBehavior: Bound
import QtQuick
import waywallen.control as WC
import waywallen.ui as W
import Qcm.Material as MD

W.BaseFilter {
    id: root
    required property var filter
    property string value: ""
    property WC.wallpaperStringFilter subfilter

    function syncFromFilter() {
        if (!filter.hasStringFilter)
            filter.stringFilter = subfilter;
        condition = filter.stringFilter.condition;
        value = filter.stringFilter.value;
    }

    function commitToFilter() {
        subfilter.condition = condition;
        subfilter.value = value;
        filter.stringFilter = subfilter;
    }

    Component.onCompleted: {
        syncFromFilter();
        commit.connect(commitToFilter);
    }

    conditionModel: [
        { name: qsTr("contains"), value: WC.StringCondition.STRING_CONDITION_CONTAINS },
        { name: qsTr("not contains"), value: WC.StringCondition.STRING_CONDITION_CONTAINS_NOT },
        { name: qsTr("is"), value: WC.StringCondition.STRING_CONDITION_IS },
        { name: qsTr("is not"), value: WC.StringCondition.STRING_CONDITION_IS_NOT },
        { name: qsTr("any"), value: WC.StringCondition.STRING_CONDITION_UNSPECIFIED }
    ]

    MD.InputChip {
        id: valueChip
        visible: root.condition !== WC.StringCondition.STRING_CONDITION_UNSPECIFIED
        text: root.value
        onClicked: edit = true
        editDelegate: MD.TextInput {
            text: root.value
            onAccepted: {
                root.value = text;
                valueChip.edit = false;
            }
        }
    }
}
