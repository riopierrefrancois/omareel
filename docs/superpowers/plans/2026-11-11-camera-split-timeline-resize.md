# Plan: Camera Split layout and resizable timeline

Spec: `docs/superpowers/specs/2026-11-11-camera-split-timeline-resize-design.md`. Read it first.
Repo: `~/src/omareel`, branch `pf/split-and-timeline`. Old reference code: branch `test-all`
(`git show test-all:<path>`); it is the old C++ editor, so use it only for behaviour, never copy
files from it.

Rules for the implementer:
- Do the tasks in order. One commit per task, message `<Area>: <what>` and the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Write the test first, see it fail, then implement, then run the task's verify command.
- If a step is wrong (a name does not exist, a test cannot pass as written), stop and report.
  Do not re-plan, do not touch files the task does not name.
- Never run `tools/oracle/generate-golden.sh`. Only Task 1.4 blesses goldens.
- Rust style: follow the file you are in (comments as full sentences, `cpp::` helpers where the
  file uses them).

Verify commands used below:
- `V-CORE`: `cargo test -p omareel_core --locked 2>&1 | grep -E 'test result|FAILED|panicked|error'`
  (all `ok`, no FAILED).
- `V-QT`: `cargo check -p omareel_qt --locked` (takes about 1 minute).
- `V-BUILD`: `bin/build && QT_QPA_PLATFORM=offscreen bin/test` (needs cmake, ninja, corrosion,
  qt6-shadertools; Phase 0).

---

## Phase 0 — Prerequisites (lead does this, not the implementer)

0.1 PF installs the build tools: `sudo pacman -S --needed cmake ninja corrosion qt6-shadertools`.
0.2 Baseline on clean master: `bin/build && QT_QPA_PLATFORM=offscreen bin/test`. Record the result
    and any test that already fails, so later phases are not blamed for it.
0.3 `V-CORE` is green on master (checked 2026-11-11: 215 unit + 45 golden + 2 tests, all ok).

---

## Phase 1 — Project model: `camera.layout` and `camera.splitRatio`

### 1.1 Fields on `Camera`
File `crates/omareel_core/src/project/styles.rs`, `pub struct Camera` and `impl Default for Camera`.
- Add after `enabled`:
  - `pub layout: String,` with doc comment: "auto" follows the aspect, "bubble" is the corner
    overlay, "split" shares the canvas with the screen. New projects start on auto; a saved
    project without the key stays bubble.
  - `pub split_ratio: f64,` doc: the screen's share of the canvas in Split (0.5 to 0.8).
- Default: `layout: "auto".into()`, `split_ratio: 0.6`.
- Fix every other place that builds a `Camera { .. }` literal so it compiles
  (`grep -rn 'Camera {' crates/`).
- Verify: `cargo build -p omareel_core --locked`.

### 1.2 Load (`from_json`)
File `crates/omareel_core/src/project/json.rs`, in `from_json` right after
`p.camera.enabled = camera.value("enabled").to_bool(false);` (around line 329).
- Test first, in `crates/omareel_core/src/project/tests.rs`: a new `#[test] fn camera_layout_and_split_ratio_load()`
  covering: no `layout` key → `"bubble"`; `"auto"`, `"bubble"`, `"split"` kept; `"sideways"` →
  `"bubble"`; no `camera` object at all → `"bubble"`; `splitRatio` missing → 0.6; 0.7 kept;
  0.2 → 0.5; 0.95 → 0.8. Also `Project::default().camera.layout == "auto"`. Build inputs the way
  the neighbouring tests in that file do.
- Implement:
  ```rust
  let layout = camera.value("layout").to_string_or("bubble");
  p.camera.layout = if ["auto", "bubble", "split"].contains(&layout.as_str()) { layout } else { "bubble".into() };
  p.camera.split_ratio = cpp::clamp(camera.value("splitRatio").to_double(0.6), 0.5, 0.8);
  ```
  (Use the same `to_string_or` / `to_double` helpers the surrounding lines use. If `cpp` is not
  imported in json.rs, use `f64::clamp`.) Note: `from_json` must set `"bubble"` explicitly even
  though `Camera::default()` says `"auto"`.
