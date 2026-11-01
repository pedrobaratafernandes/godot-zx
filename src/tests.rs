//! Headless tests for the emulator core. They drive `rustzx_core::Emulator`
//! directly with our `GodotHost`, so no Godot runtime is needed:
//!
//!     cargo test --release
//!
//! Any .tap / .tzx / .sna / .szx file dropped into `GodotProject/games/` is
//! picked up automatically by `every_game_in_games_dir_loads`.

use crate::formats::{self, SZX_MAGIC, TZX_MAGIC};
use crate::host::{GodotHost, GodotHostContext, GodotRomSet};
use crate::tape_activity::{TapeActivity, IDLE_FRAMES_LIMIT};
use core::time::Duration;
use rustzx_core::host::{DataRecorder, SnapshotRecorder, Tape};
use rustzx_core::zx::machine::ZXMachine;
use rustzx_core::{EmulationMode, Emulator, RustzxSettings};
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const FRAMES_PER_SECOND: u32 = 50;

fn project_path(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

fn read(rel: &str) -> Vec<u8> {
    let path = project_path(rel);
    std::fs::read(&path).unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()))
}

fn znake_tap() -> Vec<u8> {
    read("GodotProject/games/znake.tap")
}

/// Same settings as `ZXEmulatorCore::create`, minus sound (not needed here).
fn new_emulator(machine: ZXMachine, fastload: bool) -> Emulator<GodotHost> {
    let settings = RustzxSettings {
        machine,
        emulation_mode: EmulationMode::FrameCount(1),
        tape_fastload_enabled: fastload,
        kempston_enabled: true,
        mouse_enabled: true,
        ay_mode: rustzx_core::zx::sound::ay::ZXAYMode::Mono,
        ay_enabled: false,
        beeper_enabled: false,
        sound_enabled: false,
        sound_volume: 0,
        sound_sample_rate: 44100,
        load_default_rom: machine == ZXMachine::Sinclair48K,
        autoload_enabled: true,
    };
    let mut emu = Emulator::new(settings, GodotHostContext).expect("emulator creation failed");
    if machine == ZXMachine::Sinclair128K {
        let rom = read("GodotProject/roms/128.rom");
        assert_eq!(rom.len(), 32768, "128.rom must be 32KB");
        let pages = vec![rom[..16384].to_vec(), rom[16384..].to_vec()];
        emu.load_rom(GodotRomSet::new(pages)).expect("128K ROM load failed");
    }
    emu
}

fn run_frames(emu: &mut Emulator<GodotHost>, frames: u32) {
    for _ in 0..frames {
        emu.emulate_frames(Duration::from_secs(1)).expect("emulation error");
    }
}

/// Runs until `done` returns true, checking once per emulated second.
/// Returns the number of emulated seconds it took, or None on timeout.
fn run_until(
    emu: &mut Emulator<GodotHost>,
    max_seconds: u32,
    mut done: impl FnMut(&Emulator<GodotHost>) -> bool,
) -> Option<u32> {
    for second in 1..=max_seconds {
        run_frames(emu, FRAMES_PER_SECOND);
        if done(emu) {
            return Some(second);
        }
    }
    None
}

struct VecRecorder(Rc<RefCell<Vec<u8>>>);

impl DataRecorder for VecRecorder {
    fn write(&mut self, buf: &[u8]) -> Result<usize, rustzx_core::error::IoError> {
        self.0.borrow_mut().extend_from_slice(buf);
        Ok(buf.len())
    }
}

fn save(emu: &mut Emulator<GodotHost>, szx: bool) -> Vec<u8> {
    let buf = Rc::new(RefCell::new(Vec::new()));
    let rec = VecRecorder(buf.clone());
    let recorder = if szx { SnapshotRecorder::Szx(rec) } else { SnapshotRecorder::Sna(rec) };
    emu.save_snapshot(recorder).expect("snapshot save failed");
    let out = buf.borrow().clone();
    out
}

fn ram(emu: &Emulator<GodotHost>) -> Vec<u8> {
    (0x4000u32..=0xFFFF).map(|a| emu.peek(a as u16)).collect()
}

/// A CODE block from a TAP file: load address + payload (without flag/checksum).
struct CodeBlock {
    start: u16,
    data: Vec<u8>,
}

