import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Omareel.Ui

ColumnLayout {
    id: root
    spacing: theme.space.panelGap
    readonly property var camera: editor.project.camera

    OmEmptyState {
        visible: !editor.hasCamera
        iconSource: "qrc:/omareel/assets/icons/lucide/video-off.svg"
        title: "No camera in this recording"
        hint: "Turn on Camera in the launcher before recording to add a camera."
    }
    Label {
        visible: editor.hasCamera && editor.cameraStatus !== ""
        Layout.fillWidth: true
        text: editor.cameraStatus
        wrapMode: Text.WordWrap
        color: theme.textMuted
        font.pixelSize: theme.type.small
    }
    EditorSwitch {
        visible: editor.hasCamera
        text: "Show camera"
        description: "Show the camera in the video"
        enabled: editor.hasCamera
        checked: editor.hasCamera && root.camera.enabled
        onToggled: editor.setProjectValue("camera.enabled", checked)
    }
    ColumnLayout {
        visible: editor.hasCamera
        Layout.fillWidth: true
        spacing: theme.space.panelGap
        enabled: editor.hasCamera && root.camera.enabled
        opacity: enabled ? 1 : .42
        Behavior on opacity { NumberAnimation { duration: 160 } }

        PanelHeading { text: "Bubble style" }
        Label {
            objectName: "cameraBubbleStyleNote"
            visible: editor.activeCameraLayout === "split"
            Layout.fillWidth: true
            text: "Shape, shadow and border apply to the bubble. Switch Layout to Bubble to change them."
            color: theme.textMuted
            font.pixelSize: theme.type.small
            wrapMode: Text.WordWrap
        }
        ColumnLayout {
            objectName: "cameraBubbleStyle"
            visible: editor.activeCameraLayout === "bubble"
            Layout.fillWidth: true
            spacing: theme.space.panelGap
            enabled: editor.activeCameraLayout === "bubble"
            opacity: enabled ? 1 : .42
            Behavior on opacity { NumberAnimation { duration: 160 } }

            OmSettingRow {
                label: "Shape"
                OmButtonGroup {
                    objectName: "cameraShapeGroup"
                    Layout.preferredWidth: 212
                    options: [{value:"round", label:"Round"}, {value:"square", label:"Square"}, {value:"rectangle", label:"Rectangle"}]
                    value: root.camera.shape
                    onChanged: value => editor.setProjectValue("camera.shape", value)
                }
            }
            PanelSlider { visible: root.camera.shape !== "round"; Layout.fillWidth: true; label: "Corner radius"; path: "camera.radius"; from: 0; to: 80; value: root.camera.radius; stepSize: 1; suffix: " px" }
            PanelSlider { Layout.fillWidth: true; label: "Shrink while zoomed"; path: "camera.scaleDuringZoom"; from: .4; to: 1; value: root.camera.scaleDuringZoom; stepSize: .01; decimals: 2 }

            OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
            EditorSwitch { text: "Shadow"; checked: root.camera.shadow.enabled; onToggled: editor.setProjectValue("camera.shadow.enabled", checked) }
            ColumnLayout {
                visible: root.camera.shadow.enabled
                Layout.fillWidth: true
                spacing: theme.space.panelGap
                PanelSlider { Layout.fillWidth: true; label: "Intensity"; path: "camera.shadow.intensity"; from: 0; to: 1; value: root.camera.shadow.intensity; stepSize: .01; decimals: 2 }
                PanelSlider { Layout.fillWidth: true; label: "Blur"; path: "camera.shadow.blur"; from: 0; to: 64; value: root.camera.shadow.blur; stepSize: 1 }
                PanelSlider { Layout.fillWidth: true; label: "Distance"; path: "camera.shadow.distance"; from: 0; to: 80; value: root.camera.shadow.distance; stepSize: 1 }
            }

            OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
            EditorSwitch { text: "Border"; checked: root.camera.border.enabled; onToggled: editor.setProjectValue("camera.border.enabled", checked) }
            ColumnLayout {
                visible: root.camera.border.enabled
                Layout.fillWidth: true
                spacing: theme.space.panelGap
                PanelSlider { Layout.fillWidth: true; label: "Width"; path: "camera.border.width"; from: 0; to: 16; value: root.camera.border.width; stepSize: 1; suffix: " px" }
                PanelSlider { Layout.fillWidth: true; label: "Opacity"; path: "camera.border.alpha"; from: 0; to: 1; value: root.camera.border.alpha; stepSize: .01; decimals: 2 }
                OmSettingRow {
                    label: "Color"
                    OmColorWell { swatch: root.camera.border.color; onClicked: borderColourDialog.open() }
                }
            }
        }
    }
    // Orientation and the full-screen look apply to camera clips too, so they stay available
    // with the bubble switched off.
    ColumnLayout {
        visible: editor.hasCamera
        Layout.fillWidth: true
        spacing: theme.space.panelGap

        OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
        PanelHeading { text: "Full screen" }
        OmButtonGroup {
            objectName: "cameraFullFrameGroup"
            Layout.fillWidth: true
            options: [{value:"fill", label:"Fill frame"}, {value:"square", label:"Square + blur"}]
            value: root.camera.fullFrame
            onChanged: value => editor.setProjectValue("camera.fullFrame", value)
        }
        Label {
            Layout.fillWidth: true
            text: "Clips set to Show: Camera fill the frame with the camera. Set it per clip in Clip."
            color: theme.textMuted
            font.pixelSize: theme.type.small
            wrapMode: Text.WordWrap
        }

        OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
        OmSettingRow {
            label: "Rotation"
            OmButtonGroup {
                Layout.preferredWidth: 176
                options: [{value:0,label:"0°"}, {value:90,label:"90°"},
                    {value:180,label:"180°"}, {value:270,label:"270°"}]
                value: root.camera.rotation
                onChanged: value => editor.setProjectValue("camera.rotation", value)
            }
        }
        EditorSwitch {
            text: "Mirror"
            description: "Flip the camera horizontally"
            checked: root.camera.flipHorizontal
            onToggled: editor.setProjectValue("camera.flipHorizontal", checked)
        }
    }
    ColorDialog {
        id: borderColourDialog
        selectedColor: root.camera.border.color
        onAccepted: editor.setProjectValue("camera.border.color", selectedColor)
    }
}
