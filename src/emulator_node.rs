use crate::host::{GodotHost, GodotHostContext, GodotRomSet};
use core::time::Duration;
use godot::classes::{Image, ImageTexture};
use godot::prelude::*;
use rustzx_core::host::BufferCursor;
use rustzx_core::zx::keys::ZXKey;
use rustzx_core::zx::machine::ZXMachine;
use rustzx_core::{EmulationMode, Emulator, RustzxSettings};
use std::collections::VecDeque;

/// A simple command to simulate a key press over multiple frames.
/// This is used to "type" commands into the emulator (like 'LOAD ""')
/// by simulating keyboard events over several emulation frames.
struct VirtualKeyCommand {
    key: ZXKey,
    use_sym: bool,
    use_shift: bool,
    frames_left: u32,
    is_pressed: bool,
    is_delay: bool,
}

/// Memory data recorder for snapshots using shared buffer to bypass ownership.
/// This allows the emulator to write its state into a vector we can then
/// pass back to Godot as a PackedByteArray.
struct SharedBufferRecorder {
    data: std::rc::Rc<std::cell::RefCell<Vec<u8>>>,
}

impl rustzx_core::host::DataRecorder for SharedBufferRecorder {
    fn write(&mut self, buf: &[u8]) -> Result<usize, rustzx_core::error::IoError> {
        self.data.borrow_mut().extend_from_slice(buf);
        Ok(buf.len())
    }
}

/// Common logic for ZX Spectrum emulator nodes.
/// This structure encapsulates the rustzx Emulator and handles the interface
/// between the emulator core and Godot's display/input systems.
pub struct ZXEmulatorCore {
    emulator: Option<Emulator<GodotHost>>,
    texture: Option<Gd<ImageTexture>>,
    /// Queue of virtual key sequences to "type" automatically (e.g. for tape loading).
    command_queue: VecDeque<VirtualKeyCommand>,
    paused: bool,
    machine: ZXMachine,
}

impl ZXEmulatorCore {
    pub fn new() -> Self {
        Self {
            emulator: None,
            texture: None,
            command_queue: VecDeque::new(),
            paused: false,
            machine: ZXMachine::Sinclair48K,
        }
    }

    /// Initializes the emulator with specific machine settings (48K or 128K).
    pub fn create(&mut self, machine: ZXMachine) {
        self.machine = machine;
        let settings = RustzxSettings {
            machine,
            emulation_mode: EmulationMode::FrameCount(1),
            tape_fastload_enabled: true,
            kempston_enabled: true,
            mouse_enabled: true,
            ay_mode: rustzx_core::zx::sound::ay::ZXAYMode::Mono,
            ay_enabled: true,
            beeper_enabled: true,
            sound_enabled: true,
            sound_volume: 100,
            sound_sample_rate: 44100,
            // Only embedded 48k ROM exists in rustzx-core crate, so we use it for 48K model.
            load_default_rom: machine == ZXMachine::Sinclair48K,
            autoload_enabled: true,
        };

        if let Ok(emulator) = Emulator::new(settings, GodotHostContext) {
            // NOTE: 128K ROM loading is now handled via load_rom() in GDScript
            // to avoid compilation errors when the ROM file is missing in the build environment.

            self.emulator = Some(emulator);
            self.update_texture();
        }
    }

    /// Progresses the emulation by the given delta time.
    pub fn process(&mut self, delta: f32) {
        if self.paused {
            return;
        }

        // Handle virtual key sequences (for auto-load scripts).
        self.handle_virtual_keys();

        if let Some(ref mut emulator) = self.emulator {
            // Run enough CPU cycles to match the elapsed real time.
            let _ = emulator.emulate_frames(Duration::from_secs_f32(delta));
            // Update the RGB buffer so Godot can see the new frame.
            self.update_texture();
        }
    }

    pub fn set_paused(&mut self, value: bool) {
        self.paused = value;
    }

    pub fn is_paused(&self) -> bool {
        self.paused
    }

    pub fn save_snapshot(&mut self) -> PackedByteArray {
        if let Some(ref mut emulator) = self.emulator {
            let buffer = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
            let recorder = SharedBufferRecorder {
                data: buffer.clone(),
            };
            let snap_recorder = rustzx_core::host::SnapshotRecorder::Sna(recorder);
            if let Ok(_) = emulator.save_snapshot(snap_recorder) {
                return PackedByteArray::from(buffer.borrow().as_slice());
            }
        }
        PackedByteArray::new()
    }