/// Splits a TAP file into its raw blocks (flag byte + payload + checksum).
fn tap_blocks(tap: &[u8]) -> Vec<&[u8]> {
    let mut blocks = Vec::new();
    let mut i = 0;
    while i + 2 <= tap.len() {
        let len = u16::from_le_bytes([tap[i], tap[i + 1]]) as usize;
        blocks.push(&tap[i + 2..i + 2 + len]);
        i += 2 + len;
    }
    blocks
}

/// Every "Bytes:" header (type 3) paired with the data block that follows it.
fn tap_code_blocks(tap: &[u8]) -> Vec<CodeBlock> {
    let blocks = tap_blocks(tap);
    let mut out = Vec::new();
    for pair in blocks.windows(2) {
        let (hdr, data) = (pair[0], pair[1]);
        if hdr.len() == 19 && hdr[0] == 0x00 && hdr[1] == 3 && data[0] == 0xFF {
            let len = u16::from_le_bytes([hdr[12], hdr[13]]) as usize;
            let start = u16::from_le_bytes([hdr[14], hdr[15]]);
            out.push(CodeBlock { start, data: data[1..1 + len].to_vec() });
        }
    }
    out
}

/// Converts a TAP into an equivalent TZX v1.20 (one 0x10 "standard speed" block per TAP block).
fn tap_to_tzx(tap: &[u8]) -> Vec<u8> {
    let mut tzx = Vec::from(TZX_MAGIC);
    tzx.extend_from_slice(&[1, 20]);
    for block in tap_blocks(tap) {
        tzx.push(0x10);
        tzx.extend_from_slice(&1000u16.to_le_bytes()); // pause after block (ms)
        tzx.extend_from_slice(&(block.len() as u16).to_le_bytes());
        tzx.extend_from_slice(block);
    }
    tzx
}

/// True once at least 95% of the bytes of the tape's CODE blocks are in RAM at their load address.
/// Not 100%: once the game starts it draws over its loading screen and rewrites its own
/// variables (znake ends at ~98.9%). Before loading only ~60% match (zeroed RAM).
fn code_blocks_in_memory(emu: &Emulator<GodotHost>, blocks: &[CodeBlock]) -> bool {
    let total: usize = blocks.iter().map(|b| b.data.len()).sum();
    let matching: usize = blocks
        .iter()
        .map(|b| {
            b.data
                .iter()
                .enumerate()
                .filter(|(i, &byte)| emu.peek(b.start.wrapping_add(*i as u16)) == byte)
                .count()
        })
        .sum();
    matching * 100 >= total * 95
}

/// Number of distinct colours on screen; a blank/boot screen has very few.
fn distinct_colours(emu: &Emulator<GodotHost>) -> usize {
    let mut colours: Vec<&[u8]> = emu.screen_buffer().buffer.chunks(3).collect();
    colours.sort();
    colours.dedup();
    colours.len()
}

/// Loads a tape with autoload and waits until all its code is in memory.
fn load_tape_and_wait(machine: ZXMachine, fastload: bool, tape: &[u8], max_seconds: u32) -> (Emulator<GodotHost>, u32) {
    let mut emu = new_emulator(machine, fastload);
    emu.load_tape(formats::tape_from_bytes(tape).0).expect("tape load failed");
    if !fastload {
        // Without fastload nothing presses PLAY for us (in Godot fastload is always on).
        emu.play_tape();
    }
    let blocks = tap_code_blocks(&znake_tap());
    let secs = run_until(&mut emu, max_seconds, |e| code_blocks_in_memory(e, &blocks))
        .unwrap_or_else(|| panic!("{machine:?} fastload={fastload}: game not in memory after {max_seconds}s"));
    (emu, secs)
}

// ---------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------

#[test]
fn detects_formats_by_header() {
    let tap = znake_tap();
    let tzx = tap_to_tzx(&tap);
    assert!(!formats::is_tzx(&tap));
    assert!(formats::is_tzx(&tzx));
    assert!(formats::is_szx(b"ZXST\x01\x04\x01\x00"));
    assert!(!formats::is_szx(&[0u8; 27]));
    assert!(!formats::is_tzx(b""));
}

#[test]
fn tap_to_tzx_keeps_every_block() {
    let tap = znake_tap();
    let tzx = tap_to_tzx(&tap);
    let n = tap_blocks(&tap).len();
    // TZX = 10 header bytes + per block (1 id + 2 pause + 2 len) + same payload bytes.
    assert_eq!(tzx.len(), 10 + tap.len() + n * 3);
    assert_eq!(tap_code_blocks(&tap).len(), 2, "znake has a SCREEN$ and a CODE block");
}

