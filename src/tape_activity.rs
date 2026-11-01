//! Detects when a tape is being loaded, so the emulator can run at full speed
//! ("turbo load") instead of making the player wait as long as a real cassette.
//!
//! TAP (and TZX converted to TAP) already loads instantly through the ROM trap.
//! This is for tapes with turbo blocks / custom loaders, which the game itself
//! reads pulse by pulse, so they can only be sped up by running the whole machine faster.

use crate::formats::TapeProgress;

/// Frames without the tape advancing before we consider loading finished or
/// stopped. Must cover the longest silent stretch of a normal tape: header pilot
/// tones (~5 s) and pauses between blocks (often 1-6 s) produce no reads.
pub const IDLE_FRAMES_LIMIT: u32 = 10 * 50;

pub struct TapeActivity {
    progress: TapeProgress,
    last_position: usize,
    idle_frames: u32,
}

impl TapeActivity {
    pub fn new(progress: TapeProgress) -> Self {
        Self { progress, last_position: 0, idle_frames: IDLE_FRAMES_LIMIT }
    }

    /// Call once per emulated frame. Returns true while the tape is loading:
    /// it has started, has not reached its end, and moved recently.
    pub fn on_frame(&mut self) -> bool {
        let position = self.progress.position();
        if position != self.last_position {
            self.last_position = position;
            self.idle_frames = 0;
        } else if self.idle_frames < IDLE_FRAMES_LIMIT {
            self.idle_frames += 1;
        }
        position > 0 && position < self.progress.len && self.idle_frames < IDLE_FRAMES_LIMIT
    }
}