- Verify: `V-CORE` (goldens must still pass after this task: loading only).

### 1.3 Save (`to_json`)
Same file, `to_json`, the `"camera"` object (around line 518).
- Test first, in `project/tests.rs` `#[test] fn camera_layout_round_trips()`: a project with
  `layout = "split"`, `split_ratio = 0.7` → `to_json()` has `camera.layout == "split"` and
  `camera.splitRatio == 0.7`, and `from_json(to_json())` gives the same values; a project with
  `layout = "bubble"`, `split_ratio = 0.6` → `to_json()` camera has **no** `layout` and **no**
  `splitRatio` key.
- Implement: build the camera object as today, then
  `if cam.layout != "bubble" { camera.insert("layout", cam.layout.as_str()); }` and
  `if cam.split_ratio != 0.6 { camera.insert("splitRatio", cam.split_ratio); }`. Mirror how clip
  `layout` is inserted conditionally at the top of `to_json`. Key order does not matter: the JSON
  writer sorts keys.
- Verify: `cargo test -p omareel_core --locked --lib` passes. The golden run will now FAIL in the
  `project` family only (defaults now carry `"layout":"auto"`). That is expected; go to 1.4.

### 1.4 Re-bless the project goldens (own commit)
- (Plan fix, 2026-11-11.) `OMAREEL_GOLDEN_BLESS=1` only reaches `assert_golden()`; the project
  family compares many files through `difference()`, which never writes. So first, in
  `crates/omareel_core/tests/golden/support.rs`, add right after `difference()`:
  ```rust
  /// `difference()` against the golden at `relative`, or, when blessing, writes `actual` there
  /// and reports nothing.
  pub fn bless_or_difference(relative: &str, actual: &[u8]) -> Option<String> {
      if blessing() {
          std::fs::write(expected_path(relative), actual).expect("the golden file is writable");
          return None;
      }
      difference(relative, &read_expected(relative), actual)
  }
  ```
  Then in `crates/omareel_core/tests/golden/project.rs` only, replace every
  `difference(X, &read_expected(X), Y)` whose first and second arguments name the same path with
  `bless_or_difference(X, Y)` (lines ~297, 312, 385, 396). Do not touch other golden files.
  Without the env var the test must behave exactly as before.
- Run: `OMAREEL_GOLDEN_BLESS=1 cargo test -p omareel_core --locked --test golden`.
  A file list mismatch (`Rust wrote [...], the golden has [...]`) is not blessed: if one appears, STOP.
- Then `git diff --stat tests/golden/expected` and `git diff tests/golden/expected | grep '^[-+]' | grep -v '^[-+][-+]' | grep -v '"layout": *"auto"' | head`.
  Every changed line must only add `"layout":"auto"` (or `"layout": "auto"` in indented files)
  inside `camera`. If any other change shows up (a loaded legacy project gaining a key, a number
  changing, a composition file), STOP and report.
- Add this bullet to `tests/golden/README.md` under "Changed on purpose since the tag":
  `- Camera layout: `camera.layout` ("auto", "bubble", "split") and `camera.splitRatio` (0.5–0.8,
  default 0.6) were added for the Split layout. They are written only when not "bubble" and not
  0.6, so loaded projects are unchanged; new and default projects now carry `"layout": "auto"`
  in `project/defaults/`, `project/tojson/` and the save rows.` (adjust the folder list to what the
  diff actually touched).
- Verify: `V-CORE` all green.
- Commit message: `Goldens: default projects carry camera.layout "auto" (Split layout)`.

---

## Phase 2 — Split geometry and editor rules (Rust core)

