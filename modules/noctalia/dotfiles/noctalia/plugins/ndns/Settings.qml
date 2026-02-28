import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    property string oscCommand: pluginApi?.pluginSettings?.oscCommand
                                || pluginApi?.manifest?.metadata?.defaultSettings?.oscCommand
                                || "osc-mullvad"

    spacing: Style.marginL

    NLabel {
        label: "NDNS"
        description: "Panel control and backend command settings."
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Backend Command"
        description: "Executable used for Mullvad / Blocky switching."
        placeholderText: "osc-mullvad"
        text: root.oscCommand
        onTextChanged: root.oscCommand = text
    }

    RowLayout {
        spacing: Style.marginM

        NButton {
            text: "Toggle Panel"
            onClicked: {
                if (pluginApi && pluginApi.withCurrentScreen) {
                    pluginApi.withCurrentScreen(function(screen) {
                        pluginApi.togglePanel(screen, null);
                    });
                }
            }
        }

        NButton {
            text: "Sync / Repair"
            onClicked: {
                if (pluginApi && pluginApi.mainInstance) {
                    pluginApi.mainInstance.runAction("repair");
                }
            }
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            return;
        }

        pluginApi.pluginSettings.oscCommand = root.oscCommand || "osc-mullvad";
        pluginApi.saveSettings();

        if (pluginApi.withCurrentScreen) {
            pluginApi.withCurrentScreen(function(screen) {
                pluginApi.closePanel(screen);
            });
        }
    }
}