// ---------------------------------------------------------------------------
// Loading games
// ---------------------------------------------------------------------------

#[test]
fn tap_48k_fastload() {
    let (emu, _) = load_tape_and_wait(ZXMachine::Sinclair48K, true, &znake_tap(), 30);
    assert!(distinct_colours(&emu) > 2, "screen looks blank");
}

#[test]
fn tap_128k_fastload() {
    let (emu, _) = load_tape_and_wait(ZXMachine::Sinclair128K, true, &znake_tap(), 30);
    assert!(distinct_colours(&emu) > 2, "screen looks blank");
}

// Standard-speed TZX is converted to TAP, so it gets the instant fastload.
#[test]
fn tzx_48k_fastload() {
    let (emu, _) = load_tape_and_wait(ZXMachine::Sinclair48K, true, &tap_to_tzx(&znake_tap()), 30);
    assert!(distinct_colours(&emu) > 2, "screen looks blank");
}

#[test]
fn tzx_128k_fastload() {
    let (emu, _) = load_tape_and_wait(ZXMachine::Sinclair128K, true, &tap_to_tzx(&znake_tap()), 30);
    assert!(distinct_colours(&emu) > 2, "screen looks blank");
}

/// A TZX that cannot become TAP (here: a turbo block at the start) goes through
/// the fork's real TZX player, in real time (~105 emulated seconds for znake).
#[test]
fn tzx_real_time_playback() {
    let tzx = with_leading_turbo_block(&tap_to_tzx(&znake_tap()));
    assert!(matches!(formats::tape_from_bytes(&tzx).0, Tape::Tzx(_)));
    let (emu, secs) = load_tape_and_wait(ZXMachine::Sinclair48K, true, &tzx, 300);
    assert!(secs > 60, "loaded in {secs}s: was this really real-time?");
    assert!(distinct_colours(&emu) > 2, "screen looks blank");
}

/// Inserts a short 0x11 "turbo" block with ROM timings and a 1-byte payload right
/// after the TZX header. (Not 0 bytes: the fork's player hangs on empty data blocks.)
fn with_leading_turbo_block(tzx: &[u8]) -> Vec<u8> {
    let mut block = vec![0x11];
    for v in [2168u16, 667, 735, 855, 1710, 100] {
        block.extend_from_slice(&v.to_le_bytes()); // pilot, sync1, sync2, bit0, bit1, pilot pulses
    }
    block.push(8); // used bits in last byte
    block.extend_from_slice(&100u16.to_le_bytes()); // pause (ms)
    block.extend_from_slice(&[1, 0, 0]); // data length (24-bit)
    block.push(0x55); // one stray byte: the ROM loader rejects it and waits for the next block
    let mut out = tzx[..10].to_vec();
    out.extend_from_slice(&block);
    out.extend_from_slice(&tzx[10..]);
    out
}

#[test]
fn tzx_to_tap_conversion() {
    let tap = znake_tap();
    let tzx = tap_to_tzx(&tap);
    assert_eq!(formats::tzx_to_tap(&tzx).as_deref(), Some(tap.as_slice()));
    assert!(matches!(formats::tape_from_bytes(&tzx).0, Tape::Tap(_)));

    // Metadata blocks (text 0x30, archive info 0x32, group 0x21/0x22, pause 0x20) are skipped.
    let mut with_info = tzx[..10].to_vec();
    with_info.extend_from_slice(&[0x30, 5]);
    with_info.extend_from_slice(b"hello");
    with_info.extend_from_slice(&[0x32, 4, 0, 1, 0, 1, b'x']);
    with_info.extend_from_slice(&[0x21, 2, b'g', b'1']);
    with_info.extend_from_slice(&tzx[10..]);
    with_info.extend_from_slice(&[0x22, 0x20, 0, 0]);
    assert_eq!(formats::tzx_to_tap(&with_info).as_deref(), Some(tap.as_slice()));

    // Blocks that need real pulses, truncated files and empty tapes are refused.
    assert_eq!(formats::tzx_to_tap(&with_leading_turbo_block(&tzx)), None);
    assert_eq!(formats::tzx_to_tap(&tzx[..tzx.len() - 1]), None);
    assert_eq!(formats::tzx_to_tap(&tzx[..10]), None);
    assert_eq!(formats::tzx_to_tap(&tap), None);
}