### 2.1 New module `split_layout`
Create `crates/omareel_core/src/split_layout.rs`; add `pub mod split_layout;` to
`crates/omareel_core/src/lib.rs` (alphabetical, after `recording_preferences`).
Contents:
```rust
//! The camera Split layout: which layout is drawn, and where the screen and the camera go.

use crate::project::Project;

pub const DEFAULT_SPLIT_RATIO: f64 = 0.6;
pub const MIN_SPLIT_RATIO: f64 = 0.5;
pub const MAX_SPLIT_RATIO: f64 = 0.8;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect { pub x: f64, pub y: f64, pub width: f64, pub height: f64 }

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SplitGeometry { pub side_by_side: bool, pub screen_region: Rect, pub camera_rect: Rect }

pub fn is_portrait_aspect(aspect: &str) -> bool  // "9:16" | "4:5" | "3:4"
pub fn active_camera_layout(project: &Project, camera_available: bool) -> &'static str
pub fn split_geometry(output_width: f64, output_height: f64, ratio: f64) -> SplitGeometry
pub fn split_camera_decode_scale(geometry: &SplitGeometry, camera_display_width: f64, camera_display_height: f64) -> f64
```
Behaviour:
- `active_camera_layout`: `"bubble"` if `!project.camera.enabled || !camera_available`; `"split"`
  if `layout == "split"`; `"split"` if `layout == "auto" && is_portrait_aspect(&project.aspect)`;
  else `"bubble"`.
- `split_geometry`: `ratio` clamped to 0.5–0.8; `w = max(0, output_width)`, `h = max(0, output_height)`;
  `side_by_side = w > h`. Side by side: `rw = (w * ratio).round()`, screen `(0, 0, rw, h)`,
  camera `(rw, 0, max(0, w - rw), h)`. Stacked: `rh = (h * ratio).round()`, screen `(0, 0, w, rh)`,
  camera `(0, rh, w, max(0, h - rh))`. (`f64::round` rounds half away from zero, like C++
  `std::round` in the old code.)
- `split_camera_decode_scale`: `1.0` if either display size `<= 0`; else
  `clamp(max(cam.width / display_w, cam.height / display_h), 0.01, 1.0)` — a cover fill of the band.
  "Display" sizes are the camera's size after rotation (the caller swaps for 90/270).
Tests first (`#[cfg(test)] mod tests` in the same file), values from the old
`git show test-all:tests/test_composition_layout.cpp`:
- 1080x1920, ratio 0.6 → stacked, screen `(0,0,1080,1152)`, camera `(0,1152,1080,768)`.
- 1080x1080 (square) → stacked.
- 1920x1080, ratio 0.6 → side by side, screen `(0,0,1152,1080)`, camera `(1152,0,768,1080)`.
- ratio 0.2 behaves as 0.5; ratio 0.95 as 0.8.
- decode scale: out 1280x720 ratio 0.6, camera display 1920x1080 → `720/1080`;
  out 1080x1920 ratio 0.5, display 1920x1080 → `960/1080`; out 1080x1920 ratio 0.5, display
  1080x1920 (a 1920x1080 camera turned 90°) → `1.0`; display 0x0 → `1.0`.
- `active_camera_layout`: camera disabled → bubble; no camera → bubble; `split` on 16:9 → split;
  `auto` on 9:16 / 4:5 / 3:4 → split; `auto` on 16:9, 1:1, 4:3 and `"auto"` aspect → bubble;
  `bubble` on 9:16 → bubble.
- Verify: `V-CORE`.

### 2.2 `Document::active_camera_layout`
File `crates/omareel_core/src/editor/composition.rs` (inside `impl Document`).
- Add `pub fn active_camera_layout(&self) -> &'static str { split_layout::active_camera_layout(&self.project, self.has_camera()) }`.
- Test first in `crates/omareel_core/src/editor/tests.rs`, next to
  `clip_layouts_are_undoable_and_survive_splits`, using `world.camera_bundle(...)`:
  new project → `project().camera.layout == "auto"`; set `camera.enabled` true; aspect 16:9 →
  `"bubble"`; set `aspect` `"9:16"` → `"split"`.
- Verify: `V-CORE`.

