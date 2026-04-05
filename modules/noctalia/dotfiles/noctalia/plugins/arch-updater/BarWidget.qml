import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System
import qs.Modules.Bar.Extras

Item {
    id: root

    // Plugin API (injected by PluginService)
    property var pluginApi: null

    // Required properties for bar widgets
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // Per-screen bar properties (for multi-monitor and vertical bar support)
    readonly property string screenName: screen.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    // Content dimensions (visual capsule size)
    readonly property real contentWidth: content.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    // Widget dimensions (extends to full bar height for better click area)
    implicitWidth: contentWidth
    implicitHeight: contentHeight

    // Hide on empty
    visible: (root.pluginApi.mainInstance.updateCount + root.pluginApi.mainInstance.flatpakCount) | !(pluginApi.pluginSettings.hideOnEmpty ?? pluginApi.manifest.metadata.defaultSettings.hideOnEmpty)

    // Tooltip Text
    property string tooltipText: root.pluginApi.mainInstance.nameStr + (root.pluginApi.mainInstance.flatpakCount ? "\n\n" : "") + root.pluginApi.mainInstance.flatpakNameStr
    property string tooltipTextTrimmed: root.tooltipText.split("\n").slice(0, 30).join("\n")

    // Visual capsule - centered within the full click area
    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : (root.pluginApi.mainInstance.noctaliaUpdate ? "#40" + Color.mTertiary.toString().slice(1) : Style.capsuleColor)
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout { // Widget
            id: content
            anchors.centerIn: parent
            spacing: Style.marginS
            NIcon { // Icon
                color: mouseArea.containsMouse ? Color.mOnHover : (root.pluginApi.mainInstance.noctaliaUpdate ? Color.mHover : Color.mPrimary)
                icon: (root.pluginApi.mainInstance.noctaliaUpdate | mouseArea.containsMouse) ? "arrow-big-down-lines-filled" : "arrow-big-down-lines"
            }
            NText { // Count
                text: (root.pluginApi.mainInstance.updateCount + root.pluginApi.mainInstance.flatpakCount).toString() // Total count (system + flatpak)
                color: mouseArea.containsMouse ? Color.mOnHover : (root.pluginApi.mainInstance.noctaliaUpdate ? Color.mSecondary : Color.mOnSurface)
                pointSize: Style.fontSizeM
                font.weight: Font.Bold
            }
        }
    }

    NPopupContextMenu { // Context menu
        id: contextMenu
        model: [
            {
                "label": pluginApi.tr("context.refresh"),
                "action": "refresh",
                "icon": "refresh"
            },
            {
                "label": pluginApi.tr("context.update"),
                "action": "update",
                "icon": "arrow-big-down-lines"
            },
            {
                "label": pluginApi.tr("context.settings"),
                "action": "settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            // Always close the menu first
            contextMenu.close();
            PanelService.closeContextMenu(screen);

            // Handle actions
            if (action === "refresh") {
                Logger.d("Update Widget", "Refreshing from context menu...")
                root.pluginApi.mainInstance.refresh() // Refresh available updates
            }
            else if (action === "update") {
                Logger.d("Update Widget", "Updating from context menu...")
                root.pluginApi.mainInstance.update() // Update
            }
            else if (action === "settings") {
                Logger.d("Update Widget", "Opening settings from context menu...")
                BarService.openPluginSettings(screen, pluginApi.manifest) // Open plugin settings
            }
        }
    }

    MouseArea { // MouseArea at root level for extended click area
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                Logger.d("Update Widget", "Opening panel from bar...")
                pluginApi.openPanel(root.screen, root) // Open panel
            }
            else if (mouse.button === Qt.RightButton) {
                Logger.d("Update Widget", "Opening context menu from bar...")
                PanelService.showContextMenu(contextMenu, root, screen) // Open context menu
            }
            else if (mouse.button === Qt.MiddleButton) {
                Logger.d("Update Widget", "Refreshing from bar...")
                root.pluginApi.mainInstance.refresh() // Refresh available updates
            }
        }
        onEntered: {
            // Tooltip shows available updates for both system and flatpak
            TooltipService.show(root, (root.pluginApi.mainInstance.noctaliaUpdate ? pluginApi.tr("tooltip.noctaliaUpdates") : pluginApi.tr("tooltip.availableUpdates")) + "\n---------------\n" + (root.tooltipTextTrimmed !== root.tooltipText ? root.tooltipTextTrimmed + "\n..." : root.tooltipTextTrimmed), BarService.getTooltipDirection())
        }

        onExited: {
            TooltipService.hide()
        }
    }
}