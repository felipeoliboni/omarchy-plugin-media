import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "MediaPanelModel.js" as Model

// Now-playing bar widget. Shows the current track inline in the bar (icon +
// "artist — title", like Omarchy's own media widget and crmne.mpris) and
// opens a popup with full track detail, progress and transport controls on
// click. All MPRIS work is delegated to the first-party omarchy.media
// service; this plugin owns presentation only, so the service keeps getting
// upstream fixes.
BarWidget {
  id: root
  moduleName: "foliboni.media"

  // Prefer the first-party service, but do not depend on reaching it: Omarchy
  // 4.0.3 only exposes omarchy.media to plugins declaring kind "bar", so for a
  // bar-widget this is simply null and the widget would render nothing at all.
  // MediaFallback speaks the same small interface over Quickshell's own MPRIS
  // binding, which the plugin sandbox does not gate.
  readonly property var hostMediaService: bar?.shell?.firstPartyServiceFor("omarchy.media") ?? null
  readonly property var mediaService: hostMediaService || fallbackMediaService

  MediaFallback { id: fallbackMediaService }

  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  // Same condition the built-in media widget uses: a player is only "media"
  // once it reports something nameable. A paused track still counts, so the
  // widget does not vanish from the bar mid-pause.
  readonly property bool hasMedia: !!(activePlayer && (activePlayer.trackTitle || activePlayer.trackArtist))
  readonly property bool playing: !!(activePlayer && activePlayer.isPlaying)
  readonly property bool spotify: Model.isSpotify(activePlayer)

  readonly property int artSize: Number(setting("artSize", 96))
  readonly property bool showProgress: setting("showProgress", true) === true
  readonly property bool showSourcePicker: setting("showSourcePicker", true) === true
  readonly property bool spotifyAccent: setting("spotifyAccent", true) === true

  // Spotify green, resolved once here so every accent-tinted element agrees.
  readonly property color accentColor: spotify && spotifyAccent ? "#1db954" : Color.accent

  readonly property string title: Model.displayTitle(activePlayer)
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string secondary: Model.secondaryLine(activePlayer)
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""

  readonly property bool canSeek: !!(activePlayer && activePlayer.canSeek && Model.hasPosition(activePlayer))
  readonly property bool hasProgress: showProgress && Model.hasPosition(activePlayer)
  readonly property real trackLength: activePlayer && activePlayer.length ? Number(activePlayer.length) : 0

  // Bar label: "artist — title", matching the other now-playing widgets.
  readonly property string displayText: hasMedia ? (artist !== "" ? artist + " — " + title : title) : ""

  // Bar-row appearance, right-click configurable (see settingsPopup below).
  readonly property bool showBarAlbumArt: setting("showAlbumArt", false) === true
  readonly property bool showBarIcon: setting("showIcon", true) === true
  readonly property int maxLabelWidth: Math.max(60, Number(setting("maxLabelWidth", 400)))

  // Mirrored rather than bound: Quickshell only refreshes MprisPlayer.position
  // when asked, and Spotify never emits Seeked, so a timer drives it while the
  // popup is open. Bindings straight to activePlayer.position would sit still.
  property real livePosition: 0
  property bool seeking: false
  property bool popupOpen: false
  property bool settingsOpen: false

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  function openSettings() { settingsOpen = true }
  function closeSettings() { settingsOpen = false }
  function toggleSettings() { settingsOpen = !settingsOpen }

  // Settings are per-widget-instance, stored inline in shell.json's bar
  // layout entry for this id — same mechanism the built-in widgets use.
  function previewSetting(key, value) {
    var next = Object.assign({}, settings || {})
    next[key] = value
    settings = next
  }

  function saveSetting(key, value) {
    previewSetting(key, value)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  function syncPosition() {
    if (seeking) return
    livePosition = activePlayer && activePlayer.positionSupported ? Number(activePlayer.position) : 0
  }

  function runAction(action) {
    if (!mediaService || !activePlayer) return
    mediaService.runAction(action, false, mediaService.playerKey(activePlayer))
  }

  function seekTo(seconds) {
    if (!canSeek) return
    activePlayer.position = seconds
    // Spotify advertises CanSeek but its Linux client often ignores the write.
    // Re-reading on the next tick lets the bar snap back to the truth rather
    // than sitting on a position the player never accepted.
    positionTimer.restart()
  }

  function toggleShuffle() {
    if (activePlayer && activePlayer.shuffleSupported) activePlayer.shuffle = !activePlayer.shuffle
  }

  function cycleLoop() {
    if (activePlayer && activePlayer.loopSupported)
      activePlayer.loopState = Model.nextLoopState(activePlayer.loopState)
  }

  // Focus the player's own window; fall back to its web URL when the player
  // cannot be raised (browser-backed players, mostly).
  function focusPlayer() {
    if (activePlayer && activePlayer.canRaise) {
      activePlayer.raise()
      return
    }
    var url = Model.trackUrl(activePlayer)
    if (url !== "" && bar) bar.run("xdg-open " + bar.shellQuote(url))
  }

  onActivePlayerChanged: syncPosition()
  onPopupOpenChanged: if (popupOpen) syncPosition()

  // The bar widget itself disappears when media stops (visible: hasMedia,
  // width collapses to 0), but a PopupCard is a separate top-level window --
  // it does not inherit that visibility. Without this, either popup can be
  // left open and anchored to a now-invisible, zero-size item: nothing in
  // the bar to right-click or click-away-from to dismiss it, so it hangs on
  // screen until the shell restarts.
  onHasMediaChanged: if (!hasMedia) {
    popupOpen = false
    settingsOpen = false
  }

  Timer {
    id: positionTimer
    interval: 1000
    repeat: true
    running: root.popupOpen && root.hasMedia && root.playing && root.hasProgress
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  // Lets `omarchy-shell shell toggle foliboni.media` (and a bound hotkey) open
  // the Now Playing panel without touching the mouse. BarWidget itself has
  // no IPC of its own, unlike the Panel base this plugin used to extend.
  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      id: artContainer
      width: Style.space(18)
      height: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showBarAlbumArt

      Rectangle {
        anchors.fill: parent
        radius: Style.space(3)
        color: Style.normalFillFor(root.bar.barForeground, root.accentColor)
      }

      Image {
        id: barArt
        anchors.fill: parent
        anchors.margins: 1
        source: root.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        visible: status === Image.Ready
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: root.artUrl === "" || barArt.status !== Image.Ready
        text: "󰝚"
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showBarIcon
      text: root.playing ? "󰎈" : "󰏤"
      color: root.playing ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: labelClip
      width: !root.vertical && root.displayText !== "" ? Math.min(root.maxLabelWidth, label.implicitWidth) : 0
      height: label.implicitHeight
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.displayText !== ""

      Text {
        id: label
        textFormat: Text.PlainText
        text: root.displayText
        color: root.bar.barForeground
        opacity: root.playing ? 0.92 : 0.58
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: labelClip.width
        anchors.verticalCenter: parent.verticalCenter

        Behavior on opacity { NumberAnimation { duration: 140 } }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.toggleSettings()
        return
      }
      if (!root.hasMedia) return
      if (mouse.button === Qt.MiddleButton) root.runAction("playPause")
      else root.toggle()
    }
    onWheel: function(wheel) {
      if (!root.hasMedia) return
      if (wheel.angleDelta.y > 0) root.runAction("previous")
      else if (wheel.angleDelta.y < 0) root.runAction("next")
    }
    onEntered: if (root.bar) root.bar.showTooltip(root,
      (root.artist !== "" ? root.title + " — " + root.artist : root.title) + "\nRight-click: appearance")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      // ---------- Hero: album art · title / artist / album ----------
      Row {
        width: parent.width
        spacing: Style.space(12)

        BorderSurface {
          id: artTile
          width: Style.space(root.artSize)
          height: Style.space(root.artSize)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, root.accentColor)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, root.accentColor)

          Image {
            id: art
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            source: root.artUrl
            visible: status === Image.Ready
            // Spotify serves 640px covers; decode at physical pixels instead
            // of holding the full-size image for a small tile.
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
          }

          // Keyed on the image status, not on the URL, so an offline or 404
          // fetch shows the placeholder rather than an empty tile.
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            visible: art.status !== Image.Ready
            text: art.status === Image.Loading ? "󰧑" : "󰝚"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.activePlayer && (root.activePlayer.canRaise || Model.trackUrl(root.activePlayer) !== "")
              ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.focusPlayer()
          }
        }

        Column {
          width: parent.width - artTile.width - Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            text: root.title
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.album
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.secondary
            color: Qt.darker(root.bar.foreground, 1.8)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      // ---------- Progress ----------
      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.hasProgress

        PanelSlider {
          id: seekBar
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, root.trackLength)
          step: Math.max(1, root.trackLength / 200)
          value: root.livePosition
          fillColor: root.accentColor
          enabled: root.canSeek

          onDraggingChanged: root.seeking = dragging
          onMoved: function(v) { root.livePosition = v }
          onReleased: function(v) { root.seekTo(v) }
        }

        Item {
          width: parent.width
          implicitHeight: elapsedLabel.implicitHeight

          Text {
            id: elapsedLabel
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: Model.formatTime(root.livePosition)
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: Model.formatTime(root.trackLength)
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---------- Transport ----------
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(4)

        Button {
          iconText: "󰒝"
          tooltipText: root.activePlayer && root.activePlayer.shuffle ? "Shuffle on" : "Shuffle off"
          foreground: root.bar.foreground
          accent: root.accentColor
          selected: !!(root.activePlayer && root.activePlayer.shuffle)
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          visible: !!(root.activePlayer && root.activePlayer.shuffleSupported)
          onClicked: root.toggleShuffle()
        }

        Button {
          iconText: "󰒮"
          tooltipText: "Previous"
          foreground: root.bar.foreground
          accent: root.accentColor
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.runAction("previous")
        }

        Button {
          iconText: root.playing ? "󰏤" : "󰐊"
          tooltipText: root.playing ? "Pause" : "Play"
          foreground: root.bar.foreground
          accent: root.accentColor
          iconSize: Style.font.iconLarge
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          enabled: !!(root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause))
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.runAction("playPause")
        }

        Button {
          iconText: "󰒭"
          tooltipText: "Next"
          foreground: root.bar.foreground
          accent: root.accentColor
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.runAction("next")
        }

        Button {
          iconText: Model.loopGlyph(root.activePlayer ? root.activePlayer.loopState : 0)
          tooltipText: Model.loopLabel(root.activePlayer ? root.activePlayer.loopState : 0)
          foreground: root.bar.foreground
          accent: root.accentColor
          selected: !!(root.activePlayer && root.activePlayer.loopState !== 0)
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          visible: !!(root.activePlayer && root.activePlayer.loopSupported)
          onClicked: root.cycleLoop()
        }
      }

      // ---------- Sources ----------
      PanelSeparator {
        width: parent.width
        foreground: root.bar.foreground
        visible: sourceList.visible
      }

      PanelSectionHeader {
        text: "SOURCES"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        visible: sourceList.visible
      }

      Column {
        id: sourceList
        width: parent.width
        spacing: Style.space(2)
        visible: root.showSourcePicker && root.sourcePlayers.length > 1

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool isActive: !!(root.activePlayer && player && root.mediaService
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player))

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: isActive ? Style.selectedFillFor(root.bar.foreground, root.accentColor) : "transparent"
            borderSpec: isActive ? Border.controlSpec("normal", root.bar.foreground, root.accentColor) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }

              Column {
                width: parent.width - Style.space(26)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  text: Model.displayTitle(sourceRow.player)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.isActive
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: Model.playerLabel(sourceRow.player)
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }

  // ---------- Appearance (right-click) ----------

  // A dedicated owner, distinct from the Now Playing popup's. PopupCard
  // dismisses itself (outside click, Esc) by calling `owner.close()`, and
  // both popups sharing `owner: root` meant that call always resolved to
  // root.close() -- which only ever clears popupOpen. The appearance popup
  // never got a close signal of its own, so it stuck around once opened,
  // and its coordinatorKey (used for the bar's one-popout-at-a-time
  // tracking) collided with the other popup's for the same reason.
  QtObject {
    id: settingsOwner
    function close() { root.closeSettings() }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: settingsOwner
    open: root.settingsOpen
    contentWidth: settingsPopup.fittedContentWidth(Style.space(300))
    contentHeight: settingsPopup.fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "NOW PLAYING"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: "Show album art"
        description: "Small cover thumbnail next to the track name."
        checked: root.showBarAlbumArt
        foreground: root.bar.foreground
        accent: root.accentColor
        fontFamily: root.bar.fontFamily
        onClicked: root.saveSetting("showAlbumArt", !root.showBarAlbumArt)
      }

      Toggle {
        width: parent.width
        label: "Show music icon"
        description: "Play/pause note before the track name."
        checked: root.showBarIcon
        foreground: root.bar.foreground
        accent: root.accentColor
        fontFamily: root.bar.fontFamily
        onClicked: root.saveSetting("showIcon", !root.showBarIcon)
      }

      SettingSlider {
        label: "Widget width"
        suffix: "px"
        minimum: 60
        maximum: 600
        step: 10
        currentValue: root.maxLabelWidth
        onPreviewed: function(value) { root.previewSetting("maxLabelWidth", Math.round(value / 10) * 10) }
        onCommitted: function(value) { root.saveSetting("maxLabelWidth", Math.round(value / 10) * 10) }
      }
    }
  }

  component SettingSlider: Column {
    id: sliderSetting

    required property string label
    property string suffix: ""
    required property real minimum
    required property real maximum
    required property real step
    required property real currentValue

    signal previewed(real value)
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(settingLabel.implicitHeight, settingValue.implicitHeight)

      Text {
        id: settingLabel
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: sliderSetting.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: settingValue
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: Math.round(slider.dragging ? slider.liveValue : sliderSetting.currentValue) + sliderSetting.suffix
        color: Qt.darker(root.bar.foreground, 1.35)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: sliderSetting.step
      integer: true
      value: sliderSetting.currentValue
      onMoved: function(value) { sliderSetting.previewed(value) }
      onReleased: function(value) { sliderSetting.committed(value) }
    }
  }
}