### 2.3 Reset to auto on aspect / camera change
File `crates/omareel_core/src/editor/document.rs`, `pub fn set_project_value` (line ~715).
After `let parsed = Project::from_json(&next);` and before the `if parsed.to_json() == old` check:
```rust
// A real change of the aspect or of the camera switch picks the layout automatically again.
// An unchanged edit, or an aspect from_json rejected, keeps an explicit Bubble or Split.
let parsed = if parsed.aspect != self.project.aspect || parsed.camera.enabled != self.project.camera.enabled {
    let mut next = next;
    let mut camera = next.value("camera").to_object();
    camera.insert("layout", "auto");
    next.insert("camera", camera);
    Project::from_json(&next)
} else {
    parsed
};
```
(Adjust `next` mutability to compile; keep one snapshot/undo step.)
- Test first (editor tests, port of old `splitLayoutFollowsAspectUntilAnExplicitChoice`):
  camera bundle, camera on, aspect 9:16 → split; set `camera.layout` `"bubble"` → bubble;
  set aspect to `"9:16"` again (unchanged) → still bubble and layout `"bubble"`; set aspect
  `"bogus"` (rejected) → still `"bubble"`; set aspect `"4:5"` → layout `"auto"`, active split;
  set `camera.layout` `"bubble"`, then toggle `camera.enabled` false then true → layout `"auto"`;
  one undo after the aspect change restores both the aspect and `"bubble"`.
- Verify: `V-CORE`.

### 2.4 Presets keep the current layout
File `crates/omareel_core/src/editor/presets.rs`, `pub fn load_preset`.
- Before the `for key in PRESET_KEYS` loop: `let current_layout = self.project.camera.layout.clone();`
  After the loop, if `preset.contains("camera")`: take `project.value("camera").to_object()`,
  `insert("layout", current_layout.as_str())`, put it back with `project.insert("camera", ...)`.
- Test first (editor tests): camera on, aspect 9:16 (split), `save_preset("split-test")`,
  set `camera.layout` `"bubble"`, `load_preset("split-test")` → layout still `"bubble"`.
  And the reverse: save while `"bubble"`, set `"split"`, load → still `"split"`.
- Verify: `V-CORE`.

---

## Phase 3 — Composition state, export decode, Qt bridge

### 3.1 Editor preview layout carries the split
File `crates/omareel_core/src/editor/composition.rs`.
- `PreviewLayout`: add `pub split_active: bool,` and `pub split: SplitGeometry,` (doc: Split is
  drawn, and where the screen and camera go in output pixels; when not active the screen region is
  the whole canvas and the camera rect is zero).
- `preview_layout()`: `split_active = self.active_camera_layout() == "split"`; `split` =
  `split_geometry(self.output_width() as f64, self.output_height() as f64, self.project.camera.split_ratio)`
  when active, else `SplitGeometry { side_by_side: false, screen_region: Rect { x: 0, y: 0, width: w, height: h }, camera_rect: Rect::default() }`.
  Put that "else" value in a helper `split_layout::no_split(w, h) -> SplitGeometry` (add it to
  the module, with a test).
- Fix other `PreviewLayout { .. }` literals (`grep -rn 'PreviewLayout {' crates`).
- Test first (editor tests): camera bundle, camera on, aspect 9:16 → `preview_layout().split_active`
  and `split.camera_rect.height > 0`; aspect 16:9 → not active, `screen_region.width == output_width`.
- Verify: `V-CORE` (composition goldens must not change).

### 3.2 Export layout carries the split
File `crates/omareel_core/src/export/composition.rs`.
- `Layout`: add the same two fields. `CompositionState::initial`: `split_active: false`,
  `split: SplitGeometry::default()`.
- `export_frame`: after `self.layout = Layout { .. }`, set `split_active` from
  `split_layout::active_camera_layout(project, sources.camera_width > 0) == "split"` and `split` from
  `split_geometry(self.output_width as f64, self.output_height as f64, project.camera.split_ratio)`
  or `no_split(...)`. (`state.output_width` is set in `export/mod.rs` line ~381 before frames run;
  check that, and stop if it is not.)
