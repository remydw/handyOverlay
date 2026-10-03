import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Floating pill showing Handy's state (recording / transcribing) with a live
// mic waveform. State comes from Handy's log; the level comes from level.py.
PluginComponent {
    id: root

    readonly property string logPath: Paths.strip(Paths.home) + "/.local/share/com.pais.handy/logs/handy.log"
    readonly property string levelScript: Paths.strip(Qt.resolvedUrl("level.py"))
    readonly property int barCount: 17
    // PipeWire node name of the mic to meter; empty follows the default source (what Handy uses).
    readonly property string micNode: ""

    property string state: "idle" // idle | recording | transcribing
    property var levels: new Array(barCount).fill(0)

    function setState(s) {
        if (root.state === s)
            return;
        root.state = s;
        if (s === "recording")
            root.levels = new Array(root.barCount).fill(0);
        if (s === "transcribing")
            watchdog.restart();
        else
            watchdog.stop();
    }

    function handleLine(line) {
        if (line.indexOf("TranscribeAction::start completed") >= 0)
            setState("recording");
        else if (line.indexOf("TranscribeAction::stop called") >= 0)
            setState("transcribing");
        else if (line.indexOf("Text pasted successfully") >= 0 || line.indexOf("Transcription result is empty") >= 0 || line.indexOf("Recording produced no audio samples") >= 0 || line.indexOf("cancellation completed") >= 0)
            setState("idle");
    }

    function pushLevel(v) {
        const next = root.levels.slice(1);
        next.push(v);
        root.levels = next;
    }

    // Safety net: never leave the pill stuck on screen.
    Timer {
        id: watchdog
        interval: 30000
        onTriggered: root.setState("idle")
    }

    Process {
        id: logTail
        running: true
        command: ["tail", "-n", "0", "-F", root.logPath]
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
    }

    Process {
        id: levelProc
        running: root.state === "recording"
        command: ["python3", root.levelScript, root.micNode]
        stdout: SplitParser {
            onRead: data => root.pushLevel(parseFloat(data) || 0)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool onFocusedScreen: modelData && CompositorService.getFocusedScreen() && modelData.name === CompositorService.getFocusedScreen().name
            readonly property bool wanted: root.state !== "idle" && onFocusedScreen

            screen: modelData
            visible: pill.opacity > 0.01
            color: "transparent"
            mask: Region {}

            WlrLayershell.namespace: "dms:handy-overlay"
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.bottom: true
            WlrLayershell.margins.bottom: 56
            implicitWidth: 220
            implicitHeight: 52

            Rectangle {
                id: pill
                anchors.centerIn: parent
                width: 200
                height: 40
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)
                opacity: win.wanted ? 1 : 0
                scale: win.wanted ? 1 : 0.92

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.shortDuration
                    }
                }

                Rectangle {
                    id: dot
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    color: root.state === "recording" ? Theme.error : Theme.primary

                    SequentialAnimation on opacity {
                        running: pill.opacity > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.35
                            duration: 600
                        }
                        NumberAnimation {
                            to: 1
                            duration: 600
                        }
                    }
                }

                Row {
                    id: bars
                    anchors.left: dot.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    spacing: 3

                    Repeater {
                        model: root.barCount

                        Rectangle {
                            required property int index
                            // While transcribing, show a gentle travelling wave instead of the mic level.
                            property real wave: 0.25 + 0.2 * Math.sin(phase.value + index * 0.6)
                            readonly property real level: root.state === "recording" ? root.levels[index] : wave

                            width: (bars.width - (root.barCount - 1) * bars.spacing) / root.barCount
                            height: Math.max(3, Math.min(bars.height, 3 + level * (bars.height - 3)))
                            anchors.verticalCenter: parent.verticalCenter
                            radius: width / 2
                            color: root.state === "recording" ? Theme.primary : Theme.withAlpha(Theme.primary, 0.6)

                            Behavior on height {
                                NumberAnimation {
                                    duration: 60
                                }
                            }
                        }
                    }
                }

                QtObject {
                    id: phase
                    property real value: 0
                }
                Timer {
                    interval: 50
                    repeat: true
                    running: root.state === "transcribing"
                    onTriggered: phase.value += 0.45
                }
            }
        }
    }
}
