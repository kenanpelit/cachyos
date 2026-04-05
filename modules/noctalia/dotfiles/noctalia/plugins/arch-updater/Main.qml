import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    // Plugin API (injected by PluginService)
    property var pluginApi: null 
    
    // System
    property string nameStr: ""
    property string newVerStr: ""
    property string oldVerStr: ""

    // Flatpak
    property string flatpakNameStr: ""
    property string flatpakNewVerStr: ""
    property string flatpakOldVerStr: ""

    // Plugins
    property string pluginNameStr: ""
    property string pluginNewVerStr: ""
    property string pluginOldVerStr: ""

    // Counts
    property int updateCount: 0
    property int flatpakCount: 0

    // Noctalia updates
    property variant noctaliaNames: ["noctalia-qs", "noctalia-shell"]
    property bool noctaliaUpdate: false

    function checkNoctalia() { // Check Noctalia Updates
        if (noctaliaNames.some(name => root.nameStr.includes(name)) && (pluginApi.pluginSettings.noctalia ?? pluginApi.manifest.metadata.defaultSettings.toast ?? true)) {
            root.noctaliaUpdate = true
            Logger.d("Update Widget", "Noctalia updates found");
        } else {
            Logger.d("Update Widget", "No Noctalia updates found");
        }
    }

    // On plugin load
    Component.onCompleted: {
        refresh()
    }
    
    function refresh() { // Refresh available updates
        Logger.i("Update Widget", "Refreshing updates...")
        if (pluginApi.pluginSettings.toast ?? pluginApi.manifest.metadata.defaultSettings.toast ?? true) {
            ToastService.showNotice("Refreshing updates...")
        }
        root.nameStr = ""
        root.newVerStr = ""
        root.oldVerStr = ""
        root.flatpakNameStr = ""
        root.flatpakNewVerStr = ""
        root.flatpakOldVerStr = ""
        root.pluginNameStr = ""
        root.pluginNewVerStr = ""
        root.pluginOldVerStr = ""
        root.updateCount = 0
        root.flatpakCount = 0
        root.noctaliaUpdate = false

        getNames.command   = ["sh", "-c", pluginApi.pluginSettings.nameCmd   || pluginApi.manifest.metadata.defaultSettings.nameCmd]
        getOldVers.command = ["sh", "-c", pluginApi.pluginSettings.oldVerCmd || pluginApi.manifest.metadata.defaultSettings.oldVerCmd]
        getNewVers.command = ["sh", "-c", pluginApi.pluginSettings.newVerCmd || pluginApi.manifest.metadata.defaultSettings.newVerCmd]

        getNames.running = true
        getFlatpakIDs.running = pluginApi.pluginSettings.flatpak ?? pluginApi.manifest.metadata.defaultSettings.flatpak
    }
    function update() { // Run Update
        Logger.i("Update Widget", "Updating...")
        runUpdate.command = ["sh", "-c", pluginApi.pluginSettings.updateCmd || pluginApi.manifest.metadata.defaultSettings.updateCmd]
        runUpdate.running = true
    }

    // System Updates
    Process { // Update Names
        id: getNames
        stdout: StdioCollector {
            onStreamFinished: {
                root.nameStr = this.text.slice(0,-1) // Slice removes the newline from the end of the output
                root.updateCount = root.nameStr ? root.nameStr.split("\n").length : 0
                Logger.d("Update Widget", "Update names: " + root.nameStr.split("\n"))
                Logger.d("Update Widget", "Update count: " + root.updateCount)
                checkNoctalia()

                getOldVers.running = true
            }
        }
    }
    Process { // Update Old Versions
        id: getOldVers
        stdout: StdioCollector {
            onStreamFinished: {
                root.oldVerStr = this.text.slice(0,-1)
                Logger.d("Update Widget", "Update old versions: " + root.oldVerStr.split("\n"))

                getNewVers.running = true
            }
        }
    }
    Process { // Update New Versions
        id: getNewVers
        stdout: StdioCollector {
            onStreamFinished: {
                root.newVerStr = this.text.slice(0,-1)
                Logger.d("Update Widget", "Update new versions: " + root.newVerStr.split("\n"))
            }
        }
    }

    // Flatpak Updates
    Process { // Flatpak IDs
        id: getFlatpakIDs
        command: ["sh", "-c", " flatpak remote-ls --updates --columns=application | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                Logger.d("Update Widget", "Flatpak refresh")
                root.flatpakCount = this.text.slice(0,-1) ? this.text.slice(0,-1).split("\n").length : 0
                Logger.d("Update Widget", "Flatpak update IDs: " + this.text.slice(0,-1).slice("\n"))
                Logger.d("Update Widget", "Flatpak count: " + root.flatpakCount)

                if (root.flatpakCount) {
                    getFlatpakOldVers.command = ["sh", "-c", "flatpak list --columns=application,version | grep -E '" + this.text.slice(0,-1).replace(/\n/g, "|") +"' | sort | awk '{print $2}'"]
                    getFlatpakOldVers.running = true
                }
            }
        }
    }
    Process { // Flatpak Old Versions
        id: getFlatpakOldVers
        stdout: StdioCollector {
            onStreamFinished: {
                root.flatpakOldVerStr = this.text.slice(0, -1)
                Logger.d("Update Widget", "Flatpak update old versions: " + root.flatpakOldVerStr.split("\n"))
                getFlatpakNewVers.running = true
            }
        }
    }
    Process { // Flatpak New Versions
        id: getFlatpakNewVers
        command: ["sh", "-c", "flatpak remote-ls --updates --columns=application,version | sort | awk '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.flatpakNewVerStr = this.text.slice(0, -1)
                Logger.d("Update Widget", "Flatpak update new versions: " + root.flatpakNewVerStr.split("\n"))
                getFlatpakNames.running = true
            }
        }
    }
    Process { // Flatpak Names
        id: getFlatpakNames
        command: ["sh", "-c", "flatpak remote-ls --updates --columns=application,name | sort | awk '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.flatpakNameStr = this.text.slice(0, -1)
                Logger.d("Update Widget", "Flatpak update names: " + root.flatpakNameStr.split("\n"))
            }
        }
    }
    
    Process { // Update process
        id: runUpdate

        stdout: StdioCollector {
            onStreamFinished: {
                refresh()
            }
        }
    }

    Timer { // Refresh interval timer
        interval: (pluginApi.pluginSettings.refreshInterval || pluginApi.manifest.metadata.defaultSettings.refreshInterval) * 60000
        running: true
        repeat: true

        onTriggered: {
            Logger.d("Update Widget", "Timer refresh...")
            refresh()
        }
    }

    IpcHandler { // IPC!
        target: "plugin:arch-updater"

        function refresh() {
            Logger.d("Update Widget", "Refreshing through IPC...")
            root.pluginApi.mainInstance.refresh()
        }

        function update() {
            Logger.d("Update Widget", "Updating through IPC...")
            root.pluginApi.mainInstance.update()
        }
    }
}