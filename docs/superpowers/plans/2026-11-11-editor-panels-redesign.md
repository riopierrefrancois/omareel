# Plan: editor side panels — Layout, Screen, Webcam, Clip "Show"

Spec: `docs/superpowers/specs/2026-11-11-editor-panels-redesign-design.md`. Read it first; the
tables there are the target.
Repo: `~/src/omareel`, branch `pf/split-and-timeline`. Start after the delete-recording task's
commits (it adds a trash button to `TopBar.qml` and tests to `tests/test_editor.cpp`; build on
them, do not undo them).

Rules for the implementer:
- Do the tasks in order. One commit per task, message `<Area>: <what>` and the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Write the test first where the task says so, see it fail, then implement, then run the verify
  command.
- If a step is wrong (a name does not exist, a test cannot pass as written), stop and report.
  Do not re-plan, do not touch files the task does not name.
- **No project data, rendering or export change.** No Rust change in this plan except where a
  task names it (none do). Never bless goldens; if one fails, stop.
- Keep the QML file names (`ShapePanel.qml`, `CameraPanel.qml`); only user-visible names change.
- Keep every existing objectName unless a task says otherwise; tests and debug tools find
  controls by them.
- Every new `Text`/`Label` is plain text (`textFormat: Text.PlainText` where the file's other
  Labels use it; `Label` from QtQuick.Controls is fine as the files already use it).

Verify commands:
- `V-BUILD`: `bin/build && QT_QPA_PLATFORM=offscreen bin/test`. Allowed failures, and only these
  (see `/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/baseline-known-failures.txt`):
  `CameraCaptureTest::cameraFramesKeepTheirTimes`, `everyPackedFormatEncodes(NV12)`,
  `everyPackedFormatEncodes(NV21)`, `killedCameraEncoderKeepsCompletedFragments`.
  To run one test directly: `QT_QPA_PLATFORM=offscreen ./build/test_editor <testName>`.

Test helpers already in `tests/test_editor.cpp`: `cameraBundle(name)` (a camera recording),
the QML-in-a-Window pattern of `cameraPanelLayoutFollowsTheAspect` (~line 2042) with its
`findItem` lambda. Reuse them; do not invent new scaffolding.

---

## Phase 1 — Sections by name (no visible change)

### 1.1 `SidePanel.qml`: name lookup
File `src/ui/qml/SidePanel.qml`.
- Add `function sectionIndex(name)` returning the index of `sections[i].name === name`, else -1.
- Add `function showSection(name)` doing `const i = sectionIndex(name); if (i >= 0) section = i`.
- Replace the index chain in `panelLoader.sourceComponent` with a name switch on
  `root.sections[root.displayedSection].name` ("Background" → backgroundPanel, "Shape" →
  shapePanel, "Cursor", "Zoom", "Clip", "Camera" → cameraPanel, "Keystrokes", default → audioPanel).
- `setBackgroundExpanded`, `setGradientExpanded`, `setBackgroundHoverProof`: `root.section = 0`
  → `root.showSection("Background")`.
- `Connections { target: editor ... onSelectionChanged }`: `section = 3` → `showSection("Zoom")`,
  `section = 4` → `showSection("Clip")`.
