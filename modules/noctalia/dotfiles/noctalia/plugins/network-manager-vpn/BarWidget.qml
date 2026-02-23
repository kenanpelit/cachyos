import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Modules.Bar.Extras

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property var vpnList: main?.vpnList ?? []
    readonly property bool anyConnected: main?.anyConnected ?? false
    readonly property bool isLoading: main?.isLoading ?? false

    implicitWidth: pill.width
    implicitHeight: pill.height

    BarPill {
        id: pill

        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        autoHide: false
        text: pluginApi?.tr("common.vpn") || "VPN"
        icon: root.isLoading ? "reload"
            : root.anyConnected ? "shield-lock" : "shield"

        onClicked: {
            if (pluginApi) pluginApi.openPanel(root.screen, root)
        }
    }


    Component.onCompleted: {
        Logger.i("NetworkManagerVPN", "Bar widget loaded")
    }
}
