import QtQuick
import QtQuick.Effects
import Omareel
import "Framing.js" as Framing

Item {
    id: composition
    // Preview-only access point. Exporter continues finding the same objectName.
    readonly property alias frameSource: frame.frameSource
    readonly property alias videoOutput: frame.videoOutput
    readonly property alias cameraFrameSource: cameraOverlay.cameraFrameSource
    readonly property alias cameraVideoOutput: cameraOverlay.cameraVideoOutput
    readonly property alias mediaVideoOutput: mediaLayer.videoOutput
    property bool nativePreview: false
    width: comp.outputWidth
    height: comp.outputHeight
    property real ref: height / 1080
    // The cursor keeps the size it had on screen: one logical screen pixel is captureScale
    // source pixels, and the (cropped) source is drawn at videoWidth output pixels. A small
    // region therefore gets a proportionally large cursor instead of a microscopic one.
    property real cursorRef: (comp.captureScale > 0 ? comp.captureScale : 1)
                             * videoWidth / Math.max(1, comp.sourceWidth * comp.project.crop.w)
    property bool noBackground: comp.project.background.type === "none"
    readonly property bool splitActive: !!comp.layout.splitActive
    // How far Split is shown: the bubble's value, so screen clips and camera clips ease out of it.
    readonly property real splitAmount: splitActive && cameraShown && !mediaActive ? comp.layout.bubble : 0
    readonly property real regionX: (comp.layout.screenX || 0) * splitAmount
    readonly property real regionY: (comp.layout.screenY || 0) * splitAmount
    readonly property real regionWidth: width + ((comp.layout.screenWidth || width) - width) * splitAmount
    readonly property real regionHeight: height + ((comp.layout.screenHeight || height) - height) * splitAmount
    // No background stretches the screen to the canvas, except in Split, which keeps its shape.
    readonly property bool stretchScreen: noBackground && splitAmount <= 0
    property real pad: noBackground ? 0 : Math.min(regionWidth, regionHeight) * comp.project.frame.padding
    property real availableWidth: regionWidth - 2 * pad
    property real availableHeight: regionHeight - 2 * pad
    property real borderWidth: !noBackground && comp.project.frame.border.enabled
                               ? comp.project.frame.border.width * ref : 0
    property real sourceAspect: (comp.sourceWidth * comp.project.crop.w) / Math.max(1, comp.sourceHeight * comp.project.crop.h)
    property real fitWidth: stretchScreen ? regionWidth
        : Math.max(1, Math.min(availableWidth - 2 * borderWidth,
                              (availableHeight - 2 * borderWidth) * sourceAspect))
    property real fitHeight: stretchScreen ? regionHeight : fitWidth / sourceAspect
    readonly property real screenZoom: comp.project.screen ? comp.project.screen.zoom : 1
    readonly property real screenPanX: comp.project.screen && comp.project.screen.pan ? comp.project.screen.pan.x : 0
    readonly property real screenPanY: comp.project.screen && comp.project.screen.pan ? comp.project.screen.pan.y : 0
    readonly property var screenRect: Framing.screenFrame(regionWidth, regionHeight, fitWidth, fitHeight,
                                                           screenZoom, screenPanX, screenPanY)
    property real videoWidth: screenRect.width
    property real videoHeight: screenRect.height
    readonly property real frameX: regionX + screenRect.x
    readonly property real frameY: regionY + screenRect.y
    readonly property real frameWidth: videoWidth
    readonly property real frameHeight: videoHeight
    readonly property bool cameraShown: comp.cameraAvailable && comp.cameraVisible
    // How far the current clip's layout has grown the camera to full frame.
    readonly property real cameraFull: cameraShown ? comp.layout.cameraFull : 0
    // The camera's source facts and Split framing, for the preview's drag and wheel handlers.
    readonly property int cameraSourceWidth: comp.cameraSourceWidth
    readonly property int cameraSourceHeight: comp.cameraSourceHeight
    readonly property int cameraRotation: comp.project.camera.rotation
    readonly property real cameraSplitZoom: comp.project.camera.splitZoom === undefined ? 1 : comp.project.camera.splitZoom
    readonly property real cameraSplitPanX: comp.project.camera.splitPan ? comp.project.camera.splitPan.x : 0
    readonly property real cameraSplitPanY: comp.project.camera.splitPan ? comp.project.camera.splitPan.y : 0
    // An inserted video replaces the recording, its camera and keys while it plays.
    readonly property bool mediaActive: comp.media.active
    // Once the camera or an inserted video covers the canvas, nothing beneath needs drawing.
    readonly property bool screenCovered: cameraFull >= 1 || mediaActive
    readonly property bool backgroundCovered: cameraFull >= 1
        || (mediaActive && comp.media.ready && comp.media.fit !== "framed")
    clip: true

    Background {
        anchors.fill: parent
        visible: !composition.backgroundCovered
        settings: comp.project.background
        softwareRendering: comp.softwareRendering
        loadAsynchronously: composition.nativePreview
    }

    // With no background the export leaves uncovered pixels black; Split does the same.
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: composition.noBackground && composition.splitAmount > 0
    }

    Item {
        id: screenClip
        x: composition.regionX
        y: composition.regionY
        width: composition.regionWidth
        height: composition.regionHeight
        clip: composition.splitAmount > 0 || composition.screenZoom > 1
        visible: !composition.screenCovered

        Item {
            id: stage
            anchors.fill: parent
            layer.enabled: !comp.softwareRendering && comp.project.zoomStyle.motionBlur > 0
                && comp.zoom.velocity > 0.01
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 32
                blur: Math.min(1, comp.zoom.velocity * .32) * comp.project.zoomStyle.motionBlur
            }
            transform: Scale {
                origin.x: frame.x + comp.zoom.cx * frame.width
                origin.y: frame.y + comp.zoom.cy * frame.height
                xScale: comp.zoom.scale
                yScale: comp.zoom.scale
            }
            RoundedFrame {
                id: frame
                x: composition.screenRect.x
                y: composition.screenRect.y
                width: composition.videoWidth
                height: composition.videoHeight
                settings: comp.project.frame
                crop: comp.project.crop
                softwareRendering: comp.softwareRendering
                ref: composition.ref
                unframed: composition.noBackground
                nativePreview: composition.nativePreview
            }
            CursorOverlay {
                x: frame.x
                y: frame.y
                width: frame.width
                height: frame.height
                cursor: comp.cursor
                ripples: comp.ripples
                settings: comp.project.cursor
                ref: composition.cursorRef
            }
        }
    }
    CameraOverlay {
        id: cameraOverlay
        visible: composition.cameraShown && !composition.mediaActive
            && (composition.cameraFull > 0 || comp.layout.bubble > 0)
        settings: comp.project.camera
        fullProgress: composition.cameraFull
        bubbleOpacity: comp.layout.bubble
        splitMode: composition.splitActive
        bandRect: Qt.rect(comp.layout.cameraX || 0, comp.layout.cameraY || 0,
                          comp.layout.cameraWidth || 0, comp.layout.cameraHeight || 0)
        splitZoom: comp.project.camera.splitZoom === undefined ? 1 : comp.project.camera.splitZoom
        splitPanX: comp.project.camera.splitPan ? comp.project.camera.splitPan.x : 0
        splitPanY: comp.project.camera.splitPan ? comp.project.camera.splitPan.y : 0
        zoomScale: comp.zoom.scale
        outputWidth: composition.width
        outputHeight: composition.height
        sourceWidth: comp.cameraSourceWidth
        sourceHeight: comp.cameraSourceHeight
        softwareRendering: comp.softwareRendering
        nativePreview: composition.nativePreview
    }
    MediaLayer {
        id: mediaLayer
        anchors.fill: parent
        visible: composition.mediaActive
        // The preview holds the layer back until the clip's first frame, so the last frame of
        // an earlier clip never flashes.
        opacity: comp.media.ready ? 1 : 0
        media: comp.media
        frameSettings: comp.project.frame
        padding: composition.pad
        ref: composition.ref
        softwareRendering: comp.softwareRendering
        nativePreview: composition.nativePreview
    }
    Item {
        x: composition.regionX
        y: composition.regionY
        width: composition.regionWidth
        height: composition.regionHeight

        KeystrokeOverlay {
            visible: comp.project.keystrokes.enabled && comp.keystrokePills.length > 0
                && !composition.screenCovered
            opacity: 1 - composition.cameraFull
            pills: comp.keystrokePills
            settings: comp.project.keystrokes
            colors: comp.project.renderTheme
            ref: composition.ref
        }
    }
}
