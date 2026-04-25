use godot::prelude::*;
use rustzx_core::host::{FrameBuffer, FrameBufferSource, Host, HostContext, Stopwatch, StubIoExtender, StubDebugInterface, BufferCursor};
use rustzx_core::zx::video::colors::{ZXBrightness, ZXColor};
use core::time::Duration;
use std::time::Instant;
use std::collections::VecDeque;

/// The GodotHost struct identifies our custom "environment" for the emulator.
/// It tells the rustzx core which implementations to use for the screen, timer, etc.
pub struct GodotHost;

impl Host for GodotHost {
    type Context = GodotHostContext;
    type TapeAsset = BufferCursor<Vec<u8>>;
    type FrameBuffer = GodotFrameBuffer;
    type EmulationStopwatch = GodotStopwatch;
    type IoExtender = StubIoExtender;
    type DebugInterface = StubDebugInterface;
}

/// A simple context object required by the Host trait.
/// In more complex hosts, this could hold shared state or configuration.
pub struct GodotHostContext;

impl HostContext<GodotHost> for GodotHostContext {
    fn frame_buffer_context(&self) -> <GodotFrameBuffer as FrameBuffer>::Context {
        () 
    }
}

/// This is where the emulator "paints" the screen.
/// We maintain a raw RGB buffer that Godot can later convert into an ImageTexture.
pub struct GodotFrameBuffer {
    pub width: usize,
    pub height: usize,
    /// The raw pixel data in RGB format (3 bytes per pixel: [R, G, B, R, G, B, ...]).
    pub buffer: Vec<u8>, 
}

impl FrameBuffer for GodotFrameBuffer {
    type Context = ();

    /// Called by the emulator core to create a new screen buffer.
    fn new(width: usize, height: usize, _source: FrameBufferSource, _context: Self::Context) -> Self {
        Self {
            width,
            height,
            // We allocate enough space for (width * height) pixels, each with Red, Green, and Blue.
            buffer: vec![0; width * height * 3],

        }
    }

    /// This function is called for EVERY PIXEL the emulator wants to draw.
    /// It translates the Spectrum's internal color format to standard RGB.
    fn set_color(&mut self, x: usize, y: usize, color: ZXColor, brightness: ZXBrightness) {
        // Convert the ZX Spectrum color format into standard RGB values.
        let (r, g, b) = zx_to_rgb(color, brightness);
        
        // Calculate the position in our 1D buffer from 2D coordinates.
        let index = (y * self.width + x) * 3;
        if index + 2 < self.buffer.len() {
            self.buffer[index] = r;
            self.buffer[index + 1] = g;
            self.buffer[index + 2] = b;
        }
    }
}

/// Helper function to convert ZX Spectrum hardware colors to standard 0-255 RGB bytes.
/// The Spectrum had a unique palette of 8 colors, each with a 'normal' and 'bright' variant.
fn zx_to_rgb(color: ZXColor, brightness: ZXBrightness) -> (u8, u8, u8) {
    // Determine the brightness (Spectrum had a "Bright" mode toggle).
    let intensity = match brightness {
        ZXBrightness::Normal => 205,
        ZXBrightness::Bright => 255,
    };

    // Map each ZXColor enum value to a simple Red/Green/Blue structure.
    let (r, g, b) = match color {
        ZXColor::Black => (0, 0, 0),
        ZXColor::Blue => (0, 0, 1),
        ZXColor::Red => (1, 0, 0),
        ZXColor::Purple => (1, 0, 1),
        ZXColor::Green => (0, 1, 0),
        ZXColor::Cyan => (0, 1, 1),
        ZXColor::Yellow => (1, 1, 0),
        ZXColor::White => (1, 1, 1),
    };

    // Scale by the intensity (0 or 1 * intensity).
    (r * intensity, g * intensity, b * intensity)
}

/// A standard high-resolution timer implementation using Rust's std::time::Instant.
/// Used by the emulator to keep track of time for frame synchronization.
pub struct GodotStopwatch {
    start: Instant,
}

impl Stopwatch for GodotStopwatch {
    fn new() -> Self {
        Self {
            start: Instant::now(),
        }
    }

    fn measure(&self) -> Duration {
        self.start.elapsed()
    }
}

/// The RomSet trait tells the emulator which ROM files to load.
/// For 48K it's usually one 16KB file. For 128K it's multiple banks.
pub struct GodotRomSet {
    assets: VecDeque<BufferCursor<Vec<u8>>>,
}

impl GodotRomSet {
    /// Creates a new RomSet from a vector of byte buffers (pages).
    pub fn new(pages: Vec<Vec<u8>>) -> Self {
        let mut assets = VecDeque::new();
        for page in pages {
            assets.push_back(BufferCursor::new(page));
        }
        Self { assets }
    }
}

impl rustzx_core::host::RomSet for GodotRomSet {
    type Asset = BufferCursor<Vec<u8>>;

    /// We use standard 16KB binary pages for the ROMs.
    fn format(&self) -> rustzx_core::host::RomFormat {
        rustzx_core::host::RomFormat::Binary16KPages
    }

    /// Provides the next ROM page to the core during initialization.
    fn next_asset(&mut self) -> Option<Self::Asset> {
        self.assets.pop_front()
    }
}