    fn handle_virtual_keys(&mut self) {
        if let Some(ref mut emulator) = self.emulator {
            if let Some(cmd) = self.command_queue.front_mut() {
                if cmd.frames_left > 0 {
                    if !cmd.is_delay {
                        // Send keys
                        emulator.send_key(cmd.key, cmd.is_pressed);

                        if cmd.use_sym {
                            emulator.send_key(ZXKey::SymShift, cmd.is_pressed);
                        }
                        if cmd.use_shift {
                            emulator.send_key(ZXKey::Shift, cmd.is_pressed);
                        }
                    }

                    cmd.frames_left -= 1;
                } else {
                    // Command finished
                    if cmd.is_pressed && !cmd.is_delay {
                        // Release it for 10 frames before next command
                        cmd.is_pressed = false;
                        cmd.frames_left = 10;
                    } else {
                        // Fully done, remove from queue
                        self.command_queue.pop_front();
                    }
                }
            }
        }
    }

    /// Starts the automatic typing sequence to load a tape.
    /// This differs based on the machine (48K needs 'LOAD ""', 128K just needs ENTER).
    pub fn start_tape_load(&mut self) {
        self.command_queue.clear();

        let wait_frames = 120; // ~2 seconds initial wait for the machine to boot

        match self.machine {
            ZXMachine::Sinclair48K => {
                // Sequence for 48K: Wait -> J (LOAD) -> SYM+P (") -> SYM+P (") -> ENTER
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Space,
                    use_sym: false,
                    use_shift: false,
                    frames_left: wait_frames,
                    is_pressed: false,
                    is_delay: true,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Enter,
                    use_sym: false,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: true,
                    is_delay: false,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Space,
                    use_sym: false,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: false,
                    is_delay: true,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::J,
                    use_sym: false,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: true,
                    is_delay: false,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::P,
                    use_sym: true,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: true,
                    is_delay: false,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::P,
                    use_sym: true,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: true,
                    is_delay: false,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Enter,
                    use_sym: false,
                    use_shift: false,
                    frames_left: 20,
                    is_pressed: true,
                    is_delay: false,
                });
            }
            ZXMachine::Sinclair128K => {
                // Sequence for 128K: The menu starts with "Tape Loader" selected. Just press ENTER.
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Space,
                    use_sym: false,
                    use_shift: false,
                    frames_left: wait_frames,
                    is_pressed: false,
                    is_delay: true,
                });
                self.command_queue.push_back(VirtualKeyCommand {
                    key: ZXKey::Enter,
                    use_sym: false,
                    use_shift: false,
                    frames_left: 40,
                    is_pressed: true,
                    is_delay: false,
                });
            }
        }
    }

    /// Loads ROM data into the emulator. Can handle 16K (48K) or 32K (128K) buffers.
    pub fn load_rom(&mut self, data: &[u8]) {
        if let Some(ref mut emulator) = self.emulator {
            let mut pages = Vec::new();
            // Split 32KB ROM into 2 x 16KB pages for 128K model.
            if data.len() == 32768 {
                pages.push(data[0..16384].to_vec());
                pages.push(data[16384..32768].to_vec());
            } else {
                pages.push(data.to_vec());
            }

            let rom_set = GodotRomSet::new(pages);
            if let Err(e) = emulator.load_rom(rom_set) {
                godot_error!("Failed to load ROM: {:?}", e);
            }
        }
    }

    /// Loads a standard .SNA snapshot file.
    pub fn load_snapshot(&mut self, data: &[u8]) {
        if let Some(ref mut emulator) = self.emulator {
            let asset = BufferCursor::new(data.to_vec());
            if let Err(e) = emulator.load_snapshot(rustzx_core::host::Snapshot::Sna(asset)) {
                godot_error!("Failed to load SNA snapshot: {:?}", e);
            }
        }
    }



    /// Loads a .TAP tape file into the virtual tape recorder.
    pub fn load_tape(&mut self, data: &[u8]) {
        if let Some(ref mut emulator) = self.emulator {
            let asset = BufferCursor::new(data.to_vec());
            if let Err(e) = emulator.load_tape(rustzx_core::host::Tape::Tap(asset)) {
                godot_error!("Failed to load tape: {:?}", e);
            }
        }
    }

    /// Returns the Godot texture containing the current Spectrum screen.
    pub fn get_texture(&self) -> Option<Gd<ImageTexture>> {
        self.texture.clone()
    }

    /// Sends relative mouse movement to the Kempston Mouse interface.
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        if let Some(ref mut emulator) = self.emulator {
            emulator.send_mouse_pos_diff(x as i8, y as i8);
        }
    }

    /// Sends mouse button state to the Kempston Mouse interface.
    pub fn send_mouse_button(&mut self, button: i32, pressed: bool) {
        if let Some(ref mut emulator) = self.emulator {
            use rustzx_core::zx::mouse::kempston::KempstonMouseButton;
            let btn = match button {
                0 => KempstonMouseButton::Left,
                1 => KempstonMouseButton::Right,
                2 => KempstonMouseButton::Middle,
                _ => return,
            };
            emulator.send_mouse_button(btn, pressed);
        }
    }

    /// Sends joystick state to the Kempston Joystick interface.
    pub fn send_joystick(&mut self, key: &str, pressed: bool) {
        if let Some(ref mut emulator) = self.emulator {
            use rustzx_core::zx::joy::kempston::KempstonKey;
            let k_key = match key.to_uppercase().as_str() {
                "UP" => KempstonKey::Up,
                "DOWN" => KempstonKey::Down,
                "LEFT" => KempstonKey::Left,
                "RIGHT" => KempstonKey::Right,
                "FIRE" => KempstonKey::Fire,
                "EXT1" => KempstonKey::Ext1,
                "EXT2" => KempstonKey::Ext2,
                "EXT3" => KempstonKey::Ext3,
                _ => return,
            };
            emulator.send_kempston_key(k_key, pressed);
        }
    }

    /// Sends Sinclair Joystick state using the dedicated rustzx-core API.
    /// `joy_num`: 1 for Sinclair Joy 1 (keys 6-0), 2 for Sinclair Joy 2 (keys 1-5)
    /// `key`: "UP", "DOWN", "LEFT", "RIGHT", "FIRE"
    pub fn send_sinclair(&mut self, joy_num: i32, key: &str, pressed: bool) {
        if let Some(ref mut emulator) = self.emulator {
            use rustzx_core::zx::joy::sinclair::{SinclairJoyNum, SinclairKey};
            let num = match joy_num {
                1 => SinclairJoyNum::Fist,
                2 => SinclairJoyNum::Second,
                _ => return,
            };
            let s_key = match key.to_uppercase().as_str() {
                "UP" => SinclairKey::Up,
                "DOWN" => SinclairKey::Down,
                "LEFT" => SinclairKey::Left,
                "RIGHT" => SinclairKey::Right,
                "FIRE" => SinclairKey::Fire,
                _ => return,
            };
            emulator.send_sinclair_key(num, s_key, pressed);
        }
    }

    /// Retrieves accumulated audio samples since the last call.
    /// Returns interleaved Stereo samples (Left, Right, Left, Right...).
    pub fn get_audio_samples(&mut self) -> PackedFloat32Array {
        let mut result = PackedFloat32Array::new();
        if let Some(ref mut emulator) = self.emulator {
            // Drain all available samples from the internal mixer.
            while let Some(sample) = emulator.next_audio_sample() {
                result.push(sample.left);
                result.push(sample.right);
            }
        }
        result
    }

    /// Updates the internal Godot ImageTexture with the latest frame buffer data.
    fn update_texture(&mut self) {
        if let Some(ref emulator) = self.emulator {
            let frame_buffer = emulator.screen_buffer();
            let width = frame_buffer.width as i32;
            let height = frame_buffer.height as i32;
            let data = frame_buffer.buffer.as_slice();

            // Create an image from the raw RGB buffer.
            let image = Image::create_from_data(
                width,
                height,
                false,
                godot::classes::image::Format::RGB8,
                &PackedByteArray::from(data),
            )
            .unwrap();

            // Re-use existing texture or create a new one.
            if let Some(ref mut tex) = self.texture {
                tex.update(&image);
            } else {
                self.texture = ImageTexture::create_from_image(&image);
            }
        }
    }

    pub fn send_key(&mut self, key_code: &str, pressed: bool) {
        if let Some(ref mut emulator) = self.emulator {
            // Convert to uppercase so "zx_space" and "zx_SPACE" both work
            let normalized_key = key_code.to_uppercase();
            if let Some((key, shift, sym)) = map_key(&normalized_key) {
                emulator.send_key(key, pressed);
                if shift {
                    emulator.send_key(ZXKey::Shift, pressed);
                }
                if sym {
                    emulator.send_key(ZXKey::SymShift, pressed);
                }
            }
        }
    }
}

