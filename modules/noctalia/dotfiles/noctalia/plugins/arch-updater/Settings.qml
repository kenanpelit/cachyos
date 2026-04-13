import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    // Commands
    property string checkCmd: pluginApi.pluginSettings.checkCmd || pluginApi.manifest.metadata.defaultSettings.checkCmd
    property string updateCmd: pluginApi.pluginSettings.updateCmd || pluginApi.manifest.metadata.defaultSettings.updateCmd

    // Show toast on refresh
    property bool toast: pluginApi.pluginSettings.toast ?? pluginApi.manifest.metadata.defaultSettings.toast

    // Show hover tip on desktop widget
    property bool desktopTip: pluginApi.pluginSettings.desktopTip ?? pluginApi.manifest.metadata.defaultSettings.desktopTip

    // Also check for flatpaks
    property bool flatpak: pluginApi.pluginSettings.flatpak ?? pluginApi.manifest.metadata.defaultSettings.flatpak

    // Noctalia update highlighting
    property bool noctalia: pluginApi.pluginSettings.noctalia ?? pluginApi.manifest.metadata.defaultSettings.noctalia

    // Noctalia update highlighting
    property bool boldVer: pluginApi.pluginSettings.boldVer ?? pluginApi.manifest.metadata.defaultSettings.boldVer

    // Hide the bar widget when there are no updates
    property bool hideOnEmpty: pluginApi.pluginSettings.hideOnEmpty ?? pluginApi.manifest.metadata.defaultSettings.hideOnEmpty

    // Refresh after time intervals
    property bool refreshTimer: pluginApi.pluginSettings.refreshTimer ?? pluginApi.manifest.metadata.defaultSettings.refreshTimer

    // The time interval between available update refreshes
    property int refreshInterval: pluginApi.pluginSettings.refreshInterval || pluginApi.manifest.metadata.defaultSettings.refreshInterval

    // Appearance
    property bool tooltip: pluginApi.pluginSettings.tooltip ?? pluginApi.manifest.metadata.defaultSettings.tooltip
    property bool boldText: pluginApi.pluginSettings.boldText ?? pluginApi.manifest.metadata.defaultSettings.boldText
    property string iconName: pluginApi.pluginSettings.iconName || pluginApi.manifest.metadata.defaultSettings.iconName
    property bool useDistroLogo: pluginApi.pluginSettings.useDistroLogo ?? pluginApi.manifest.metadata.defaultSettings.useDistroLogo
    property string customIconPath: pluginApi.pluginSettings.customIconPath ?? pluginApi.manifest.metadata.defaultSettings.customIconPath
    property bool enableColorization: pluginApi.pluginSettings.enableColorization ?? pluginApi.manifest.metadata.defaultSettings.enableColorization
    property string iconColor: pluginApi.pluginSettings.iconColor ?? pluginApi.manifest.metadata.defaultSettings.iconColor ?? "none"

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

    NTextInput { // Check Command
        Layout.fillWidth: true
        label: pluginApi.tr("settings.checkCmd")
        description: pluginApi.tr("settings.checkCmdDesc")
        placeholderText: pluginApi.manifest.metadata.defaultSettings.checkCmd
        text: root.checkCmd
        onTextChanged: {
            root.checkCmd = text
            Logger.d("Update Widget", "Check command set to: " + root.checkCmd)
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

    // Bold New Version Number Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: boldVerToggle.implicitHeight
        NToggle {
            id: boldVerToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.boldVer")
            description: pluginApi.tr("settings.boldVerDesc")
            checked: root.boldVer
            onToggled: checked => root.boldVer = checked
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

    // Bar Appearance

    NText {
        text: pluginApi.tr("settings.appearance")
        pointSize: Style.fontSizeXL
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    // Bold Text Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: boldTextToggle.implicitHeight
        NToggle {
            id: boldTextToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.boldText")
            description: pluginApi.tr("settings.boldTextDesc")
            checked: root.boldText
            onToggled: checked => root.boldText = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Tooltip Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: tooltipToggle.implicitHeight
        NToggle {
            id: tooltipToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.tooltip")
            description: pluginApi.tr("settings.tooltipDesc")
            checked: root.tooltip
            onToggled: checked => root.tooltip = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Use Distro Logo Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: distroLogoToggle.implicitHeight
        NToggle {
            id: distroLogoToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.useDistroLogo")
            description: pluginApi.tr("settings.useDistroLogoDesc")
            checked: root.useDistroLogo
            onToggled: checked => root.useDistroLogo = checked
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Enable Colorization Toggle
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: colorizeToggle.implicitHeight
        NToggle {
            id: colorizeToggle
            anchors.fill: parent
            label: pluginApi.tr("settings.enableColorization")
            description: pluginApi.tr("settings.enableColorizationDesc")
            checked: root.enableColorization
            onToggled: checked => root.enableColorization = checked
        }
    }

    // Icon Color (only visible when colorization is enabled)
    NColorChoice {
        visible: root.enableColorization
        label: pluginApi.tr("settings.iconColor")
        description: pluginApi.tr("settings.iconColorDesc")
        currentKey: root.iconColor
        onSelected: key => root.iconColor = key
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    // Icon preview and selection
    RowLayout {
        spacing: Style.marginM

        NLabel {
            label: pluginApi.tr("settings.iconName")
            description: pluginApi.tr("settings.iconNameDesc")
        }

        NImageRounded {
            Layout.preferredWidth: Style.fontSizeXL * 2
            Layout.preferredHeight: Style.fontSizeXL * 2
            Layout.alignment: Qt.AlignVCenter
            radius: Math.min(Style.radiusL, Layout.preferredWidth / 2)
            imagePath: root.customIconPath
            visible: root.customIconPath !== "" && !root.useDistroLogo
        }

        NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: root.iconName
            pointSize: Style.fontSizeXXL * 1.5
            visible: root.iconName !== "" && root.customIconPath === "" && !root.useDistroLogo
        }
    }

    RowLayout {
        spacing: Style.marginM
        NButton {
            enabled: !root.useDistroLogo
            text: pluginApi.tr("settings.browseLibrary")
            onClicked: iconPicker.open()
        }
        NButton {
            enabled: !root.useDistroLogo
            text: pluginApi.tr("settings.browseFile")
            onClicked: imagePicker.openFilePicker()
        }
    }

    NIconPicker {
        id: iconPicker
        initialIcon: root.iconName
        onIconSelected: iconName => {
            root.iconName = iconName
            root.customIconPath = ""
        }
    }

    NFilePicker {
        id: imagePicker
        title: pluginApi.tr("settings.selectCustomIcon")
        selectionMode: "files"
        nameFilters: ImageCacheService.basicImageFilters.concat(["*.svg"])
        initialPath: Quickshell.env("HOME")
        onAccepted: paths => {
            if (paths.length > 0) {
                root.customIconPath = paths[0]
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

        pluginApi.pluginSettings.checkCmd = root.checkCmd
        pluginApi.pluginSettings.updateCmd = root.updateCmd

        pluginApi.pluginSettings.flatpak = root.flatpak
        pluginApi.pluginSettings.noctalia = root.noctalia
        pluginApi.pluginSettings.boldVer = root.boldVer
        pluginApi.pluginSettings.toast = root.toast
        pluginApi.pluginSettings.desktopTip = root.desktopTip
        pluginApi.pluginSettings.hideOnEmpty = root.hideOnEmpty
        pluginApi.pluginSettings.refreshTimer = root.refreshTimer

        pluginApi.pluginSettings.refreshInterval = root.refreshInterval

        pluginApi.pluginSettings.tooltip = root.tooltip
        pluginApi.pluginSettings.boldText = root.boldText
        pluginApi.pluginSettings.iconName = root.iconName
        pluginApi.pluginSettings.useDistroLogo = root.useDistroLogo
        pluginApi.pluginSettings.customIconPath = root.customIconPath
        pluginApi.pluginSettings.enableColorization = root.enableColorization
        pluginApi.pluginSettings.iconColor = root.iconColor

        pluginApi.saveSettings()
        root.pluginApi.mainInstance.refresh()

        Logger.i("Update Widget", "Settings saved successfully")
    }
}