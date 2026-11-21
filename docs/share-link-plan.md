# Share link: upload an export and copy its link (PF, 2026-11-20)

Branch `pf/share-link` (from `pf/split-and-timeline`). PF wants a **Share link** button in Omareel that turns a finished export into a link on PF's OmaShare server (self-hosted Cap Web), like Loom. `docs/feature-parity.md` already lists "Shareable links: Missing". This plan fills that gap.

## The tool it calls

`omashare` (installed at `/usr/bin/omashare`, from github.com/riopierrefrancois/omashare-cli) does the upload. Omareel runs it and shows progress:

```
omashare --json --name "TITLE" /abs/path/export.mp4
```

stdout is one JSON object per line:

```json
{"event": "progress", "stage": "preparing", "percent": 37.5}
{"event": "progress", "stage": "uploading", "percent": 81.2}
{"event": "done", "id": "kxed3ytz2z7ht2t", "link": "https://share.example.com/s/kxed3ytz2z7ht2t"}
{"event": "error", "error": "Not signed in. Run: omashare login"}
```

The exit code is 0 or 1. It copies the link to the clipboard itself (via wl-copy) and converts GIF or other formats to MP4 by itself. Never run `omashare login` from the app (it opens a browser); say what to do instead. Share the exported file (`root.successPath` in `ExportDialog.qml`), never the `.omareel` bundle.

## Rules

- Logic lives in Rust, following `docs/rust-migration.md`. The process and parsing go in `omareel_core` (no Qt). The properties, signals and invokable go on the `Editor` CXX-Qt object (`crates/omareel_qt/src/editor.rs`). QML only shows state.
- Run the process off the GUI thread:
  - Use `omareel_core::compat::qprocess::Process` with a cancel flag, like `launcher.rs` `run_record` / `start_record_job`.
  - Read stdout line by line (`wait_for_ready_read`) and parse each line with `compat::qjson`.
  - Report back with `qt_thread().queue(...)`.
  - Closing the window cancels and kills the upload; the `EditorRust` drop must not hang.
- Find the tool with `qstandardpaths::find_executable("omashare")`. The env var `OMAREEL_OMASHARE` overrides it, which is the test seam.
- Commits are "Area: sentence" (e.g. "Share: …"), one per task, with the box ticked in the same commit.
- `./bin/build && ./bin/test` pass before each commit.
- Install nothing. Stop at the gate and report.

## Tasks

### R1: share in the core and on the Editor
- [x] `omareel_core`:
  - a share runner that starts `omashare --json --name <title> <path>` (separate arguments) and turns its stdout lines into events: progress (stage, percent), done (link), error (message).
  - Missing tool: "Install omashare to share links."
  - "Not signed in": "Sign in to OmaShare first: run omashare login in a terminal."
  - A non-zero exit with no message: "Couldn't share the video."
  - `cargo test` for the line parser: progress, done, error, junk lines ignored, a missing done with exit 1.
- [x] `Editor`:
  - qproperties `sharing` (bool), `share_stage` (QString), `share_percent` (f64), `share_link` (QString), `share_error` (QString)
  - signal `share_finished(link)`
  - invokable `share(path, title)`, which is ignored while a share runs and resets link/error on start
  - Follow the existing `exporting` / `exportProgress` / `exportError` / `exportFinished` pattern.

### R2: the button in the Export window
- [ ] In `ExportDialog.qml`'s done state (the button row with "Show in folder", "Copy path", "Done"), add **Share link** (`OmButton`, primary).
  - It calls `editor.share(root.successPath, editor.bundleName)`.
  - It's hidden when `omashare` isn't installed. Expose a `share_available` bool on `Editor`, checked once.
- [ ] While sharing:
  - The dialog shows "Preparing link… 40%" or "Uploading… 80%" with the dialog's existing progress bar.
  - The buttons are disabled, and the dialog can't be closed (`closePolicy` locked, as during export).
- [ ] When done:
  - Show the link (selectable text) under the path, with "Link copied" in the success style.
  - Add a **Copy link** button (uses the existing `copy_path` shim) and an **Open** button (opens the link in the browser).
- [ ] On error, show the message in the dialog's error style (`theme.record`), and let them try again.
- [ ] Add a share-link icon (Lucide `link.svg`) to `assets/icons/lucide/` and list it in `qt_add_resources` in `CMakeLists.txt`.
- [ ] Shortcut: **Ctrl+L** in the done state shares. Add it to the README shortcut table and the `BottomBar.qml` shortcuts sheet.

### R3: tests and docs
- [ ] `tests/golden/shims/omashare`: a fake that prints two progress lines and a done line, or an error when `OMASHARE_FAKE_FAIL=1`.
  - `test_editor`: export → share → `share_finished` with the link (QSignalSpy), progress properties seen, error path shows the message, the button is hidden when the tool is missing.
- [ ] `docs/feature-parity.md`: Shareable links becomes **Done** (via omashare). Add one short section to `README.md` and `docs/USAGE.md`: "Share link: after an export, click Share link (or Ctrl+L) to upload it to your OmaShare and copy the link. Needs `omashare` and `omashare login` once."

### R4: release
- [ ] `pkg/PKGBUILD`: `pkgver=0.5.0.pf9`, plus `optdepends=('omashare: Share link button')`. Commit as "Package: 0.5.0.pf9".
- [ ] Build the package with `makepkg -f` in `pkg/` (not `./bin/install`, which installs).

## Gate
`./bin/build && ./bin/test` green (including `cargo test`), package built. Write the report to the path the orchestrator gives: commits, test output, anything this plan got wrong. Stop.