/// Maps Godot key names to (hardware key, use_shift, use_sym)
fn map_key(key: &str) -> Option<(ZXKey, bool, bool)> {
    match key {
        "1" => Some((ZXKey::N1, false, false)),
        "2" => Some((ZXKey::N2, false, false)),
        "3" => Some((ZXKey::N3, false, false)),
        "4" => Some((ZXKey::N4, false, false)),
        "5" => Some((ZXKey::N5, false, false)),
        "6" => Some((ZXKey::N6, false, false)),
        "7" => Some((ZXKey::N7, false, false)),
        "8" => Some((ZXKey::N8, false, false)),
        "9" => Some((ZXKey::N9, false, false)),
        "0" => Some((ZXKey::N0, false, false)),
        "Q" => Some((ZXKey::Q, false, false)),
        "W" => Some((ZXKey::W, false, false)),
        "E" => Some((ZXKey::E, false, false)),
        "R" => Some((ZXKey::R, false, false)),
        "T" => Some((ZXKey::T, false, false)),
        "Y" => Some((ZXKey::Y, false, false)),
        "U" => Some((ZXKey::U, false, false)),
        "I" => Some((ZXKey::I, false, false)),
        "O" => Some((ZXKey::O, false, false)),
        "P" => Some((ZXKey::P, false, false)),
        "A" => Some((ZXKey::A, false, false)),
        "S" => Some((ZXKey::S, false, false)),
        "D" => Some((ZXKey::D, false, false)),
        "F" => Some((ZXKey::F, false, false)),
        "G" => Some((ZXKey::G, false, false)),
        "H" => Some((ZXKey::H, false, false)),
        "J" => Some((ZXKey::J, false, false)),
        "K" => Some((ZXKey::K, false, false)),
        "L" => Some((ZXKey::L, false, false)),
        "Z" => Some((ZXKey::Z, false, false)),
        "X" => Some((ZXKey::X, false, false)),
        "C" => Some((ZXKey::C, false, false)),
        "V" => Some((ZXKey::V, false, false)),
        "B" => Some((ZXKey::B, false, false)),
        "N" => Some((ZXKey::N, false, false)),
        "M" => Some((ZXKey::M, false, false)),
        "SPACE" => Some((ZXKey::Space, false, false)),
        "ENTER" | "KP ENTER" => Some((ZXKey::Enter, false, false)),
        "SHIFT" => Some((ZXKey::Shift, false, false)),
        "SYM" => Some((ZXKey::SymShift, false, false)),
        "COMMA" | "," => Some((ZXKey::N, false, true)),
        "PERIOD" | "." => Some((ZXKey::M, false, true)),
        "SEMICOLON" | ";" => Some((ZXKey::O, false, true)),
        "SLASH" | "/" => Some((ZXKey::V, false, true)),
        "EQUAL" | "=" => Some((ZXKey::L, false, true)),
        "MINUS" | "-" => Some((ZXKey::J, false, true)),
        "PLUS" | "+" => Some((ZXKey::K, false, true)),
        "ASTERISK" | "*" => Some((ZXKey::B, false, true)),
        "BACKSPACE" => Some((ZXKey::N0, true, false)), // Caps Shift + 0
        "LEFT" => Some((ZXKey::N5, true, false)),      // Caps Shift + 5
        "DOWN" => Some((ZXKey::N6, true, false)),      // Caps Shift + 6
        "UP" => Some((ZXKey::N7, true, false)),        // Caps Shift + 7
        "RIGHT" => Some((ZXKey::N8, true, false)),     // Caps Shift + 8
        "QUOTELEFT" => Some((ZXKey::N1, true, false)), // Edit = Shift + 1
        "CAPS LOCK" => Some((ZXKey::N2, true, false)), // Caps Lock = Shift + 2
        _ => None,
    }
}

