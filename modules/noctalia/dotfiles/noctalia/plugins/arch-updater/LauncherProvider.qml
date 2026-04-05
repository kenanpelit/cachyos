import QtQuick
import qs.Commons

Item {
    id: root

    // Required properties
    property var pluginApi: null
    property var launcher: null
    property string name: "Update Widget"

    // Return available commands when user types ">"
    function commands() {
        return [
            {
                "name": ">au-refresh",
                "description": pluginApi.tr("launcher.refreshDesc"),
                "icon": "refresh",
                "isTablerIcon": true,
                "onActivate": function() {
                    root.pluginApi.mainInstance.refresh()
                }
            },
            {
                "name": ">au-update",
                "description": pluginApi.tr("launcher.updateDesc"),
                "icon": "arrow-big-down-lines",
                "isTablerIcon": true,
                "onActivate": function() {
                    root.pluginApi.mainInstance.update()
                }
            }
        ]
    }
}