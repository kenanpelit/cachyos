import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var modeMeta: mainInstance?.currentMeta || ({})
  readonly property string shortLabel: modeMeta.shortLabel || ""
  readonly property string colorKey: modeMeta.color || "none"
  readonly property color backgroundColor: {
    switch (colorKey) {
    case "primary":
      return Color.mPrimary;
    case "secondary":
      return Color.mSecondary;
    default:
      return Style.capsuleColor;
    }
  }
  readonly property color foregroundColor: {
    switch (colorKey) {
    case "primary":
      return Color.mOnPrimary;
    case "secondary":
      return Color.mOnSecondary;
    default:
      return Color.mOnSurface;
    }
  }

  visible: CompositorService.isMango && (mainInstance?.modeActive ?? false)
  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: modeMeta.icon || "keyboard"
    text: shortLabel
    tooltipText: (modeMeta.label || "Mode") + " Mode\n"
               + (modeMeta.hint || "Esc exits current Mango keymode")
               + "\nClick: exit mode\nRight click: cheatsheet"
    forceOpen: true
    customBackgroundColor: root.backgroundColor
    customTextIconColor: root.foregroundColor

    onClicked: {
      mainInstance?.exitMode();
    }

    onRightClicked: {
      mainInstance?.openCheatsheet();
    }
  }
}
