import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    readonly property var mainInstance: pluginApi ? pluginApi.mainInstance : null

    property real contentPreferredWidth: Math.round(430 * Style.uiScaleRatio)
    property real contentPreferredHeight: mainLayout.implicitHeight + (Style.marginL * 2)

    readonly property var geometryPlaceholder: bg
    readonly property bool allowAttach: true

    function actionIsActive(actionId) {
        if (!mainInstance) {
            return false;
        }

        switch (actionId) {
        case "mullvad":
        case "blocky":
        case "default":
            return mainInstance.modeId === actionId;
        default:
            return false;
        }
    }

    function actionBackground(actionId) {
        if (actionIsActive(actionId)) {
            return Qt.alpha(Color.mPrimary, 0.16);
        }
        if (actionId === "toggle") {
            return Qt.alpha(Color.mSurfaceVariant, 0.75);
        }
        return Qt.alpha(Color.mSurfaceVariant, 0.48);
    }

    function actionTextColor(actionId) {
        return actionIsActive(actionId) ? Color.mPrimary : Color.mOnSurface;
    }

    function providerIsActive(providerId) {
        return mainInstance && mainInstance.activeProviderId === providerId;
    }

    function providerBadgeText() {
        if (!mainInstance) {
            return "Idle";
        }
        if (mainInstance.modeId === "mullvad" || mainInstance.modeId === "blocky" || mainInstance.modeId === "mixed") {
            return "Protected";
        }
        if (mainInstance.modeId === "default") {
            return "Auto";
        }
        if (mainInstance.isCustomDns) {
            return "Preset";
        }
        return "Ready";
    }

    function providerBadgeColor() {
        if (!mainInstance) {
            return Qt.alpha(Color.mSurfaceVariant, 0.85);
        }
        if (mainInstance.modeId === "mullvad" || mainInstance.modeId === "blocky" || mainInstance.modeId === "mixed") {
            return Qt.alpha(Color.mPrimary, 0.16);
        }
        if (mainInstance.modeId === "default") {
            return Qt.alpha(Color.mSurfaceVariant, 0.9);
        }
        return Qt.alpha(Color.mSurfaceVariant, 0.7);
    }

    function providerBadgeTextColor() {
        if (mainInstance && (mainInstance.modeId === "mullvad" || mainInstance.modeId === "blocky" || mainInstance.modeId === "mixed")) {
            return Color.mPrimary;
        }
        return Color.mOnSurface;
    }

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

            Rectangle {
                Layout.fillWidth: true
                color: Qt.alpha(Color.mPrimary, 0.08)
                radius: Style.radiusL
                border.color: Qt.alpha(Color.mPrimary, 0.16)
                border.width: 1
                implicitHeight: heroLayout.implicitHeight + (Style.marginM * 2)

                ColumnLayout {
                    id: heroLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginM

                        Rectangle {
                            Layout.preferredWidth: Math.round(42 * Style.uiScaleRatio)
                            Layout.preferredHeight: Math.round(42 * Style.uiScaleRatio)
                            radius: width / 2
                            color: Qt.alpha(Color.mPrimary, 0.14)
                            border.color: Qt.alpha(Color.mPrimary, 0.22)
                            border.width: 1

                            NIcon {
                                anchors.centerIn: parent
                                icon: mainInstance ? mainInstance.currentIconName : "world"
                                pointSize: Style.fontSizeL
                                color: Color.mPrimary
                            }
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
                                      : (pluginApi ? pluginApi.tr("status.probing") : "Probing network state...")
                                pointSize: Style.fontSizeXS
                                color: Color.mSecondary
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            radius: height / 2
                            color: providerBadgeColor()
                            border.color: Qt.alpha(Color.mOutline, 0.12)
                            border.width: 1
                            implicitHeight: badgeText.implicitHeight + (Style.marginS * 2)
                            implicitWidth: badgeText.implicitWidth + (Style.marginM * 2)

                            NText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: root.providerBadgeText()
                                pointSize: Style.fontSizeXS
                                font.weight: Font.Medium
                                color: root.providerBadgeTextColor()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Style.radiusM
                        color: Qt.alpha(Color.mSurface, 0.9)
                        border.color: Qt.alpha(Color.mOutline, 0.12)
                        border.width: 1
                        implicitHeight: liveLayout.implicitHeight + (Style.marginM * 2)

                        RowLayout {
                            id: liveLayout
                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginM

                            Rectangle {
                                Layout.preferredWidth: 4
                                Layout.fillHeight: true
                                radius: 2
                                color: mainInstance && (mainInstance.vpnConnected || mainInstance.blockyActive)
                                       ? Color.mPrimary
                                       : Qt.alpha(Color.mOutline, 0.35)
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
                                    text: mainInstance && mainInstance.currentDnsIp !== ""
                                          ? mainInstance.currentDnsIp
                                          : (pluginApi ? pluginApi.tr("panel.default_dns") : "Default (ISP)")
                                    pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        Rectangle {
                            Layout.fillWidth: true
                            radius: Style.radiusS
                            color: Qt.alpha(Color.mSurfaceVariant, 0.62)
                            implicitHeight: vpnChipText.implicitHeight + (Style.marginS * 2)

                            NText {
                                id: vpnChipText
                                anchors.centerIn: parent
                                text: "VPN " + (mainInstance && mainInstance.vpnConnected ? "On" : "Off")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: Style.radiusS
                            color: Qt.alpha(Color.mSurfaceVariant, 0.62)
                            implicitHeight: dnsChipText.implicitHeight + (Style.marginS * 2)

                            NText {
                                id: dnsChipText
                                anchors.centerIn: parent
                                text: "Resolver " + (mainInstance && mainInstance.blockyActive ? "Blocky" : (mainInstance && mainInstance.isCustomDns ? "Preset" : "Auto"))
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                font.weight: Font.Medium
                            }
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

            NText {
                Layout.fillWidth: true
                text: "Managed Modes"
                pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: Color.mSecondary
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
                    backgroundColor: root.actionBackground("mullvad")
                    textColor: root.actionTextColor("mullvad")
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("mullvad")
                }

                NButton {
                    Layout.fillWidth: true
                    text: "Blocky"
                    icon: "shield-check"
                    backgroundColor: root.actionBackground("blocky")
                    textColor: root.actionTextColor("blocky")
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("blocky")
                }

                NButton {
                    Layout.fillWidth: true
                    text: pluginApi ? pluginApi.tr("panel.default_dns") : "Default (ISP)"
                    icon: "world"
                    backgroundColor: root.actionBackground("default")
                    textColor: root.actionTextColor("default")
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("default")
                }

                NButton {
                    Layout.fillWidth: true
                    text: pluginApi ? pluginApi.tr("panel.toggle") : "Toggle"
                    icon: "switch-2"
                    backgroundColor: root.actionBackground("toggle")
                    textColor: root.actionTextColor("toggle")
                    enabled: !(mainInstance && mainInstance.isChanging)
                    onClicked: mainInstance && mainInstance.runAction("toggle")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Style.radiusM
                color: Qt.alpha(Color.mSurfaceVariant, 0.36)
                border.color: Qt.alpha(Color.mOutline, 0.12)
                border.width: 1
                implicitHeight: backendLayout.implicitHeight + (Style.marginM * 2)

                ColumnLayout {
                    id: backendLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NText {
                            text: "Backend"
                            pointSize: Style.fontSizeXS
                            color: Color.mSecondary
                        }

                        NText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: mainInstance ? mainInstance.oscCommand : "osc-mullvad"
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurface
                            elide: Text.ElideLeft
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
                }
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

                    delegate: Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        radius: Style.radiusM
                        color: root.providerIsActive(modelData.id)
                               ? Qt.alpha(Color.mPrimary, 0.12)
                               : Qt.alpha(Color.mSurfaceVariant, 0.34)
                        border.color: root.providerIsActive(modelData.id)
                                      ? Qt.alpha(Color.mPrimary, 0.2)
                                      : Qt.alpha(Color.mOutline, 0.12)
                        border.width: 1
                        implicitHeight: providerLayout.implicitHeight + (Style.marginM * 2)

                        RowLayout {
                            id: providerLayout
                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginM

                            Rectangle {
                                Layout.preferredWidth: Math.round(32 * Style.uiScaleRatio)
                                Layout.preferredHeight: Math.round(32 * Style.uiScaleRatio)
                                radius: width / 2
                                color: root.providerIsActive(modelData.id)
                                       ? Qt.alpha(Color.mPrimary, 0.14)
                                       : Qt.alpha(Color.mSurface, 0.75)

                                NIcon {
                                    anchors.centerIn: parent
                                    icon: modelData.icon
                                    pointSize: Style.fontSizeS
                                    color: root.providerIsActive(modelData.id) ? Color.mPrimary : Color.mOnSurface
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                NText {
                                    text: modelData.label
                                    pointSize: Style.fontSizeS
                                    font.weight: Font.Medium
                                    color: Color.mOnSurface
                                }

                                NText {
                                    text: modelData.ip
                                    pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            NText {
                                text: root.providerIsActive(modelData.id) ? "Active" : "Apply"
                                pointSize: Style.fontSizeXS
                                color: root.providerIsActive(modelData.id) ? Color.mPrimary : Color.mSecondary
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !(mainInstance && mainInstance.isChanging)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mainInstance && mainInstance.runAction("provider:" + modelData.id)
                        }
                    }
                }
            }
        }
    }
}
