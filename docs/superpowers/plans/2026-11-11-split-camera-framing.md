# Plan: framing the camera (Split) and the screen

Spec: `docs/superpowers/specs/2026-11-11-split-camera-framing-design.md`. Read it first,
especially "Where the math lives" (a JS library, not Rust, and why) and the pan directions.
Repo: `~/src/omareel`, branch `pf/split-and-timeline` (starts after `8c33083`).

Rules for the implementer:
- Do the tasks in order. One commit per task, message `<Area>: <what>` and the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Write the test first, see it fail, then implement, then run the task's verify command.
- If a step is wrong (a name does not exist, a test cannot pass as written), stop and report.
  Do not re-plan, do not touch files the task does not name.
- Never run `tools/oracle/generate-golden.sh` and never bless goldens. **No golden may change in
  this plan.** If one fails, stop and report.
- Rust style: follow the file you are in. QML: follow the file you are in; every new `Text` is
  plain text.

Verify commands:
- `V-CORE`: `cargo test -p omareel_core --locked 2>&1 | grep -E 'test result|FAILED|panicked|error'`
  (all `ok`, no FAILED).
- `V-QT`: `cargo check -p omareel_qt --locked`.
- `V-BUILD`: `bin/build && QT_QPA_PLATFORM=offscreen bin/test`. Allowed failures, and only
  these (known on clean master, see
  `/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/baseline-known-failures.txt`):
  `CameraCaptureTest::cameraFramesKeepTheirTimes`, `everyPackedFormatEncodes(NV12)`,
  `everyPackedFormatEncodes(NV21)`, `killedCameraEncoderKeepsCompletedFragments`.
  Every other suite must pass. To run one new test directly:
  `QT_QPA_PLATFORM=offscreen ./build/test_editor <testName>` (or `./build/test_exporter_smoke`).

Pan directions everywhere: **x +1 moves the picture right, y +1 moves the picture up.**

---

## Phase 1 — Camera framing in the project (Rust)

