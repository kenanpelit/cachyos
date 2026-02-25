import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var currentItem: null
    
    implicitHeight: contentArea.implicitHeight + Style.marginL * 2

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: Style.marginS
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS
            
            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                
                horizontalPolicy: ScrollBar.AlwaysOff 

                NText {
                    id: textItem
                    text: root.currentItem ? (root.currentItem.name || "") : ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                    font.family: Settings.data.ui.fontFixed
                }
            }
        }
    }
}
