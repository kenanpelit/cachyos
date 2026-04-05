import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Widgets
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets
import qs.Services.UI

DraggableDesktopWidget {
    id: root

    property var pluginApi: null

    // Scale dimensions by widgetScale
    implicitWidth: Math.round(200 * widgetScale)
    implicitHeight: Math.round(120 * widgetScale)
    width: implicitWidth
    height: implicitHeight

    Column {
        spacing: Style.marginL
        padding: Style.marginXL

        Rectangle { // Heading
            width: root.implicitWidth - 2 * Style.marginXL
            height: Style.fontSizeXL
            color: "transparent"

            NText {
                text: (root.pluginApi.mainInstance.updateCount + root.pluginApi.mainInstance.flatpakCount).toString() +" "+ pluginApi.trp("desktop.header", root.pluginApi.mainInstance.updateCount + root.pluginApi.mainInstance.flatpakCount)
                pointSize: Style.fontSizeXL
                font.weight: Font.Bold
                color: Color.mOnSurface
                anchors.centerIn: parent
            }
        }

        NDivider {
            color: Color.mOnSurface
            width: root.implicitWidth - 2 * Style.marginL
            height: 1
            Layout.topMargin: Style.marginL
            Layout.bottomMargin: Style.marginL
        }

        Row { // Sub Headings
            spacing: Style.marginL

            Rectangle {
                width: (root.implicitWidth - 2 * Style.marginL - 2 * Style.marginXL) / 3 
                height: Style.fontSizeM
                color: "transparent"
                NText {
                    text: pluginApi.tr("desktop.name")
                    pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    anchors.centerIn: parent
                }
            }
            Rectangle {
                width: (root.implicitWidth - 4 * Style.marginL - 2 * Style.marginXL) / 3 
                height: Style.fontSizeM
                color: "transparent"
                NText {
                    text: pluginApi.tr("desktop.oldVer")
                    pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    anchors.centerIn: parent
                }
            }
            Rectangle {
                width: (root.implicitWidth - 4 * Style.marginL - 2 * Style.marginXL) / 3 
                height: Style.fontSizeM
                color: "transparent"
                NText {
                    text: pluginApi.tr("desktop.newVer")
                    pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    anchors.centerIn: parent
                }
            }
        }

        Row { // Tables
            spacing: Style.marginL

            ClippingRectangle {
                width: (root.implicitWidth - 4 * Style.marginL - 2 * Style.marginXL) / 3 
                height: root.implicitHeight - Style.fontSizeM - 3 * Style.marginL - 2 * Style.marginXL - Style.fontSizeXL - 1
                color: "transparent"

                ScrollView {
                    anchors.fill: parent

                    ScrollBar.vertical{
                        id: scrollOne
                        onPositionChanged: {
                            hoverTip.visible = false
                            // Sync up scrolling
                            scrollTwo.position = scrollOne.position
                            scrollThree.position = scrollOne.position
                        }
                    }
                    Column  {
                        NText {
                            text: root.pluginApi.mainInstance.nameStr
                            pointSize: Style.fontSizeM
                            color: Color.mSecondary
                            padding: Style.marginM
                        }
                        NText {
                            text: root.pluginApi.mainInstance.flatpakNameStr
                            pointSize: Style.fontSizeM
                            color: Color.mTertiary
                            padding: Style.marginM
                        }
                    }
                }
            }

            ClippingRectangle {
                width: (root.implicitWidth - 4 * Style.marginL - 2 * Style.marginXL) / 3 
                height: root.implicitHeight - Style.fontSizeM - 3 * Style.marginL - 2 * Style.marginXL - Style.fontSizeXL - 1
                color: "transparent"

                ScrollView {
                    anchors.fill: parent
                    ScrollBar.vertical{
                        id: scrollTwo
                        onPositionChanged: {
                            hoverTip.visible = false
                            // Sync up scrolling
                            scrollOne.position = scrollTwo.position
                            scrollThree.position = scrollTwo.position
                        }
                    }
                    Column  {
                        NText {
                            text: root.pluginApi.mainInstance.oldVerStr
                            pointSize: Style.fontSizeM
                            color: Color.mSecondary
                            padding: Style.marginM
                        }
                        NText {
                            text: root.pluginApi.mainInstance.flatpakOldVerStr
                            pointSize: Style.fontSizeM
                            color: Color.mTertiary
                            padding: Style.marginM
                        }
                    }
                }
            }

            ClippingRectangle {
                width: (root.implicitWidth - 4 * Style.marginL - 2 * Style.marginXL) / 3 
                height: root.implicitHeight - Style.fontSizeM - 3 * Style.marginL - 2 * Style.marginXL - Style.fontSizeXL - 1
                color: "transparent"

                ScrollView {
                    anchors.fill: parent
                    ScrollBar.vertical{
                        id: scrollThree
                        onPositionChanged: {
                            hoverTip.visible = false
                            // Sync up scrolling
                            scrollOne.position = scrollThree.position
                            scrollTwo.position = scrollThree.position
                        }
                    }
                    Column  {
                        NText {
                            text: root.pluginApi.mainInstance.newVerStr
                            pointSize: Style.fontSizeM
                            color: Color.mSecondary
                            padding: Style.marginM
                        }
                        NText {
                            text: root.pluginApi.mainInstance.flatpakNewVerStr
                            pointSize: Style.fontSizeM
                            color: Color.mTertiary
                            padding: Style.marginM
                        }
                    }
                    
                }
            }
        }
    }

    Rectangle { // Hover Tip
        id: hoverTip

        width: root.width - (Style.marginL * widgetScale)
        height: root.height - (Style.marginL * widgetScale)
        anchors.centerIn: parent
        radius: Style.marginL

        color: Color.mShadow
        opacity: 0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        NText {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter

            pointSize: Style.fontSizeXL
            font.weight: Font.Bold
            color: Color.mOnSurface

            text: pluginApi.tr("desktop.tipLeft") + "\n---------------\n" + pluginApi.tr("desktop.tipMiddle") + "\n---------------\n" + pluginApi.tr("desktop.tipRight")
        }
    }

    MouseArea { // Clicks
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                Logger.d("Update Widget", "Refreshing from desktop widget...")
                root.pluginApi.mainInstance.refresh() // Refresh available updates
            }
            else if (mouse.button === Qt.MiddleButton) {
                Logger.d("Update Widget", "Updating from desktop widget...")
                root.pluginApi.mainInstance.update() // Update
            }
            else if (mouse.button === Qt.RightButton) {
                Logger.d("Update Widget", "Opening settings from desktop widget...")
                BarService.openPluginSettings(screen, pluginApi.manifest)
            }
        }

        Timer {
            id: hoverTimer
            interval: 1500
            running: false
            repeat: false
            onTriggered: {
                Logger.d("Update Widget", "Showing hover tip...")
                hoverTip.opacity = 0.85
                hoverTip.visible = true
            }
        }

        onEntered: {
            if (pluginApi.pluginSettings.desktopTip) {
                Logger.d("Update Widget", "Starting hover tip timer...")
                hoverTimer.restart()
            }
        }

        onExited: {
            Logger.d("Update Widget", "Hover tip timer stopped!")
            hoverTimer.stop()
            hoverTip.opacity = 0
            hoverTip.visible = false
        }
    }
}