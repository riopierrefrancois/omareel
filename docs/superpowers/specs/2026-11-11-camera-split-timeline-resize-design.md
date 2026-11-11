# Camera Split layout and resizable timeline — design

Date: 2026-11-11. Branch `pf/split-and-timeline`, from `origin/master` at v0.5.0 (`b1610ac`).

Both features first existed on PF's local branch `test-all` (commits `2f766c5`, `55e9c1f`,
`1f1f3fe`, October 2026), written against the old all-C++ editor. Upstream has since moved the
logic to Rust (`crates/omareel_core`, see `docs/rust-migration.md`) and added per-clip layouts
(`default` / `camera` / `screen`) with a bubble-to-full-frame morph. Neither feature is upstream.
This is a re-implementation on the new code, not a cherry-pick.

## 1. Camera Split layout

### What the user sees

- Camera panel gets a **Layout** control at the top of the camera settings: `Split | Bubble`.
- When Split is active, a **Screen / camera** control: `50 / 50 | 60 / 40 | 70 / 30` (default
  60 / 40), and a one-line hint. Bubble-only controls (Position pad, Size, Shape, Corner radius,
  Shrink while zoomed, Shadow, Border) are hidden in Split. Full screen, Rotation and Mirror stay.
- Split on a **tall or square canvas** (height >= width): screen on top, camera below.
  On a **wide canvas**: screen left, camera right. The screen gets `splitRatio` of the canvas
  (height when stacked, width when side by side); the camera gets the rest.
- The screen keeps its shape and the project's padding/border inside its part. The camera is
  cover-cropped to fill its part, no rounded corners, no border, no shadow.
- Zooms stay inside the screen part (clipped), never over the camera.
- Keystroke pills sit inside the screen part.
- With background `none`, uncovered pixels are black in the preview (the export already makes
  them black).
- The zoom-target picker in the preview uses the same frame geometry as the composition.

### Project model

`camera` gains two keys:

| Key | Values | Default for a new project | Missing in a saved project |
|---|---|---|---|
| `layout` | `"auto"`, `"bubble"`, `"split"`; anything else → `"bubble"` | `"auto"` | `"bubble"` (old projects keep their bubble) |
| `splitRatio` | double, clamped to 0.5–0.8 | 0.6 | 0.6 |

Written to JSON only when they differ from the "missing" value (`layout` when not `"bubble"`,
`splitRatio` when not 0.6), the same way clip `layout` is only written when not `"default"`. This
keeps every saved project from before this change byte-identical on load+save.

**Active layout** (what is drawn), one function in Rust:
`active_camera_layout(project, camera_available, canvas_aspect)`:
- camera disabled or no camera file → `"bubble"`
- `layout == "split"` → `"split"`
- `layout == "auto"` and the canvas is taller than wide (width / height < 1, including an "auto" aspect on a portrait recording) → `"split"`
- otherwise `"bubble"`

Editor rules (from the old branch, in `Document::set_project_value` and `load_preset`):
- An edit that really changes `aspect` or `camera.enabled` resets `camera.layout` to `"auto"` in
  the same undo step. An unchanged or rejected value does not.
- `load_preset` keeps the project's current `camera.layout` even if the preset has one.

### Per-clip layouts (new upstream feature) and Split

Clip layouts keep their meaning. The layout timeline is unchanged (`LayoutSample { camera_full,
bubble }`). With Split active:
- `default` clip: Split. The split amount is the timeline's `bubble` value (1 on a default clip,
  0 when the camera is off or on a `screen` clip, eased between clips).
- `screen` clip: split amount eases to 0, the screen region grows back to the full canvas and the
  camera band fades out.
- `camera` clip: the camera morphs from its band to full frame using the existing
  `fullProgress` morph (band rect replaces the bubble rect as the morph's start).
- Inserted media: unchanged (covers the canvas, no camera).

### One geometry

New Rust module `crates/omareel_core/src/split_layout.rs`: `active_camera_layout`, `split_geometry(output_w, output_h, ratio) -> SplitGeometry {
side_by_side, screen_region, camera_rect }` (output pixels, region starts at the origin,
`round()` like the old C++), and `split_camera_decode_scale`.

It reaches QML through the existing `layout` map that both the editor (`comp` = editor) and the
exporter (`comp` = `ExportRenderer`'s state) already send to `Composition.qml`. New keys:
`splitActive` (bool), `sideBySide` (bool), `screenX/Y/Width/Height`,
`cameraX/Y/Width/Height` (doubles, output px). When Split is not active the screen rect is the
whole canvas and the camera rect is zero. QML only interpolates between the full canvas and these
rects by the split amount; it holds no layout rule. The export's camera decode size uses the same
geometry so the band is decoded sharp enough.

Editor: `activeCameraLayout` property (QString, notifies on project change) for the Camera panel.

## 2. Resizable timeline

- An 8 px drag handle on the top edge of the timeline (whole width, vertical-resize cursor, a 2 px
  accent line when hovered or dragged, tooltip "Drag to resize the timeline. Double-click to
  reset.").
- Dragging up makes the timeline taller; rows (Clip, Zoom, Camera) grow together; the minimum row
  is today's 48 px, so the minimum timeline is today's height (148 / 204 px).
- The timeline never grows past what leaves the preview its minimum height (338 px).
- Double-click resets to the minimum.
- Height is remembered across sessions with QtCore `Settings` (category `editor`, key
  `timelineHeight`, 0 = minimum). The app already sets organisation and application name.
- While dragging, row-position animations are off.

QML only: `src/ui/qml/Main.qml`, `src/ui/qml/Timeline.qml`.

## Constraints and risks

- **Goldens** (`tests/golden/`, see its README): they pin the old C++ output byte for byte and
  must never be regenerated from the tag for this. The new `camera.layout: "auto"` default changes
  the `project` family's outputs for *new/default* projects only. Those files are re-blessed from
  the Rust output (`OMAREEL_GOLDEN_BLESS=1`) in their own commit, the diff is checked to contain
  only `"layout":"auto"` additions, and a bullet is added under "Changed on purpose since the
  tag". Composition goldens print named fields only and must not change.
- `docs/rust-migration.md` rules: logic in Rust, Qt names in Rust style, plumbing never calls
  Rust. Nothing here touches plumbing.
- Building the app needs `cmake ninja corrosion qt6-shadertools` (not installed on this machine
  on 2026-11-11). `cargo test -p omareel_core` and `cargo check -p omareel_qt` work without them.
- Local package: `pkg/PKGBUILD` with `pkgver=0.5.0.pf1` so pacman sees it as newer than the stock
  `0.5.0-1` and older than any upstream `0.5.1`.

## Decided by PF (2026-11-11)

Auto splits any canvas taller than wide, not only 9:16, 4:5 and 3:4, so portrait-monitor
recordings on the "auto" aspect get Split too. Square stays Bubble.
