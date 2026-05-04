pragma ComponentBehavior: Bound
import QtQuick
import waywallen.control as WC
import waywallen.ui as W
import Qcm.Material as MD

W.BaseFilter {
    id: root
    required property var filter
    property int value: 0
    property WC.wallpaperIntFilter subfilter

    function syncFromFilter() {
        if (!filter.hasIntFilter)
            filter.intFilter = subfilter;
        const active = filter.hasIntFilter ? filter.intFilter : subfilter;
        condition = active.condition;
        value = active.value;
    }

    function commitToFilter() {
        subfilter.condition = condition;
        subfilter.value = value;
        filter.intFilter = subfilter;
    }

    Component.onCompleted: {
        syncFromFilter();
        commit.connect(commitToFilter);
    }

    conditionModel: [
        { name: qsTr("equal"), value: WC.IntCondition.INT_CONDITION_EQUAL },
        { name: qsTr("not equal"), value: WC.IntCondition.INT_CONDITION_EQUAL_NOT },
        { name: qsTr("less"), value: WC.IntCondition.INT_CONDITION_LESS },
        { name: qsTr("less equal"), value: WC.IntCondition.INT_CONDITION_LESS_EQUAL },
        { name: qsTr("greater"), value: WC.IntCondition.INT_CONDITION_GREATER },
        { name: qsTr("greater equal"), value: WC.IntCondition.INT_CONDITION_GREATER_EQUAL },
        { name: qsTr("any"), value: WC.IntCondition.INT_CONDITION_UNSPECIFIED }
    ]

    MD.InputChip {
        id: valueChip
        visible: root.condition !== WC.IntCondition.INT_CONDITION_UNSPECIFIED
        text: String(root.value)
        onClicked: edit = true
        editDelegate: MD.TextInput {
            text: String(root.value)
            validator: IntValidator {}
            onAccepted: {
                const parsed = parseInt(text, 10);
                root.value = isNaN(parsed) ? 0 : parsed;
                valueChip.edit = false;
            }
        }
    }
}
