import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property bool protectedMode: Boolean(mainInstance?.vpnConnected || mainInstance?.blockyActive)
    readonly property bool customMode: Boolean(mainInstance?.isCustomDns && !protectedMode)

    readonly property real contentWidth: contentRow.implicitWidth + (Style.marginM * 2)
    readonly property real contentHeight: Style.capsuleHeight
    readonly property color capsuleBg: protectedMode
                                      ? Qt.alpha(Color.mPrimary, 0.14)
                                      : (customMode ? Qt.alpha(Color.mSurfaceVariant, 0.92) : Style.capsuleColor)
    readonly property color capsuleFg: protectedMode
                                      ? Color.mPrimary
                                      : (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : root.capsuleBg
        radius: height / 2
        border.color: protectedMode ? Qt.alpha(Color.mPrimary, 0.22) : Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: Style.marginS

            Rectangle {
                Layout.preferredWidth: Math.round(20 * Style.uiScaleRatio)
                Layout.preferredHeight: Math.round(20 * Style.uiScaleRatio)
                radius: width / 2
                color: protectedMode ? Qt.alpha(Color.mPrimary, 0.12) : Qt.alpha(Color.mSurfaceVariant, 0.7)

                NIcon {
                    anchors.centerIn: parent
                    icon: mainInstance?.currentIconName || "world"
                    pointSize: Style.fontSizeS
                    color: root.capsuleFg
                }
            }

            NText {
                text: mainInstance?.currentDnsName || pluginApi?.tr("plugin.short_title") || "DNS"
                color: root.capsuleFg
                pointSize: Style.barFontSize
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: width / 2
                color: protectedMode ? Color.mPrimary : (customMode ? Color.mSecondary : Qt.alpha(Color.mOutline, 0.45))
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (pluginApi) {
                pluginApi.openPanel(root.screen, root);
            }
        }
    }
}