- Test: add a `#[test]` in the same file's tests module if it has one, else in
  `crates/omareel_core/src/export/mod.rs` tests, building a `CompositionState` the way existing
  tests there do. If no existing test builds `Sources`, skip the test and say so in the commit.
- Verify: `V-CORE`.

### 3.3 Export decodes the camera big enough for the band
File `crates/omareel_core/src/export/mod.rs`, the `camera_decode_scale` block (~line 360).
- Inside the `cpp::max(...)` add a third term: when
  `split_layout::active_camera_layout(&project, camera_media.width > 0) == "split"`,
  `split_layout::split_camera_decode_scale(&split_geometry(f64::from(width), f64::from(height), project.camera.split_ratio), camera_display_width, camera_display_height)`,
  else `0.0`. Use nested `cpp::max` like the existing code.
- Verify: `V-CORE`.

### 3.4 The `layout` map gets the new keys (editor and export)
Files `crates/omareel_qt/src/editor.rs` (`fn preview_layout`, ~line 1174) and
`crates/omareel_qt/src/export.rs` (`fn layout_map`, ~line 414).
- Both maps become: `cameraFull`, `bubble`, `splitActive` (bool), `sideBySide` (bool),
  `screenX`, `screenY`, `screenWidth`, `screenHeight`, `cameraX`, `cameraY`, `cameraWidth`,
  `cameraHeight` (f64). Use `QVariant::from(&value)` as the existing entries do; `map` takes a
  fixed-size array, so just list all 12.
- Verify: `V-QT`.

### 3.5 `activeCameraLayout` on the editor object
File `crates/omareel_qt/src/editor.rs`.
- Add `#[qproperty(QString, active_camera_layout, READ = active_camera_layout, NOTIFY = project_changed)]`
  next to `camera_status`; declare `fn active_camera_layout(self: &Editor) -> QString;` next to
  `fn camera_status`; implement next to `fn camera_status(&self)`:
  `self.document.as_ref().map_or_else(|| qstring("bubble"), |d| qstring(d.active_camera_layout()))`.
- Verify: `V-QT`. QML name is `editor.activeCameraLayout` (cxx-qt camel-cases, as with
  `selectedClipId`); check one existing property to confirm.

---

## Phase 4 — Composition QML (needs Phase 0 for `V-BUILD`)

### 4.1 Screen region in `src/ui/qml/Composition.qml`
- Add properties:
  ```qml
  readonly property bool splitActive: !!comp.layout.splitActive
  // How far Split is shown: the bubble's value, so screen clips and camera clips ease out of it.
  readonly property real splitAmount: splitActive && cameraShown && !mediaActive ? comp.layout.bubble : 0
  readonly property real regionX: (comp.layout.screenX || 0) * splitAmount
  readonly property real regionY: (comp.layout.screenY || 0) * splitAmount
  readonly property real regionWidth: width + ((comp.layout.screenWidth || width) - width) * splitAmount
  readonly property real regionHeight: height + ((comp.layout.screenHeight || height) - height) * splitAmount
  // No background stretches the screen to the canvas, except in Split, which keeps its shape.
  readonly property bool stretchScreen: noBackground && splitAmount <= 0
  ```
- Replace `pad`, `availableWidth`, `availableHeight`, `videoWidth`, `videoHeight` so they use
  `regionWidth`/`regionHeight` instead of `width`/`height`, and `stretchScreen` instead of
  `noBackground` in `videoWidth`/`videoHeight` (`stretchScreen ? regionWidth : ...`,
  `stretchScreen ? regionHeight : videoWidth / sourceAspect`). Keep `ref` = `height / 1080`.
- Add `readonly property real frameX: regionX + (regionWidth - videoWidth) / 2` and
  `frameY` likewise; `frameWidth: videoWidth`, `frameHeight: videoHeight`.
