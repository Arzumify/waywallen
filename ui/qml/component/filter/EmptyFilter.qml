import QtQuick
import waywallen.ui as W
import Qcm.Material as MD

W.BaseFilter {
    id: root

    conditionModel: [ { name: qsTr("select type"), value: 0 } ]

    MD.Text {
        text: qsTr("Choose a filter type")
        color: MD.Token.color.on_surface_variant
    }
}