// specialized Nodes

/// Godot Node representing a ZX Spectrum 48K.
#[derive(GodotClass)]
#[class(base=Node)]
pub struct ZXEmulator48K {
    core: ZXEmulatorCore,
    base: Base<Node>,
}

#[godot_api]
impl INode for ZXEmulator48K {
    fn init(base: Base<Node>) -> Self {
        let mut core = ZXEmulatorCore::new();
        core.create(ZXMachine::Sinclair48K);
        Self { core, base }
    }

    fn process(&mut self, delta: f64) {
        self.core.process(delta as f32);
    }
}

#[godot_api]
impl ZXEmulator48K {
    #[func]
    pub fn load_rom(&mut self, data: PackedByteArray) {
        self.core.load_rom(data.as_slice());
    }
    #[func]
    pub fn load_snapshot(&mut self, data: PackedByteArray) {
        self.core.load_snapshot(data.as_slice());
    }
    #[func]
    pub fn save_snapshot(&mut self) -> PackedByteArray {
        self.core.save_snapshot()
    }
    #[func]
    pub fn load_tape(&mut self, data: PackedByteArray) {
        self.core.load_tape(data.as_slice());
    }
    #[func]
    pub fn start_tape_load(&mut self) {
        self.core.start_tape_load();
    }
    #[func]
    pub fn get_audio_samples(&mut self) -> PackedFloat32Array {
        self.core.get_audio_samples()
    }
    #[func]
    pub fn get_texture(&self) -> Option<Gd<ImageTexture>> {
        self.core.get_texture()
    }
    #[func]
    pub fn send_key(&mut self, key_code: String, pressed: bool) {
        self.core.send_key(&key_code, pressed);
    }
    #[func]
    pub fn set_paused(&mut self, value: bool) {
        self.core.set_paused(value);
    }
    #[func]
    pub fn is_paused(&self) -> bool {
        self.core.is_paused()
    }
    #[func]
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        self.core.send_mouse_move(x, y);
    }
    #[func]
    pub fn send_mouse_button(&mut self, button: i32, pressed: bool) {
        self.core.send_mouse_button(button, pressed);
    }
    #[func]
    pub fn send_joystick(&mut self, key: String, pressed: bool) {
        self.core.send_joystick(&key, pressed);
    }
    #[func]
    pub fn send_sinclair(&mut self, joy_num: i32, key: String, pressed: bool) {
        self.core.send_sinclair(joy_num, &key, pressed);
    }
}

