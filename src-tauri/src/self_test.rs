//! `text-to-speech --self-test <dir>`: both voices, end to end, with no window.
//!
//! Synthesizes one sentence with Rafael (over the internet, tts.rs) into
//! <dir>/rafael.mp3 and with Piper (on this Mac, piper.rs) into <dir>/piper.wav,
//! downloading the Piper voice into <dir>/voices the first time. It never reads
//! or writes the app's own settings or voices. Exits 0 only when both worked.
//! Run it on the packaged app to check a signed build:
//!
//!   "Text to Speech.app/Contents/MacOS/text-to-speech" --self-test /tmp/tts-check

use std::path::Path;

const SENTENCE: &str = "Olá. Este é o teste de leitura do Text to Speech.";

pub fn run(dir: &Path) -> i32 {
    if let Err(e) = std::fs::create_dir_all(dir) {
        eprintln!("✗ cannot create {}: {e}", dir.display());
        return 1;
    }
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("✗ tokio: {e}");
            return 1;
        }
    };
    let mut failed = 0;

    let server = crate::tts::server(None);
    match runtime.block_on(crate::tts::synthesize(&server, SENTENCE, 1.0)) {
        Ok((audio, words)) => {
            let file = dir.join("rafael.mp3");
            let is_mp3 = audio.starts_with(b"ID3") || (audio.len() > 1 && audio[0] == 0xFF && audio[1] & 0xE0 == 0xE0);
            match std::fs::write(&file, &audio) {
                Ok(()) if is_mp3 => println!("✓ rafael: {} bytes of MP3, {} timed words → {}", audio.len(), words.len(), file.display()),
                Ok(()) => { eprintln!("✗ rafael: the answer is not an MP3"); failed += 1 }
                Err(e) => { eprintln!("✗ rafael: {e}"); failed += 1 }
            }
        }
        Err(e) => {
            eprintln!("✗ rafael ({server}): {e}");
            failed += 1;
        }
    }

    let voice = "pt_BR-faber-medium";
    let piper = runtime
        .block_on(crate::piper::download_voice(dir, voice))
        .and_then(|_| crate::piper::synthesize_wav(dir, voice, SENTENCE, 1.0));
    match piper {
        Ok(wav) if wav.len() > 44 && wav.starts_with(b"RIFF") => {
            let file = dir.join("piper.wav");
            match std::fs::write(&file, &wav) {
                Ok(()) => println!("✓ piper: {} bytes of WAV → {}", wav.len(), file.display()),
                Err(e) => { eprintln!("✗ piper: {e}"); failed += 1 }
            }
        }
        Ok(_) => { eprintln!("✗ piper: empty audio"); failed += 1 }
        Err(e) => { eprintln!("✗ piper: {e}"); failed += 1 }
    }

    if failed == 0 { 0 } else { 1 }
}
