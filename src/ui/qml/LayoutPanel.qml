import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Omareel.Ui
import "Aspects.js" as Aspects

ColumnLayout {
    id: root
    spacing: theme.space.panelGap
    readonly property var camera: editor.project.camera
    readonly property bool cameraShown: editor.hasCamera && root.camera.enabled

    PanelHeading { text: "Canvas" }
    OmDropdown {
        objectName: "layoutAspectMenu"
        Layout.fillWidth: true
        textRole: "text"
        model: Aspects.list
        currentIndex: {
            for (let i = 0; i < Aspects.list.length; ++i)
                if (Aspects.list[i].value === editor.project.aspect) return i
            return 0
        }
        onActivated: editor.setProjectValue("aspect", model[currentIndex].value)
    }

    ColumnLayout {
        visible: editor.hasCamera
        Layout.fillWidth: true
        spacing: theme.space.panelGap

        PanelHeading { text: "Camera layout"; Layout.topMargin: 2 }
        OmButtonGroup {
            objectName: "cameraLayoutGroup"
            Layout.fillWidth: true
            visible: root.cameraShown
            options: [{value: "split", label: "Split"}, {value: "bubble", label: "Bubble"}]
            value: editor.activeCameraLayout
            onChanged: value => editor.setProjectValue("camera.layout", value)
        }
        Label {
            visible: !root.cameraShown
            Layout.fillWidth: true
            text: "Turn on Show camera in Camera to place it."
            color: theme.textMuted
            font.pixelSize: theme.type.small
            wrapMode: Text.WordWrap
        }
        PanelLabel {
            visible: root.cameraShown && editor.activeCameraLayout === "split"
            text: "Split"
        }
        OmButtonGroup {
            objectName: "cameraSplitRatioGroup"
            Layout.fillWidth: true
            visible: root.cameraShown && editor.activeCameraLayout === "split"
            options: [{value: 0.5, label: "50/50"}, {value: 0.6, label: "60/40"}, {value: 0.7, label: "70/30"}]
            value: root.camera.splitRatio === undefined ? 0.6 : root.camera.splitRatio
            onChanged: value => editor.setProjectValue("camera.splitRatio", value)
        }
        Label {
            objectName: "layoutSplitOrientation"
            visible: root.cameraShown && editor.activeCameraLayout === "split"
            Layout.fillWidth: true
            text: editor.outputWidth > editor.outputHeight ? "Screen left, camera right" : "Screen on top, camera below"
            color: theme.textMuted
            font.pixelSize: theme.type.small
            wrapMode: Text.WordWrap
        }
    }

    PanelHeading { text: "Screen"; Layout.topMargin: 2 }
    PanelSlider { objectName: "screenFramingZoom"; Layout.fillWidth: true; label: "Zoom"; path: "screen.zoom"; from: 1; to: 4; value: editor.project.screen ? editor.project.screen.zoom : 1; stepSize: .01; decimals: 2 }
    PanelSlider { objectName: "screenFramingHorizontal"; Layout.fillWidth: true; label: "Move ↔"; path: "screen.pan.x"; from: -1; to: 1; value: editor.project.screen && editor.project.screen.pan ? editor.project.screen.pan.x : 0; stepSize: .01; decimals: 2 }
    PanelSlider { objectName: "screenFramingVertical"; Layout.fillWidth: true; label: "Move ↕"; path: "screen.pan.y"; from: -1; to: 1; value: editor.project.screen && editor.project.screen.pan ? editor.project.screen.pan.y : 0; stepSize: .01; decimals: 2 }
    EditorButton {
        objectName: "screenFramingReset"
        text: "Reset"
        onClicked: {
            editor.beginCoalescedEdit("screen.framing")
            editor.setProjectValue("screen.zoom", 1, true)
            editor.setProjectValue("screen.pan.x", 0, true)
            editor.setProjectValue("screen.pan.y", 0, true)
            editor.endCoalescedEdit()
        }
    }

    ColumnLayout {
        visible: root.cameraShown
        Layout.fillWidth: true
        spacing: theme.space.panelGap

        PanelHeading { text: "Camera"; Layout.topMargin: 2 }

        ColumnLayout {
            visible: editor.activeCameraLayout === "split"
            Layout.fillWidth: true
            spacing: theme.space.panelGap

            PanelSlider { objectName: "cameraFramingZoom"; Layout.fillWidth: true; label: "Zoom"; path: "camera.splitZoom"; from: 1; to: 3; value: root.camera.splitZoom === undefined ? 1 : root.camera.splitZoom; stepSize: .01; decimals: 2 }
            PanelSlider { objectName: "cameraFramingHorizontal"; Layout.fillWidth: true; label: "Move ↔"; path: "camera.splitPan.x"; from: -1; to: 1; value: root.camera.splitPan ? root.camera.splitPan.x : 0; stepSize: .01; decimals: 2 }
            PanelSlider { objectName: "cameraFramingVertical"; Layout.fillWidth: true; label: "Move ↕"; path: "camera.splitPan.y"; from: -1; to: 1; value: root.camera.splitPan ? root.camera.splitPan.y : 0; stepSize: .01; decimals: 2 }
            EditorButton {
                objectName: "cameraFramingReset"
                text: "Reset"
                onClicked: {
                    editor.beginCoalescedEdit("camera.framing")
                    editor.setProjectValue("camera.splitZoom", 1, true)
                    editor.setProjectValue("camera.splitPan.x", 0, true)
                    editor.setProjectValue("camera.splitPan.y", 0, true)
                    editor.endCoalescedEdit()
                }
            }
        }

        ColumnLayout {
            visible: editor.activeCameraLayout === "bubble"
            Layout.fillWidth: true
            spacing: theme.space.panelGap

            // A miniature canvas: click a quadrant and the bubble glides to that corner.
            Rectangle {
                id: positionPad
                objectName: "cameraPositionPad"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * 9 / 16 * .62)
                radius: theme.controlRadius
                color: theme.fill
                border.width: 1
                border.color: theme.stroke
                readonly property real inset: 10
                readonly property real bubble: Math.max(16, height * (.22 + root.camera.size * .6))
                Repeater {
                    model: ["top-left", "top-right", "bottom-left", "bottom-right"]
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool atRight: modelData.endsWith("right")
                        readonly property bool atBottom: modelData.startsWith("bottom")
                        x: atRight ? positionPad.width / 2 : 0
                        y: atBottom ? positionPad.height / 2 : 0
                        width: positionPad.width / 2
                        height: positionPad.height / 2
                        color: quadrantMouse.containsMouse && root.camera.position !== modelData ? theme.fillHover : "transparent"
                        radius: theme.controlRadius
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            x: parent.atRight ? parent.width - width - positionPad.inset - 4 : positionPad.inset + 4
                            y: parent.atBottom ? parent.height - height - positionPad.inset - 4 : positionPad.inset + 4
                            color: theme.textFaint
                            opacity: root.camera.position === parent.modelData ? 0 : 1
                        }
                        MouseArea {
                            id: quadrantMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.setProjectValue("camera.position", parent.modelData)
                        }
                    }
                }
                Rectangle {
                    id: bubble
                    readonly property bool atRight: root.camera.position.endsWith("right")
                    readonly property bool atBottom: root.camera.position.startsWith("bottom")
                    width: positionPad.bubble
                    height: root.camera.shape === "rectangle" ? width * 9 / 16 : width
                    x: atRight ? positionPad.width - width - positionPad.inset : positionPad.inset
                    y: atBottom ? positionPad.height - height - positionPad.inset : positionPad.inset
                    radius: root.camera.shape === "round" ? width / 2 : Math.min(width / 3, root.camera.radius / 4)
                    color: Qt.alpha(theme.accent, .85)
                    border.width: root.camera.border.enabled ? 2 : 0
                    border.color: root.camera.border.color
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
            PanelSlider { Layout.fillWidth: true; label: "Size"; path: "camera.size"; from: .1; to: .5; value: root.camera.size; stepSize: .01; decimals: 2 }
        }
    }

    Label {
        objectName: "layoutTip"
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: "Drag in the preview to move, Ctrl+scroll to zoom."
        color: theme.textMuted
        font.pixelSize: theme.type.small
        wrapMode: Text.WordWrap
    }
}