/// Godot Node representing a ZX Spectrum 128K.
#[derive(GodotClass)]
#[class(base=Node)]
pub struct ZXEmulator128K {
    core: ZXEmulatorCore,
    base: Base<Node>,
}

#[godot_api]
impl INode for ZXEmulator128K {
    fn init(base: Base<Node>) -> Self {
        let mut core = ZXEmulatorCore::new();
        core.create(ZXMachine::Sinclair128K);
        Self { core, base }
    }

    fn process(&mut self, delta: f64) {
        self.core.process(delta as f32);
    }
}

#[godot_api]
impl ZXEmulator128K {
    #[func]
    pub fn load_rom(&mut self, data: PackedByteArray) {
        self.core.load_rom(data.as_slice());
    }
    #[func]
    pub fn load_snapshot(&mut self, data: PackedByteArray) {
        self.core.load_snapshot(data.as_slice());
    }
    #[func]
    pub fn save_snapshot(&mut self) -> PackedByteArray {
        self.core.save_snapshot()
    }
    #[func]
    pub fn load_tape(&mut self, data: PackedByteArray) {
        self.core.load_tape(data.as_slice());
    }
    #[func]
    pub fn start_tape_load(&mut self) {
        self.core.start_tape_load();
    }
    #[func]
    pub fn get_audio_samples(&mut self) -> PackedFloat32Array {
        self.core.get_audio_samples()
    }
    #[func]
    pub fn get_texture(&self) -> Option<Gd<ImageTexture>> {
        self.core.get_texture()
    }
    #[func]
    pub fn send_key(&mut self, key_code: String, pressed: bool) {
        self.core.send_key(&key_code, pressed);
    }
    #[func]
    pub fn set_paused(&mut self, value: bool) {
        self.core.set_paused(value);
    }
    #[func]
    pub fn is_paused(&self) -> bool {
        self.core.is_paused()
    }
    #[func]
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        self.core.send_mouse_move(x, y);
    }
    #[func]
    pub fn send_mouse_button(&mut self, button: i32, pressed: bool) {
        self.core.send_mouse_button(button, pressed);
    }
    #[func]
    pub fn send_joystick(&mut self, key: String, pressed: bool) {
        self.core.send_joystick(&key, pressed);
    }
    #[func]
    pub fn send_sinclair(&mut self, joy_num: i32, key: String, pressed: bool) {
        self.core.send_sinclair(joy_num, &key, pressed);
    }
}
