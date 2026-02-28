import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property var screen: null
    readonly property var mainInstance: pluginApi?.mainInstance

    readonly property bool protectedMode: Boolean(mainInstance?.vpnConnected || mainInstance?.blockyActive)
    readonly property bool customMode: Boolean(mainInstance?.isCustomDns && !protectedMode)

    icon: mainInstance?.currentIconName || "world"

    colorBg: protectedMode
             ? Qt.alpha(Color.mPrimary, 0.16)
             : (customMode ? Qt.alpha(Color.mSurfaceVariant, 0.9) : Color.mSurfaceVariant)
    colorFg: protectedMode ? Color.mPrimary : Color.mOnSurface

    tooltipText: mainInstance
                 ? ((mainInstance.currentDnsName || (pluginApi?.tr("plugin.title") || "DNS / VPN Switcher"))
                    + "\n"
                    + (mainInstance.currentStatusDetail || ""))
                 : (pluginApi?.tr("plugin.title") || "DNS / VPN Switcher")

    onClicked: {
        if (pluginApi) {
            pluginApi.openPanel(root.screen, root);
        }
    }
}