- Wrap the `stage` Item in `Item { id: screenClip; x: composition.regionX; y: composition.regionY; width: composition.regionWidth; height: composition.regionHeight; clip: composition.splitAmount > 0; visible: !composition.screenCovered }`;
  inside it `stage` keeps `anchors.fill: parent`; `RoundedFrame` gets `x: (screenClip.width - width) / 2`, `y: (screenClip.height - height) / 2`.
  The zoom `Scale` origin stays `frame.x + cx * frame.width` (now relative to the clip item — correct).
- After `Background`, add a black `Rectangle { anchors.fill: parent; color: "black"; visible: composition.noBackground && composition.splitAmount > 0 }`.
- Wrap `KeystrokeOverlay` in `Item { x/y/width/height = region }` and give it `anchors.fill: parent`
  if it does not fill already (it uses `anchors.fill: parent` internally — check).
- Verify: `V-BUILD` (all tests as in the Phase 0 baseline).

### 4.2 Camera band in `src/ui/qml/CameraOverlay.qml`
- New properties: `property bool splitMode: false`, `property rect bandRect: Qt.rect(0, 0, 0, 0)`.
- In split mode the "bubble" end of the morph is the band: change `bubbleX/bubbleY/bubbleWidth/bubbleHeight`
  to `splitMode ? bandRect.x/y/width/height : <today's expression>`; `bubbleRadius` → 0 in split
  mode; `sourceBorderWidth` → 0 in split mode; shadow opacity and the software shadow
  rectangle → 0 in split mode; `scale` → `splitMode ? 1 : .85 + .15 * presence`.
  `fullProgress` morph and `coverCrop(width, height)` stay as they are (they already cover-crop).
- In `Composition.qml` pass `splitMode: composition.splitActive` and
  `bandRect: Qt.rect(comp.layout.cameraX || 0, comp.layout.cameraY || 0, comp.layout.cameraWidth || 0, comp.layout.cameraHeight || 0)`.
- Verify: `V-BUILD`.

### 4.3 Zoom target picker uses the composition's geometry
File `src/ui/qml/PreviewPane.qml`, inside `Item { id: scaled ... }`.
- Delete the local `noBackground`, `pad`, `sourceAspect`, `videoWidth`, `videoHeight`, `frameX`,
  `frameY` computations and replace with
  `readonly property real frameX: composition.frameX`, `frameY: composition.frameY`,
  `videoWidth: composition.frameWidth`, `videoHeight: composition.frameHeight`. Keep the names so
  `zoomOriginX`, `targetFromScene` and the target marker keep working.
- Verify: `V-BUILD`.

### 4.4 Lead check (not the implementer)
Open a camera recording in the built app (`build/omareel <bundle>.omareel`), 9:16 aspect: split
stacked; 16:9 with Split chosen: side by side; a zoom stays in the screen part; a camera clip
morphs band → full; export a short 9:16 clip and look at it. Screenshot each.

---

## Phase 5 — Camera panel

