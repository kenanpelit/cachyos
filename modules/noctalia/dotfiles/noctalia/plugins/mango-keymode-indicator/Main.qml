import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property string currentMode: "default"
  property string currentOutput: ""
  property bool readyForAnnouncements: false
  property bool hasMmsg: true

  readonly property bool modeActive: currentMode !== "default" && currentMode !== "common"
  readonly property var modeMeta: ({
    "default": {
      "label": "Default",
      "shortLabel": "",
      "icon": "keyboard",
      "hint": "Normal Mango binds active",
      "color": "none"
    },
    "layout": {
      "label": "Layout",
      "shortLabel": "LAYOUT",
      "icon": "layout-board",
      "hint": "H/L size, J/K masters, T/V/C/X layouts, Esc exit",
      "color": "primary"
    },
    "monitor": {
      "label": "Monitor",
      "shortLabel": "MONITOR",
      "icon": "device-desktop",
      "hint": "H/J/K/L focus, Shift+H/J/K/L move tag, Esc exit",
      "color": "secondary"
    }
  })

  readonly property var currentMeta: modeMeta[currentMode] || {
    "label": formatModeLabel(currentMode),
    "shortLabel": formatModeLabel(currentMode).toUpperCase(),
    "icon": "keyboard",
    "hint": "Esc exits current Mango keymode",
    "color": "none"
  }

  visible: CompositorService.isMango

  function normalizeMode(mode) {
    var normalized = String(mode || "").trim().toLowerCase();
    return normalized.length > 0 ? normalized : "default";
  }

  function formatModeLabel(mode) {
    var normalized = normalizeMode(mode);
    return normalized.charAt(0).toUpperCase() + normalized.slice(1).replace(/_/g, " ");
  }

  function parseModeLine(line) {
    var text = String(line || "").trim();
    if (!text.length)
      return null;

    var match = text.match(/^(?:(\S+)\s+)?keymode\s+(\S+)$/);
    if (!match)
      return null;

    return {
      output: match[1] || "",
      mode: normalizeMode(match[2])
    };
  }

  function toastEnabled() {
    return (pluginApi?.pluginSettings?.showToasts
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.showToasts
            ?? true) && hasMmsg;
  }

  function toastDuration() {
    return pluginApi?.pluginSettings?.toastDuration
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.toastDuration
        ?? 1400;
  }

  function applyMode(mode, outputName, announce) {
    var normalized = normalizeMode(mode);
    var changed = normalized !== currentMode;

    currentMode = normalized;
    if (outputName)
      currentOutput = outputName;

    if (!changed || !announce || !readyForAnnouncements || !toastEnabled() || !modeActive)
      return;

    var meta = currentMeta;
    ToastService.showNotice(meta.label + " Mode", meta.hint, meta.icon, toastDuration());
  }

  function refresh() {
    if (!CompositorService.isMango)
      return;

    modeQuery.running = false;
    modeWatcher.running = false;
    modeQuery.running = true;
    if (hasMmsg)
      modeWatcher.running = true;
  }

  function exitMode() {
    if (!modeActive || !hasMmsg)
      return;

    Quickshell.execDetached(["mmsg", "-d", "setkeymode,default"]);
  }

  function openCheatsheet() {
    Quickshell.execDetached(["osc-shell", "ipc", "call", "plugin:keybind-cheatsheet", "toggle"]);
  }

  Component.onCompleted: {
    refresh();
  }

  onVisibleChanged: {
    if (visible) {
      refresh();
    } else {
      modeQuery.running = false;
      modeWatcher.running = false;
    }
  }

  Process {
    id: modeQuery
    command: ["mmsg", "-g", "-b"]
    running: false
    property bool sawMode: false

    stdout: SplitParser {
      onRead: line => {
        var parsed = root.parseModeLine(line);
        if (!parsed)
          return;

        modeQuery.sawMode = true;
        root.applyMode(parsed.mode, parsed.output, false);
      }
    }

    onExited: exitCode => {
      root.hasMmsg = exitCode === 0;
      if (!modeQuery.sawMode)
        root.applyMode("default", "", false);

      modeQuery.sawMode = false;
      root.readyForAnnouncements = true;
    }
  }

  Process {
    id: modeWatcher
    command: ["mmsg", "-w", "-b"]
    running: false

    stdout: SplitParser {
      onRead: line => {
        var parsed = root.parseModeLine(line);
        if (!parsed)
          return;

        root.applyMode(parsed.mode, parsed.output, true);
      }
    }

    onExited: exitCode => {
      root.hasMmsg = exitCode === 0;
      if (root.visible && root.hasMmsg) {
        Qt.callLater(function () {
          modeWatcher.running = true;
        });
      }
    }
  }
}
