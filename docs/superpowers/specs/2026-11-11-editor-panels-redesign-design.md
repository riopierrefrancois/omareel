# Editor side panels: Layout, Screen, Camera, Clip "Show"

Date: 2026-11-11. Approved by PF the same day. Branch `pf/split-and-timeline`.

## Problem

PF finds the editor's settings scattered and confusing:

- Where things go on the canvas lives in four places: Split / Bubble and the split ratio in
  **Camera**, screen framing in **Shape**, the bubble's position and size in **Camera**, the
  canvas aspect in the bottom bar.
- "Layout" means two things: the project-wide Split / Bubble choice (Camera panel) and the
  per-clip Screen & camera / Camera / Screen choice (Clip panel).
- The Split hint ("Tall canvas: camera below the screen. Wide canvas: camera to the right.
  Changing the aspect or turning the camera off and on picks the layout again.") is a paragraph.
- The ratio row's label "Screen / camera" shares a row with a 212 px button group, so it is
  elided to "Screen".

## Design

Rule: **Layout** says where things go; **Screen** and **Camera** say what they look like; **Clip**
says what one clip shows. Nothing about project data, rendering or export changes. Existing
projects open and render exactly as before; the project keys (`camera.layout`,
`camera.splitRatio`, `camera.splitZoom`, `camera.splitPan`, `screen.zoom`, `screen.pan`,
`camera.position`, `camera.size`, clip `layout`) keep their names and values.

### Side panel sections (rail order)

| # | Name | Meta | Icon | Panel file |
|---|---|---|---|---|
| 0 | Background | Canvas behind the video | palette.svg | BackgroundPanel.qml |
| 1 | **Layout** (new) | Where the screen and camera go | layers.svg (already in the resources) | **LayoutPanel.qml** (new) |
| 2 | **Screen** (was Shape) | Padding, corners, shadow and border | square.svg | ShapePanel.qml (file name kept) |
| 3 | Cursor | Pointer, clicks, and motion | mouse-pointer-2.svg | CursorPanel.qml |
| 4 | Zoom | Focus and camera motion | zoom-in.svg | ZoomPanel.qml |
| 5 | Clip | Trim, speed and what it shows | film.svg | ClipPanel.qml |
| 6 | **Camera** (was Camera) | Look of the camera | camera.svg | CameraPanel.qml (file name kept) |
| 7 | Keystrokes | Shortcut overlay | keyboard.svg | KeystrokesPanel.qml |
| 8 | Audio | Tracks and volume | volume-2.svg | AudioPanel.qml |

File names stay as they are (ShapePanel.qml, CameraPanel.qml) to keep the diff and the tests
small; only what the user sees changes.

Sections are addressed **by name** everywhere (`sidePanel.showSection("Camera")`), never by
index, so adding Layout cannot shift anything again.

### Layout panel (new), top to bottom

1. **Canvas**: a full-width dropdown of the aspects (Auto, Wide 16:9, Vertical 9:16, Square 1:1,
   Portrait 4:5, Classic 4:3, Tall 3:4), bound to `editor.project.aspect`, writing
   `editor.setProjectValue("aspect", value)`. The list moves to a shared `Aspects.js` that the
   bottom bar uses too, so the two can't drift. The bottom bar's control stays.
2. **Camera layout** (only when `editor.hasCamera`):
   - when the camera is shown (`editor.project.camera.enabled`): a full-width segmented
     `[Split | Bubble]` (objectName `cameraLayoutGroup`, unchanged behaviour: value
     `editor.activeCameraLayout`, writes `camera.layout`);
   - when it is hidden: one muted line "Turn on Show camera in Camera to place it."
   - When the recording has no camera at all, this whole group is absent.
3. **Split** (Split only): a `PanelLabel` "Split" on its own line, then a full-width segmented
   `[50/50][60/40][70/30]` (objectName `cameraSplitRatioGroup`, unchanged values and setter).
   Below it one muted line from the canvas shape:
   `editor.outputWidth > editor.outputHeight ? "Screen left, camera right" : "Screen on top, camera below"`
   (same rule as `split_geometry`: side by side only when wider than tall). The old paragraph is
   removed.
4. **Screen** heading: Zoom (1–4), Move ↔, Move ↕ sliders and "Reset" (moved from ShapePanel;
   objectNames `screenFramingZoom`, `screenFramingHorizontal`, `screenFramingVertical`,
   `screenFramingReset` kept; slider labels become "Zoom", "Move ↔", "Move ↕").
5. **Camera** heading (only when the camera is shown):
   - Split: Zoom (1–3), Move ↔, Move ↕, "Reset" (moved from CameraPanel; objectNames
     `cameraFramingZoom`, `cameraFramingHorizontal`, `cameraFramingVertical`,
     `cameraFramingReset` kept).
   - Bubble: the position pad (four corners) and the Size slider (moved from CameraPanel).
6. A last muted line: "Drag in the preview to move, Ctrl+scroll to zoom."

### Screen panel (was Shape)

Only the frame look: the "background None" note, Padding, Roundness, Shadow (+ its sliders),
Border (+ its sliders and colour). The Screen framing group is gone (now in Layout).

### Camera panel (was Camera)

Only the camera's look: the no-camera empty state, the camera status line, **Show camera**
switch (was "Show camera"; description "Show the camera in the video"), then:

- **Bubble style** heading: Shape, Corner radius, Shrink while zoomed, Shadow (+ sliders),
  Border (+ sliders, colour). These style only the bubble. In Split they stay visible but
  disabled (opacity .42, like other disabled groups), with one muted line above them:
  "Bubble style applies when Layout is Bubble."
- **Full screen** heading: Fill frame / Square + blur, with the hint reworded to
  "Clips set to Show: Camera fill the frame with the camera. Set it per clip in Clip."
- Rotation and Mirror, unchanged.

Removed from this panel: Layout, Split ratio, the long hint, Framing, Position pad, Size.

### Clip panel and timeline: "Show"

- ClipPanel: the label "Layout" becomes **Show**; options "Both" (default), "Camera" (camera),
  "Screen" (screen). objectName `clipLayoutGroup` and values unchanged.
- Hints: Camera → "The camera fills the frame. Choose Fill or Square in Camera."; Screen → "The
  screen alone, without the camera."; Both with the camera on → "The screen and the camera, as
  set in Layout."; Both with the camera off → "The screen alone: Show camera is off in Camera."
- ClipTrack: the clip label shows "Camera" instead of "Camera" for camera clips (~line 258); the
  label menu's options (~line 355, no header) read "Both", "Camera", "Screen".
- Timeline: the camera track's row label "Camera" becomes "Camera" (Timeline.qml ~194, the
  `name` of the third row) and the camera block's label (~524) becomes "Camera".
- Launcher, recording bar and anything outside the editor: untouched.

### Debug screenshots

`OMAREEL_SCREENSHOT_PANEL` (src/main.cpp ~122) maps names to section indexes today. It becomes a
name lookup through `sidePanel.showSection(name)`, accepting `background, layout, screen, cursor,
zoom, clip, camera, keystrokes, audio`, with `shape` → Screen and `camera` → Camera kept as
aliases (tools/parity/compare-binaries.sh and older notes use them). `prepareScreenshot` views
`rail-tooltip` and `camera-proof` use names too (`forcedTooltip` becomes "Camera").

## Out of scope

Project data, rendering, export, the launcher, the bar widget, the bottom bar's own layout.

## Risks

- Moving controls between files can drop a binding (e.g. `root.camera` exists in CameraPanel,
  not in LayoutPanel). Each moved control is checked by an editor test or the lead's screenshot.
- The rail grows from 8 to 9 buttons (36 px + 4 px each); at the 720 px minimum window height
  this still fits (9 × 40 + 10 = 370 px).
