pragma ComponentBehavior: Bound
import QtQuick
import Qcm.Material as MD

Flow {
    id: root
    spacing: 12

    property string name
    property int condition
    property var conditionModel

    signal clicked
    signal commit

    Connections {
        target: root
        ignoreUnknownSignals: true
        function onConditionChanged() { root.commit(); }
        function onValueChanged() { root.commit(); }
    }

    MD.InputChip {
        id: nameChip
        text: root.name
        onClicked: root.clicked()
    }

    MD.InputChip {
        id: conditionChip
        text: {
            const item = (root.conditionModel || []).find(e => e.value === root.condition);
            return item ? item.name : "";
        }
        onClicked: menu.open()

        MD.Menu {
            id: menu
            parent: conditionChip
            y: parent.height
            model: root.conditionModel || []
            contentDelegate: MD.MenuItem {
                required property var modelData
                text: modelData.name
                onClicked: {
                    root.condition = modelData.value;
                    menu.close();
                }
            }
        }
    }
}