/// Real-time loading through the pilot/sync/data pulses (no ROM trap).
#[test]
fn tap_48k_without_fastload() {
    load_tape_and_wait(ZXMachine::Sinclair48K, false, &znake_tap(), 300);
}

// ---------------------------------------------------------------------------
// Snapshots
// ---------------------------------------------------------------------------

/// Appends one SZX block (4-char id + u32 size + data).
fn szx_block(out: &mut Vec<u8>, id: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(id);
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(data);
}

/// Converts a 48K or 128K .SNA into an equivalent .SZX (v1.4).
/// The fork can only *read* SZX, so this is how we get SZX test data.
fn sna_to_szx(sna: &[u8], compress: bool) -> Vec<u8> {
    let h = &sna[..27];
    let is_128k = sna.len() > 49179;

    // RAM banks: (SZX page number, 16K of data). SNA order is bank 5, bank 2, paged bank.
    let mut pages: Vec<(u8, Vec<u8>)> = Vec::new();
    let ram48 = &sna[27..27 + 49152];
    let (pc, sp, port_7ffd);
    if is_128k {
        let ext = &sna[49179..];
        pc = u16::from_le_bytes([ext[0], ext[1]]);
        sp = u16::from_le_bytes([h[23], h[24]]);
        port_7ffd = ext[2];
        let paged = port_7ffd & 7;
        pages.push((5, ram48[..16384].to_vec()));
        pages.push((2, ram48[16384..32768].to_vec()));
        pages.push((paged, ram48[32768..].to_vec()));
        let mut rest = &ext[4..];
        for bank in (0u8..8).filter(|b| ![2, 5, paged].contains(b)) {
            pages.push((bank, rest[..16384].to_vec()));
            rest = &rest[16384..];
        }
    } else {
        // 48K SNA keeps PC on the stack: pop it.
        let sp_raw = u16::from_le_bytes([h[23], h[24]]);
        let at = |addr: u16| ram48[(addr - 0x4000) as usize];
        pc = u16::from_le_bytes([at(sp_raw), at(sp_raw.wrapping_add(1))]);
        sp = sp_raw.wrapping_add(2);
        port_7ffd = 0;
        pages.push((5, ram48[..16384].to_vec()));
        pages.push((2, ram48[16384..32768].to_vec()));
        pages.push((0, ram48[32768..].to_vec()));
    }

    let mut out = Vec::from(SZX_MAGIC);
    out.extend_from_slice(&[1, 4, if is_128k { 2 } else { 1 }, 0]);

    let iff = (h[19] >> 2) & 1;
    let mut z80r = Vec::new();
    for off in [21usize, 13, 11, 9, 7, 5, 3, 1, 17, 15] {
        z80r.extend_from_slice(&h[off..off + 2]); // AF BC DE HL AF' BC' DE' HL' IX IY
    }
    z80r.extend_from_slice(&sp.to_le_bytes());
    z80r.extend_from_slice(&pc.to_le_bytes());
    z80r.extend_from_slice(&[h[0], h[20], iff, iff, h[25]]); // I R IFF1 IFF2 IM
    // dwCyclesStart. The 48K SNA loader pops PC off the stack through the memory bus,
    // which advances the frame clock by ~20-27 T-states (with contention); 128K SNA
    // stores PC in the file and costs nothing. Matching that keeps both loads in lockstep.
    let cycles_start: u32 = if is_128k { 0 } else { 24 };
    z80r.extend_from_slice(&cycles_start.to_le_bytes());
    z80r.extend_from_slice(&[0, 0, 0, 0]); // chHoldIntReqCycles, chFlags, wMemPtr
    szx_block(&mut out, b"Z80R", &z80r);
    szx_block(&mut out, b"SPCR", &[h[26], port_7ffd, 0, h[26], 0, 0, 0, 0]);

    for (page, data) in pages {
        let mut ramp = Vec::new();
        if compress {
            ramp.extend_from_slice(&1u16.to_le_bytes()); // ZXSTRF_COMPRESSED
            ramp.push(page);
            ramp.extend_from_slice(&miniz_oxide::deflate::compress_to_vec_zlib(&data, 6));
        } else {
            ramp.extend_from_slice(&0u16.to_le_bytes());
            ramp.push(page);
            ramp.extend_from_slice(&data);
        }
        szx_block(&mut out, b"RAMP", &ramp);
    }
    out
}

