//! How late a camera's pictures arrive. Some cameras process and compress each picture before
//! sending it over USB, so a picture reaches the computer a moment after it was taken while the
//! sound arrives at once. The recorder moves the camera's start earlier by this delay, so the
//! camera lines up with the sound in the editor and in exports.

use crate::compat::qjson::Object;

/// The longest delay taken from the settings, in milliseconds.
pub const MAX_MS: i64 = 2000;

/// Cameras measured by a clap test: a part of their `/dev/v4l/by-id` name and their delay in
/// milliseconds.
const MEASURED: &[(&str, i64)] = &[
    // Sony ZV-E10 over USB, 720p: the clap's picture came 0.28 s after its sound.
    ("Sony_ZV-E10", 280),
];

/// The delay of the camera at `device`, in milliseconds: the settings' `webcam.delaysMs` entry
/// for that device when there is one (0 to `MAX_MS`), else the measured delay for its model,
/// else 0.
pub fn delay_ms(device: &str, webcam: &Object) -> i64 {
    let saved = webcam.value("delaysMs").to_object();
    if saved.contains(device) {
        let value = saved.value(device).to_double(0.0);
        return if value.is_finite() { (value.round() as i64).clamp(0, MAX_MS) } else { 0 };
    }
    MEASURED.iter().find(|(name, _)| device.contains(name)).map_or(0, |(_, ms)| *ms)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compat::qjson;

    const ZV_E10: &str = "/dev/v4l/by-id/usb-Sony_ZV-E10_D02E605E0B6B-video-index0";
    const BRIO: &str = "/dev/v4l/by-id/usb-046d_Brio_500_2233LZ53VBK8-video-index0";

    #[test]
    fn measured_cameras_have_their_delay_and_others_none() {
        assert_eq!(delay_ms(ZV_E10, &Object::new()), 280);
        assert_eq!(delay_ms(BRIO, &Object::new()), 0);
        assert_eq!(delay_ms("", &Object::new()), 0);
    }

    #[test]
    fn a_saved_delay_wins_and_is_kept_in_range() {
        let webcam = qjson::object_from_json(
            format!(r#"{{"delaysMs":{{"{ZV_E10}":150,"{BRIO}":90.6,"/dev/video9":-40,"/dev/video8":99999}}}}"#)
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(delay_ms(ZV_E10, &webcam), 150);
        assert_eq!(delay_ms(BRIO, &webcam), 91);
        assert_eq!(delay_ms("/dev/video9", &webcam), 0);
        assert_eq!(delay_ms("/dev/video8", &webcam), MAX_MS);
        assert_eq!(delay_ms("/dev/video7", &webcam), 0);
    }
}
