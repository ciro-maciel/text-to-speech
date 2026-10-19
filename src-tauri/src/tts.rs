use anyhow::{anyhow, Result};
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// The voice over the internet is Rafael, from Fish Audio, through the Text to
// Speech server: the same call the page at ciromaciel.click/tools/text-to-speech
// makes. The app never holds a Fish Audio key: the server does. What goes over
// the network is the text of the part being read and the speed, nothing else.
// `speak-timed` answers the MP3 and when each word is spoken, for the
// word-by-word highlight.
//
// `server_url` in config.json, or the TEXT_TO_SPEECH_SERVER environment
// variable, points the app at another server that answers the same route
// (README, "Use your own server").
pub const DEFAULT_SERVER: &str = "https://manager.ciromaciel.click/text-to-speech";
// A sentence takes a few seconds; the server may also queue it behind other
// people's parts and retry Fish, so the wait is generous.
const TIMEOUT: Duration = Duration::from_secs(120);
const FALLBACK_ERROR: &str = "A voz não respondeu agora. Tente de novo em alguns segundos.";

/// A spoken word and when, in seconds of its part's audio.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Word {
    pub text: String,
    pub start: f32,
    pub end: f32,
}

#[derive(Deserialize)]
struct Timed {
    audio: String,
    #[serde(default)]
    words: Vec<Word>,
}

/// The server to call: the environment variable, then config.json, then the default.
pub fn server(configured: Option<&str>) -> String {
    std::env::var("TEXT_TO_SPEECH_SERVER")
        .ok()
        .or_else(|| configured.map(str::to_string))
        .map(|s| s.trim().trim_end_matches('/').to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_SERVER.to_string())
}

pub async fn synthesize(server: &str, text: &str, speed: f32) -> Result<(Vec<u8>, Vec<Word>)> {
    let client = reqwest::Client::builder().timeout(TIMEOUT).build()?;
    let response = client
        .post(format!("{server}/speak-timed"))
        .json(&serde_json::json!({ "text": text, "speed": speed }))
        .send()
        .await
        .map_err(|_| anyhow!("Sem conexão com a voz. Confira a internet ou use a Piper, que funciona sem rede."))?;

    if !response.status().is_success() {
        // The server writes its errors for people ({ "error": "…" }); anything else gets the generic one.
        let message = response
            .json::<serde_json::Value>()
            .await
            .ok()
            .and_then(|body| body.get("error").and_then(|e| e.as_str()).map(str::to_string))
            .unwrap_or_else(|| FALLBACK_ERROR.to_string());
        return Err(anyhow!(message));
    }

    let timed: Timed = response.json().await.map_err(|_| anyhow!(FALLBACK_ERROR))?;
    let audio = base64::engine::general_purpose::STANDARD
        .decode(timed.audio)
        .map_err(|_| anyhow!(FALLBACK_ERROR))?;
    if audio.is_empty() {
        return Err(anyhow!(FALLBACK_ERROR));
    }
    Ok((audio, timed.words))
}
