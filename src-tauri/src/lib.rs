mod config;
mod i18n;
mod permissions;
mod piper;
mod selection;
mod self_test;
mod tts;

use base64::Engine;
use serde::Serialize;
use std::path::PathBuf;
use std::str::FromStr;
use std::sync::Mutex;
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager, WindowEvent,
};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

const CANCEL_SHORTCUT: &str = "Escape";

struct AppState {
    config: Mutex<config::Config>,
    config_dir: PathBuf,
    app_data_dir: PathBuf,
    speak_active: Mutex<bool>,
}

#[derive(Serialize)]
struct SynthResult {
    audio_b64: String,
    mime: &'static str,
    /// When each word is spoken (Rafael only; Piper has none).
    words: Vec<tts::Word>,
}

#[tauri::command]
async fn read_selection() -> Result<String, String> {
    tokio::task::spawn_blocking(selection::read_current_selection)
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn synthesize(
    text: String,
    speed: Option<f32>,
    state: tauri::State<'_, AppState>,
) -> Result<SynthResult, String> {
    let cfg = state.config.lock().map(|c| c.clone()).map_err(|e| e.to_string())?;
    let speed = speed.unwrap_or(cfg.speed);
    let server = tts::server(cfg.server_url.as_deref());
    let (bytes, words) = tts::synthesize(&server, &text, speed.clamp(0.5, 2.0))
        .await
        .map_err(|e| e.to_string())?;

    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Ok(SynthResult {
        audio_b64: b64,
        mime: "audio/mpeg",
        words,
    })
}

#[tauri::command]
fn get_config(state: tauri::State<'_, AppState>) -> Result<config::Config, String> {
    let cfg = state.config.lock().map_err(|e| e.to_string())?;
    Ok(cfg.clone())
}

#[tauri::command]
fn set_speak_shortcut(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
    speak_shortcut: String,
) -> Result<config::Config, String> {
    let new_speak = parse_shortcut(&speak_shortcut)
        .map_err(|e| format!("{}: {}", i18n::t(i18n::Text::InvalidShortcut), e))?;

    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    let old = parse_shortcut(&cfg.speak_shortcut).ok();

    let gs = app.global_shortcut();
    if let Some(s) = &old {
        let _ = gs.unregister(s.clone());
    }

    if let Err(e) = gs.register(new_speak) {
        if let Some(s) = old {
            let _ = gs.register(s);
        }
        return Err(format!("{}: {}", i18n::t(i18n::Text::CannotRegisterShortcut), e));
    }

    cfg.speak_shortcut = speak_shortcut;
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[tauri::command]
fn set_speed(
    state: tauri::State<'_, AppState>,
    speed: f32,
) -> Result<config::Config, String> {
    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    cfg.speed = speed.clamp(0.5, 2.0);
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[derive(Serialize)]
struct PiperVoiceInfo {
    id: &'static str,
    label: &'static str,
    locale: &'static str,
    size_mb: u32,
    ready: bool,
}

#[tauri::command]
fn list_piper_voices(state: tauri::State<'_, AppState>) -> Vec<PiperVoiceInfo> {
    piper::VOICES
        .iter()
        .map(|v| PiperVoiceInfo {
            id: v.id,
            label: v.label,
            locale: v.locale,
            size_mb: v.size_mb,
            ready: piper::voice_is_ready(&state.app_data_dir, v.id),
        })
        .collect()
}

#[tauri::command]
async fn download_piper_voice(
    voice_id: String,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    let dir = state.app_data_dir.clone();
    piper::download_voice(&dir, &voice_id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn synthesize_piper(
    text: String,
    voice: Option<String>,
    speed: Option<f32>,
    state: tauri::State<'_, AppState>,
) -> Result<SynthResult, String> {
    let cfg = state
        .config
        .lock()
        .map(|c| c.clone())
        .map_err(|e| e.to_string())?;
    let voice_id = voice.unwrap_or_else(|| cfg.piper_voice.clone());
    let speed = speed.unwrap_or(cfg.speed);
    let length_scale = if speed > 0.0 { 1.0 / speed } else { 1.0 };
    let dir = state.app_data_dir.clone();

    let bytes = tokio::task::spawn_blocking(move || {
        piper::synthesize_wav(&dir, &voice_id, &text, length_scale)
    })
    .await
    .map_err(|e| e.to_string())?
    .map_err(|e| e.to_string())?;

    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Ok(SynthResult {
        audio_b64: b64,
        mime: "audio/wav",
        words: Vec::new(),
    })
}

#[tauri::command]
fn set_engine(
    state: tauri::State<'_, AppState>,
    engine: String,
) -> Result<config::Config, String> {
    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    cfg.engine = engine;
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[tauri::command]
fn set_piper_voice(
    state: tauri::State<'_, AppState>,
    piper_voice: String,
) -> Result<config::Config, String> {
    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    cfg.piper_voice = piper_voice;
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[tauri::command]
fn set_player_position(
    state: tauri::State<'_, AppState>,
    player_position: String,
) -> Result<config::Config, String> {
    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    cfg.player_position = player_position;
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[tauri::command]
fn set_player_size(
    state: tauri::State<'_, AppState>,
    player_size: String,
) -> Result<config::Config, String> {
    let mut cfg = state.config.lock().map_err(|e| e.to_string())?;
    cfg.player_size = player_size;
    let _ = config::save(&state.config_dir, &cfg);
    Ok(cfg.clone())
}

#[tauri::command]
fn arm_cancel_key(app: AppHandle) -> Result<(), String> {
    let s = parse_shortcut(CANCEL_SHORTCUT).map_err(|e| e.to_string())?;
    let gs = app.global_shortcut();
    if !gs.is_registered(s.clone()) {
        gs.register(s).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn disarm_cancel_key(app: AppHandle) -> Result<(), String> {
    let s = parse_shortcut(CANCEL_SHORTCUT).map_err(|e| e.to_string())?;
    let gs = app.global_shortcut();
    if gs.is_registered(s.clone()) {
        let _ = gs.unregister(s);
    }
    Ok(())
}

#[tauri::command]
fn open_settings(app: AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("settings") {
        w.show().map_err(|e| e.to_string())?;
        w.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

// Opening at login lives in macOS (a LaunchAgent), not in config.json: the system is the
// truth, so a login item removed in System Settings shows up here as off.
#[tauri::command]
fn get_auto_launch(app: AppHandle) -> bool {
    use tauri_plugin_autostart::ManagerExt;
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn set_auto_launch(app: AppHandle, enabled: bool) -> Result<bool, String> {
    use tauri_plugin_autostart::ManagerExt;
    let manager = app.autolaunch();
    if enabled { manager.enable() } else { manager.disable() }.map_err(|e| e.to_string())?;
    Ok(manager.is_enabled().unwrap_or(false))
}

/// The interface language, "en" or "pt-BR": the windows use the same one as the menu bar.
#[tauri::command]
fn ui_language() -> &'static str {
    i18n::lang().code()
}

/// The tab named after `--open-settings`, if the app was launched with it.
#[tauri::command]
fn startup_tab() -> Option<String> {
    open_settings_arg().flatten()
}

/// `--open-settings [tab]`: the settings window opens at launch, on that tab.
/// Used to capture the window in each language (AGENTS.md).
fn open_settings_arg() -> Option<Option<String>> {
    let args: Vec<String> = std::env::args().collect();
    let i = args.iter().position(|a| a == "--open-settings")?;
    Some(args.get(i + 1).filter(|a| !a.starts_with('-')).cloned())
}

#[tauri::command]
fn accessibility_granted() -> bool {
    permissions::accessibility_granted()
}

#[tauri::command]
fn request_accessibility() {
    permissions::request_accessibility();
}

fn parse_shortcut(s: &str) -> Result<Shortcut, String> {
    Shortcut::from_str(s).map_err(|e| e.to_string())
}

fn trigger_speak(app: &AppHandle) {
    let _ = app.emit("tts://speak-selection", ());
}

fn trigger_stop(app: &AppHandle) {
    let _ = app.emit("tts://stop-speaking", ());
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(i) = args.iter().position(|a| a == "--self-test") {
        let dir = args.get(i + 1).map(PathBuf::from).unwrap_or_else(|| std::env::temp_dir().join("text-to-speech-self-test"));
        std::process::exit(self_test::run(&dir));
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec![]),
        ))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    let state = app.state::<AppState>();
                    let cfg = match state.config.lock() {
                        Ok(c) => c.clone(),
                        Err(_) => return,
                    };
                    let speak = parse_shortcut(&cfg.speak_shortcut).ok();
                    let cancel = parse_shortcut(CANCEL_SHORTCUT).ok();

                    if Some(shortcut) == cancel.as_ref() {
                        if event.state() == ShortcutState::Pressed {
                            if let Ok(mut active) = state.speak_active.lock() {
                                *active = false;
                            }
                            trigger_stop(app);
                        }
                        return;
                    }

                    if Some(shortcut) != speak.as_ref() {
                        return;
                    }
                    let mut active = match state.speak_active.lock() {
                        Ok(a) => a,
                        Err(_) => return,
                    };
                    match event.state() {
                        ShortcutState::Pressed => {
                            if !*active {
                                *active = true;
                                trigger_speak(app);
                            }
                        }
                        ShortcutState::Released => {
                            *active = false;
                        }
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            read_selection,
            synthesize,
            synthesize_piper,
            get_config,
            set_speak_shortcut,
            set_speed,
            set_engine,
            set_piper_voice,
            set_player_position,
            set_player_size,
            list_piper_voices,
            download_piper_voice,
            open_settings,
            accessibility_granted,
            request_accessibility,
            get_auto_launch,
            set_auto_launch,
            arm_cancel_key,
            disarm_cancel_key,
            ui_language,
            startup_tab
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            {
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            let config_dir = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("text-to-speech"));
            let app_data_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| config_dir.clone());
            let cfg = config::load(&config_dir);

            app.manage(AppState {
                config: Mutex::new(cfg.clone()),
                config_dir: config_dir.clone(),
                app_data_dir: app_data_dir.clone(),
                speak_active: Mutex::new(false),
            });

            let speak_item = MenuItem::with_id(
                app,
                "speak",
                i18n::t(i18n::Text::MenuReadSelection),
                true,
                Some(cfg.speak_shortcut.as_str()),
            )?;
            let stop_item =
                MenuItem::with_id(app, "stop", i18n::t(i18n::Text::MenuStop), true, None::<&str>)?;
            let settings_item =
                MenuItem::with_id(app, "settings", i18n::t(i18n::Text::MenuOpen), true, Some("CmdOrCtrl+,"))?;
            let sep1 = PredefinedMenuItem::separator(app)?;
            let sep2 = PredefinedMenuItem::separator(app)?;
            let quit_item = MenuItem::with_id(app, "quit", i18n::t(i18n::Text::MenuQuit), true, None::<&str>)?;
            let menu = Menu::with_items(
                app,
                &[&speak_item, &stop_item, &sep1, &settings_item, &sep2, &quit_item],
            )?;

            let tray_icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray-icon@2x.png"))
                .unwrap_or_else(|_| app.default_window_icon().cloned().unwrap());
            let mut tray_builder = TrayIconBuilder::with_id("main")
                .tooltip("Text to Speech")
                .icon(tray_icon)
                .menu(&menu)
                .show_menu_on_left_click(true);

            #[cfg(target_os = "macos")]
            {
                tray_builder = tray_builder.icon_as_template(true);
            }

            let _tray = tray_builder
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "speak" => trigger_speak(app),
                    "stop" => trigger_stop(app),
                    "settings" => {
                        if let Some(w) = app.get_webview_window("settings") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            let gs = app.global_shortcut();
            if let Ok(s) = parse_shortcut(&cfg.speak_shortcut) {
                let _ = gs.register(s);
            }

            if open_settings_arg().is_some() {
                if let Some(w) = app.get_webview_window("settings") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }

            for label in ["main", "settings"] {
                if let Some(window) = app.get_webview_window(label) {
                    let w = window.clone();
                    window.on_window_event(move |event| {
                        if let WindowEvent::CloseRequested { api, .. } = event {
                            api.prevent_close();
                            let _ = w.hide();
                        }
                    });
                }
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
