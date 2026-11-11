# Design: framing the camera (Split) and the screen

Date: 2026-11-11. Branch `pf/split-and-timeline` (after `8c33083`, package 0.5.0.pf2).
Plan: `docs/superpowers/plans/2026-11-11-split-camera-framing.md`.

## Why

PF edits screen recordings into vertical reels. Two framing problems show up while editing:

1. **Camera in Split.** The webcam picture is cover-cropped into its band, always centred. When
   PF is not centred in the webcam shot, the band shows him off to one side. He wants to scale
   the camera picture up and move it ("a bit right and up") until he sits well in the band.
2. **Screen.** A desktop recording fitted into a tall canvas (or the Split screen region) is
   small and sometimes looks off-centre. He wants to scale the screen picture up past today's fit
   and move it (e.g. a bit left), then export.

Both are a static base framing chosen once per project. The existing auto/manual zooms, the
cursor, the click ripples and the keystroke pills keep working on top of it.

## Behaviour

### Camera framing (Split only)

- **Zoom** 1.0–3.0. 1.0 is today's cover crop (the band is filled, nothing is stretched).
- **Horizontal / Vertical** -1..1. They move the **picture**: Horizontal +1 moves the picture
  fully right (the band then shows the picture's left part), -1 fully left; Vertical +1 moves
  the picture fully up (the band shows its lower part), -1 fully down. 0 is centred. ±1 is the
  furthest the picture can go while still covering the band; at zoom 1 there is still room on
  the axis the cover crop trims (on a 9:16 canvas that is horizontal), none on the other.
- Applies only while the Split layout is drawn. Bubble and full-frame camera are unchanged.
- Camera clips morph band → full frame (`fullProgress` 0 → 1). The framing blends out with it:
  effective zoom `1 + (zoom - 1)(1 - fullProgress)`, effective pan `pan · (1 - fullProgress)`,
  so the picture never jumps.
- Rotation and mirror are respected: the controls always move the picture as seen on the canvas.
- Presets carry the camera look but not the framing (it belongs to one webcam shot), just as
  they already keep the current layout.

### Screen framing (every layout)

- **Zoom** 1.0–4.0. 1.0 is today's fitted frame (padding, border and all).
- **Horizontal / Vertical** -1..1, moving the picture the same way as the camera's. ±1 puts the
  frame's edge on the region's edge: when the zoomed frame is larger than its region, ±1 shows
  one edge of the picture; when it is smaller (zoom near 1 with padding), ±1 slides it until it
  touches that side. 0 is centred (today).
- The region is the whole canvas, or the Split screen region (already clipped). Bubble, Split,
  no-background (stretched) and padded frames all apply it.
- The cursor, ripples and click effects sit on the frame, so they follow the scaled, moved
  screen. The cursor grows with the zoom, as it grows today with a larger frame.
- Auto/manual zooms compose: the zoom `Scale` on `stage` takes its origin from the frame's
  position and size, which now include the base framing.
- The zoom target picker maps a click to the source point through the composition's frame
  geometry, which now includes the framing, so picked points stay right.
- Presets do not carry the screen framing (it is a new top-level key, not in `PRESET_KEYS`).

### Editing

- **Camera panel**, visible in Split: a "Framing" group with Zoom, Horizontal and Vertical
  sliders and a "Reset framing" button. One undo step per slider drag (PanelSlider already
  coalesces) and one for Reset.
- **Shape panel**, at the top and outside the part greyed out for "background: None" (the
  framing applies there too): a "Screen framing" group with Zoom, Horizontal and Vertical sliders
  and "Reset framing". Shape is the panel about the screen's frame, so this fits there.
- **Preview** (last phase): drag on the camera band pans the camera picture (Split only); drag on
  the screen pans the screen picture. Ctrl+wheel over either zooms it (around the centre). Plain
  wheel is left alone so scrolling never reframes by accident. Both are off while the zoom
  target picker or crop mode is active, and the camera band area wins over the screen area.

## Data

Project JSON (camelCase, like the rest):

```json
"camera": { "splitZoom": 1.6, "splitPan": { "x": 0.4, "y": 0.25 }, ... },
"screen": { "zoom": 1.5, "pan": { "x": -0.3, "y": 0 } }
```

- `camera.splitZoom` clamped 1–3 (default 1), `camera.splitPan.x/y` clamped -1..1 (default 0).
- Top-level `screen.zoom` clamped 1–4 (default 1), `screen.pan.x/y` clamped -1..1 (default 0).
  (A top-level object rather than `screenZoom`/`screenPan` keys: it reads as one thing and stays
  out of presets, whose keys are whole top-level objects.)
- Written only when not default (`splitZoom` when ≠ 1, `splitPan` when either axis ≠ 0, `screen`
  when zoom ≠ 1 or either axis ≠ 0), exactly like `splitRatio`. Every saved project and every
  golden stays byte-identical; a golden change means a mistake.
- Rust: `Camera.split_zoom: f64`, `Camera.split_pan: PointF` (the type `offset` uses);
  `Project.screen: ScreenFraming { zoom: f64, pan: PointF }` in `project/styles.rs`.

## Where the math lives (and why not in Rust)

The plan first asked for one pure Rust function used by preview and export. The code says
otherwise:

- Preview and export draw the **same QML**: the editor shows `Composition.qml` with
  `nativePreview: true`; the exporter loads the same `Composition.qml` offscreen
  (`ExportRenderer.cpp`), with a C++ `CompositionState` as `comp`.
- The camera crop is computed per frame from **animated item sizes** (`CameraOverlay` morphs
  between band and full frame, and in the preview springs edits), and the screen frame from the
  animated Split region (`splitAmount`). Rust does not see those sizes.
- Exposing a Rust function to both would need an invokable on the Rust `Editor` *and* on the C++
  `CompositionState`, for no gain in consistency: the QML is already the single path.

So the geometry lives in one JS library, `src/ui/qml/Framing.js` (`.pragma library`, part of the
`Omareel` QML module), used by `CameraOverlay.qml`, `Composition.qml` and `PreviewPane.qml`, and
unit-tested from C++ (`tests/test_editor.cpp` loads it through a `QQmlEngine`). Rust keeps what
Rust owns, with Rust unit tests: the project fields, clamping, save rules, presets, and the export
**decode sizes**.

### `Framing.js`

```
cameraCrop(itemW, itemH, srcW, srcH, rotation, flip, zoom, panX, panY) -> {x, y, width, height}
cameraPanPerPixel(itemW, itemH, srcW, srcH, rotation, zoom) -> {x, y}
screenFrame(regionW, regionH, fitW, fitH, zoom, panX, panY) -> {x, y, width, height}
screenPanPerPixel(regionW, regionH, fitW, fitH, zoom) -> {x, y}
```

- `cameraCrop` returns the visible part of the **camera source** (unrotated, unmirrored),
  normalised 0..1, for an item of `itemW × itemH` on the canvas. Work in display space: display
  aspect = `srcH/srcW` for 90/270, else `srcW/srcH`; cover-fit the item (visible fraction
  `visW, visH`), divide both by `zoom`; window `x = (1 - visW)/2 · (1 - panX)`,
  `y = (1 - visH)/2 · (1 + panY)`. Then undo the rotation (QML rotates clockwise; the item's
  `transform` list, the mirror, applies before its rotation):
  90°: `(dy, 1 - dx - dw, dh, dw)`; 180°: `(1 - dx - dw, 1 - dy - dh, dw, dh)`;
  270°: `(1 - dy - dh, dx, dh, dw)`; then mirror: `x = 1 - x - w`.
  At zoom 1 and pan 0 it equals today's `coverCrop` for every rotation and mirror (tested).
- `screenFrame` returns the frame rect relative to its region: `w = fitW·zoom`,
  `h = fitH·zoom`, `x = (regionW - w)/2 + panX·|regionW - w|/2`,
  `y = (regionH - h)/2 - panY·|regionH - h|/2`.
- `…PanPerPixel` give the pan change per canvas pixel of drag (0 on an axis with no room), for
  the preview drag. Camera: `2 / ((1 - visW)·itemW/visW)` and likewise for y.
- Inputs are clamped inside the functions (zoom 1–3 camera / 1–4 screen, pan -1..1); sizes ≤ 0
  return the identity crop `(0, 0, 1, 1)` / the centred fit.

### QML use

- `CameraOverlay`: the effective zoom/pan (Split only, blended by `fullProgress`) feed
  `Framing.cameraCrop(root.width, root.height, …)`. The export `FrameSource` takes it as
  `cropRect`. The preview's native `VideoOutput` cannot crop, so it switches from
  `PreserveAspectCrop` to `Stretch` and is sized and placed from the same crop inside
  `cameraRotated` (`width = parent.width / crop.width`, `x = -crop.x · width`, likewise y),
  clipped by the existing `cameraClip`. At zoom 1 / pan 0 this is exactly the old picture, in
  every layout.
- `Composition`: today's `videoWidth/videoHeight` become `fitWidth/fitHeight`; `videoWidth/Height`
  are the fit times the screen zoom (so `cursorRef` and `RoundedFrame` follow), and
  `frameX/frameY`, `RoundedFrame.x/y` come from `Framing.screenFrame`.

## Export sharpness

- Camera: `split_layout::split_camera_decode_scale` gains a `zoom` argument and multiplies
  before its clamp to 1.0, so a zoomed band is decoded at enough pixels.
- Screen: `export/mod.rs` sizes the screen decode from the largest zoom level; it multiplies by
  `project.screen.zoom` too. Both are clamped to the source size as before, and unchanged at 1.

## Tests

- Rust: project load/save round trips and clamps for both; default projects omit the keys;
  presets keep the current framing; decode scale with zoom; V-CORE goldens unchanged.
- `Framing.js` (from `test_editor.cpp`): centre, edges, zoom, clamping, all four rotations with
  and without mirror, equality with the old cover crop at zoom 1; screen frame centre, pan to
  edges both when larger and smaller than the region; pan-per-pixel zero when there is no room.
- Editor: setting the values through `setProjectValue`, undo restoring defaults (keys gone), the
  Reset buttons as one undo step, Camera panel framing controls visible only in Split.
- Export (`test_exporter_smoke.cpp`): a two-colour camera (left red, right yellow) in a 9:16
  Split export shows red/yellow across the band by default, all red with zoom 2 and pan +1,
  all yellow with pan -1; a two-colour screen at zoom 2 shows the left or right colour across the
  canvas depending on pan, and the background no longer shows.

## Risks

- **Native preview path.** The camera `VideoOutput` moves from `PreserveAspectCrop` to explicit
  geometry for every layout (bubble too), so preview and export use the same crop. It must look
  identical at zoom 1; Phase 2 ends with a lead check of bubble, Split and the morph.
- **Big screen zoom and motion blur.** A zoomed frame is a larger layer when motion blur is on;
  the blur layer covers `stage` (the region), so cost is unchanged. Watch the preview frame rate.
- **Cursor size.** The cursor scales with the screen zoom by design (it stays the size it had on
  screen, relative to the picture). If PF prefers a fixed cursor, it is a one-line change.

## Product questions for PF (not blocking)

1. Wheel zoom needs Ctrl (plain wheel never reframes). OK?
2. The pan sliders move the picture (right = picture right, up = picture up). OK?
