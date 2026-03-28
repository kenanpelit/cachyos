import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "MusicUtils.js" as MusicUtils

Item {
  id: root

  property var pluginApi: null

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var geometryPlaceholder: panelContainer
  readonly property string helperPath: mainInstance?.helperPath || Qt.resolvedUrl("musicctl.sh").toString().replace("file://", "")
  readonly property bool hasPlayback: mainInstance?.isPlaying === true || mainInstance?.playbackStarting === true
  readonly property var filteredLibraryEntries: buildFilteredLibraryEntries()
  readonly property var recentLibraryEntries: buildRecentLibraryEntries()

  property real contentPreferredWidth: 620 * Style.uiScaleRatio
  property real contentPreferredHeight: 760 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  property string activeTab: "search"
  property string searchText: ""
  property string libraryFilterText: ""
  property var searchResults: []
  property string searchError: ""
  property bool searchBusy: false
  property string activeSearchQuery: ""
  property string pendingSearchQuery: ""
  property string lastCompletedQuery: ""
  property string runningSearchQuery: ""
  property string runningSearchProvider: ""
  property int searchEpoch: 0
  property int runningSearchEpoch: 0
  property bool pendingSearchRestart: false
  property bool seekDragging: false
  property real localSeekRatio: -1

  anchors.fill: parent

  Process {
    id: searchProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      var completedQuery = root.runningSearchQuery;
      var staleSearch = root.runningSearchEpoch !== root.searchEpoch;

      root.searchBusy = false;
      root.searchError = "";

      if (!staleSearch && exitCode === 0) {
        try {
          var parsed = JSON.parse(searchProcess.stdout.text || "[]");
          root.searchResults = Array.isArray(parsed) ? parsed : [];
          root.lastCompletedQuery = completedQuery;
        } catch (error) {
          root.searchResults = [];
          root.lastCompletedQuery = completedQuery;
          root.searchError = pluginApi?.tr("errors.searchMalformed");
        }
      } else if (!staleSearch) {
        root.searchResults = [];
        root.lastCompletedQuery = completedQuery;
        root.searchError = (searchProcess.stderr.text || "").trim() || pluginApi?.tr("search.failed");
      }

      root.runningSearchQuery = "";
      root.runningSearchProvider = "";

      if (root.pendingSearchQuery && (root.pendingSearchRestart || root.pendingSearchQuery !== completedQuery)) {
        var nextQuery = root.pendingSearchQuery;
        root.pendingSearchQuery = "";
        root.pendingSearchRestart = false;
        root.startSearch(nextQuery);
      }
    }
  }

  Timer {
    id: searchDelay
    interval: 250
    repeat: false
    onTriggered: root.performSearch()
  }

  Connections {
    target: mainInstance
    ignoreUnknownSignals: true

    function onCurrentProviderChanged() {
      root.searchEpoch += 1;
      root.searchResults = [];
      root.lastCompletedQuery = "";
      root.searchError = "";

      if (root.searchBusy && root.trimmedSearchText().length > 0) {
        if (root.pendingSearchQuery.length === 0) {
          root.pendingSearchQuery = root.trimmedSearchText();
        }
        root.pendingSearchRestart = true;
      } else if (root.activeTab === "search" && root.trimmedSearchText().length > 0 && !root.looksLikeUrl(root.trimmedSearchText())) {
        searchDelay.restart();
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      mainInstance?.refreshStatus(true);
      Qt.callLater(root.focusCurrentInput);
    }
  }

  onActiveTabChanged: {
    if (visible) {
      Qt.callLater(root.focusCurrentInput);
    }
  }

  function focusCurrentInput() {
    if (activeTab === "search") {
      if (searchInput.inputItem) {
        searchInput.inputItem.forceActiveFocus();
      } else {
        searchInput.forceActiveFocus();
      }
      return;
    }

    if (activeTab === "library") {
      if (libraryFilterInput.inputItem) {
        libraryFilterInput.inputItem.forceActiveFocus();
      } else {
        libraryFilterInput.forceActiveFocus();
      }
    }
  }

  function trimmedSearchText() {
    return (searchText || "").trim();
  }

  function providerLabel(provider) {
    return mainInstance?.providerLabel(provider)
        || (provider === "soundcloud"
            ? pluginApi?.tr("providers.soundcloud")
            : (provider === "local"
                ? pluginApi?.tr("providers.local")
                : pluginApi?.tr("providers.youtube")));
  }

  function looksLikeUrl(value) {
    var trimmed = (value || "").trim();
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed) || /^www\./i.test(trimmed);
  }

  function parseSearchProviderQuery(query) {
    var raw = query || "";
    var match = raw.match(/^(yt|youtube|sc|soundcloud|local):\s*(.*)$/i);
    if (!match) {
      return {
        "provider": mainInstance?.currentProvider || "youtube",
        "query": raw
      };
    }

    var prefix = (match[1] || "").toLowerCase();
    var provider = "youtube";
    if (prefix === "sc" || prefix === "soundcloud") {
      provider = "soundcloud";
    } else if (prefix === "local") {
      provider = "local";
    }

    return {
      "provider": provider,
      "query": (match[2] || "").trim()
    };
  }

  function performSearch(forceImmediate) {
    var query = trimmedSearchText();

    if (looksLikeUrl(query) || query.length === 0) {
      searchEpoch += 1;
      searchResults = [];
      searchError = "";
      activeSearchQuery = "";
      pendingSearchQuery = "";
      pendingSearchRestart = false;
      lastCompletedQuery = "";
      return;
    }

    var parsed = parseSearchProviderQuery(query);
    var resolvedQuery = (parsed.query || "").trim();
    if (resolvedQuery.length < 2) {
      searchEpoch += 1;
      searchResults = [];
      searchError = "";
      activeSearchQuery = query;
      pendingSearchQuery = "";
      pendingSearchRestart = false;
      return;
    }

    if (forceImmediate === true) {
      if (searchBusy) {
        pendingSearchQuery = query;
        pendingSearchRestart = true;
        return;
      }
      startSearch(query);
      return;
    }

    if (searchBusy) {
      pendingSearchQuery = query;
      return;
    }

    startSearch(query);
  }

  function startSearch(query) {
    if (!helperPath) {
      return;
    }

    var parsed = parseSearchProviderQuery(query);
    var provider = parsed.provider;
    var resolvedQuery = (parsed.query || "").trim();

    if (resolvedQuery.length < 2) {
      searchResults = [];
      searchError = "";
      return;
    }

    activeSearchQuery = query;
    pendingSearchQuery = "";
    pendingSearchRestart = false;
    searchBusy = true;
    searchError = "";
    runningSearchQuery = query;
    runningSearchProvider = provider;
    runningSearchEpoch = searchEpoch;
    searchProcess.exec({
                         "command": ["bash", helperPath, "search", resolvedQuery, provider]
                       });
  }

  function normalizedEntry(entry) {
    return {
      "id": entry?.id || "",
      "title": entry?.title || entry?.name || pluginApi?.tr("common.untitled"),
      "url": entry?.url || "",
      "uploader": entry?.uploader || "",
      "duration": entry?.duration || 0,
      "provider": entry?.provider || "",
      "album": entry?.album || "",
      "tags": Array.isArray(entry?.tags) ? entry.tags : [],
      "rating": entry?.rating || 0,
      "playCount": entry?.playCount || 0,
      "savedAt": entry?.savedAt || "",
      "lastPlayedAt": entry?.lastPlayedAt || "",
      "queuedAt": entry?.queuedAt || ""
    };
  }

  function compareIsoStringsDesc(a, b) {
    var aValue = a || "";
    var bValue = b || "";
    if (aValue === bValue) {
      return 0;
    }
    return aValue > bValue ? -1 : 1;
  }

  function buildFilteredLibraryEntries() {
    var entries = (mainInstance?.visibleLibraryEntries() || []).slice();
    var mode = mainInstance?.currentSortBy || "date";
    var query = (libraryFilterText || "").trim().toLowerCase();

    entries.sort(function (left, right) {
      if (mode === "title") {
        return (left?.title || "").localeCompare(right?.title || "");
      }
      if (mode === "duration") {
        return (right?.duration || 0) - (left?.duration || 0);
      }
      if (mode === "rating") {
        var ratingDiff = (right?.rating || 0) - (left?.rating || 0);
        if (ratingDiff !== 0) {
          return ratingDiff;
        }
      }
      return compareIsoStringsDesc(left?.savedAt, right?.savedAt);
    });

    if (query.length === 0) {
      return entries;
    }

    return entries.filter(function (entry) {
      var haystack = [
        entry?.title || "",
        entry?.uploader || "",
        entry?.album || "",
        (entry?.tags || []).join(" ") || ""
      ].join(" ").toLowerCase();
      return haystack.indexOf(query) >= 0;
    });
  }

  function buildRecentLibraryEntries() {
    var entries = (mainInstance?.visibleLibraryEntries() || []).slice();
    entries.sort(function (left, right) {
      var leftDate = left?.lastPlayedAt || left?.savedAt || "";
      var rightDate = right?.lastPlayedAt || right?.savedAt || "";
      return compareIsoStringsDesc(leftDate, rightDate);
    });
    return entries.slice(0, 10);
  }

  function formatRating(rating) {
    var value = rating || 0;
    if (!isFinite(value) || value <= 0) {
      return "";
    }

    var stars = "";
    for (var i = 0; i < value; i++) {
      stars += "\u2605";
    }
    return stars;
  }

  function formatPlayCount(count) {
    var plays = count || 0;
    if (!isFinite(plays) || plays <= 0) {
      return "";
    }
    return plays === 1 ? pluginApi?.tr("common.onePlay") : pluginApi?.tr("common.plays", {"count": plays});
  }

  function formatSpeed(speed) {
    var value = speed || 1;
    if (!isFinite(value)) {
      return pluginApi?.tr("speed.multiplier", {"speed": "1.00"});
    }

    var rounded = Math.round(value * 100) / 100;
    return pluginApi?.tr("speed.multiplier", {"speed": rounded.toFixed(2)});
  }

  function effectiveSeekPosition() {
    var duration = mainInstance?.currentDuration || 0;
    if (seekDragging && localSeekRatio >= 0 && duration > 0) {
      return Math.max(0, Math.min(duration, localSeekRatio * duration));
    }
    return Math.max(0, mainInstance?.currentPosition || 0);
  }

  function entrySummary(entry, section) {
    var normalized = normalizedEntry(entry);
    var parts = [];

    if (normalized.uploader.length > 0) {
      parts.push(normalized.uploader);
    }

    var duration = MusicUtils.formatDuration(normalized.duration);
    if (duration.length > 0) {
      parts.push(duration);
    }

    if (section === "search") {
      parts.push(providerLabel(normalized.provider || parseSearchProviderQuery(trimmedSearchText()).provider));
    } else if (section === "library") {
      var rating = formatRating(normalized.rating);
      if (rating.length > 0) {
        parts.push(rating);
      }
      var playCount = formatPlayCount(normalized.playCount);
      if (playCount.length > 0) {
        parts.push(playCount);
      }
      if (normalized.tags.length > 0) {
        parts.push(normalized.tags.map(function (tag) { return "#" + tag; }).join(" "));
      }
    } else if (section === "queue") {
      var queuedAt = MusicUtils.formatRelativeTime(normalized.queuedAt);
      if (queuedAt.length > 0) {
        parts.push(pluginApi?.tr("panel.queuedAt", {"time": queuedAt}));
      }
    }

    return parts.join(" • ");
  }

  function isCurrentEntry(entry) {
    var normalized = normalizedEntry(entry);
    if (!hasPlayback) {
      return false;
    }
    if (normalized.id.length > 0 && normalized.id === (mainInstance?.currentEntryId || "")) {
      return true;
    }
    return normalized.url.length > 0 && normalized.url === (mainInstance?.currentUrl || "");
  }

  function isRemoteEntry(entry) {
    var normalized = normalizedEntry(entry);
    return normalized.url.length > 0 && !normalized.url.startsWith("/");
  }

  function closePanel() {
    var screen = pluginApi?.panelOpenScreen;
    if (screen) {
      pluginApi.closePanel(screen);
      return;
    }

    pluginApi?.withCurrentScreen(function (currentScreen) {
      pluginApi.closePanel(currentScreen);
    });
  }

  function openSettings() {
    var screen = pluginApi?.panelOpenScreen;
    if (screen) {
      BarService.openPluginSettings(screen, pluginApi.manifest);
      return;
    }

    pluginApi?.withCurrentScreen(function (currentScreen) {
      BarService.openPluginSettings(currentScreen, pluginApi.manifest);
    });
  }

  component ProviderChip: Rectangle {
    id: chip

    property string providerKey: "youtube"
    readonly property bool active: (root.mainInstance?.currentProvider || "youtube") === providerKey

    radius: Style.radiusM
    color: active ? (Color.mPrimaryContainer || Qt.alpha(Color.mPrimary, 0.14) || Color.mSurfaceVariant) : Color.mSurfaceVariant
    border.width: 1
    border.color: active ? Color.mPrimary : Qt.alpha((Color.mOutline || Color.mOnSurfaceVariant || "#888888"), 0.35)
    implicitWidth: providerLabelText.implicitWidth + (Style.marginL * 2)
    implicitHeight: providerLabelText.implicitHeight + (Style.marginS * 2)

    NText {
      id: providerLabelText
      anchors.centerIn: parent
      text: root.providerLabel(chip.providerKey)
      color: chip.active ? (Color.mOnPrimaryContainer || Color.mOnSurface) : Color.mOnSurface
      pointSize: Style.fontSizeS
      font.weight: chip.active ? Font.DemiBold : Font.Normal
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.mainInstance?.setProvider(chip.providerKey)
    }
  }

  component TrackCard: Rectangle {
    id: card

    property var entry: null
    property string section: "search"

    readonly property var normalized: root.normalizedEntry(entry)
    readonly property bool saved: root.mainInstance?.isSaved(normalized) === true
    readonly property bool current: root.isCurrentEntry(normalized)
    readonly property bool remoteEntry: root.isRemoteEntry(normalized)

    Layout.fillWidth: true
    radius: Style.radiusL
    color: current ? (Color.mSurface || Color.mSurfaceVariant) : Color.mSurfaceVariant
    border.width: current ? 1 : 0
    border.color: current ? (Color.mPrimary || Color.mOnSurface) : "transparent"
    implicitHeight: content.implicitHeight + (Style.marginL * 2)

    ColumnLayout {
      id: content
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          NText {
            Layout.fillWidth: true
            text: normalized.title
            color: Color.mOnSurface
            pointSize: Style.fontSizeM
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }

          NText {
            Layout.fillWidth: true
            text: root.entrySummary(normalized, section)
            visible: text.length > 0
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
          }
        }

        Rectangle {
          visible: saved
          radius: Style.radiusM
          color: current ? Qt.alpha(Color.mPrimary, 0.16) : Qt.alpha(Color.mPrimary, 0.12)
          implicitWidth: savedLabel.implicitWidth + (Style.marginM * 2)
          implicitHeight: savedLabel.implicitHeight + (Style.marginXS * 2)

          NText {
            id: savedLabel
            anchors.centerIn: parent
            text: root.pluginApi?.tr("panel.savedLabel")
            color: Color.mPrimary
            pointSize: Style.fontSizeXS
            font.weight: Font.DemiBold
          }
        }
      }

      Flow {
        Layout.fillWidth: true
        width: parent.width
        spacing: Style.marginS

        NButton {
          text: root.pluginApi?.tr("panel.playAction")
          icon: "player-play-filled"
          fontSize: Style.fontSizeS
          onClicked: {
            if (section === "queue") {
              root.mainInstance?.playQueueEntryNow(normalized);
            } else {
              root.mainInstance?.playEntry(normalized);
            }
          }
        }

        NButton {
          text: root.pluginApi?.tr("panel.queueAction")
          icon: "list"
          fontSize: Style.fontSizeS
          visible: section !== "queue"
          onClicked: root.mainInstance?.enqueueEntry(normalized)
        }

        NButton {
          text: root.pluginApi?.tr("panel.saveAction")
          icon: "bookmark-plus"
          fontSize: Style.fontSizeS
          visible: !saved && section !== "queue"
          onClicked: root.mainInstance?.saveEntry(normalized)
        }

        NButton {
          text: root.pluginApi?.tr("panel.downloadAction")
          icon: "download"
          fontSize: Style.fontSizeS
          visible: section !== "queue" && remoteEntry
          onClicked: root.mainInstance?.downloadEntry(normalized)
        }

        NButton {
          text: root.pluginApi?.tr("panel.removeAction")
          icon: "trash"
          fontSize: Style.fontSizeS
          visible: section === "queue" || section === "library"
          onClicked: {
            if (section === "queue") {
              root.mainInstance?.removeQueueEntry(normalized.id, true);
            } else {
              root.mainInstance?.removeEntry(normalized.id);
            }
          }
        }
      }
    }
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      Rectangle {
        Layout.fillWidth: true
        radius: Style.radiusL
        color: Color.mSurfaceVariant
        implicitHeight: headerContent.implicitHeight + (Style.marginL * 2)

        RowLayout {
          id: headerContent
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: "music"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NText {
              text: pluginApi?.tr("panel.title")
              color: Color.mOnSurface
              pointSize: Style.fontSizeL
              font.weight: Font.Bold
            }

            NText {
              Layout.fillWidth: true
              text: pluginApi?.tr("panel.subtitle")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              wrapMode: Text.Wrap
            }
          }

          NButton {
            text: pluginApi?.tr("panel.openLauncher")
            icon: "search"
            fontSize: Style.fontSizeS
            onClicked: {
              root.closePanel();
              mainInstance?.openLauncher();
            }
          }

          NIconButton {
            icon: "settings"
            tooltipText: pluginApi?.tr("panel.openSettings")
            onClicked: root.openSettings()
          }

          NIconButton {
            icon: "x"
            tooltipText: pluginApi?.tr("panel.close")
            onClicked: root.closePanel()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        radius: Style.radiusL
        color: Color.mSurfaceVariant
        implicitHeight: playbackColumn.implicitHeight + (Style.marginL * 2)

        ColumnLayout {
          id: playbackColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              NText {
                text: pluginApi?.tr("panel.nowPlaying")
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                font.weight: Font.DemiBold
              }

              NText {
                Layout.fillWidth: true
                text: {
                  if (mainInstance?.playbackStarting === true && (mainInstance?.currentTitle || "").trim().length === 0) {
                    return pluginApi?.tr("status.starting");
                  }
                  return (mainInstance?.currentTitle || "").trim() || pluginApi?.tr("panel.nothingPlaying");
                }
                color: Color.mOnSurface
                pointSize: Style.fontSizeM
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
              }

              NText {
                Layout.fillWidth: true
                visible: root.hasPlayback
                text: {
                  var parts = [];
                  var uploader = (mainInstance?.currentUploader || "").trim();
                  var provider = root.providerLabel(mainInstance?.currentProvider || "youtube");
                  var duration = MusicUtils.formatDuration(mainInstance?.currentDuration || 0);
                  if (uploader.length > 0) {
                    parts.push(uploader);
                  }
                  if (provider.length > 0) {
                    parts.push(provider);
                  }
                  if (duration.length > 0) {
                    parts.push(duration);
                  }
                  return parts.join(" • ");
                }
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                wrapMode: Text.Wrap
              }
            }

            NButton {
              text: mainInstance?.isPaused === true ? pluginApi?.tr("panel.resume") : pluginApi?.tr("panel.pause")
              icon: mainInstance?.isPaused === true ? "player-play-filled" : "player-pause-filled"
              fontSize: Style.fontSizeS
              enabled: mainInstance?.isPlaying === true
              onClicked: mainInstance?.togglePause()
            }

            NButton {
              text: pluginApi?.tr("panel.stop")
              icon: "player-stop-filled"
              fontSize: Style.fontSizeS
              enabled: root.hasPlayback
              onClicked: mainInstance?.stopPlayback()
            }
          }

          NSlider {
            id: playbackSlider
            Layout.fillWidth: true
            from: 0
            to: 1
            stepSize: 0
            snapAlways: false
            heightRatio: 0.4
            enabled: mainInstance?.isPlaying === true && (mainInstance?.currentDuration || 0) > 0
            value: {
              var duration = mainInstance?.currentDuration || 0;
              if (!isFinite(duration) || duration <= 0) {
                return 0;
              }
              if (root.seekDragging && root.localSeekRatio >= 0) {
                return Math.max(0, Math.min(1, root.localSeekRatio));
              }
              return Math.max(0, Math.min(1, (mainInstance?.currentPosition || 0) / duration));
            }

            onMoved: {
              root.seekDragging = true;
              root.localSeekRatio = value;
            }
            onPressedChanged: {
              if (pressed) {
                root.seekDragging = true;
                root.localSeekRatio = value;
              } else if (enabled) {
                root.mainInstance?.seekToRatio(value);
                root.seekDragging = false;
                root.localSeekRatio = -1;
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: MusicUtils.formatDuration(root.effectiveSeekPosition())
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
            }

            Item {
              Layout.fillWidth: true
            }

            NText {
              text: MusicUtils.formatDuration(mainInstance?.currentDuration || 0)
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NButton {
              text: pluginApi?.tr("panel.saveCurrent")
              icon: "bookmark-plus"
              fontSize: Style.fontSizeS
              enabled: root.hasPlayback && mainInstance?.findSavedEntry({
                                                     "id": mainInstance?.currentEntryId || "",
                                                     "url": mainInstance?.currentUrl || ""
                                                   }) === null
              onClicked: mainInstance?.saveEntry({
                                                   "id": mainInstance?.currentEntryId || "",
                                                   "title": mainInstance?.currentTitle || "",
                                                   "url": mainInstance?.currentUrl || "",
                                                   "uploader": mainInstance?.currentUploader || "",
                                                   "duration": mainInstance?.currentDuration || 0,
                                                   "provider": mainInstance?.currentProvider || ""
                                                 })
            }

            NButton {
              text: pluginApi?.tr("panel.saveCurrentMp3")
              icon: "download"
              fontSize: Style.fontSizeS
              enabled: root.hasPlayback && root.isRemoteEntry({
                                               "url": mainInstance?.currentUrl || "",
                                               "provider": mainInstance?.currentProvider || ""
                                             })
              onClicked: mainInstance?.downloadCurrentTrack()
            }

            NButton {
              text: pluginApi?.tr("panel.refresh")
              icon: "refresh"
              fontSize: Style.fontSizeS
              onClicked: mainInstance?.refreshStatus(true)
            }

            Item {
              Layout.fillWidth: true
              implicitHeight: playbackStatusText.visible ? playbackStatusText.implicitHeight : 0

              NText {
                id: playbackStatusText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (mainInstance?.playbackStartingMessage || "").trim()
                visible: mainInstance?.playbackStarting === true && text.length > 0
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
              }
            }

            RowLayout {
              visible: root.hasPlayback
              spacing: Math.max(2, Math.round(Style.marginXS * 0.5))

              NButton {
                text: "-"
                backgroundColor: "transparent"
                textColor: Color.mOnSurfaceVariant
                outlined: false
                enabled: mainInstance?.isPlaying === true && mainInstance?.speedBusy !== true
                implicitWidth: Math.round(24 * Style.uiScaleRatio)
                implicitHeight: Math.round(24 * Style.uiScaleRatio)
                onClicked: mainInstance?.adjustSpeed(-0.05)
              }

              Rectangle {
                radius: Style.radiusM
                color: Color.mPrimary
                implicitHeight: Math.round(24 * Style.uiScaleRatio)
                implicitWidth: Math.max(speedChipLabel.implicitWidth, speedChipWidthReference.implicitWidth) + Math.round(18 * Style.uiScaleRatio)
                opacity: mainInstance?.speedBusy === true ? 0.75 : 1

                NText {
                  id: speedChipLabel
                  anchors.centerIn: parent
                  text: root.formatSpeed(mainInstance?.currentSpeed || 1)
                  pointSize: Style.fontSizeS
                  color: Color.mOnPrimary
                }

                NText {
                  id: speedChipWidthReference
                  visible: false
                  text: root.formatSpeed(4)
                  pointSize: Style.fontSizeS
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  enabled: mainInstance?.isPlaying === true && mainInstance?.speedBusy !== true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: mainInstance?.setSpeed(1)
                  onWheel: wheel => {
                             if (!enabled || wheel.angleDelta.y === 0) {
                               return;
                             }

                             mainInstance?.adjustSpeed(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                             wheel.accepted = true;
                           }
                }
              }

              NButton {
                text: "+"
                backgroundColor: "transparent"
                textColor: Color.mOnSurfaceVariant
                outlined: false
                enabled: mainInstance?.isPlaying === true && mainInstance?.speedBusy !== true
                implicitWidth: Math.round(24 * Style.uiScaleRatio)
                implicitHeight: Math.round(24 * Style.uiScaleRatio)
                onClicked: mainInstance?.adjustSpeed(0.05)
              }
            }
          }
        }
      }

      Rectangle {
        visible: (mainInstance?.lastError || "").trim().length > 0 || (mainInstance?.lastNotice || "").trim().length > 0
        Layout.fillWidth: true
        radius: Style.radiusM
        color: (mainInstance?.lastError || "").trim().length > 0 ? Qt.alpha(Color.mError, 0.14) : Qt.alpha(Color.mPrimary, 0.12)
        implicitHeight: statusText.implicitHeight + (Style.marginM * 2)

        NText {
          id: statusText
          anchors.fill: parent
          anchors.margins: Style.marginM
          text: (mainInstance?.lastError || "").trim().length > 0 ? (mainInstance?.lastError || "").trim() : (mainInstance?.lastNotice || "").trim()
          color: (mainInstance?.lastError || "").trim().length > 0 ? Color.mError : Color.mOnSurface
          pointSize: Style.fontSizeS
          wrapMode: Text.Wrap
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Style.radiusL
        color: Color.mSurfaceVariant
        clip: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NTabBar {
            id: tabBar
            Layout.fillWidth: true
            distributeEvenly: true
            currentIndex: root.activeTab === "library" ? 1 : (root.activeTab === "queue" ? 2 : 0)

            NTabButton {
              text: pluginApi?.tr("panel.search")
              tabIndex: 0
              checked: tabBar.currentIndex === 0
              onClicked: root.activeTab = "search"
            }

            NTabButton {
              text: pluginApi?.tr("panel.library")
              tabIndex: 1
              checked: tabBar.currentIndex === 1
              onClicked: root.activeTab = "library"
            }

            NTabButton {
              text: pluginApi?.tr("panel.queue")
              tabIndex: 2
              checked: tabBar.currentIndex === 2
              onClicked: root.activeTab = "queue"
            }
          }

          NTabView {
            id: tabView
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            Item {
              height: tabView.height

              ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NTextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: pluginApi?.tr("panel.searchPlaceholder")
                    text: root.searchText

                    onTextChanged: {
                      root.searchText = text;
                      searchDelay.restart();
                    }

                    Keys.onReturnPressed: root.performSearch(true)
                    Keys.onEnterPressed: root.performSearch(true)
                  }

                  NButton {
                    text: pluginApi?.tr("panel.search")
                    icon: "search"
                    fontSize: Style.fontSizeS
                    enabled: !root.searchBusy
                    onClicked: root.performSearch(true)
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  ProviderChip { providerKey: "youtube" }
                  ProviderChip { providerKey: "soundcloud" }
                  ProviderChip { providerKey: "local" }

                  Item { Layout.fillWidth: true }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS
                  visible: root.looksLikeUrl(root.trimmedSearchText())

                  NButton {
                    text: pluginApi?.tr("panel.playUrl")
                    icon: "player-play-filled"
                    fontSize: Style.fontSizeS
                    onClicked: root.mainInstance?.playUrl(root.trimmedSearchText(), pluginApi?.tr("common.customUrl"))
                  }

                  NButton {
                    text: pluginApi?.tr("panel.saveUrl")
                    icon: "bookmark-plus"
                    fontSize: Style.fontSizeS
                    onClicked: root.mainInstance?.saveUrl(root.trimmedSearchText())
                  }

                  NButton {
                    text: pluginApi?.tr("panel.queueUrl")
                    icon: "list"
                    fontSize: Style.fontSizeS
                    onClicked: root.mainInstance?.enqueueUrl(root.trimmedSearchText(), pluginApi?.tr("common.queuedUrl"))
                  }
                }

                NScrollView {
                  id: searchScroll
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.bottomMargin: Style.marginS
                  horizontalPolicy: ScrollBar.AlwaysOff
                  verticalPolicy: ScrollBar.AsNeeded
                  reserveScrollbarSpace: false
                  gradientColor: Color.mSurfaceVariant
                  bottomPadding: Style.marginS

                  ColumnLayout {
                    width: searchScroll.availableWidth
                    spacing: Style.marginM

                    Rectangle {
                      visible: root.searchBusy
                      Layout.fillWidth: true
                      radius: Style.radiusL
                      color: Qt.alpha(Color.mPrimary, 0.08)
                      implicitHeight: loadingRow.implicitHeight + (Style.marginL * 2)

                      RowLayout {
                        id: loadingRow
                        anchors.centerIn: parent
                        spacing: Style.marginM

                        NBusyIndicator {
                          running: root.searchBusy
                          color: Color.mPrimary
                          size: Style.baseWidgetSize * 0.75
                        }

                        NText {
                          text: pluginApi?.tr("panel.searching", {"provider": root.providerLabel(root.runningSearchProvider || root.parseSearchProviderQuery(root.trimmedSearchText()).provider)})
                          color: Color.mOnSurface
                          pointSize: Style.fontSizeS
                        }
                      }
                    }

                    Rectangle {
                      visible: !root.searchBusy && (root.searchError || "").trim().length > 0
                      Layout.fillWidth: true
                      radius: Style.radiusL
                      color: Qt.alpha(Color.mError, 0.12)
                      implicitHeight: searchErrorText.implicitHeight + (Style.marginL * 2)

                      NText {
                        id: searchErrorText
                        anchors.fill: parent
                        anchors.margins: Style.marginL
                        text: root.searchError
                        color: Color.mError
                        pointSize: Style.fontSizeS
                        wrapMode: Text.Wrap
                      }
                    }

                    Rectangle {
                      visible: !root.searchBusy && !root.looksLikeUrl(root.trimmedSearchText()) && root.trimmedSearchText().length > 0 && root.parseSearchProviderQuery(root.trimmedSearchText()).query.length > 0 && root.parseSearchProviderQuery(root.trimmedSearchText()).query.length < 2
                      Layout.fillWidth: true
                      radius: Style.radiusL
                      color: Qt.alpha(Color.mSurface, 0.6)
                      implicitHeight: shortSearchText.implicitHeight + (Style.marginL * 2)

                      NText {
                        id: shortSearchText
                        anchors.fill: parent
                        anchors.margins: Style.marginL
                        text: pluginApi?.tr("panel.typeMore", {"provider": root.providerLabel(root.parseSearchProviderQuery(root.trimmedSearchText()).provider)})
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeS
                        wrapMode: Text.Wrap
                      }
                    }

                    Rectangle {
                      visible: !root.searchBusy && root.trimmedSearchText().length === 0
                      Layout.fillWidth: true
                      radius: Style.radiusL
                      color: Qt.alpha(Color.mSurface, 0.6)
                      implicitHeight: helperColumn.implicitHeight + (Style.marginL * 2)

                      ColumnLayout {
                        id: helperColumn
                        anchors.fill: parent
                        anchors.margins: Style.marginL
                        spacing: Style.marginS

                        NText {
                          Layout.fillWidth: true
                          text: pluginApi?.tr("panel.searchHint", {"provider": root.providerLabel(mainInstance?.currentProvider || "youtube")})
                          color: Color.mOnSurface
                          pointSize: Style.fontSizeS
                          wrapMode: Text.Wrap
                        }

                        NText {
                          Layout.fillWidth: true
                          text: pluginApi?.tr("panel.helperHint")
                          color: Color.mOnSurfaceVariant
                          pointSize: Style.fontSizeXS
                          wrapMode: Text.Wrap
                        }
                      }
                    }

                    NText {
                      Layout.fillWidth: true
                      visible: !root.searchBusy && root.trimmedSearchText().length === 0 && root.recentLibraryEntries.length > 0
                      text: pluginApi?.tr("panel.recentTracks")
                      color: Color.mOnSurface
                      pointSize: Style.fontSizeM
                      font.weight: Font.DemiBold
                    }

                    Repeater {
                      model: !root.searchBusy && root.trimmedSearchText().length === 0 ? root.recentLibraryEntries : []

                      delegate: TrackCard {
                        entry: modelData
                        section: "library"
                      }
                    }

                    NText {
                      Layout.fillWidth: true
                      visible: !root.searchBusy && root.trimmedSearchText().length > 0 && !root.looksLikeUrl(root.trimmedSearchText()) && root.parseSearchProviderQuery(root.trimmedSearchText()).query.length >= 2 && root.searchResults.length === 0 && (root.searchError || "").trim().length === 0
                      text: pluginApi?.tr("panel.noSearchResults", {"query": root.parseSearchProviderQuery(root.trimmedSearchText()).query})
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeS
                      wrapMode: Text.Wrap
                    }

                    Repeater {
                      model: !root.searchBusy && root.trimmedSearchText().length > 0 && !root.looksLikeUrl(root.trimmedSearchText()) ? root.searchResults : []

                      delegate: TrackCard {
                        entry: modelData
                        section: "search"
                      }
                    }
                  }
                }
              }
            }

            Item {
              height: tabView.height

              ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NTextInput {
                    id: libraryFilterInput
                    Layout.fillWidth: true
                    placeholderText: pluginApi?.tr("panel.libraryPlaceholder")
                    text: root.libraryFilterText
                    onTextChanged: root.libraryFilterText = text
                  }

                  NButton {
                    text: pluginApi?.tr("panel.playSaved")
                    icon: "player-play-filled"
                    fontSize: Style.fontSizeS
                    enabled: (mainInstance?.visibleLibraryEntries() || []).length > 0
                    onClicked: root.mainInstance?.autoplaySavedTracks(false)
                  }

                  NButton {
                    text: pluginApi?.tr("panel.shuffleSaved")
                    icon: "arrows-shuffle"
                    fontSize: Style.fontSizeS
                    enabled: (mainInstance?.visibleLibraryEntries() || []).length > 0
                    onClicked: root.mainInstance?.autoplaySavedTracks(true)
                  }
                }

                NText {
                  Layout.fillWidth: true
                  text: pluginApi?.tr("panel.savedCount", {"count": root.filteredLibraryEntries.length})
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                }

                NScrollView {
                  id: libraryScroll
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.bottomMargin: Style.marginS
                  horizontalPolicy: ScrollBar.AlwaysOff
                  verticalPolicy: ScrollBar.AsNeeded
                  reserveScrollbarSpace: false
                  gradientColor: Color.mSurfaceVariant
                  bottomPadding: Style.marginS

                  ColumnLayout {
                    width: libraryScroll.availableWidth
                    spacing: Style.marginM

                    NText {
                      Layout.fillWidth: true
                      visible: root.filteredLibraryEntries.length === 0
                      text: pluginApi?.tr("panel.emptyLibrary")
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeS
                      wrapMode: Text.Wrap
                    }

                    Repeater {
                      model: root.filteredLibraryEntries

                      delegate: TrackCard {
                        entry: modelData
                        section: "library"
                      }
                    }
                  }
                }
              }
            }

            Item {
              height: tabView.height

              ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginM

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NButton {
                    text: pluginApi?.tr("panel.startQueue")
                    icon: "player-play-filled"
                    fontSize: Style.fontSizeS
                    enabled: (mainInstance?.queueEntries || []).length > 0
                    onClicked: root.mainInstance?.startQueue()
                  }

                  NButton {
                    text: pluginApi?.tr("panel.skipQueue")
                    icon: "player-skip-forward"
                    fontSize: Style.fontSizeS
                    enabled: (mainInstance?.queueEntries || []).length > 0
                    onClicked: root.mainInstance?.skipQueue()
                  }

                  NButton {
                    text: pluginApi?.tr("panel.clearQueue")
                    icon: "trash"
                    fontSize: Style.fontSizeS
                    enabled: (mainInstance?.queueEntries || []).length > 0
                    onClicked: root.mainInstance?.clearQueue()
                  }

                  Item {
                    Layout.fillWidth: true
                  }
                }

                NText {
                  Layout.fillWidth: true
                  text: pluginApi?.tr("panel.queueCount", {"count": (mainInstance?.queueEntries || []).length})
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                }

                Item {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.bottomMargin: Style.marginS

                  NText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: (mainInstance?.queueEntries || []).length === 0
                    text: pluginApi?.tr("panel.emptyQueue")
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    wrapMode: Text.Wrap
                  }

                  NListView {
                    id: queueList
                    anchors.fill: parent
                    visible: (mainInstance?.queueEntries || []).length > 0
                    spacing: Style.marginM
                    cacheBuffer: Math.round(800 * Style.uiScaleRatio)
                    boundsBehavior: Flickable.StopAtBounds
                    model: mainInstance?.queueEntries || []
                    verticalPolicy: ScrollBar.AsNeeded
                    horizontalPolicy: ScrollBar.AlwaysOff
                    reserveScrollbarSpace: false
                    gradientColor: Color.mSurfaceVariant

                    delegate: Item {
                      width: queueList.availableWidth
                      implicitHeight: queueCard.implicitHeight

                      TrackCard {
                        id: queueCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        entry: modelData
                        section: "queue"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
