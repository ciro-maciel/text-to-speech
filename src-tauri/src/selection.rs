use anyhow::{anyhow, Result};
use arboard::Clipboard;
use std::process::Command;
use std::thread;
use std::time::Duration;

#[cfg(target_os = "macos")]
fn simulate_copy() -> Result<()> {
    let status = Command::new("osascript")
        .arg("-e")
        .arg("tell application \"System Events\" to keystroke \"c\" using command down")
        .status()?;
    if !status.success() {
        return Err(anyhow!(
            "osascript failed (status {:?}) — Accessibility permission required",
            status.code()
        ));
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn simulate_copy() -> Result<()> {
    Err(anyhow!("simulate_copy not implemented for this OS yet"))
}

pub fn read_current_selection() -> Result<String> {
    let mut clipboard = Clipboard::new().map_err(|e| anyhow!("clipboard init failed: {e}"))?;

    let previous = clipboard.get_text().ok();
    let sentinel = format!("__tts_sentinel_{}", random_token());
    clipboard
        .set_text(&sentinel)
        .map_err(|e| anyhow!("clipboard write failed: {e}"))?;

    simulate_copy()?;

    let mut text = String::new();
    let started = std::time::Instant::now();
    loop {
        thread::sleep(Duration::from_millis(40));
        match clipboard.get_text() {
            Ok(t) if t != sentinel => {
                text = t;
                break;
            }
            _ => {}
        }
        if started.elapsed() > Duration::from_millis(800) {
            break;
        }
    }

    if let Some(prev) = previous {
        let _ = clipboard.set_text(prev);
    }

    let trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        return Err(anyhow!("no text selected"));
    }
    Ok(trimmed)
}

fn random_token() -> String {
    use rand::RngCore;
    let mut buf = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut buf);
    hex::encode(buf)
}