/// A running game saved as SNA, restored into a fresh emulator: RAM must be
/// identical and the game must keep running.
/// (Not frame-exact afterwards: SNA does not store the position inside the frame.)
fn sna_roundtrip(machine: ZXMachine) {
    let (mut original, _) = load_tape_and_wait(machine, true, &znake_tap(), 30);
    run_frames(&mut original, 25);
    let sna = save(&mut original, false);
    assert!(!formats::is_szx(&sna));

    let mut restored = new_emulator(machine, true);
    restored.load_snapshot(formats::snapshot_from_bytes(&sna)).expect("SNA load failed");
    assert!(ram(&original) == ram(&restored), "RAM differs right after restore");

    run_frames(&mut restored, 5 * FRAMES_PER_SECOND);
    assert!(code_blocks_in_memory(&restored, &tap_code_blocks(&znake_tap())), "game vanished from memory");
    assert!(distinct_colours(&restored) > 2, "screen looks blank");
}

#[test]
fn sna_roundtrip_48k() {
    sna_roundtrip(ZXMachine::Sinclair48K);
}

#[test]
fn sna_roundtrip_128k() {
    sna_roundtrip(ZXMachine::Sinclair128K);
}

/// The same machine state loaded once from SNA and once from SZX must then
/// run identically, frame by frame.
fn szx_matches_sna(machine: ZXMachine, compress: bool) {
    let (mut original, _) = load_tape_and_wait(machine, true, &znake_tap(), 30);
    run_frames(&mut original, 25);
    let sna = save(&mut original, false);
    let szx = sna_to_szx(&sna, compress);
    assert!(formats::is_szx(&szx));

    let mut from_sna = new_emulator(machine, true);
    from_sna.load_snapshot(formats::snapshot_from_bytes(&sna)).expect("SNA load failed");
    let mut from_szx = new_emulator(machine, true);
    from_szx.load_snapshot(formats::snapshot_from_bytes(&szx)).expect("SZX load failed");
    assert!(ram(&from_sna) == ram(&from_szx), "RAM differs right after load");

    for second in 1..=3 {
        run_frames(&mut from_sna, FRAMES_PER_SECOND);
        run_frames(&mut from_szx, FRAMES_PER_SECOND);
        assert!(ram(&from_sna) == ram(&from_szx), "RAM diverged after {second}s");
        assert!(
            from_sna.screen_buffer().buffer == from_szx.screen_buffer().buffer,
            "screen diverged after {second}s"
        );
    }
    assert!(distinct_colours(&from_szx) > 2, "screen looks blank");
}

#[test]
fn szx_48k() {
    szx_matches_sna(ZXMachine::Sinclair48K, false);
}

#[test]
fn szx_48k_zlib() {
    szx_matches_sna(ZXMachine::Sinclair48K, true);
}

#[test]
fn szx_128k() {
    szx_matches_sna(ZXMachine::Sinclair128K, false);
}

#[test]
fn szx_128k_zlib() {
    szx_matches_sna(ZXMachine::Sinclair128K, true);
}

#[test]
fn szx_save_is_not_supported_by_the_fork() {
    // If this starts failing, the fork learned to save SZX: we could then use it for save states.
    let mut emu = new_emulator(ZXMachine::Sinclair48K, true);
    let rec = VecRecorder(Rc::new(RefCell::new(Vec::new())));
    assert!(emu.save_snapshot(SnapshotRecorder::Szx(rec)).is_err());
}

// ---------------------------------------------------------------------------
// Every game in GodotProject/games
// ---------------------------------------------------------------------------

/// Smoke test for every game file in the games folder: it must load without
/// errors and show a non-blank screen 20 emulated seconds after the tape stops.
/// Machine is 128K if the file name contains "128", otherwise 48K.
#[test]
fn every_game_in_games_dir_loads() {
    let dir = project_path("GodotProject/games");
    let mut checked = 0;
    for entry in std::fs::read_dir(&dir).unwrap() {
        let path = entry.unwrap().path();
        let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
        if !["tap", "tzx", "sna", "szx"].contains(&ext.as_str()) {
            continue;
        }
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        let machine = if name.contains("128") { ZXMachine::Sinclair128K } else { ZXMachine::Sinclair48K };
        let data = std::fs::read(&path).unwrap();

        let mut emu = new_emulator(machine, true);
        let mut loading_secs = 0;
        if ext == "tap" || ext == "tzx" {
            let (tape, progress) = formats::tape_from_bytes(&data);
            emu.load_tape(tape).unwrap_or_else(|e| panic!("{name}: load failed: {e:?}"));
            loading_secs = run_while_loading(&mut emu, &mut TapeActivity::new(progress), 15 * 60)
                .unwrap_or_else(|| panic!("{name}: tape still loading after 15 emulated minutes"));
        } else {
            emu.load_snapshot(formats::snapshot_from_bytes(&data))
                .unwrap_or_else(|e| panic!("{name}: load failed: {e:?}"));
        }
        run_frames(&mut emu, 20 * FRAMES_PER_SECOND);
        let colours = distinct_colours(&emu);
        assert!(colours > 2, "{name}: screen still blank ({colours} colours)");
        println!("{name}: OK ({machine:?}, tape loading {loading_secs}s emulated, {colours} colours)");
        checked += 1;
    }
    assert!(checked > 0, "no games found in {}", dir.display());
}