File `src/ui/qml/CameraPanel.qml`, inside the `ColumnLayout` that has `enabled: editor.hasCamera && root.camera.enabled`.
5.1 At its top, before `PanelHeading { text: "Position" ... }`, add:
```qml
OmSettingRow {
    label: "Layout"
    OmButtonGroup {
        objectName: "cameraLayoutGroup"
        Layout.preferredWidth: 176
        options: [{value: "split", label: "Split"}, {value: "bubble", label: "Bubble"}]
        value: editor.activeCameraLayout
        onChanged: value => editor.setProjectValue("camera.layout", value)
    }
}
OmSettingRow {
    visible: editor.activeCameraLayout === "split"
    label: "Screen / camera"
    OmButtonGroup {
        objectName: "cameraSplitRatioGroup"
        Layout.preferredWidth: 212
        options: [{value: 0.5, label: "50/50"}, {value: 0.6, label: "60/40"}, {value: 0.7, label: "70/30"}]
        value: root.camera.splitRatio === undefined ? 0.6 : root.camera.splitRatio
        onChanged: value => editor.setProjectValue("camera.splitRatio", value)
    }
}
Label {
    visible: editor.activeCameraLayout === "split"
    Layout.fillWidth: true
    text: "Tall canvas: camera below the screen. Wide canvas: camera to the right. Changing the aspect or turning the camera off and on picks the layout again."
    color: theme.textMuted
    font.pixelSize: theme.type.small
    wrapMode: Text.WordWrap
}
```
Note `editor.project.camera.splitRatio` is absent from the map when it is 0.6 (not written), hence
the `undefined` check. Same for `layout`; the panel reads `activeCameraLayout`, not the key.
5.2 Wrap everything after those items to the end of that `ColumnLayout` (Position heading, position
pad, Size, Shape, Corner radius, Shrink while zoomed, Shadow, Border sections) in
`ColumnLayout { visible: editor.activeCameraLayout === "bubble"; Layout.fillWidth: true; spacing: theme.space.panelGap ... }`.
Leave the second `ColumnLayout` (Full screen, Rotation, Mirror) as it is.
5.3 `src/ui/qml/SidePanel.qml` line 19: Camera section `meta:"Webcam bubble"` → `meta:"Webcam & layout"`.
5.4 Test in `tests/test_editor.cpp`: the file finds items by `objectName` with a helper (see
around lines 184 and 305, `item->objectName() == name`); use it. Add a test
that loads a camera bundle, sets aspect 9:16, finds `cameraLayoutGroup` and checks its `value` is
`"split"`, then emits `changed("bubble")` and checks `editor.activeCameraLayout == "bubble"`. If
there is no pattern for finding panel items, skip this test and say so.
Verify: `V-BUILD`.

---

## Phase 6 — Resizable timeline (QML only)

### 6.1 `src/ui/qml/Timeline.qml` row geometry
- Add properties next to `trackCount`:
  ```qml
  // True while the editor's resize handle is dragged, so row moves are not animated.
  property bool resizing: false
  readonly property real rulerHeight: 32
  readonly property real rowGap: 8
  readonly property real blockInset: 4
  readonly property real bottomSpace: 12
  readonly property real minimumRowHeight: 48
  // The rows share the height the editor gives the timeline; implicitHeight is the smallest.
  readonly property real rowHeight: Math.max(minimumRowHeight,
      Math.floor((height - rulerHeight - bottomSpace - (trackCount - 1) * rowGap) / trackCount))
  function rowY(index) { return rulerHeight + index * (rowHeight + rowGap) }
  ```
