import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null

    property real contentPreferredWidth: Math.round(400 * Style.uiScaleRatio)
    property real contentPreferredHeight: mainLayout.implicitHeight + (Style.marginL * 2)

    readonly property var geometryPlaceholder: bg
    readonly property bool allowAttach: true

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Color.mSurface
        radius: Style.radiusL
        border.color: Qt.alpha(Color.mOutline, 0.2)
        border.width: 1

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: headerRow.implicitHeight + Style.marginM

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    spacing: Style.marginS

                    NIcon {
                        icon: mainInstance ? mainInstance.currentIconName : "world"
                        pointSize: Style.fontSizeL
                        color: Color.mPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                            text: pluginApi ? pluginApi.tr("plugin.title") : "DNS / VPN Switcher"
                            pointSize: Style.fontSizeL
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                        }

                        NText {
                            text: mainInstance
                                  ? (mainInstance.isChanging
                                     ? (pluginApi ? pluginApi.tr("status.switching") : "Switching...")
                                     : mainInstance.currentStatusDetail)
                                  : ""
                            pointSize: Style.fontSizeXS
                            color: Color.mSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Style.radiusM
                color: Qt.alpha(Color.mSurfaceVariant, 0.7)
                border.color: Qt.alpha(Color.mOutline, 0.15)
                border.width: 1
                implicitHeight: stateLayout.implicitHeight + (Style.marginM * 2)

                RowLayout {
                    id: stateLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                        icon: mainInstance ? mainInstance.currentIconName : "world"
                        pointSize: Style.fontSizeL
                        color: Color.mPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                            text: mainInstance ? mainInstance.currentDnsName : (pluginApi ? pluginApi.tr("status.checking") : "Checking...")
                            pointSize: Style.fontSizeM
                            font.weight: Font.Medium
                            color: Color.mOnSurface
                        }

                        NText {
                            text: mainInstance ? mainInstance.currentDnsIp : ""
                            visible: text !== ""
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: mainInstance ? mainInstance.lastError !== "" : false
                color: Qt.alpha(Color.mError, 0.1)
                radius: Style.radiusS
                border.color: Qt.alpha(Color.mError, 0.3)
                border.width: 1
                implicitHeight: errorText.implicitHeight + Style.marginM

                NText {
                    id: errorText
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    text: mainInstance ? mainInstance.lastError : ""
                    color: Color.mError
                    pointSize: Style.fontSizeS
                    wrapMode: Text.WordWrap
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Style.marginS
                rowSpacing: Style.marginS

                NButton {
                    Layout.fillWidth: true
                    text: "Mullvad"
                    icon: "shield-lock"
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("mullvad")
                }

                NButton {
                    Layout.fillWidth: true
                    text: "Blocky"
                    icon: "shield-check"
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("blocky")
                }

                NButton {
                    Layout.fillWidth: true
                    text: pluginApi ? pluginApi.tr("panel.default_dns") : "Default (ISP)"
                    icon: "world"
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("default")
                }

                NButton {
                    Layout.fillWidth: true
                    text: pluginApi ? pluginApi.tr("panel.toggle") : "Toggle"
                    icon: "switch-2"
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("toggle")
                }
            }

            NButton {
                Layout.fillWidth: true
                text: pluginApi ? pluginApi.tr("panel.repair") : "Sync / Repair"
                icon: "refresh"
                backgroundColor: Qt.alpha(Color.mPrimary, 0.12)
                textColor: Color.mPrimary
                enabled: !(mainInstance && mainInstance.isChanging)
                onClicked: mainInstance && mainInstance.runAction("repair")
            }

            NText {
                Layout.fillWidth: true
                text: pluginApi ? pluginApi.tr("panel.presets") : "DNS Presets"
                pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: Color.mSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                Repeater {
                    model: mainInstance ? mainInstance.defaultProviders : []
                    delegate: NButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label + "  |  " + modelData.ip
                        icon: modelData.icon
                        enabled: !(mainInstance && mainInstance.isChanging)
                        onClicked: mainInstance && mainInstance.runAction("provider:" + modelData.id)
                    }
                }
            }

            NText {
                Layout.fillWidth: true
                text: (pluginApi ? pluginApi.tr("panel.command") : "Backend") + ": " + (mainInstance ? mainInstance.oscCommand : "osc-mullvad")
                pointSize: Style.fontSizeXS
                color: Color.mSecondary
                wrapMode: Text.WordWrap
            }
        }
    }
}