### 1.1 Fields on `Camera`
File `crates/omareel_core/src/project/styles.rs`, `pub struct Camera` and its `Default`.
- After `split_ratio` add `pub split_zoom: f64,` (doc: "How far the camera picture is scaled up
  in its Split band, 1 to 3; 1 fills the band.") and `pub split_pan: PointF,` (doc: "Where the
  camera picture sits in its Split band, each axis -1 to 1; x +1 moves it right, y +1 up.").
  `PointF` is the type `offset` already uses.
- Defaults: `split_zoom: 1.0`, `split_pan` x 0, y 0 (build it the way `offset`'s default is built).
- Fix every other `Camera { .. }` literal (`grep -rn 'Camera {' crates/`).
- Verify: `cargo build -p omareel_core --locked`.

### 1.2 Load and save
File `crates/omareel_core/src/project/json.rs`.
- Test first in `crates/omareel_core/src/project/tests.rs`, `#[test] fn camera_split_framing_loads_and_saves()`:
  no keys → zoom 1, pan (0,0), and `to_json()`'s camera has neither `splitZoom` nor `splitPan`;
  `splitZoom` 2 kept, 0.5 → 1, 9 → 3; `splitPan` {x: 0.4, y: -0.2} kept, {x: 3, y: -3} → (1, -1),
  only `x` given → y 0; a project with zoom 1.5 and pan (0.4, 0) writes `splitZoom: 1.5` and
  `splitPan: {x: 0.4, y: 0}` and loads back equal; pan (0,0) with zoom 2 writes no `splitPan`.
- Load, right after the `split_ratio` line in `from_json`:
  `split_zoom = clamp(camera.value("splitZoom").to_double(1.0), 1.0, 3.0)`; read
  `camera.value("splitPan").to_object()` and clamp its `x`/`y` (`to_double(0.0)`) to -1..1.
  Use the helpers the neighbouring lines use (`cpp::clamp`).
- Save, after the `splitRatio` insert in `to_json`: `splitZoom` when `!= 1.0`; `splitPan` (an
  object with `x` and `y`) when either axis `!= 0.0`. Build the pan object the way `offset` is.
- Verify: `V-CORE` (goldens must still pass: keys are absent at default).

### 1.3 Presets keep the framing
File `crates/omareel_core/src/editor/presets.rs`, `load_preset`, next to the existing
"A preset provides the look, not which layout" block.
- Test first in `crates/omareel_core/src/editor/tests.rs` (next to the 2.4 preset test from the
  previous plan): set `camera.splitZoom` 2 and `camera.splitPan.x` 0.5, save a preset, set zoom
  back to 1 and pan x to 0, load the preset → zoom 1 and pan x 0 (the current framing stays);
  and the other way round (preset saved at default, current zoom 2 → still 2 after loading).
- Implement: capture `self.project.camera.split_zoom` and `split_pan` before the merge; after it,
  when the preset contains `camera`, insert `splitZoom` and `splitPan` (`{x, y}`) with the
  captured values into the merged camera object (from_json clamps; to_json drops defaults).
- Verify: `V-CORE`.

### 1.4 Export decodes a zoomed camera sharp
Files `crates/omareel_core/src/split_layout.rs` and `crates/omareel_core/src/export/mod.rs`.
- Test first in `split_layout.rs` tests: `split_camera_decode_scale(&g, 1920.0, 1080.0, 2.0)` is
  twice the zoom-1 value when that is ≤ 0.5, and clamps at 1.0 (use the existing 1280x720 / 0.6
  case: 720/1080 at zoom 1 → 1.0 at zoom 2).
- Add a last parameter `zoom: f64` to `split_camera_decode_scale`; multiply the `max(...)` by
  `cpp::max(1.0, zoom)` before the existing clamp. Update the existing tests to pass `1.0`.
- In `export/mod.rs` (`camera_decode_scale`, the split term) pass `project.camera.split_zoom`.
- Verify: `V-CORE`.

---

## Phase 2 — Camera framing on screen (QML) — needs `V-BUILD`

### 2.1 `Framing.js`, camera part
- New file `src/ui/qml/Framing.js`, first line `.pragma library`. Functions exactly as the spec's
  "Framing.js" section: `cameraCrop(itemW, itemH, srcW, srcH, rotation, flip, zoom, panX, panY)`
  returning `{x, y, width, height}`, and `cameraPanPerPixel(itemW, itemH, srcW, srcH, rotation, zoom)`
  returning `{x, y}`. Clamp inputs inside (zoom 1–3, pan -1..1, rotation one of 0/90/180/270,
  anything else 0). Comments as full sentences.
- Register it: in `CMakeLists.txt` add `src/ui/qml/Framing.js` to the `omareel_render` module's
  `QML_FILES` (after `KeystrokeOverlay.qml`), to the `set_source_files_properties(... QT_RESOURCE_ALIAS "")`
  list, and give it `QT_RESOURCE_ALIAS "Framing.js"` like `CameraOverlay.qml`. It then loads as
  `qrc:/qt/qml/Omareel/Framing.js`.
- Test first in `tests/test_editor.cpp`, new slot `framingCameraCropMath()`: build a
  `QQmlEngine` + `QQmlComponent` from
  `import QtQuick; import "qrc:/qt/qml/Omareel/Framing.js" as F; QtObject { function crop(a,b,c,d,e,f,g,h,i) { return F.cameraCrop(a,b,c,d,e,f,g,h,i) } function ppp(a,b,c,d,e,f) { return F.cameraPanPerPixel(a,b,c,d,e,f) } }`
  and call through `QMetaObject::invokeMethod` (QVariant args/return; read the map's keys).
  Cases (compare with `qFuzzyCompare`-style tolerance 1e-9):
  - Item 1080x768, source 1920x1080, rotation 0, no flip, zoom 1, pan 0 →
    `(0.1048…, 0, 0.7901…, 1)`: compute the expected values in the test from the formula
    (visible = (1080/768)/(1920/1080)), do not paste decimals.
  - The same with every rotation 0/90/180/270 × flip true/false at zoom 1, pan 0 equals the old
    `coverCrop`: for 90/270 the old crop is computed on the swapped item (768x1080) against the
    unrotated source aspect, as `CameraOverlay.coverCrop(width, height)` does on `cameraRotated`.
  - Zoom 2, pan (1, 0), rotation 0: x = 0, width = half the zoom-1 width; pan (-1, 0): x + width = 1.
  - Pan (0, 1) at zoom 2 (vertical room exists): y + height = 1 (picture up → window low);
    (0, -1): y = 0.
  - Rotation 90, zoom 2, pan (1, 0) (picture right on canvas): check against the mapping in the
    spec (the window's display x 0 becomes source `y = 1 - dw`… compute from the spec formulas).
  - Flip true, rotation 0, zoom 2, pan (1, 0): source x + width = 1 (mirrored).
  - Clamping: zoom 9 behaves as 3, pan 5 as 1, rotation 45 as 0; item 0x0 → (0, 0, 1, 1).
  - `ppp`: at zoom 1 on 1080x768 with a 1920x1080 source, x > 0 and y == 0; at zoom 2 both > 0.
- Verify: `V-BUILD`.

### 2.2 `CameraOverlay` uses the crop
File `src/ui/qml/CameraOverlay.qml`.
- `import "Framing.js" as Framing`.
- New properties: `property real splitZoom: 1`, `property real splitPanX: 0`,
  `property real splitPanY: 0` (set by Composition in 2.3), and
  `readonly property real framingZoom: splitMode ? 1 + (Math.max(1, splitZoom) - 1) * (1 - fullProgress) : 1`,
  `readonly property real framingPanX: splitMode ? splitPanX * (1 - fullProgress) : 0`, same for Y.
- `readonly property rect cameraCrop: { const c = Framing.cameraCrop(width, height, sourceWidth, sourceHeight, settings.rotation, settings.flipHorizontal, framingZoom, framingPanX, framingPanY); return Qt.rect(c.x, c.y, c.width, c.height) }`.
- `FrameSource { cropRect: root.cameraCrop }` (replaces `root.coverCrop(width, height)`). Keep
  the `coverCrop` function (tests and nothing else may use it; grep first, and leave it if used).
- Native `VideoOutput` (`nativeCameraVideo`): replace `anchors.fill: parent` and
  `fillMode: VideoOutput.PreserveAspectCrop` with `fillMode: VideoOutput.Stretch`,
  `width: parent.width / Math.max(0.0001, root.cameraCrop.width)`,
  `height: parent.height / Math.max(0.0001, root.cameraCrop.height)`,
  `x: -root.cameraCrop.x * width`, `y: -root.cameraCrop.y * height`.
- Test first (in `tests/test_editor.cpp`, extend or add next to the existing CameraOverlay test
  around line 1160): an overlay with `splitMode: true`, `bandRect` 1080x768, source 1920x1080,
  `splitZoom: 2`, `splitPanX: 1` → the `cameraFrameSource`'s `cropRect` x is 0; with
  `fullProgress: 1` the crop equals the zoom-1 crop of the full-frame size (framing blended out);
  with `splitMode: false` and `splitZoom: 2` the crop equals the zoom-1 crop (no effect outside Split).
- Verify: `V-BUILD`.

### 2.3 `Composition` passes the values
File `src/ui/qml/Composition.qml`, the `CameraOverlay { ... }` block.
- Add `splitZoom: comp.project.camera.splitZoom === undefined ? 1 : comp.project.camera.splitZoom`,
  `splitPanX: comp.project.camera.splitPan ? comp.project.camera.splitPan.x : 0`, same for Y.
- Verify: `V-BUILD`.

### 2.4 Lead check (not the implementer)
Bubble, Split and a camera clip's morph look exactly as before at default framing (preview and a
short export); set `camera.splitZoom`/`splitPan` by hand in a project.json and see the band move.

---

## Phase 3 — Camera panel framing controls

### 3.1 Framing group
File `src/ui/qml/CameraPanel.qml`, after the Split hint `Label` (the one starting "Tall canvas").
- A `ColumnLayout { visible: editor.activeCameraLayout === "split"; Layout.fillWidth: true; spacing: theme.space.panelGap }`
  containing `PanelHeading { text: "Framing"; Layout.topMargin: 2 }` and three `PanelSlider`s like
  the "Size" slider: objectNames `cameraFramingZoom`, `cameraFramingHorizontal`,
  `cameraFramingVertical`; labels "Zoom", "Horizontal", "Vertical"; paths `camera.splitZoom`,
  `camera.splitPan.x`, `camera.splitPan.y`; ranges 1–3 (step .01, decimals 2), -1–1 (step .01,
  decimals 2) ×2; values read with defaults (`root.camera.splitZoom === undefined ? 1 : …`,
  `root.camera.splitPan ? root.camera.splitPan.x : 0`).
- A button `EditorButton { objectName: "cameraFramingReset"; text: "Reset framing" }` (check
  `EditorButton.qml`'s API first) whose click does
  `editor.beginCoalescedEdit("camera.framing")`, `setProjectValue("camera.splitZoom", 1, true)`,
  `setProjectValue("camera.splitPan.x", 0, true)`, `setProjectValue("camera.splitPan.y", 0, true)`,
  `editor.endCoalescedEdit()`.
- Test first in `tests/test_editor.cpp`, next to `cameraPanelLayoutFollowsTheAspect`, new slot
  `cameraPanelFramingControls()` built the same way: aspect 9:16 → `cameraFramingZoom` found and
  visible; `editor.setProjectValue("camera.splitZoom", 2.0)` → project camera `splitZoom` is 2;
  `editor.undo()` → the key is gone; set zoom 2 and pan x .5, invoke the Reset button's click
  (`QMetaObject::invokeMethod(button, "clicked")`) → zoom key and pan key gone, and one `undo()`
  brings both back; switching the layout to bubble hides `cameraFramingZoom`.
- Verify: `V-BUILD`.

---

## Phase 4 — Camera framing export check

### 4.1 Two-colour camera export
File `tests/test_exporter_smoke.cpp`.
- Add a helper `makeTwoColourVideo(left, right, path, seconds = 2.0, half = "320x360")` next to
  `makeColourVideo`, using lavfi
  `color=c=<left>:s=<half>:r=30[l];color=c=<right>:s=<half>:r=30[r];[l][r]hstack` and the same
  encoder arguments.
- New slot `splitCameraFramingExports()` modelled on `cameraLayoutsRenderFullFrame`: blue screen,
  camera 640x360 left red / right yellow (half `320x360`), capture.json as there, project
  defaults with `aspect` "9:16", `camera.enabled` true, `camera.layout` "split",
  `camera.shadow.enabled` false, cursor hidden.
  Output 640 wide (the helper's default) → about 640x1138; the band is the bottom 40%.
  Probe the real height with ffprobe (add a small helper like `probeDuration` if none exists) and
  sample at `y = height * 0.8`, `x = 160` and `x = 480`, at 1.0 s:
  default → red at 160, yellow at 480; `splitZoom` 2 + `splitPan` {x: 1, y: 0} → red at both;
  `splitPan` {x: -1, y: 0} → yellow at both. Reuse `isRed`/`isYellow`.
- Verify: `V-BUILD` (and run the slot directly once).

---

## Phase 5 — Screen framing in the project (Rust)

### 5.1 `ScreenFraming`
File `crates/omareel_core/src/project/styles.rs`.
- New `#[derive(Clone, Debug, PartialEq)] pub struct ScreenFraming { pub zoom: f64, pub pan: PointF }`
  with docs (zoom 1–4, 1 = fitted; pan each axis -1..1, x +1 right, y +1 up) and a `Default`
  (1, (0,0)). Add `pub screen: ScreenFraming,` to `Project` after `frame`, default included.
- Fix every `Project { .. }` literal if any.
- Verify: `cargo build -p omareel_core --locked`.

### 5.2 Load and save
File `crates/omareel_core/src/project/json.rs`.
- Test first in `project/tests.rs`, `#[test] fn screen_framing_loads_and_saves()`: absent →
  default and `to_json()` has no `screen` key; zoom 2 kept, 0.5 → 1, 9 → 4; pan clamps like the
  camera's; zoom 1.5 pan (-0.3, 0) round-trips and writes `screen: {zoom: 1.5, pan: {x: -0.3, y: 0}}`;
  zoom 1 with pan (0.2, 0) writes `screen` too (both keys).
- Load next to where `frame` is read; save: insert `screen` (`zoom` and `pan`) only when zoom ≠ 1
  or either pan axis ≠ 0. Key order does not matter (sorted writer).
- Confirm `"screen"` is not in `PRESET_KEYS` (`editor/presets.rs`); do not add it.
- Verify: `V-CORE` (goldens unchanged).

### 5.3 Export decodes a zoomed screen sharp
File `crates/omareel_core/src/export/mod.rs`, where `maximum_zoom` is computed (~line 341).
- Multiply: `let maximum_zoom = maximum_zoom * cpp::max(1.0, project.screen.zoom);` before
  `needed_width`. Add a unit test only if this module already has a test that builds a decode
  plan; otherwise say so in the commit (Phase 8 covers it end to end).
- Verify: `V-CORE`.

---

## Phase 6 — Screen framing on screen (QML) — needs `V-BUILD`

### 6.1 `Framing.js`, screen part
- Add `screenFrame(regionW, regionH, fitW, fitH, zoom, panX, panY)` → `{x, y, width, height}` and
  `screenPanPerPixel(regionW, regionH, fitW, fitH, zoom)` → `{x, y}` as in the spec (zoom 1–4,
  pan -1..1; `|regionW - w|` slack; 0 per-pixel when slack < 1e-6).
- Test first in `tests/test_editor.cpp`, slot `framingScreenMath()` (same QtObject trick):
  region 1000x600, fit 800x450: zoom 1 pan 0 → (100, 75, 800, 450); pan (1, 0) → x 200
  (touches the right edge: 200 + 800 = 1000); pan (0, 1) → y 0 (up); zoom 2 → 1600x900 at
  (-300, -150); zoom 2 pan (1, 0) → x 0 (left edge of the picture at the region's left);
  zoom 2 pan (-1, 0) → x + width = 1000; clamping (zoom 9 = 4, pan 3 = 1); per-pixel 0 on an axis
  with no slack (region 800x450, fit 800x450, zoom 1).
- Verify: `V-BUILD`.

### 6.2 `Composition` applies it
File `src/ui/qml/Composition.qml`.
- `import "Framing.js" as Framing`.
- Rename today's `videoWidth` / `videoHeight` expressions to `fitWidth` / `fitHeight` (same
  expressions). Then:
  `readonly property real screenZoom: comp.project.screen ? comp.project.screen.zoom : 1`,
  `readonly property real screenPanX: comp.project.screen && comp.project.screen.pan ? comp.project.screen.pan.x : 0`,
  same for Y;
  `readonly property var screenRect: Framing.screenFrame(regionWidth, regionHeight, fitWidth, fitHeight, screenZoom, screenPanX, screenPanY)`;
  `property real videoWidth: screenRect.width`, `property real videoHeight: screenRect.height`;
  `frameX: regionX + screenRect.x`, `frameY: regionY + screenRect.y`.
- `RoundedFrame { x: composition.screenRect.x; y: composition.screenRect.y; ... }` (replaces the
  centring). `CursorOverlay` already binds to `frame`'s geometry; the stage `Scale` origin already
  uses `frame.x/width`; leave both.
- `screenClip.clip`: `composition.splitAmount > 0 || composition.screenZoom > 1` (the canvas
  clip already covers the full-canvas case; this keeps a zoomed frame out of the camera band).
- Test first in `tests/test_editor.cpp`: load `Composition.qml` the way an existing editor test
  does (or build an `Editor` with the synthetic bundle and read the preview's `composition`):
  default project → `frameX/frameWidth` unchanged from before (compare with the same project's
  values computed with zoom 1); `screen.zoom` 2 → `frameWidth` doubles and `frameX` is centred;
  pan x 1 → `frameX` moves right by half the slack. If no test builds `Composition` with a
  `comp`, use the `Editor` + `PreviewPane` window pattern of `cameraPanelLayoutFollowsTheAspect`
  and find the `Composition` by type; say which in the commit.
- Verify: `V-BUILD`. All existing editor tests (zoom picker, cursor) must pass unchanged.

### 6.3 Lead check (not the implementer)
Preview and export of a recording with `screen.zoom` 1.6 and pan x -0.3: the cursor stays on the
right UI element, an auto zoom zooms the right place, the zoom target picker picks the right
point, and Split keeps the zoomed screen inside its region.

---

## Phase 7 — Shape panel framing controls

### 7.1 Screen framing group
File `src/ui/qml/ShapePanel.qml`.
- At the top of the root `ColumnLayout`, before the "ignored while the background type is None"
  `Label` (the framing works without a background), add `PanelHeading { text: "Screen framing" }`,
  three `PanelSlider`s (objectNames `screenFramingZoom`, `screenFramingHorizontal`,
  `screenFramingVertical`; labels "Zoom", "Horizontal", "Vertical"; paths `screen.zoom`,
  `screen.pan.x`, `screen.pan.y`; ranges 1–4 step .01 decimals 2, -1–1 step .01 decimals 2;
  values with defaults as in 3.1, from `editor.project.screen`), an `EditorButton`
  `screenFramingReset` "Reset framing" doing the same coalesced reset on the three paths, and an
  `OmSeparator { Layout.fillWidth: true }` after it.
- In `src/ui/qml/SidePanel.qml` change the Shape section's `meta` to
  `"Framing, frame, shadow, and border"`.
- Test first in `tests/test_editor.cpp`, slot `shapePanelScreenFraming()` (window pattern):
  `screenFramingZoom` found; `setProjectValue("screen.zoom", 2.0)` → project `screen.zoom` 2;
  undo → `screen` key gone; reset after zoom 2 and pan x .5 → `screen` gone, one undo restores;
  with background type "none" the slider is still `enabled`.
- Verify: `V-BUILD`.

---

## Phase 8 — Screen framing export check

### 8.1 Two-colour screen export
File `tests/test_exporter_smoke.cpp`, new slot `screenFramingExports()`:
- Screen 640x360 left red / right yellow (`makeTwoColourVideo`), camera off, green background,
  cursor hidden, default aspect (16:9), output 640x360.
- Default → green at (4, 180) (padding shows background), red at (200, 180), yellow at (440, 180).
- `screen` {zoom: 2, pan: {x: 1, y: 0}} → red at (100, 180) and (300, 180), not green at (4, 180).
- `screen` {zoom: 2, pan: {x: -1, y: 0}} → yellow at (340, 180) and (600, 180).
- Verify: `V-BUILD` (and run the slot directly once).

---

## Phase 9 — Drag and wheel in the preview

### 9.1 Camera band and screen drag
File `src/ui/qml/PreviewPane.qml`, inside `Item { id: scaled }`, after the zoom target
`MouseArea` and before `manualTargetMarker`.
- `import "Framing.js" as Framing`.
- Screen drag: `MouseArea { objectName: "screenFramingDrag"; x: composition.frameX; y: composition.frameY; width: composition.frameWidth; height: composition.frameHeight; enabled: !editor.pickingZoomTarget && !root.cropMode && !composition.screenCovered; acceptedButtons: Qt.LeftButton; cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor }`
  (clip it to the region: intersect with `composition.regionX/Y/Width/Height`). On press:
  `root.forceActiveFocus()`, remember the point and the current pan, `editor.beginCoalescedEdit("screen.pan")`.
  On move: `const k = Framing.screenPanPerPixel(composition.regionWidth, composition.regionHeight, composition.fitWidth, composition.fitHeight, composition.screenZoom)`;
  new x = clamp(startX + dx·k.x, -1, 1), new y = clamp(startY - dy·k.y, -1, 1) (drag up = picture
  up); `setProjectValue("screen.pan.x", x, true)` and `.y`. On release/cancel: `endCoalescedEdit()`.
  Positions are in `scaled`'s coordinates (output pixels), so no extra scaling.
- Camera drag: a second `MouseArea { objectName: "cameraFramingDrag" }` over the band
  (`comp.layout.cameraX/Y/Width/Height`), `z` above the screen one, enabled only when
  `composition.splitActive && composition.cameraShown && composition.cameraFull < 0.01` and not
  picking/cropping; same pattern with `Framing.cameraPanPerPixel(bandW, bandH, editor.cameraWidth?, …)`.
  Find the camera source size and rotation the preview has (the overlay's `sourceWidth/Height`,
  `settings.rotation`; expose them as `readonly property` aliases on `Composition` if needed) and
  write `camera.splitPan.x/.y` with the camera key `camera.splitPan`.
- Ctrl+wheel: `onWheel` on both areas: only with `wheel.modifiers & Qt.ControlModifier` (else
  `wheel.accepted = false`); zoom = clamp(current · 1.1^(angleDelta.y/120), 1, 3 or 4), written
  inside a coalesced edit that ends 400 ms after the last wheel event (a `Timer`).
- Test first in `tests/test_editor.cpp`: both areas exist; `screenFramingDrag` is disabled while
  `editor.pickingZoomTarget` is true; `cameraFramingDrag` is disabled outside Split. (Mouse drags
  themselves are checked by the lead.)
- Verify: `V-BUILD`.

### 9.2 Lead check (not the implementer)
Drag and Ctrl+wheel on the screen and on the band; the zoom target picker and crop mode still
work and take precedence; one undo per drag.

---

## Phase 10 — Docs and package

10.1 `docs/USAGE.md`: in "Camera layout" add a short paragraph on Framing (zoom, horizontal,
vertical, reset, drag and Ctrl+wheel on the band); add a "Screen framing" paragraph (Shape panel,
drag and Ctrl+wheel on the screen). Verify: read back.
10.2 `pkg/PKGBUILD`: `pkgver=0.5.0.pf3`, `pkgrel=1`; `vercmp 0.5.0.pf3-1 0.5.0.pf2-1` prints `1`.
10.3 `cd pkg && makepkg -f --noconfirm` (no `-s`, no `-i`). Output
`pkg/omareel-0.5.0.pf3-1-aarch64.pkg.tar.xz` (this machine's makepkg uses xz). Then
`QT_QPA_PLATFORM=offscreen BUILD_DIR=build-pkg ./bin/test` (same allowed failures).
10.4 Lead: PF installs with `sudo pacman -U ~/src/omareel/pkg/omareel-0.5.0.pf3-1-aarch64.pkg.tar.xz`.