- `implicitHeight: rulerHeight + trackCount * minimumRowHeight + (trackCount - 1) * rowGap + bottomSpace`
  (equals today's 204 / 148).
- `tracksBottom: rulerHeight + trackCount * rowHeight + (trackCount - 1) * rowGap`.
- Replace every hard-coded row position (today's lines ~189, 328-338, 359-361, 408-418, 426-438):
  - label row `y: 32 + index * 56 + (48 - height) / 2` → `y: root.rowY(index) + (root.rowHeight - height) / 2`
  - row backgrounds `y: 32 / 88 / 144`, `height: 48` → `y: root.rowY(0/1/2)`, `height: root.rowHeight`
  - tracks `y: 36 / 92`, `height: 40` → `y: root.rowY(0/1) + root.blockInset`, `height: root.rowHeight - 2 * root.blockInset`
  - range highlight `y: 32`, `height: 48` → `root.rowY(0)`, `root.rowHeight`
  - camera block `y: cameraHover.hovered ? 147 : 148`, `height: 40` →
    `y: root.rowY(2) + root.blockInset - (cameraHover.hovered ? 1 : 0)`, `height: root.rowHeight - 2 * root.blockInset`;
    its `Behavior on y { enabled: !editor.loading }` → `enabled: !editor.loading && !root.resizing`.
  - Grep the file afterwards for ` 32\b`, `48`, `56`, `88`, `144` and fix any other row-dependent
    value; leave the ruler's own internals (height 32 of the ruler item can become `root.rulerHeight`).
- Check `ClipTrack.qml` and `ZoomTrack.qml` draw from their own `height` (no fixed 40). Fix only
  if they hard-code it.

### 6.2 `src/ui/qml/Main.qml` handle and saved height
- `import QtCore` at the top.
- In the `ApplicationWindow`, add:
  ```qml
  Settings {
      id: editorLayout
      category: "editor"
      // 0 means the timeline's own minimum height.
      property real timelineHeight: 0
  }
  // Tallest timeline that still leaves the preview its minimum height.
  readonly property real maximumTimelineHeight: Math.max(timeline.implicitHeight,
      editorUi.height - topBar.height - bottomBar.height - previewPane.Layout.minimumHeight)
  ```
  (`editorUi` is the root Item; inside it a ColumnLayout holds `topBar`, a RowLayout (whose left
  ColumnLayout holds `previewPane` with `Layout.minimumHeight: 338` and `bottomBar`; the right side
  is `sidePanel`), then `timeline`. So the formula above is right.)
- `Timeline { ... }`: `Layout.preferredHeight: Math.max(implicitHeight, Math.min(editorLayout.timelineHeight, window.maximumTimelineHeight))`
  (use the window's real id), `resizing: timelineResize.pressed`.
- Add the handle as a sibling *after* the layout that holds the timeline, inside `editorUi`
  (copy from `git show test-all:src/ui/qml/Main.qml`, the `MouseArea { id: timelineResize ... }`
  block), with `objectName: "timelineResizeHandle"`, `y: timeline.y - height / 2` mapped into
  `editorUi` coordinates if `timeline` is nested (use `timeline.mapToItem(editorUi, 0, 0).y`
  in a binding if needed), `height: 8`, `z: 10`, `cursorShape: Qt.SizeVerCursor`,
  drag sets `editorLayout.timelineHeight` clamped to `[timeline.implicitHeight, window.maximumTimelineHeight]`,
  `onDoubleClicked: editorLayout.timelineHeight = 0`, tooltip and accent line as in the old code
  (use this repo's tooltip component if `ToolTip` attached properties are not used elsewhere in
  Main.qml — check `OmToolTip`).
### 6.3 Test
In `tests/test_editor.cpp`, next to the existing `editorTimeline` lookups: find
`timelineResizeHandle` and `editorTimeline`; record `editorTimeline` height; set
`editorLayout`'s height by simulating a drag (or, if the test file never drives mouse input,
check only that the handle exists and that `editorTimeline.rowHeight == 48` at the default
height). Verify: `V-BUILD`.

---

## Phase 7 — Docs and local package

7.1 `docs/USAGE.md`: in the camera section add a short paragraph on Layout (Split / Bubble,
auto on 9:16, 4:5, 3:4), the Screen / camera ratios, and that the timeline's top edge drags to
resize (double-click resets). `README.md` feature list: one line "Split layout for vertical
video". Verify: read back.
7.2 `pkg/PKGBUILD`: `pkgver=0.5.0.pf1`, `pkgrel=1`. Check `vercmp 0.5.0.pf1-1 0.5.0-1` prints `1`.
Do not change `CMakeLists.txt`'s project version.
7.3 Build the package: `cd pkg && makepkg -f --noconfirm` (no `-s`, no `-i`: dependencies are
installed and installing needs sudo). It runs `bin/build` in `build-pkg/`. Then
`QT_QPA_PLATFORM=offscreen BUILD_DIR=build-pkg ./bin/test` from the repo root.
Output: `pkg/omareel-0.5.0.pf1-1-aarch64.pkg.tar.zst` (git-ignored).
7.4 Lead: PF installs it over the stock package:
`sudo pacman -U ~/src/omareel/pkg/omareel-0.5.0.pf1-1-aarch64.pkg.tar.zst`.
Rollback to stock: `gh release download v0.5.0 -R omacom/omareel -p 'omareel-0.5.0-1-aarch64.pkg.tar.zst'`
then `sudo pacman -U omareel-0.5.0-1-aarch64.pkg.tar.zst`.
