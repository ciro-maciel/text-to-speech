use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

fn default_speak_shortcut() -> String {
    "CmdOrCtrl+Shift+KeyS".into()
}
fn default_speed() -> f32 {
    1.0
}
// "rafael": the voice over the internet, through the Text to Speech server
// (tts.rs). "piper": offline, on this Mac (piper.rs). Any other value, such as
// "edge" in a config saved by an older version, is read as "rafael".
fn default_engine() -> String {
    "rafael".into()
}
fn default_piper_voice() -> String {
    "pt_BR-faber-medium".into()
}
fn default_player_position() -> String {
    "center".into()
}
fn default_player_size() -> String {
    "standard".into()
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Config {
    #[serde(default = "default_speak_shortcut")]
    pub speak_shortcut: String,
    #[serde(default = "default_speed")]
    pub speed: f32,
    #[serde(default = "default_engine")]
    pub engine: String,
    #[serde(default = "default_piper_voice")]
    pub piper_voice: String,
    #[serde(default = "default_player_position")]
    pub player_position: String,
    #[serde(default = "default_player_size")]
    pub player_size: String,
    /// Another server for the internet voice (tts.rs). Only set by hand in config.json.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub server_url: Option<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            speak_shortcut: default_speak_shortcut(),
            speed: default_speed(),
            engine: default_engine(),
            piper_voice: default_piper_voice(),
            player_position: default_player_position(),
            player_size: default_player_size(),
            server_url: None,
        }
    }
}

pub fn config_file(base: &Path) -> PathBuf {
    base.join("config.json")
}

pub fn load(base: &Path) -> Config {
    let p = config_file(base);
    let mut cfg: Config = std::fs::read_to_string(&p)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    if cfg.engine != "piper" {
        cfg.engine = default_engine();
    }
    cfg
}

pub fn save(base: &Path, cfg: &Config) -> std::io::Result<()> {
    std::fs::create_dir_all(base)?;
    let p = config_file(base);
    let s = serde_json::to_string_pretty(cfg).unwrap_or_else(|_| "{}".into());
    std::fs::write(p, s)
}
