import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property var screen: null
    readonly property var mainInstance: pluginApi?.mainInstance

    icon: mainInstance?.currentIconName || "world"

    property bool isActive: Boolean(mainInstance?.vpnConnected || mainInstance?.blockyActive)

    colorBg: isActive ? Color.mPrimary : Color.mSurfaceVariant
    colorFg: isActive ? Color.mOnPrimary : Color.mOnSurface

    tooltipText: mainInstance?.currentStatusDetail || pluginApi?.tr("plugin.title") || "DNS / VPN Switcher"

    onClicked: {
        if (pluginApi) {
            pluginApi.openPanel(root.screen, root);
        }
    }
}
