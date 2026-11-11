import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Omareel.Ui

ColumnLayout {
    id: root
    spacing: theme.space.panelGap
    readonly property bool frameEnabled: editor.project.background.type !== "none"
    PanelHeading { text: "Screen framing" }
    PanelSlider { objectName: "screenFramingZoom"; Layout.fillWidth: true; label: "Zoom"; path: "screen.zoom"; from: 1; to: 4; value: editor.project.screen ? editor.project.screen.zoom : 1; stepSize: .01; decimals: 2 }
    PanelSlider { objectName: "screenFramingHorizontal"; Layout.fillWidth: true; label: "Horizontal"; path: "screen.pan.x"; from: -1; to: 1; value: editor.project.screen && editor.project.screen.pan ? editor.project.screen.pan.x : 0; stepSize: .01; decimals: 2 }
    PanelSlider { objectName: "screenFramingVertical"; Layout.fillWidth: true; label: "Vertical"; path: "screen.pan.y"; from: -1; to: 1; value: editor.project.screen && editor.project.screen.pan ? editor.project.screen.pan.y : 0; stepSize: .01; decimals: 2 }
    EditorButton {
        objectName: "screenFramingReset"
        text: "Reset framing"
        onClicked: {
            editor.beginCoalescedEdit("screen.framing")
            editor.setProjectValue("screen.zoom", 1, true)
            editor.setProjectValue("screen.pan.x", 0, true)
            editor.setProjectValue("screen.pan.y", 0, true)
            editor.endCoalescedEdit()
        }
    }
    OmSeparator { Layout.fillWidth: true }
    Label {
        visible: !root.frameEnabled
        Layout.fillWidth: true
        text: "Shape settings stay saved but are ignored while the background type is None."
        wrapMode: Text.WordWrap
        color: theme.textMuted
        font.pixelSize: theme.type.small
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: theme.space.panelGap
        enabled: root.frameEnabled
        opacity: enabled ? 1 : .42
        PanelHeading { text: "Frame" }
        PanelSlider { Layout.fillWidth: true; label: "Padding"; path: "frame.padding"; from: 0; to: 0.3; value: editor.project.frame.padding; stepSize: 0.005; decimals: 2 }
        PanelSlider { Layout.fillWidth: true; label: "Roundness"; path: "frame.radius"; from: 0; to: 80; value: editor.project.frame.radius; stepSize: 1; suffix: " px" }
        OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
        EditorSwitch { text: "Shadow"; description: "Drop shadow under the recording"; checked: editor.project.frame.shadow.enabled; onToggled: editor.setProjectValue("frame.shadow.enabled", checked) }
        PanelSlider { Layout.fillWidth: true; label: "Intensity"; path: "frame.shadow.intensity"; from: 0; to: 1; value: editor.project.frame.shadow.intensity; stepSize: 0.01; decimals: 2 }
        PanelSlider { Layout.fillWidth: true; label: "Blur"; path: "frame.shadow.blur"; from: 0; to: 100; value: editor.project.frame.shadow.blur; stepSize: 1 }
        PanelSlider { Layout.fillWidth: true; label: "Distance"; path: "frame.shadow.distance"; from: 0; to: 100; value: editor.project.frame.shadow.distance; stepSize: 1 }
        PanelSlider { Layout.fillWidth: true; label: "Angle"; path: "frame.shadow.angle"; from: 0; to: 360; value: editor.project.frame.shadow.angle; stepSize: 1; suffix: "°" }
        OmSeparator { Layout.fillWidth: true; Layout.topMargin: 2 }
        EditorSwitch { text: "Border"; description: "Inset outline around the frame"; checked: editor.project.frame.border.enabled; onToggled: editor.setProjectValue("frame.border.enabled", checked) }
        PanelSlider { Layout.fillWidth: true; label: "Width"; path: "frame.border.width"; from: 0; to: 16; value: editor.project.frame.border.width; stepSize: 1; suffix: " px" }
        OmSettingRow {
            label: "Color"
            OmColorWell { swatch: editor.project.frame.border.color; onClicked: borderColorDialog.open() }
        }
        PanelSlider { Layout.fillWidth: true; label: "Opacity"; path: "frame.border.alpha"; from: 0; to: 1; value: editor.project.frame.border.alpha; stepSize: 0.01; decimals: 2 }
    }
    ColorDialog {
        id: borderColorDialog
        selectedColor: editor.project.frame.border.color
        onAccepted: editor.setProjectValue("frame.border.color", selectedColor)
    }
}
