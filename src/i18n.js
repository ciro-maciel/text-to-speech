// The interface in English and Brazilian Portuguese. The app follows the Mac's language:
// Brazilian Portuguese when the first preferred language starts with "pt", English
// otherwise. The Rust side decides (i18n.rs, `ui_language`), so the menu bar, the
// errors and the windows always agree; navigator.languages is only the fallback.
// A key missing in Portuguese falls back to English. Every key exists in both
// (i18n.test.js checks it).
//
// The voices are not translated: Rafael and Piper both speak Brazilian Portuguese.

export const STRINGS = {
    en: {
        // Player
        reading: 'Reading',
        paused: 'Paused',
        preparing: 'Preparing',
        engineInternet: 'Internet',
        keySpace: 'Space',
        keyResume: 'resume',
        keyPart: 'part',
        partOf: 'part {n} of {total}',
        clockOf: '{elapsed} of {total}',
        partFailed: "Couldn't play this part. Try again.",
        needsAccessibility: 'Turn on Accessibility for Text to Speech',
        nothingSelected: 'Nothing selected',

        // Settings: sidebar
        sections: 'Sections',
        groupReading: 'Reading',
        groupSettings: 'Settings',
        tabShortcut: 'Shortcut',
        tabVoice: 'Voice',
        tabPlayer: 'Player',
        tabSystem: 'System',
        accessibilityOn: 'Accessibility on',
        accessibilityOff: 'Accessibility off',
        accessibilityOpen: 'Open Accessibility in System Settings',
        version: 'Version {version} · by Ciro Cesar Maciel',

        // Settings: Shortcut
        shortcutTitle: 'Shortcut',
        shortcutSub: 'Select text in any app and press the shortcut to hear it. Esc stops the reading midway.',
        readSelection: 'Read the selection',
        shortcutHint: 'Click the shortcut and press the new combination: ⌘ ⌃ ⌥ ⇧ plus one key.',
        readSelectionAria: 'Shortcut to read the selection',
        resetShortcut: 'Default',
        stopReading: 'Stop reading',
        stopReadingHint: 'Works while the player is open.',
        pressCombination: 'Press the combination…',
        shortcutSaved: 'Shortcut saved',

        // Settings: Voice
        voiceTitle: 'Voice',
        voiceSub: 'Both voices speak Brazilian Portuguese. Rafael is the most natural, over the internet: the text goes through the tool\'s server and Fish Audio. Piper runs on this computer, with no network.',
        testVoice: 'Hear the voice',
        stopTest: 'Stop',
        engine: 'Engine',
        engineHint: 'Rafael: the most natural voice, needs the internet. Piper: offline, the text never leaves this computer.',
        piperVoice: 'Voice',
        piperVoiceAria: 'Piper voice',
        download: 'Download',
        speed: 'Speed',
        speedHint: '{speed} is the voice\'s natural pace.',
        notDownloaded: '{label} (not downloaded)',
        downloading: 'Downloading {size} MB…',
        onThisComputer: 'On this computer · {size} MB',
        notDownloadedYet: 'Not downloaded yet · {size} MB',
        engineSaved: 'Engine: {engine}',
        voiceSaved: 'Voice saved',
        voiceDownloaded: 'Voice downloaded',

        // Settings: Player
        playerTitle: 'Player',
        playerSub: 'Where the reading strip appears when you press the shortcut, and how big, always 24 points from the edge of the screen.',
        position: 'Position on screen',
        positionAria: 'Player position',
        size: 'Size',
        positionSaved: 'Position: {position}',
        sizeSaved: 'Size: {size}',
        'pos.top-left': 'Top left',
        'pos.top-center': 'Top center',
        'pos.top-right': 'Top right',
        'pos.middle-left': 'Middle left',
        'pos.center': 'Center',
        'pos.middle-right': 'Middle right',
        'pos.bottom-left': 'Bottom left',
        'pos.bottom-center': 'Bottom center',
        'pos.bottom-right': 'Bottom right',
        'size.compact': 'Compact',
        'size.standard': 'Standard',
        'size.spacious': 'Spacious',

        // Settings: System
        systemTitle: 'System',
        systemSub: 'How the app fits in with your Mac.',
        openAtLogin: 'Open at login',
        openAtLoginHint: 'Stays in the menu bar, ready for the shortcut, without you opening it.',
        opensAtLogin: 'Opens at login',
        noLongerOpensAtLogin: 'No longer opens at login',

        error: 'Error: {error}',
    },
    'pt-BR': {
        reading: 'Lendo',
        paused: 'Pausado',
        preparing: 'Preparando',
        engineInternet: 'Internet',
        keySpace: 'Espaço',
        keyResume: 'continuar',
        keyPart: 'trecho',
        partOf: 'trecho {n} de {total}',
        clockOf: '{elapsed} de {total}',
        partFailed: 'Não foi possível tocar este trecho. Tente de novo.',
        needsAccessibility: 'Falta ligar a Acessibilidade para o Text to Speech',
        nothingSelected: 'Nada selecionado',

        sections: 'Seções',
        groupReading: 'Leitura',
        groupSettings: 'Ajustes',
        tabShortcut: 'Atalho',
        tabVoice: 'Voz',
        tabPlayer: 'Player',
        tabSystem: 'Sistema',
        accessibilityOn: 'Acessibilidade ligada',
        accessibilityOff: 'Acessibilidade desligada',
        accessibilityOpen: 'Abrir a Acessibilidade nos Ajustes do Sistema',
        version: 'Versão {version} · por Ciro Cesar Maciel',

        shortcutTitle: 'Atalho',
        shortcutSub: 'Selecione um texto em qualquer app e aperte o atalho para ouvir. Esc para a leitura no meio.',
        readSelection: 'Ler a seleção',
        shortcutHint: 'Clique no atalho e aperte a combinação nova: ⌘ ⌃ ⌥ ⇧ mais uma tecla.',
        readSelectionAria: 'Atalho para ler a seleção',
        resetShortcut: 'Padrão',
        stopReading: 'Parar a leitura',
        stopReadingHint: 'Vale enquanto o player está aberto.',
        pressCombination: 'Aperte a combinação…',
        shortcutSaved: 'Atalho salvo',

        voiceTitle: 'Voz',
        voiceSub: 'O Rafael é uma voz natural em português do Brasil, pela internet: o texto passa pelo servidor da ferramenta e pelo Fish Audio. O Piper roda neste computador, sem rede.',
        testVoice: 'Ouvir a voz',
        stopTest: 'Parar',
        engine: 'Motor',
        engineHint: 'Rafael: a voz mais natural, precisa de internet. Piper: offline, o texto não sai do computador.',
        piperVoice: 'Voz',
        piperVoiceAria: 'Voz do Piper',
        download: 'Baixar',
        speed: 'Velocidade',
        speedHint: '{speed} é o ritmo natural da voz.',
        notDownloaded: '{label} (não baixada)',
        downloading: 'Baixando {size} MB…',
        onThisComputer: 'Neste computador · {size} MB',
        notDownloadedYet: 'Ainda não baixada · {size} MB',
        engineSaved: 'Motor: {engine}',
        voiceSaved: 'Voz salva',
        voiceDownloaded: 'Voz baixada',

        playerTitle: 'Player',
        playerSub: 'Onde a faixa de leitura aparece quando você aperta o atalho, e de que tamanho, sempre a 24 pontos da borda da tela.',
        position: 'Posição na tela',
        positionAria: 'Posição do player',
        size: 'Tamanho',
        positionSaved: 'Posição: {position}',
        sizeSaved: 'Tamanho: {size}',
        'pos.top-left': 'Superior esquerdo',
        'pos.top-center': 'Superior centro',
        'pos.top-right': 'Superior direito',
        'pos.middle-left': 'Centro esquerdo',
        'pos.center': 'Centro',
        'pos.middle-right': 'Centro direito',
        'pos.bottom-left': 'Inferior esquerdo',
        'pos.bottom-center': 'Inferior centro',
        'pos.bottom-right': 'Inferior direito',
        'size.compact': 'Compacto',
        'size.standard': 'Padrão',
        'size.spacious': 'Espaçoso',

        systemTitle: 'Sistema',
        systemSub: 'Como o app convive com o Mac.',
        openAtLogin: 'Abrir ao iniciar o Mac',
        openAtLoginHint: 'Fica na barra de menus, pronto para o atalho, sem você abrir.',
        opensAtLogin: 'Abre ao iniciar o Mac',
        noLongerOpensAtLogin: 'Não abre mais ao iniciar o Mac',

        error: 'Erro: {error}',
    },
}

