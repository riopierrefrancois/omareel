.pragma library

// The framing maths shared by the preview and the exporter's QML. Pan is signed so that +1
// moves the picture right and up.

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// The visible part of the unrotated camera source, normalised 0..1, for an item of itemW x itemH
// on the canvas. Rotation is clockwise, as QML draws it, and the mirror applies after it.
function cameraCrop(itemW, itemH, srcW, srcH, rotation, flip, zoom, panX, panY) {
    if (itemW <= 0 || itemH <= 0 || srcW <= 0 || srcH <= 0)
        return { x: 0, y: 0, width: 1, height: 1 }
    var turn = rotation === 90 || rotation === 180 || rotation === 270 ? rotation : 0
    zoom = clamp(zoom, 1, 3)
    panX = clamp(panX, -1, 1)
    panY = clamp(panY, -1, 1)
    var displayAspect = turn === 90 || turn === 270 ? srcH / srcW : srcW / srcH
    var itemAspect = itemW / itemH
    // Cover the item: the cropped axis is the one where the item's shape differs from the source's.
    var visW = 1
    var visH = 1
    if (itemAspect > displayAspect)
        visH = displayAspect / itemAspect
    else
        visW = itemAspect / displayAspect
    visW = visW / zoom
    visH = visH / zoom
    // The window starts centred; +1 pan moves the picture right or up, showing its left or lower
    // part.
    var dx = (1 - visW) / 2 * (1 - panX)
    var dy = (1 - visH) / 2 * (1 + panY)
    var x = dx
    var y = dy
    var w = visW
    var h = visH
    if (turn === 90) {
        x = dy
        y = 1 - dx - visW
        w = visH
        h = visW
    } else if (turn === 180) {
        x = 1 - dx - visW
        y = 1 - dy - visH
    } else if (turn === 270) {
        x = 1 - dy - visH
        y = dx
        w = visH
        h = visW
    }
    if (flip)
        x = 1 - x - w
    return { x: x, y: y, width: w, height: h }
}

// How much pan one canvas pixel of drag is worth for the camera band.
function cameraPanPerPixel(itemW, itemH, srcW, srcH, rotation, zoom) {
    if (itemW <= 0 || itemH <= 0 || srcW <= 0 || srcH <= 0)
        return { x: 0, y: 0 }
    var turn = rotation === 90 || rotation === 180 || rotation === 270 ? rotation : 0
    zoom = clamp(zoom, 1, 3)
    var displayAspect = turn === 90 || turn === 270 ? srcH / srcW : srcW / srcH
    var itemAspect = itemW / itemH
    var visW = 1
    var visH = 1
    if (itemAspect > displayAspect)
        visH = displayAspect / itemAspect
    else
        visW = itemAspect / displayAspect
    visW = visW / zoom
    visH = visH / zoom
    return {
        x: 1 - visW < 0.000001 ? 0 : 2 / ((1 - visW) * itemW / visW),
        y: 1 - visH < 0.000001 ? 0 : 2 / ((1 - visH) * itemH / visH)
    }
}

// Where the fitted screen frame sits, and how large it is, relative to the region it is drawn in.
function screenFrame(regionW, regionH, fitW, fitH, zoom, panX, panY) {
    if (regionW <= 0 || regionH <= 0 || fitW <= 0 || fitH <= 0)
        return { x: (regionW - fitW) / 2, y: (regionH - fitH) / 2, width: fitW, height: fitH }
    zoom = clamp(zoom, 1, 4)
    panX = clamp(panX, -1, 1)
    panY = clamp(panY, -1, 1)
    var w = fitW * zoom
    var h = fitH * zoom
    return {
        x: (regionW - w) / 2 + panX * Math.abs(regionW - w) / 2,
        y: (regionH - h) / 2 - panY * Math.abs(regionH - h) / 2,
        width: w,
        height: h
    }
}

// How much screen pan one canvas pixel of drag is worth, and zero on an axis with no slack.
function screenPanPerPixel(regionW, regionH, fitW, fitH, zoom) {
    if (regionW <= 0 || regionH <= 0 || fitW <= 0 || fitH <= 0)
        return { x: 0, y: 0 }
    zoom = clamp(zoom, 1, 4)
    var slackX = Math.abs(regionW - fitW * zoom)
    var slackY = Math.abs(regionH - fitH * zoom)
    return {
        x: slackX < 0.000001 ? 0 : 2 / slackX,
        y: slackY < 0.000001 ? 0 : 2 / slackY
    }
}
