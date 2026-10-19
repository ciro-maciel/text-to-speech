use anyhow::{anyhow, Result};
use piper_rs::Piper;
use serde::Serialize;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Clone, Serialize)]
pub struct PiperVoiceMeta {
    pub id: &'static str,
    pub label: &'static str,
    pub locale: &'static str,
    pub onnx_url: &'static str,
    pub config_url: &'static str,
    pub size_mb: u32,
}

pub const VOICES: &[PiperVoiceMeta] = &[PiperVoiceMeta {
    id: "pt_BR-faber-medium",
    label: "Faber · pt-BR (Piper, ~63MB)",
    locale: "pt-BR",
    onnx_url: "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx",
    config_url: "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx.json",
    size_mb: 63,
}];

pub fn voice_meta(id: &str) -> Option<&'static PiperVoiceMeta> {
    VOICES.iter().find(|v| v.id == id)
}

pub fn voices_dir(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join("voices")
}

pub fn voice_paths(app_data_dir: &Path, id: &str) -> (PathBuf, PathBuf) {
    let dir = voices_dir(app_data_dir);
    (dir.join(format!("{id}.onnx")), dir.join(format!("{id}.onnx.json")))
}

pub fn voice_is_ready(app_data_dir: &Path, id: &str) -> bool {
    let (onnx, config) = voice_paths(app_data_dir, id);
    onnx.exists() && config.exists()
}

pub async fn download_voice(app_data_dir: &Path, id: &str) -> Result<()> {
    let meta =
        voice_meta(id).ok_or_else(|| anyhow!("voz desconhecida: {id}"))?;
    let dir = voices_dir(app_data_dir);
    std::fs::create_dir_all(&dir)?;
    let (onnx_path, config_path) = voice_paths(app_data_dir, id);

    let client = reqwest::Client::builder()
        .user_agent("text-to-speech/0.1")
        .build()?;

    if !config_path.exists() {
        let resp = client.get(meta.config_url).send().await?.error_for_status()?;
        let bytes = resp.bytes().await?;
        std::fs::write(&config_path, &bytes)?;
    }

    if !onnx_path.exists() {
        let resp = client.get(meta.onnx_url).send().await?.error_for_status()?;
        let bytes = resp.bytes().await?;
        std::fs::write(&onnx_path, &bytes)?;
    }

    Ok(())
}

pub fn synthesize_wav(
    app_data_dir: &Path,
    voice_id: &str,
    text: &str,
    length_scale: f32,
) -> Result<Vec<u8>> {
    let (onnx_path, config_path) = voice_paths(app_data_dir, voice_id);
    if !onnx_path.exists() || !config_path.exists() {
        return Err(anyhow!("voz '{voice_id}' não está baixada"));
    }

    let mut piper = Piper::new(&onnx_path, &config_path)
        .map_err(|e| anyhow!("falha ao carregar modelo: {e}"))?;

    let (samples, sample_rate) = piper
        .create(text, false, None, Some(length_scale), None, None)
        .map_err(|e| anyhow!("falha na síntese: {e}"))?;

    let samples_i16: Vec<i16> = samples
        .iter()
        .map(|&s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16)
        .collect();

    let wav = encode_wav(&samples_i16, sample_rate, 1);
    Ok(wav)
}

fn encode_wav(samples: &[i16], sample_rate: u32, channels: u16) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let byte_rate = sample_rate * channels as u32 * 2;
    let mut buf: Vec<u8> = Vec::with_capacity(44 + samples.len() * 2);
    buf.extend_from_slice(b"RIFF");
    buf.extend_from_slice(&(36 + data_len).to_le_bytes());
    buf.extend_from_slice(b"WAVE");
    buf.extend_from_slice(b"fmt ");
    buf.extend_from_slice(&16u32.to_le_bytes());
    buf.extend_from_slice(&1u16.to_le_bytes()); // PCM
    buf.extend_from_slice(&channels.to_le_bytes());
    buf.extend_from_slice(&sample_rate.to_le_bytes());
    buf.extend_from_slice(&byte_rate.to_le_bytes());
    buf.extend_from_slice(&(channels * 2).to_le_bytes());
    buf.extend_from_slice(&16u16.to_le_bytes());
    buf.extend_from_slice(b"data");
    buf.extend_from_slice(&data_len.to_le_bytes());
    for s in samples {
        let _ = buf.write_all(&s.to_le_bytes());
    }
    buf
}
