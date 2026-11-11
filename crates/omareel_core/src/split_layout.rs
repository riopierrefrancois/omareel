//! The camera Split layout: which layout is drawn, and where the screen and the camera go.

use crate::compat::cpp;
use crate::project::Project;

pub const DEFAULT_SPLIT_RATIO: f64 = 0.6;
pub const MIN_SPLIT_RATIO: f64 = 0.5;
pub const MAX_SPLIT_RATIO: f64 = 0.8;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SplitGeometry {
    pub side_by_side: bool,
    pub screen_region: Rect,
    pub camera_rect: Rect,
}

/// The layout actually drawn. `canvas_aspect` is the output's width divided by its height.
pub fn active_camera_layout(project: &Project, camera_available: bool, canvas_aspect: f64) -> &'static str {
    if !project.camera.enabled || !camera_available {
        return "bubble";
    }
    match project.camera.layout.as_str() {
        "split" => "split",
        // Auto picks Split on any canvas taller than wide; square stays with the bubble.
        "auto" if canvas_aspect < 1.0 => "split",
        _ => "bubble",
    }
}

pub fn split_geometry(output_width: f64, output_height: f64, ratio: f64) -> SplitGeometry {
    let ratio = cpp::clamp(ratio, MIN_SPLIT_RATIO, MAX_SPLIT_RATIO);
    let w = cpp::max(0.0, output_width);
    let h = cpp::max(0.0, output_height);
    if w > h {
        let screen_width = (w * ratio).round();
        SplitGeometry {
            side_by_side: true,
            screen_region: Rect { x: 0.0, y: 0.0, width: screen_width, height: h },
            camera_rect: Rect { x: screen_width, y: 0.0, width: cpp::max(0.0, w - screen_width), height: h },
        }
    } else {
        let screen_height = (h * ratio).round();
        SplitGeometry {
            side_by_side: false,
            screen_region: Rect { x: 0.0, y: 0.0, width: w, height: screen_height },
            camera_rect: Rect { x: 0.0, y: screen_height, width: w, height: cpp::max(0.0, h - screen_height) },
        }
    }
}

/// A cover fill of the camera's part: the scale that makes the camera's display size at least
/// as large as its rect on both axes.
pub fn split_camera_decode_scale(geometry: &SplitGeometry, camera_display_width: f64, camera_display_height: f64) -> f64 {
    if camera_display_width <= 0.0 || camera_display_height <= 0.0 {
        return 1.0;
    }
    let scale = cpp::max(geometry.camera_rect.width / camera_display_width, geometry.camera_rect.height / camera_display_height);
    cpp::clamp(scale, 0.01, 1.0)
}

/// Split is not drawn: the screen gets the whole canvas and the camera has no part of it.
pub fn no_split(width: f64, height: f64) -> SplitGeometry {
    SplitGeometry {
        side_by_side: false,
        screen_region: Rect { x: 0.0, y: 0.0, width, height },
        camera_rect: Rect::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn project(layout: &str, enabled: bool) -> Project {
        let mut project = Project::default();
        project.camera.enabled = enabled;
        project.camera.layout = layout.into();
        project
    }

    #[test]
    fn geometry_splits_stacked_or_side_by_side() {
        assert_eq!(
            split_geometry(1080.0, 1920.0, 0.6),
            SplitGeometry {
                side_by_side: false,
                screen_region: Rect { x: 0.0, y: 0.0, width: 1080.0, height: 1152.0 },
                camera_rect: Rect { x: 0.0, y: 1152.0, width: 1080.0, height: 768.0 },
            }
        );
        // A square canvas stacks rather than splitting side by side.
        assert_eq!(
            split_geometry(1080.0, 1080.0, 0.6),
            SplitGeometry {
                side_by_side: false,
                screen_region: Rect { x: 0.0, y: 0.0, width: 1080.0, height: 648.0 },
                camera_rect: Rect { x: 0.0, y: 648.0, width: 1080.0, height: 432.0 },
            }
        );
        assert_eq!(
            split_geometry(1920.0, 1080.0, 0.6),
            SplitGeometry {
                side_by_side: true,
                screen_region: Rect { x: 0.0, y: 0.0, width: 1152.0, height: 1080.0 },
                camera_rect: Rect { x: 1152.0, y: 0.0, width: 768.0, height: 1080.0 },
            }
        );
    }

    #[test]
    fn geometry_clamps_the_ratio() {
        // 0.2 acts as 0.5 and 0.95 as 0.8.
        assert_eq!(split_geometry(1080.0, 1920.0, 0.2).screen_region.height, 960.0);
        assert_eq!(split_geometry(1080.0, 1920.0, 0.95).screen_region.height, 1536.0);
    }

    #[test]
    fn decode_scale_covers_the_camera_band() {
        let side_by_side = split_geometry(1280.0, 720.0, 0.6);
        assert!((split_camera_decode_scale(&side_by_side, 1920.0, 1080.0) - 720.0 / 1080.0).abs() < 1e-12);

        let stacked = split_geometry(1080.0, 1920.0, 0.5);
        assert!((split_camera_decode_scale(&stacked, 1920.0, 1080.0) - 960.0 / 1080.0).abs() < 1e-12);
        // A 1920x1080 camera turned 90 degrees already fills the band.
        assert!((split_camera_decode_scale(&stacked, 1080.0, 1920.0) - 1.0).abs() < 1e-12);
        assert!((split_camera_decode_scale(&stacked, 0.0, 0.0) - 1.0).abs() < 1e-12);
    }

    #[test]
    fn no_split_gives_the_screen_the_whole_canvas() {
        assert_eq!(
            no_split(1920.0, 1080.0),
            SplitGeometry {
                side_by_side: false,
                screen_region: Rect { x: 0.0, y: 0.0, width: 1920.0, height: 1080.0 },
                camera_rect: Rect::default(),
            }
        );
    }

    #[test]
    fn active_layout_needs_a_camera_and_follows_the_layout() {
        assert_eq!(active_camera_layout(&project("split", false), true, 16.0 / 9.0), "bubble");
        assert_eq!(active_camera_layout(&project("split", true), false, 16.0 / 9.0), "bubble");
        assert_eq!(active_camera_layout(&project("split", true), true, 16.0 / 9.0), "split");
        assert_eq!(active_camera_layout(&project("bubble", true), true, 9.0 / 16.0), "bubble");

        // Auto splits any canvas taller than wide, including an "auto" aspect on a portrait
        // recording.
        for aspect in [9.0 / 16.0, 4.0 / 5.0, 3.0 / 4.0, 0.99] {
            assert_eq!(active_camera_layout(&project("auto", true), true, aspect), "split");
        }
        // Square and wide stay with the bubble.
        for aspect in [16.0 / 9.0, 1.0, 4.0 / 3.0] {
            assert_eq!(active_camera_layout(&project("auto", true), true, aspect), "bubble");
        }
    }
}
