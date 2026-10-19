//! The one permission the app needs on macOS: Accessibility. Reading the
//! selection sends ⌘C to the app in front (selection.rs), and macOS only lets
//! a trusted app do that. The window shows it in the sidebar's status line
//! (15-app-mac.md); clicking it lands on the Accessibility list.

/// Whether the app can read the selection. Other systems have nothing to grant.
pub fn accessibility_granted() -> bool {
    #[cfg(target_os = "macos")]
    {
        mac::is_trusted()
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

/// Puts the app in the Accessibility list (the system's own prompt) and opens
/// that list in System Settings, where the switch is.
pub fn request_accessibility() {
    #[cfg(target_os = "macos")]
    {
        if !mac::prompt() {
            let _ = std::process::Command::new("open")
                .arg("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
                .spawn();
        }
    }
}

#[cfg(target_os = "macos")]
mod mac {
    use core_foundation::base::TCFType;
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::{CFString, CFStringRef};

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
        fn AXIsProcessTrustedWithOptions(options: core_foundation::dictionary::CFDictionaryRef) -> bool;
        static kAXTrustedCheckOptionPrompt: CFStringRef;
    }

    pub fn is_trusted() -> bool {
        unsafe { AXIsProcessTrusted() }
    }

    pub fn prompt() -> bool {
        unsafe {
            let key = CFString::wrap_under_get_rule(kAXTrustedCheckOptionPrompt);
            let options = CFDictionary::from_CFType_pairs(&[(key, CFBoolean::true_value())]);
            AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef())
        }
    }
}
