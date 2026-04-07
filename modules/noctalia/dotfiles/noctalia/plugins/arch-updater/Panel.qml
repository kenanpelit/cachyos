import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Widgets
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth: 500 * Style.uiScaleRatio
    property real contentPreferredHeight: 340 * Style.uiScaleRatio

    anchors.fill: parent

    // Shared column width reference (content area minus outer margins and table inner margins)
    readonly property real tableContentWidth: panelContainer.width - 2 * Style.marginL - 2 * Style.marginS

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

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.marginS
                Layout.rightMargin: Style.marginS
                spacing: Style.marginS

                NText {
                    Layout.preferredWidth: 0.4 * root.tableContentWidth
                    text: pluginApi?.tr("panel.name")
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignLeft
                }
                NText {
                    Layout.preferredWidth: 0.3 * root.tableContentWidth
                    text: pluginApi?.tr("panel.oldVer")
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignHCenter
                }
                NText {
                    Layout.preferredWidth: 0.3 * root.tableContentWidth
                    text: pluginApi?.tr("panel.newVer")
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Table
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Color.mSurfaceVariant
                radius: Style.radiusL

                NListView {
                    id: tableView
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    model: root.pluginApi?.mainInstance?.updates ?? []
                    clip: true
                    spacing: Style.marginXS

                    delegate: RowLayout {
                        required property var modelData
                        width: tableView.width
                        spacing: Style.marginS

                        NText {
                            Layout.preferredWidth: 0.4 * root.tableContentWidth
                            text: modelData.name
                            pointSize: Style.fontSizeM
                            color: modelData.isFlatpak ? Color.mTertiary : Color.mSecondary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        NText {
                            Layout.preferredWidth: 0.3 * root.tableContentWidth
                            text: modelData.oldVer
                            pointSize: Style.fontSizeM
                            color: modelData.isFlatpak ? Color.mTertiary : Color.mSecondary
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        NText {
                            Layout.preferredWidth: 0.3 * root.tableContentWidth
                            text: modelData.newVer
                            pointSize: Style.fontSizeM
                            color: modelData.isFlatpak ? Color.mTertiary : Color.mSecondary
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    ScrollBar.vertical: ScrollBar {}
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                NButton {
                    Layout.fillWidth: true
                    text: pluginApi?.tr("panel.refresh")
                    onClicked: {
                        Logger.d("Update Widget", "Refreshing from panel...")
                        root.pluginApi.mainInstance.refresh()
                    }
                }
                Item { width: Style.marginM }
                NButton {
                    Layout.fillWidth: true
                    text: pluginApi?.tr("panel.update")
                    onClicked: {
                        Logger.d("Update Widget", "Updating from panel...")
                        root.pluginApi.mainInstance.update()
                        pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }
                Item { width: Style.marginM }
                NIconButton {
                    icon: "settings"
                    onClicked: {
                        Logger.d("Update Widget", "Opening settings from panel...")
                        BarService.openPluginSettings(pluginApi.panelOpenScreen, pluginApi.manifest)
                        pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }
            }
        }
    }
}
