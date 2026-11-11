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
}
