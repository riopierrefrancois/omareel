//! Open a recording in Omaedit, the multi-track editor, from Omareel's editor.
//!
//! `omaedit open <bundle.omareel>` makes (or, from Omaedit 0.12, reopens) an Omaedit project
//! from the recording; Omaedit decides where that project lives. Omareel only starts it,
//! detached, so both stay open.

use crate::compat::qprocess::{self, DetachedChannels};
use crate::compat::{qdir, qstandardpaths};

pub const FAILED: &str = "Couldn't open Omaedit.";

/// The `omaedit` executable (`OMAREEL_OMAEDIT` overrides it, for tests), or empty when it is
/// not installed.
pub fn find_tool() -> String {
    let name = std::env::var("OMAREEL_OMAEDIT").unwrap_or_else(|_| "omaedit".into());
    if name.is_empty() {
        return String::new();
    }
    if name.contains('/') {
        return qstandardpaths::find_executable(&qdir::absolute_path(&name));
    }
    qstandardpaths::find_executable(&name)
}

/// The arguments that open `bundle` in Omaedit.
pub fn arguments(bundle: &str) -> [String; 2] {
    ["open".into(), bundle.into()]
}

/// Starts Omaedit on `bundle`, detached. False when it could not be started.
pub fn open(program: &str, bundle: &str) -> bool {
    if program.is_empty() || bundle.is_empty() {
        return false;
    }
    qprocess::start_detached(program, &arguments(bundle), DetachedChannels::default()).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_the_bundle() {
        assert_eq!(arguments("/v/Recording 1.omareel"), ["open".to_string(), "/v/Recording 1.omareel".to_string()]);
    }

    #[test]
    fn nothing_to_start_without_a_program_or_bundle() {
        assert!(!open("", "/v/a.omareel"));
        assert!(!open("/usr/bin/true", ""));
    }

    #[test]
    fn starts_a_program() {
        assert!(open("/usr/bin/true", "/v/a.omareel"));
    }
}
