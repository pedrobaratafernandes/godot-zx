//! Detection of tape and snapshot formats from their raw bytes.
//!
//! Godot only hands us a `PackedByteArray`, not a file name, so the format
//! is decided by the file's magic header. Unknown data falls back to the
//! headerless formats (.TAP for tapes, .SNA for snapshots).

use crate::host::TapeCursor;
use rustzx_core::host::{BufferCursor, Snapshot, Tape};
use std::cell::Cell;
use std::rc::Rc;

/// Every TZX file starts with "ZXTape!" followed by the 0x1A end-of-text marker.
pub const TZX_MAGIC: &[u8] = b"ZXTape!\x1A";
/// Every SZX (zx-state) file starts with "ZXST".
pub const SZX_MAGIC: &[u8] = b"ZXST";

pub fn is_tzx(data: &[u8]) -> bool {
    data.starts_with(TZX_MAGIC)
}

pub fn is_szx(data: &[u8]) -> bool {
    data.starts_with(SZX_MAGIC)
}

/// Wraps tape bytes in the right `Tape` variant.
///
/// TZX files that only hold standard-speed data are converted to TAP so they get
/// the instant fastload (rustzx only fastloads TAP). Anything else (turbo blocks,
/// custom loaders, loops...) is played as real TZX, in real time.
pub fn tape_from_bytes(data: &[u8]) -> (Tape<TapeCursor>, TapeProgress) {
    let (tape, is_tzx) = match tzx_to_tap(data) {
        Some(tap) => (tap, false),
        None => (data.to_vec(), is_tzx(data)),
    };
    let len = tape.len();
    let (cursor, furthest) = TapeCursor::new(tape);
    let tape = if is_tzx { Tape::Tzx(cursor) } else { Tape::Tap(cursor) };
    (tape, TapeProgress { furthest, len })
}

/// How far the emulator has read into the loaded tape.
pub struct TapeProgress {
    furthest: Rc<Cell<usize>>,
    pub len: usize,
}

impl TapeProgress {
    pub fn position(&self) -> usize {
        self.furthest.get()
    }
}

/// Converts a TZX into TAP when every block is either standard-speed data (0x10)
/// or pure metadata with no sound (text, archive info, pauses, groups...).
/// Returns `None` if any block needs real pulse playback, or if the file is malformed.
pub fn tzx_to_tap(data: &[u8]) -> Option<Vec<u8>> {
    if !is_tzx(data) || data.len() < 10 {
        return None;
    }
    let byte = |i: usize| data.get(i).copied();
    let word = |i: usize| Some(u16::from_le_bytes([byte(i)?, byte(i + 1)?]) as usize);
    let dword = |i: usize| Some(u32::from_le_bytes([byte(i)?, byte(i + 1)?, byte(i + 2)?, byte(i + 3)?]) as usize);

    let mut tap = Vec::with_capacity(data.len());
    let mut i = 10; // "ZXTape!" + 0x1A + version (2 bytes)
    while i < data.len() {
        let id = data[i];
        i += 1;
        i += match id {
            // Standard speed data: pause(2) + length(2) + data. This is exactly a TAP block.
            0x10 => {
                let len = word(i + 2)?;
                let block = data.get(i + 4..i + 4 + len)?;
                tap.extend_from_slice(&(len as u16).to_le_bytes());
                tap.extend_from_slice(block);
                4 + len
            }
            0x20 => 2,                                  // pause / stop the tape
            0x21 => 1 + byte(i)? as usize,              // group start (name)
            0x22 => 0,                                  // group end
            0x30 => 1 + byte(i)? as usize,              // text description
            0x31 => 2 + byte(i + 1)? as usize,          // message
            0x32 => 2 + word(i)?,                       // archive info
            0x33 => 1 + 3 * byte(i)? as usize,          // hardware type
            0x35 => 20 + dword(i + 16)?,                // custom info
            0x5A => 9,                                  // "glue" between merged files
            _ => return None,                           // needs real pulses (or unknown)
        };
    }
    if i != data.len() || tap.is_empty() {
        return None;
    }
    Some(tap)
}

/// Wraps snapshot bytes in the right `Snapshot` variant (SZX or SNA).
pub fn snapshot_from_bytes(data: &[u8]) -> Snapshot<BufferCursor<Vec<u8>>> {
    let asset = BufferCursor::new(data.to_vec());
    if is_szx(data) {
        Snapshot::Szx(asset)
    } else {
        Snapshot::Sna(asset)
    }
}
