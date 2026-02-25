import QtQuick
import Quickshell
import qs.Widgets

NIconButtonHot {
		property ShellScreen screen
		property var pluginApi: null

		icon: "file-text"
		tooltipText: pluginApi?.tr("bar_widget.tooltip") || "Scratchpad"

		onClicked: pluginApi?.togglePanel(screen, this)
}