- Test first in `tests/test_editor.cpp`, new slot `sidePanelShowsSectionsByName`: load
  `SidePanel { anchors.fill: parent }` in the Window pattern with a camera bundle; call
  `showSection("Camera")` via `QMetaObject::invokeMethod(panel, "showSection", Q_ARG(QVariant, "Camera"))`;
  assert `section` equals `sectionIndex("Camera")` and that, after the swap animation
  (`QTRY_VERIFY`), the loaded panel contains `cameraFullFrameGroup` (a CameraPanel objectName);
  `showSection("Nope")` leaves `section` unchanged. (The panel's root has `objectName: "sidePanel"`.)
- Verify: `V-BUILD`.

### 1.2 `Main.qml` and `src/main.cpp` use names
- `src/ui/qml/Main.qml`: every `sidePanel.section = N` → `sidePanel.showSection("<Name>")`
  (0 → "Background", 5 → "Camera"; lines ~56, ~59, ~63, ~67, and `onCameraSelected` ~129).
  `forcedTooltip` stays "Camera" in this task.
- `src/main.cpp` (~line 122, `static const QHash<QString, int> panels`): replace the index map
  with a name map `QHash<QString, QString>`: background→"Background", shape→"Shape",
  cursor→"Cursor", zoom→"Zoom", clip→"Clip", camera→"Camera", keystrokes→"Keystrokes",
  audio→"Audio"; call `QMetaObject::invokeMethod(sidePanel, "showSection", Q_ARG(QVariant, name))`
  instead of `setProperty("section", …)`. The zoom/clip selection code below it stays, keyed on
  the lower-case env value as now.
- Test: build, then run
  `OMAREEL_SCREENSHOT=/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/p1-camera.png OMAREEL_SCREENSHOT_PANEL=camera OMAREEL_SCREENSHOT_SIZE=1400x900 QT_QPA_PLATFORM=offscreen timeout 40 build/omareel edit <a camera bundle>`
  (make one with the same steps `cameraBundle` uses, or ask the lead for
  `/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/split-test.omareel`,
  which exists) and confirm the PNG was written. Say in the report that you did.
- Verify: `V-BUILD`.

---

## Phase 2 — The Layout panel

### 2.1 Shared aspect list
- New `src/ui/qml/Aspects.js` with `.pragma library` and `var list = [...]`, the exact array now
  in `BottomBar.qml`'s `aspects` (text/value pairs, same order).
- Register it like `Framing.js` (find every place `Framing.js` appears in `CMakeLists.txt`: the
  `QML_FILES` list, the `set_source_files_properties` list and its `QT_RESOURCE_ALIAS`) and do the
  same for `Aspects.js`.
- `BottomBar.qml`: `import "Aspects.js" as Aspects`; `readonly property var aspects: Aspects.list`.
- Verify: `V-BUILD` (behaviour unchanged; the aspect menu tests, if any, still pass).

### 2.2 `LayoutPanel.qml`: canvas, webcam layout, split
- New `src/ui/qml/LayoutPanel.qml`, registered next to `CameraPanel.qml` in both CMake lists
  (it appears twice in `CMakeLists.txt`, ~124 and ~184; add `LayoutPanel.qml` after it in both).
- Root: `ColumnLayout { id: root; spacing: theme.space.panelGap; readonly property var camera: editor.project.camera; readonly property bool webcamShown: editor.hasCamera && root.camera.enabled }`.
- Contents in this task (spec "Layout panel" items 1–3):
  - `PanelHeading { text: "Canvas" }`, then an `OmDropdown { objectName: "layoutAspectMenu"; Layout.fillWidth: true; textRole: "text"; model: Aspects.list; currentIndex: <index of editor.project.aspect, -1 → 0>; onActivated: editor.setProjectValue("aspect", model[currentIndex].value) }`
    (`import "Aspects.js" as Aspects`; follow how BottomBar's `aspectBox` sets `currentIndex`).
  - `ColumnLayout { visible: editor.hasCamera; … }` holding:
    - `PanelHeading { text: "Webcam layout"; Layout.topMargin: 2 }`.
    - The `OmButtonGroup` **moved** from CameraPanel (objectName `cameraLayoutGroup`, options
      Split/Bubble, `value: editor.activeCameraLayout`, `onChanged` writes `camera.layout`),
      now `Layout.fillWidth: true` and `visible: root.webcamShown`.
    - `Label { visible: !root.webcamShown; text: "Turn on Show webcam in Webcam to place it."; muted small style as CameraPanel's labels }`.
    - Split only (`visible: root.webcamShown && editor.activeCameraLayout === "split"`):
      `PanelLabel { text: "Split" }`, the ratio `OmButtonGroup` **moved** from CameraPanel
      (objectName `cameraSplitRatioGroup`, same options/value/onChanged) with `Layout.fillWidth: true`,
      and `Label { objectName: "layoutSplitOrientation"; text: editor.outputWidth > editor.outputHeight ? "Screen left, webcam right" : "Screen on top, webcam below" }` in the muted small style.
  - In `CameraPanel.qml` delete the moved Layout row, the ratio row and the long "Tall canvas…"
    Label (keep everything else for now).
- `SidePanel.qml`: insert `{name:"Layout", meta:"Where the screen and webcam go", icon:"layers.svg"}`
  right after Background; add `Component { id: layoutPanel; LayoutPanel { } }` and the "Layout"
  case in the name switch.
- Tests: change `cameraPanelLayoutFollowsTheAspect` to instantiate `LayoutPanel` instead of
  `CameraPanel` (same assertions; rename the slot to `layoutPanelLayoutFollowsTheAspect`), and
  add to it: `cameraSplitRatioGroup` exists and its `value` is 0.6; `layoutSplitOrientation`'s
  `text` is "Screen on top, webcam below" at 9:16 and "Screen left, webcam right" after
  `editor.setProjectValue("aspect", "16:9")` + `camera.layout` "split". Run it first against the
  new file before moving the controls (it fails), then move them.
- Verify: `V-BUILD`.

### 2.3 Screen framing moves to Layout
- `LayoutPanel.qml`, after the webcam layout group: `PanelHeading { text: "Screen"; Layout.topMargin: 2 }`
  and the four controls **moved** from `ShapePanel.qml` (the three `PanelSlider`s and the Reset
  `EditorButton`, objectNames unchanged). Slider labels: "Zoom", "Move ↔", "Move ↕"; button text "Reset".
- `ShapePanel.qml`: delete the "Screen framing" heading, the four controls and the
  `OmSeparator` right after them.
- Tests: `shapePanelScreenFraming` (~line 2153) instantiates `LayoutPanel` instead of
  `ShapePanel`; rename it `layoutPanelScreenFraming`. Assertions unchanged.
- Verify: `V-BUILD`.

### 2.4 Webcam framing and bubble placement move to Layout
- `LayoutPanel.qml`, after Screen: a `ColumnLayout { visible: root.webcamShown; … }` with
  `PanelHeading { text: "Webcam"; Layout.topMargin: 2 }` and:
  - Split (`visible: editor.activeCameraLayout === "split"`): the framing sliders + Reset
    **moved** from CameraPanel (objectNames `cameraFramingZoom`, `cameraFramingHorizontal`,
    `cameraFramingVertical`, `cameraFramingReset` unchanged; labels "Zoom", "Move ↔", "Move ↕";
    button "Reset"). Uses `root.camera` exactly as CameraPanel did.
  - Bubble (`visible: editor.activeCameraLayout === "bubble"`): the position pad (`positionPad`
    Rectangle with its Repeater and the bubble Rectangle) and the Size `PanelSlider`, **moved**
    from CameraPanel. Inside the pad the code reads `root.camera.position`, `.size`, `.shape`,
    `.radius`, `.border` — `root.camera` exists in LayoutPanel, so they work unchanged.
- Last item: `Label { objectName: "layoutTip"; text: "Drag in the preview to move, Ctrl+scroll to zoom."; muted small; Layout.topMargin: 4 }`.
- `CameraPanel.qml`: delete the moved Framing column, the Position heading, the pad and the Size
  slider.
- Tests: `cameraPanelFramingControls` (~line 2087) instantiates `LayoutPanel`; rename it
  `layoutPanelWebcamFraming`. Add one assertion: after `editor.setProjectValue("camera.layout", "bubble")`
  the item `cameraFramingZoom` is not visible (`isVisible()` false) — find the pad by giving it
  `objectName: "cameraPositionPad"` and assert it is visible.
- Verify: `V-BUILD`.

---

## Phase 3 — Screen and Webcam panels

### 3.1 Rename Shape → Screen, Camera → Webcam
- `SidePanel.qml` sections: `{name:"Screen", meta:"Padding, corners, shadow and border", icon:"square.svg"}`
  (was Shape) and `{name:"Webcam", meta:"Look of the webcam", icon:"camera.svg"}` (was Camera).
  Update the name switch ("Screen" → shapePanel, "Webcam" → cameraPanel) and the `onSelectionChanged`
  names if they mention them (they don't; Zoom/Clip).
- `Main.qml`: `showSection("Camera")` → `showSection("Webcam")` everywhere; `forcedTooltip = "Webcam"`.
- `src/main.cpp` panel map: add "layout"→"Layout", "screen"→"Screen", "webcam"→"Webcam", keep
  "shape"→"Screen" and "camera"→"Webcam" as aliases.
- Tests: `sidePanelShowsSectionsByName` uses "Webcam"; add that `showSection("Layout")` loads a
  panel containing `layoutAspectMenu`.
- Verify: `V-BUILD`.

### 3.2 Webcam panel content
File `src/ui/qml/CameraPanel.qml`, after Phase 2 it holds: empty state, status, Show camera
switch, the bubble style controls (Shape group, Corner radius, Shrink while zoomed, Shadow,
Border), then Full screen / Rotation / Mirror.
- "Show camera" → text "Show webcam", description "Show the webcam in the video".
- Empty-state hint: "Turn on Webcam in the launcher before recording to add a webcam."
- Wrap Shape … Border in `ColumnLayout { objectName: "webcamBubbleStyle"; enabled: editor.activeCameraLayout === "bubble"; opacity: enabled ? 1 : .42 }`
  preceded by `PanelHeading { text: "Bubble style" }` and, visible only in Split,
  `Label { objectName: "webcamBubbleStyleNote"; text: "Bubble style applies when Layout is Bubble." }` (muted small).
  Check after Phase 2 that no leftover `visible: editor.activeCameraLayout === "bubble"` wrapper
  hides these controls in Split; the new rule is "shown, disabled in Split".
- Full screen hint → "Clips set to Show: Webcam fill the frame with the webcam. Set it per clip in Clip."
- Test first (new slot `webcamPanelIsLookOnly`): instantiate `CameraPanel` with a camera bundle at
  9:16 (Split): `cameraLayoutGroup`, `cameraSplitRatioGroup`, `cameraFramingZoom` are **absent**
  (`findItem` returns nullptr); `webcamBubbleStyle` exists with `enabled` false and
  `webcamBubbleStyleNote` visible; after `camera.layout` "bubble", `webcamBubbleStyle.enabled` is true.
- Verify: `V-BUILD`.

### 3.3 Screen panel wording
File `src/ui/qml/ShapePanel.qml`.
- The note "Shape settings stay saved but are ignored while the background type is None." →
  "Screen style stays saved but is ignored while the background is None."
- Nothing else (Frame heading and controls stay).
- Verify: `V-BUILD`.

### 3.4 Timeline wording
- `src/ui/qml/Timeline.qml`: the third track row `{name: "Camera", icon: "camera.svg"}` →
  `{name: "Webcam", …}` (~194); the camera block label `text: "Camera"` (~524) → "Webcam".
  Before changing, `grep -n '"Camera"' src/ui/qml/Timeline.qml tests/*.cpp` and make sure no code
  compares against the row name; if something does, update it in the same commit and say so.
- Verify: `V-BUILD`.

---

## Phase 4 — Clip "Show"

### 4.1 Clip panel and clip label menu
- `src/ui/qml/ClipPanel.qml` (~36–55): `PanelLabel` text "Layout" → "Show"; options →
  `[{value:"default", label:"Both"}, {value:"camera", label:"Webcam"}, {value:"screen", label:"Screen"}]`
  (objectName `clipLayoutGroup` unchanged); hints exactly as in the spec ("Clip panel and timeline").
  The Clip section meta in `SidePanel.qml` → "Trim, speed and what it shows".
- `src/ui/qml/ClipTrack.qml`: clip label (~258) `"Camera"` → `"Webcam"`; label menu options
  (~355) → Both / Webcam / Screen with the same values.
- Test first (new slot `clipPanelShowLabels`): with a camera bundle and the first clip selected
  (`editor.setProperty("selectedClipId", …)` as `src/main.cpp` does for the clip panel), instantiate
  `ClipPanel`; `clipLayoutGroup`'s `options` labels are ["Both", "Webcam", "Screen"]; invoking its
  `changed("camera")` sets the clip's layout to "camera" (read back via `editor.clips`).
- Verify: `V-BUILD`.

---

## Phase 5 — Lead visual check (the lead, not the implementer)

Build `build/omareel`, then for each of these, render the editor offscreen and look at it:

```
B=/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/split-test.omareel
for p in layout screen webcam clip; do
  OMAREEL_SCREENSHOT=/tmp/claude-1000/-home-pfr/6ea9ca0f-878a-4c73-ab17-8702be44a1da/scratchpad/panel-$p-split.png \
  OMAREEL_SCREENSHOT_PANEL=$p OMAREEL_SCREENSHOT_SIZE=1400x900 QT_QPA_PLATFORM=offscreen \
  timeout 40 build/omareel edit "$B"
done
```

and again with `OMAREEL_SCREENSHOT_PROJECT_VALUES='{"aspect":"16:9","camera.layout":"bubble"}'`
into `panel-$p-bubble.png`. Check: Layout shows Canvas, Webcam layout, the full-width Split row
with "Screen on top, webcam below" (9:16), Screen and Webcam framing, the tip; in Bubble the
corner pad and Size. Screen shows only frame style. Webcam shows no placement controls, bubble
style disabled in Split. Clip shows "Show: Both / Webcam / Screen". The rail has 9 buttons and
fits. Nothing is elided that shouldn't be.
(`OMAREEL_SCREENSHOT_PROJECT_VALUES` is documented in `docs/USAGE.md` ~274; check its exact
format there before running.)

---

## Phase 6 — Docs and package

### 6.1 Docs
- `docs/USAGE.md`: update every mention of the Camera panel, Shape panel, "Layout control",
  clip layouts ("Screen & camera / Camera / Screen" → "Show: Both / Webcam / Screen") to the new
  names; add one short paragraph "Side panel" listing the sections and what each holds, as in
  the spec table. In the debug section, list `OMAREEL_SCREENSHOT_PANEL` values
  `background|layout|screen|cursor|zoom|clip|webcam|keystrokes|audio` and note the `shape` /
  `camera` aliases.
- Verify: read it back.

### 6.2 Package
- `pkg/PKGBUILD`: bump `pkgver` by one from whatever it is now (e.g. 0.5.0.pf5 → 0.5.0.pf6),
  `vercmp <new>-1 <old>-1` prints 1, commit "Package: <version>".
- `cd pkg && makepkg -f --noconfirm` (no `-s`, no `-i`). Output is `.pkg.tar.xz`. Then
  `QT_QPA_PLATFORM=offscreen BUILD_DIR=build-pkg ./bin/test` from the repo root (same allowed
  failures). Do not install.
