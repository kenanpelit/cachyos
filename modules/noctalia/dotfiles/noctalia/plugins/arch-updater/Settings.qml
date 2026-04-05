import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    // Commands
    property string nameCmd: pluginApi.pluginSettings.nameCmd || pluginApi.manifest.metadata.defaultSettings.nameCmd
    property string oldVerCmd: pluginApi.pluginSettings.oldVerCmd || pluginApi.manifest.metadata.defaultSettings.oldVerCmd
    property string newVerCmd: pluginApi.pluginSettings.newVerCmd || pluginApi.manifest.metadata.defaultSettings.newVerCmd
    property string updateCmd: pluginApi.pluginSettings.updateCmd || pluginApi.manifest.metadata.defaultSettings.updateCmd

    // Show toast on refresh
    property bool toast: pluginApi.pluginSettings.toast ?? pluginApi.manifest.metadata.defaultSettings.toast

    // Show hover tip on desktop widget
    property bool desktopTip: pluginApi.pluginSettings.desktopTip ?? pluginApi.manifest.metadata.defaultSettings.desktopTip

    // Also check for flatpaks
    property bool flatpak: pluginApi.pluginSettings.flatpak ?? pluginApi.manifest.metadata.defaultSettings.flatpak

    // Noctalia update highlighting
    property bool noctalia: pluginApi.pluginSettings.noctalia ?? pluginApi.manifest.metadata.defaultSettings.noctalia

    // Hide the bar widget when there are no updates
    property bool hideOnEmpty: pluginApi.pluginSettings.hideOnEmpty ?? pluginApi.manifest.metadata.defaultSettings.hideOnEmpty

    // Refresh after time intervals
    property bool refreshTimer: pluginApi.pluginSettings.refreshTimer ?? pluginApi.manifest.metadata.defaultSettings.refreshTimer
    
    // The time interval between available update refreshes
    property int refreshInterval: pluginApi.pluginSettings.refreshInterval || pluginApi.manifest.metadata.defaultSettings.refreshInterval

    spacing: Style.marginM

    // Runs when the plugin settings are loaded
    Component.onCompleted: {
        Logger.i("Update Widget", "Settings UI loaded")
    }

    NText { // Commands Heading
        text: pluginApi.tr("settings.commands")
        pointSize: Style.fontSizeXL
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    // Commands

    NTextInput { // Name Command
        Layout.fillWidth: true
        label: pluginApi.tr("settings.nameCmd")
        description: pluginApi.tr("settings.nameCmdDesc")
        placeholderText: pluginApi.manifest.metadata.defaultSettings.nameCmd
        text: root.nameCmd
        onTextChanged: {
            root.nameCmd = text
            Logger.d("Update Widget", "Name command set to: " + root.nameCmd)
        }
    }

    NTextInput { // Old Version Command
        Layout.fillWidth: true
        label: pluginApi.tr("settings.oldVerCmd")
        description: pluginApi.tr("settings.oldVerCmdDesc")
        placeholderText: pluginApi.manifest.metadata.defaultSettings.oldVerCmd
        text: root.oldVerCmd
        onTextChanged: {
            root.oldVerCmd = text
            Logger.d("Update Widget", "Name command set to: " + root.oldVerCmd)
        }
    }

    NTextInput { // New Version Command
        Layout.fillWidth: true
        label: pluginApi.tr("settings.newVerCmd")
        description: pluginApi.tr("settings.newVerCmdDesc")
        placeholderText: pluginApi.manifest.metadata.defaultSettings.newVerCmd
        text: root.newVerCmd
        onTextChanged: {
            root.newVerCmd = text
            Logger.d("Update Widget", "Name command set to: " + root.newVerCmd)
        }
    }

    NTextInput { // Update Command
        Layout.fillWidth: true
        label: pluginApi.tr("settings.updateCmd")
        description: pluginApi.tr("settings.updateCmdDesc")
        placeholderText: pluginApi.manifest.metadata.defaultSettings.updateCmd
        text: root.updateCmd
        onTextChanged: {
            root.updateCmd = text
            Logger.d("Update Widget", "Name command set to: " + root.updateCmd)
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Toggles

    // Toast Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: toastToggle.implicitHeight
        NToggle {
            id: toastToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.toast")
            description: pluginApi.tr("settings.toastDesc")
            checked: root.toast
            onToggled: checked => root.toast = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Flatpak Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: flatpakToggle.implicitHeight
        NToggle {
            id: flatpakToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.flatpak")
            description: pluginApi.tr("settings.flatpakDesc")
            checked: root.flatpak
            onToggled: checked => root.flatpak = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Noctalia Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: noctaliaToggle.implicitHeight
        NToggle {
            id: noctaliaToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.noctalia")
            description: pluginApi.tr("settings.noctaliaDesc")
            checked: root.noctalia
            onToggled: checked => root.noctalia = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

     // Hide On Empty Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: hideOnEmptyToggle.implicitHeight
        NToggle {
            id: hideOnEmptyToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.hideOnEmpty")
            description: pluginApi.tr("settings.hideOnEmptyDesc")
            checked: root.hideOnEmpty
            onToggled: checked => root.hideOnEmpty = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Desktop Hover Tip Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: desktopTipToggle.implicitHeight
        NToggle {
            id: desktopTipToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.desktopTip")
            description: pluginApi.tr("settings.desktopTipDesc")
            checked: root.desktopTip
            onToggled: checked => root.desktopTip = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Refresh Interval Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: refreshTimerToggle.implicitHeight
        NToggle {
            id: refreshTimerToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.refreshTimer")
            description: pluginApi.tr("settings.refreshTimerDesc")
            checked: root.refreshTimer
            onToggled: checked => root.refreshTimer = checked
        }
    }

    // Refresh Interval
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: root.refreshTimer
        NLabel {
            //label: pluginApi.tr("settings.interval")
            description: pluginApi.tr("settings.intervalDesc") + root.refreshInterval
        }
        NSlider {
            Layout.fillWidth: true
            from: 5
            to: 360
            stepSize: 5
            value: root.refreshInterval
            onValueChanged: {
                root.refreshInterval = value
                Logger.d("Update Widget", "Refresh interval set to: " + root.refreshInterval)
            }
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Save function - called by the dialog
    function saveSettings() {
        if (!pluginApi) {
            Logger.e("Update Widget", "Cannot save: pluginApi is null")
            return
        }

        pluginApi.pluginSettings.nameCmd = root.nameCmd
        pluginApi.pluginSettings.oldVerCmd = root.oldVerCmd
        pluginApi.pluginSettings.newVerCmd = root.newVerCmd
        pluginApi.pluginSettings.updateCmd = root.updateCmd

        pluginApi.pluginSettings.flatpak = root.flatpak
        pluginApi.pluginSettings.noctalia = root.noctalia
        pluginApi.pluginSettings.toast = root.toast
        pluginApi.pluginSettings.desktopTip = root.desktopTip
        pluginApi.pluginSettings.hideOnEmpty = root.hideOnEmpty
        pluginApi.pluginSettings.refreshTimer = root.refreshTimer

        pluginApi.pluginSettings.refreshInterval = root.refreshInterval

        pluginApi.saveSettings()
        root.pluginApi.mainInstance.refresh()

        Logger.i("Update Widget", "Settings saved successfully")
    }
}