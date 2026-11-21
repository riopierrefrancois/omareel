//! Run the OmaShare CLI and decode its JSON-lines output.

use crate::compat::{qjson, qstandardpaths};
use crate::compat::qprocess::{ExitStatus, Process, ProcessState};
use std::sync::atomic::{AtomicBool, Ordering};

pub const FAILED: &str = "Couldn't share the video.";
const MISSING: &str = "Install omashare to share links.";

#[derive(Debug, PartialEq)]
pub enum Event {
    Progress { stage: String, percent: f64 },
    Done(String),
    Error(String),
}

pub fn find_tool() -> String {
    let name = std::env::var("OMAREEL_OMASHARE").unwrap_or_else(|_| "omashare".into());
    if name.contains('/') {
        return qstandardpaths::find_executable(&crate::compat::qdir::absolute_path(&name));
    }
    if name.is_empty() {
        return String::new();
    }
    qstandardpaths::find_executable(&name)
}

fn parse_line(line: &[u8]) -> Option<Event> {
    let json = qjson::from_json(line).ok()?;
    let string = |key| json.get(key).as_str().filter(|value| !value.trim().is_empty());
    match string("event")? {
        "progress" => {
            let percent = json.get("percent").to_double(f64::NAN);
            percent.is_finite().then_some(Event::Progress {
                stage: string("stage")?.into(),
                percent: percent.clamp(0.0, 100.0),
            })
        }
        "done" => Some(Event::Done(string("link")?.into())),
        "error" => {
            let message = string("error")?;
            Some(Event::Error(if message.starts_with("Not signed in") {
                "Sign in to OmaShare first: run omashare login in a terminal.".into()
            } else {
                message.into()
            }))
        }
        _ => None,
    }
}

/// Forward progress as it arrives. Report the terminal event only once the CLI has exited.
pub fn run(
    program: &str,
    path: &str,
    title: &str,
    cancel: &AtomicBool,
    mut progress: impl FnMut(String, f64),
) -> Option<Event> {
    if cancel.load(Ordering::Relaxed) {
        return None;
    }
    if program.is_empty() {
        return Some(Event::Error(MISSING.into()));
    }
    let mut process = Process::new();
    process.start(program, &["--json", "upload", "--name", title, path]);
    if process.state() != ProcessState::Running {
        return Some(Event::Error(MISSING.into()));
    }
    process.close_write_channel();

    let mut pending = Vec::new();
    let mut terminal = None;
    loop {
        if cancel.load(Ordering::Relaxed) {
            process.kill();
            process.wait_for_finished(100);
            return None;
        }
        process.wait_for_ready_read(25);
        let finished = process.state() == ProcessState::NotRunning;
        pending.extend(process.read_all_standard_output());
        process.read_all_standard_error();

        let mut consumed = 0;
        for line in pending.split_inclusive(|byte| *byte == b'\n') {
            if !finished && !line.ends_with(b"\n") {
                break;
            }
            match parse_line(line) {
                Some(Event::Progress { stage, percent }) if terminal.is_none() => progress(stage, percent),
                Some(event @ Event::Done(_)) if terminal.is_none() => terminal = Some(event),
                Some(event @ Event::Error(_)) => terminal = Some(event),
                _ => {}
            }
            consumed += line.len();
        }
        pending.drain(..consumed);
        if finished {
            break;
        }
    }

    let succeeded = process.exit_status() == ExitStatus::NormalExit && process.exit_code() == 0;
    Some(match terminal {
        Some(event @ Event::Error(_)) => event,
        Some(event @ Event::Done(_)) if succeeded => event,
        _ => Event::Error(FAILED.into()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_events_and_ignores_junk() {
        assert_eq!(
            parse_line(br#"{"event":"progress","stage":"preparing","percent":37.5}"#),
            Some(Event::Progress { stage: "preparing".into(), percent: 37.5 })
        );
        assert_eq!(
            parse_line(br#"{"event":"done","link":"https://share.example.com/s/abc"}"#),
            Some(Event::Done("https://share.example.com/s/abc".into()))
        );
        assert_eq!(
            parse_line(br#"{"event":"error","error":"Not signed in. Run: omashare login"}"#),
            Some(Event::Error("Sign in to OmaShare first: run omashare login in a terminal.".into()))
        );
        assert_eq!(parse_line(b"some junk"), None);
        assert_eq!(parse_line(br#"{"event":"done"}"#), None);
    }

    #[test]
    fn nonzero_exit_without_done_or_error() {
        assert_eq!(
            run("/usr/bin/false", "/tmp/export.mp4", "Title", &AtomicBool::new(false), |_, _| {}),
            Some(Event::Error(FAILED.into()))
        );
    }
}
