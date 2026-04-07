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

    // Structured update data (used by Panel)
    property var updates: []

    // State
    property bool refreshing: false

    // Counts
    property int updateCount: 0
    property int flatpakCount: 0

    // Noctalia updates
    property variant noctaliaNames: ["noctalia-qs", "noctalia-shell"]
    property bool noctaliaUpdate: false

    function checkNoctalia() {
        if (noctaliaNames.some(name => root.nameStr.includes(name)) && (pluginApi.pluginSettings.noctalia ?? pluginApi.manifest.metadata.defaultSettings.noctalia ?? true)) {
            root.noctaliaUpdate = true
            Logger.d("Update Widget", "Noctalia updates found")
        } else {
            Logger.d("Update Widget", "No Noctalia updates found")
        }
    }

    Component.onCompleted: {
        refresh()
    }

    function refresh() {
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
        root.updates = []
        root.updateCount = 0
        root.flatpakCount = 0
        root.noctaliaUpdate = false
        root.refreshing = true

        // Use configurable check command (output format: "name oldver -> newver")
        getUpdates.command = ["sh", "-c", pluginApi.pluginSettings.checkCmd || pluginApi.manifest.metadata.defaultSettings.checkCmd]
        getUpdates.running = true
    }

    function update() {
        Logger.i("Update Widget", "Updating...")
        runUpdate.command = ["sh", "-c", pluginApi.pluginSettings.updateCmd || pluginApi.manifest.metadata.defaultSettings.updateCmd]
        runUpdate.running = true
    }

    // Single process for all system update data
    // Expected output format: "name oldver -> newver" per line
    Process {
        id: getUpdates
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Logger.w("Update Widget", "Check command exited with code " + exitCode)
                root.refreshing = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var output = this.text.slice(0, -1)
                if (!output) {
                    Logger.d("Update Widget", "No system updates found")
                    // Still start flatpak check if enabled
                    if (pluginApi.pluginSettings.flatpak ?? pluginApi.manifest.metadata.defaultSettings.flatpak) {
                        getFlatpakUpdates.running = true
                    } else {
                        root.refreshing = false
                    }
                    return
                }

                var lines = output.split("\n")
                var names = []
                var oldVers = []
                var newVers = []
                var rows = []

                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(/\s+/)
                    // Expected format: name oldver -> newver
                    if (parts.length >= 4) {
                        names.push(parts[0])
                        oldVers.push(parts[1])
                        newVers.push(parts[3])
                        rows.push({ name: parts[0], oldVer: parts[1], newVer: parts[3], isFlatpak: false })
                    }
                }

                root.nameStr = names.join("\n")
                root.oldVerStr = oldVers.join("\n")
                root.newVerStr = newVers.join("\n")
                root.updateCount = names.length
                root.updates = rows

                Logger.d("Update Widget", "System updates: " + root.updateCount)
                checkNoctalia()

                // Chain: start flatpak check after system updates are done
                if (pluginApi.pluginSettings.flatpak ?? pluginApi.manifest.metadata.defaultSettings.flatpak) {
                    getFlatpakUpdates.running = true
                } else {
                    root.refreshing = false
                }
            }
        }
    }

    // Single process for all flatpak update data
    // Joins remote (new) versions with installed (old) versions by application ID
    // Output format: application\tname\tnewver\toldver
    Process {
        id: getFlatpakUpdates
        command: ["sh", "-c", "join -t'\t' -j1 <(flatpak remote-ls --updates --columns=application,name,version 2>/dev/null | sort -t'\t' -k1,1) <(flatpak list --columns=application,version 2>/dev/null | sort -t'\t' -k1,1)"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Logger.w("Update Widget", "Flatpak check exited with code " + exitCode)
                root.refreshing = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var output = this.text.slice(0, -1)
                if (!output) {
                    Logger.d("Update Widget", "No flatpak updates found")
                    root.refreshing = false
                    return
                }

                var lines = output.split("\n")
                var names = []
                var oldVers = []
                var newVers = []
                var current = root.updates.slice()

                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(/\t+/)
                    // Expected: application\tname\tnewver\toldver
                    if (parts.length >= 4) {
                        var name = parts[1].trim()
                        var newVer = parts[2].trim()
                        var oldVer = parts[3].trim()
                        names.push(name)
                        newVers.push(newVer)
                        oldVers.push(oldVer)
                        current.push({ name: name, oldVer: oldVer, newVer: newVer, isFlatpak: true })
                    }
                }

                root.flatpakNameStr = names.join("\n")
                root.flatpakNewVerStr = newVers.join("\n")
                root.flatpakOldVerStr = oldVers.join("\n")
                root.flatpakCount = names.length
                root.updates = current

                Logger.d("Update Widget", "Flatpak updates: " + root.flatpakCount)
                root.refreshing = false
            }
        }
    }

    Process {
        id: runUpdate
        stdout: StdioCollector {
            onStreamFinished: {
                refresh()
            }
        }
    }

    Timer {
        interval: (pluginApi.pluginSettings.refreshInterval || pluginApi.manifest.metadata.defaultSettings.refreshInterval) * 60000
        running: true
        repeat: true
        onTriggered: {
            Logger.d("Update Widget", "Timer refresh...")
            refresh()
        }
    }

    IpcHandler {
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
