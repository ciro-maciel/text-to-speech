//! The language of everything the Rust side shows: the menu bar menu and the
//! errors that reach a window. The app follows the Mac's language: Brazilian
//! Portuguese when the first preferred language starts with "pt", English
//! otherwise. The windows ask for the same choice (`ui_language`), so the
//! menu and the windows never disagree (src/i18n.js).
//!
//! Every text is a variant of `Text`, and `pair` matches all of them: a text
//! missing in one language does not compile.

use std::sync::OnceLock;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lang {
    En,
    PtBr,
}

impl Lang {
    pub fn code(self) -> &'static str {
        match self {
            Lang::En => "en",
            Lang::PtBr => "pt-BR",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum Text {
    MenuReadSelection,
    MenuStop,
    MenuOpen,
    MenuQuit,
    InvalidShortcut,
    CannotRegisterShortcut,
    VoiceNoAnswer,
    VoiceNoConnection,
    UnknownVoice,
    VoiceNotDownloaded,
    ModelLoadFailed,
    SynthesisFailed,
    ClipboardFailed,
}

fn pair(text: Text) -> (&'static str, &'static str) {
    match text {
        Text::MenuReadSelection => ("Read Selection", "Ler seleção"),
        Text::MenuStop => ("Stop", "Parar"),
        Text::MenuOpen => ("Open Text to Speech", "Abrir o Text to Speech"),
        Text::MenuQuit => ("Quit Text to Speech", "Sair"),
        Text::InvalidShortcut => ("invalid shortcut", "atalho inválido"),
        Text::CannotRegisterShortcut => ("could not register the shortcut", "não foi possível registrar"),
        Text::VoiceNoAnswer => (
            "The voice didn't answer just now. Try again in a few seconds.",
            "A voz não respondeu agora. Tente de novo em alguns segundos.",
        ),
        Text::VoiceNoConnection => (
            "Can't reach the voice. Check the internet or use Piper, which works offline.",
            "Sem conexão com a voz. Confira a internet ou use a Piper, que funciona sem rede.",
        ),
        Text::UnknownVoice => ("unknown voice", "voz desconhecida"),
        Text::VoiceNotDownloaded => ("voice '{voice}' is not downloaded", "voz '{voice}' não está baixada"),
        Text::ModelLoadFailed => ("could not load the voice model", "falha ao carregar modelo"),
        Text::SynthesisFailed => ("could not make the audio", "falha na síntese"),
        Text::ClipboardFailed => ("could not use the clipboard", "não foi possível usar a área de transferência"),
    }
}

/// The text in the app's language.
pub fn t(text: Text) -> &'static str {
    text_in(lang(), text)
}

pub fn text_in(lang: Lang, text: Text) -> &'static str {
    let (en, pt) = pair(text);
    match lang {
        Lang::En => en,
        Lang::PtBr => pt,
    }
}

/// "pt…" first → Brazilian Portuguese; anything else, or nothing, → English.
pub fn pick(first_language: Option<&str>) -> Lang {
    match first_language {
        Some(l) if l.trim().to_ascii_lowercase().starts_with("pt") => Lang::PtBr,
        _ => Lang::En,
    }
}

/// The app's language, read once from the system.
pub fn lang() -> Lang {
    static LANG: OnceLock<Lang> = OnceLock::new();
    *LANG.get_or_init(|| pick(first_preferred_language().as_deref()))
}

#[cfg(target_os = "macos")]
fn first_preferred_language() -> Option<String> {
    // CFLocaleCopyPreferredLanguages reads AppleLanguages from the app's
    // preferences, so `-AppleLanguages "(en)"` on the command line works too.
    use core_foundation::array::{CFArray, CFArrayRef};
    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFLocaleCopyPreferredLanguages() -> CFArrayRef;
    }
    unsafe {
        let raw = CFLocaleCopyPreferredLanguages();
        if raw.is_null() {
            return None;
        }
        let languages: CFArray<CFString> = CFArray::wrap_under_create_rule(raw);
        let first = languages.get(0).map(|s| s.to_string());
        first
    }
}

#[cfg(not(target_os = "macos"))]
fn first_preferred_language() -> Option<String> {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .find_map(|k| std::env::var(k).ok().filter(|v| !v.is_empty()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn portuguese_only_when_the_first_language_is_portuguese() {
        assert_eq!(pick(Some("pt-BR")), Lang::PtBr);
        assert_eq!(pick(Some("pt-PT")), Lang::PtBr);
        assert_eq!(pick(Some("pt")), Lang::PtBr);
        assert_eq!(pick(Some("en-US")), Lang::En);
        assert_eq!(pick(Some("es-ES")), Lang::En);
        assert_eq!(pick(None), Lang::En);
    }

    #[test]
    fn the_menu_exists_in_both_languages() {
        assert_eq!(text_in(Lang::En, Text::MenuQuit), "Quit Text to Speech");
        assert_eq!(text_in(Lang::PtBr, Text::MenuQuit), "Sair");
        assert_eq!(text_in(Lang::PtBr, Text::MenuReadSelection), "Ler seleção");
    }
}