/** "pt-BR" when the first language starts with "pt", "en" for anything else. */
export function pickLanguage(languages) {
    const first = String((languages && languages[0]) || '').toLowerCase()
    return first.startsWith('pt') ? 'pt-BR' : 'en'
}

let current = 'en'

export const language = () => current

export function setLanguage(lang) {
    current = lang === 'pt-BR' ? 'pt-BR' : 'en'
    if (typeof document !== 'undefined') document.documentElement.lang = current
}

/** The text for a key in the current language, with {name} filled from vars. English when the key is missing. */
export function t(key, vars = {}) {
    const text = STRINGS[current]?.[key] ?? STRINGS.en[key] ?? ''
    return text.replace(/\{(\w+)\}/g, (_, name) => (name in vars ? String(vars[name]) : `{${name}}`))
}

/** 1.25 → "1.25×" in English, "1,25×" in Portuguese. */
export function formatSpeed(speed) {
    const n = Number(speed || 1)
    return `${new Intl.NumberFormat(current, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)}×`
}

/** Asks the app for its language (the same one the menu bar uses); the browser's languages if that fails. */
export async function initLanguage(invoke) {
    let lang = null
    try { lang = await invoke('ui_language') } catch {}
    setLanguage(lang || pickLanguage(typeof navigator !== 'undefined' ? navigator.languages : []))
    return current
}

/**
 * Fills the page: data-i18n sets the text (only the first text node when the
 * element has children, such as a row label with its <small>), data-i18n-aria
 * the aria-label, data-i18n-title the title.
 */
export function applyTranslations(root = document) {
    root.querySelectorAll('[data-i18n]').forEach(node => {
        const text = t(node.dataset.i18n)
        if (node.children.length === 0) {
            node.textContent = text
            return
        }
        const textNode = [...node.childNodes].find(c => c.nodeType === 3 && c.textContent.trim())
        if (textNode) textNode.textContent = text
        else node.insertBefore(document.createTextNode(text), node.firstChild)
    })
    root.querySelectorAll('[data-i18n-aria]').forEach(node => node.setAttribute('aria-label', t(node.dataset.i18nAria)))
    root.querySelectorAll('[data-i18n-title]').forEach(node => node.setAttribute('title', t(node.dataset.i18nTitle)))
}
