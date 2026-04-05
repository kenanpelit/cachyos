import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    // Plugin API (injected by PluginPanelSlot)
    property var pluginApi: null

    // SmartPanel properties (required for panel behavior)
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    // Preferred dimensions
    property real contentPreferredWidth: 500 * Style.uiScaleRatio
    property real contentPreferredHeight: 340 * Style.uiScaleRatio

    anchors.fill: parent

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors {
                fill: parent
                margins: Style.marginL
            }
            spacing: Style.marginL

            Rectangle { // Content area
                id: table
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                
                Column {
                    spacing: Style.marginL
                    Row { // Headers
                        spacing: Style.marginL

                        Rectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: Style.fontSizeL
                            color: "transparent"
                            NText {
                                text: pluginApi.tr("panel.name")
                                pointSize: Style.fontSizeL
                                font.weight: Font.Bold
                                color: Color.mOnSurface
                                anchors.centerIn: parent
                            }
                        }
                        Rectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: Style.fontSizeL
                            color: "transparent"
                            NText {
                                text: pluginApi.tr("panel.oldVer")
                                pointSize: Style.fontSizeL
                                font.weight: Font.Bold
                                color: Color.mOnSurface
                                anchors.centerIn: parent
                            }
                        }
                        Rectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: Style.fontSizeL
                            color: "transparent"
                            NText {
                                text: pluginApi.tr("panel.newVer")
                                pointSize: Style.fontSizeL
                                font.weight: Font.Bold
                                color: Color.mOnSurface
                                anchors.centerIn: parent
                            }
                        }
                    }
                    Row { // Tables
                        spacing: Style.marginL

                        ClippingRectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: table.height - 2 * Style.fontSizeL
                            color: Color.mSurfaceVariant
                            radius: Style.radiusL

                            ScrollView {
                                anchors.fill: parent

                                ScrollBar.vertical{
                                    id: scrollOne
                                    onPositionChanged: {
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
                                        text: root.pluginApi.mainInstance.flatpakNameStr + " "
                                        pointSize: Style.fontSizeM
                                        color: Color.mTertiary
                                        padding: Style.marginM
                                    }
                                }
                            }
                        }

                        ClippingRectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: table.height - 2 * Style.fontSizeL
                            color: Color.mSurfaceVariant
                            radius: Style.radiusL

                            ScrollView {
                                anchors.fill: parent
                                ScrollBar.vertical{
                                    id: scrollTwo
                                    onPositionChanged: {
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
                                        text: root.pluginApi.mainInstance.flatpakOldVerStr + " "
                                        pointSize: Style.fontSizeM
                                        color: Color.mTertiary
                                        padding: Style.marginM
                                    }
                                }
                            }
                        }

                        ClippingRectangle {
                            width: (table.width - 2 * Style.marginL) / 3
                            height: table.height - 2 * Style.fontSizeL
                            color: Color.mSurfaceVariant
                            radius: Style.radiusL

                            ScrollView {
                                anchors.fill: parent
                                ScrollBar.vertical{
                                    id: scrollThree
                                    onPositionChanged: {
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
                                        text: root.pluginApi.mainInstance.flatpakNewVerStr + " "
                                        pointSize: Style.fontSizeM
                                        color: Color.mTertiary
                                        padding: Style.marginM
                                    }
                                }
                                
                            }
                        }
                    }
                }
            }

            RowLayout { // Footer
                Layout.fillWidth: true
                NButton { // Refresh Button
                    Layout.fillWidth: true
                    text: pluginApi.tr("panel.refresh")
                    onClicked: {
                        Logger.d("Update Widget", "Refreshing from panel...")
                        root.pluginApi.mainInstance.refresh()
                    }
                }
                Item {width: Style.marginM} // Spacer
                NButton { // Update Button
                    Layout.fillWidth: true
                    text: pluginApi.tr("panel.update")
                    onClicked: {
                        Logger.d("Update Widget", "Updating from panel...")
                        root.pluginApi.mainInstance.update()
                        pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }
                Item {width: Style.marginM} // Spacer
                NIconButton { // Update Button
                    icon: "settings"
                    onClicked: {
                        Logger.d("Update Widget", "Opening settings from panel...")
                        BarService.openPluginSettings(screen, pluginApi.manifest)
                        pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }
            }
        }
    }
}