// ---------------------------------------------------------------------------
// Turbo loading (tape activity detection)
// ---------------------------------------------------------------------------

/// Runs frame by frame while `TapeActivity` says the tape is loading, i.e. the
/// frames ZXEmulatorCore would run in turbo. Returns emulated seconds spent
/// loading, or None if still loading after `max_seconds`.
fn run_while_loading(emu: &mut Emulator<GodotHost>, activity: &mut TapeActivity, max_seconds: u32) -> Option<u32> {
    // Like in Godot: the first frames run before the tape has been touched.
    run_frames(emu, 10 * FRAMES_PER_SECOND);
    let mut frames = 0;
    while activity.on_frame() {
        run_frames(emu, 1);
        frames += 1;
        if frames > max_seconds * FRAMES_PER_SECOND {
            return None;
        }
    }
    Some(frames / FRAMES_PER_SECOND)
}

/// A real-time TZX must be detected as "loading" for the whole load, and stop
/// being detected once the game is in memory.
#[test]
fn turbo_covers_whole_real_time_load() {
    let tzx = with_leading_turbo_block(&tap_to_tzx(&znake_tap()));
    let (tape, progress) = formats::tape_from_bytes(&tzx);
    let mut emu = new_emulator(ZXMachine::Sinclair48K, true);
    emu.load_tape(tape).unwrap();
    let mut activity = TapeActivity::new(progress);

    let secs = run_while_loading(&mut emu, &mut activity, 300).expect("never stopped loading");
    assert!(secs > 60, "turbo only covered {secs}s of a ~105s load");
    assert!(code_blocks_in_memory(&emu, &tap_code_blocks(&znake_tap())), "turbo stopped before the game loaded");
    run_frames(&mut emu, FRAMES_PER_SECOND);
    assert!(!activity.on_frame(), "turbo came back after loading");
}

/// TAP fastload is instant, so turbo must not kick in for more than a moment
/// (it would make the game start sped up and silent).
#[test]
fn turbo_barely_runs_with_fastload() {
    let (tape, progress) = formats::tape_from_bytes(&znake_tap());
    let mut emu = new_emulator(ZXMachine::Sinclair48K, true);
    emu.load_tape(tape).unwrap();
    let mut activity = TapeActivity::new(progress);
    let mut turbo_frames = 0;
    for _ in 0..30 * FRAMES_PER_SECOND {
        run_frames(&mut emu, 1);
        if activity.on_frame() {
            turbo_frames += 1;
        }
    }
    assert!(code_blocks_in_memory(&emu, &tap_code_blocks(&znake_tap())));
    assert!(turbo_frames < FRAMES_PER_SECOND, "turbo ran for {turbo_frames} frames");
}

/// Turbo turns off when the tape stops moving (e.g. a multi-load game waiting
/// at "press play"), even though it never reached the end.
#[test]
fn turbo_stops_when_tape_stalls() {
    let tzx = with_leading_turbo_block(&tap_to_tzx(&znake_tap()));
    let (tape, progress) = formats::tape_from_bytes(&tzx);
    let mut emu = new_emulator(ZXMachine::Sinclair48K, true);
    emu.load_tape(tape).unwrap();
    let mut activity = TapeActivity::new(progress);
    run_frames(&mut emu, 30 * FRAMES_PER_SECOND);
    assert!(activity.on_frame(), "should be loading 30s into a real-time load");

    emu.stop_tape();
    let mut frames = 0;
    while activity.on_frame() {
        run_frames(&mut emu, 1);
        frames += 1;
        assert!(frames <= IDLE_FRAMES_LIMIT + 1, "turbo did not stop after the tape stalled");
    }
}
