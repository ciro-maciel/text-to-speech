import { applyTranslations, formatSpeed, initLanguage, t } from './i18n.js'

const { invoke } = window.__TAURI__.core

const DEFAULT_SHORTCUT = 'CmdOrCtrl+Shift+KeyS'
// Both voices speak Brazilian Portuguese, so the sample stays in Portuguese in every language.
const TEST_TEXT = 'Olá, esta é uma demonstração da minha voz.'

const state = {
    config: null,
    piperVoices: [],
    recording: false,
    downloading: false,
    activeTab: 'shortcut',
    testAudio: null,
}

const el = id => document.getElementById(id)

const positionName = pos => t(`pos.${pos}`) || pos
const SIZE_DIMS = { compact: '320 × 200', standard: '380 × 240', spacious: '460 × 280' }
const sizeName = size => t(`size.${size}`) || size
const speedLabel = v => formatSpeed(v)

/* The sidebar's status line (15-app-mac.md): Accessibility is what lets the app
   copy the selection. Off, it turns red, and a click goes straight to the list
   in System Settings; it rechecks while the window is open. */
let accessibilityTimer = null
async function renderAccessibility() {
    let on = true
    try { on = await invoke('accessibility_granted') } catch { return }
    const line = el('status-line')
    if (!line) return
    line.hidden = !isMac()
    line.classList.toggle('off', !on)
    line.querySelector('use').setAttribute('href', `icons.svg#${on ? 'check' : 'lock'}`)
    line.querySelector('span').textContent = on ? t('accessibilityOn') : t('accessibilityOff')
    line.title = on ? '' : t('accessibilityOpen')
}
function watchAccessibility() {
    renderAccessibility()
    clearInterval(accessibilityTimer)
    accessibilityTimer = setInterval(() => {
        if (document.visibilityState === 'visible') renderAccessibility()
    }, 1500)
}

/* The sidebar signature, exactly as 15-app-mac.md asks: the package version, nowhere else. */
async function showVersion() {
    try {
        const version = await window.__TAURI__.app.getVersion()
        el('version').textContent = t('version', { version })
    } catch {}
}

/* ─── Tabs ─────────────────────────────────────────────────────────── */
function activateTab(name) {
    if (name === 'appearance') name = 'player'  // the tab's name before 10/10/2026
    if (!document.querySelector(`.pane[data-tab="${name}"]`)) name = 'shortcut'
    state.activeTab = name
    document.querySelectorAll('.groups button[data-tab]').forEach(b => {
        b.setAttribute('aria-pressed', String(b.dataset.tab === name))
    })
    document.querySelectorAll('.pane').forEach(t => {
        t.hidden = t.dataset.tab !== name
    })
    try { localStorage.setItem('tts.activeTab', name) } catch {}
}

/* ─── Shortcut formatting ──────────────────────────────────────────── */
function isMac() { return navigator.platform.toLowerCase().includes('mac') }

function symbolize(part) {
    if (!isMac()) return part
    return part
        .replace(/^Cmd$/i, '⌘')
        .replace(/^Command$/i, '⌘')
        .replace(/^CmdOrCtrl$/i, '⌘')
        .replace(/^CommandOrControl$/i, '⌘')
        .replace(/^Ctrl$/i, '⌃')
        .replace(/^Control$/i, '⌃')
        .replace(/^Alt$/i, '⌥')
        .replace(/^Option$/i, '⌥')
        .replace(/^Shift$/i, '⇧')
}

function prettyKey(part) {
    if (part.startsWith('Key')) return part.slice(3)
    if (part.startsWith('Digit')) return part.slice(5)
    return part
}

function format(combo) {
    if (!combo) return ''
    return combo
        .split('+')
        .map(p => p.trim())
        .filter(Boolean)
        .map(p => prettyKey(symbolize(p)))
        .join(isMac() ? ' ' : '+')
}

function captureFromEvent(e) {
    if (['Control', 'Shift', 'Alt', 'Meta', 'Hyper', 'Super'].includes(e.key)) return null
    const mods = []
    if (e.metaKey) mods.push('Cmd')
    if (e.ctrlKey) mods.push('Ctrl')
    if (e.altKey) mods.push('Alt')
    if (e.shiftKey) mods.push('Shift')
    if (mods.length === 0) return null
    if (!e.code) return null
    return [...mods, e.code].join('+')
}

/* ─── Status toast ─────────────────────────────────────────────────── */
let statusTimer = null
function setStatus(msg, kind) {
    const s = el('status')
    if (!s) return
    s.textContent = msg || ''
    s.className = 'toast' + (kind ? ' ' + kind : '')
    if (msg) s.classList.add('show')
    if (statusTimer) clearTimeout(statusTimer)
    if (msg) {
        statusTimer = setTimeout(() => s.classList.remove('show'), 2000)
    }
}

/* ─── Voice population ─────────────────────────────────────────────── */
function populatePiperVoices() {
    const sel = el('piper-voice')
    sel.innerHTML = ''
    for (const v of state.piperVoices) {
        const opt = document.createElement('option')
        opt.value = v.id
        opt.textContent = v.ready ? v.label : t('notDownloaded', { label: v.label })
        sel.appendChild(opt)
    }
    if (state.config?.piper_voice) sel.value = state.config.piper_voice
}

/* ─── Engine cards ─────────────────────────────────────────────────── */
function reflectEngineCards() {
    const eng = state.config?.engine || 'rafael'
    document.querySelectorAll('[data-engine]').forEach(c => {
        c.setAttribute('aria-pressed', String(c.dataset.engine === eng))
    })
    el('piper-voice-field').hidden = eng !== 'piper'
    if (eng === 'piper') updatePiperStatus()
}

function currentPiperVoiceMeta() {
    const id = el('piper-voice').value
    return state.piperVoices.find(v => v.id === id)
}

function updatePiperStatus() {
    const meta = currentPiperVoiceMeta()
    const status = el('piper-status')
    const dl = el('piper-download')
    if (!meta) {
        status.textContent = ''
        dl.hidden = true
        return
    }
    if (state.downloading) {
        status.textContent = t('downloading', { size: meta.size_mb })
        dl.hidden = true
        return
    }
    if (meta.ready) {
        status.textContent = t('onThisComputer', { size: meta.size_mb })
        dl.hidden = true
    } else {
        status.textContent = t('notDownloadedYet', { size: meta.size_mb })
        dl.hidden = false
    }
}

/* ─── Position picker ──────────────────────────────────────────────── */
function reflectPosition() {
    const pos = state.config?.player_position || 'center'
    document.querySelectorAll('#position-grid button').forEach(b => {
        b.setAttribute('aria-pressed', String(b.dataset.pos === pos))
    })
    const lbl = el('position-label')
    if (lbl) lbl.textContent = positionName(pos)
}

/* ─── Size picker ──────────────────────────────────────────────────── */
function reflectSize() {
    const size = state.config?.player_size || 'standard'
    document.querySelectorAll('[data-size]').forEach(c => {
        c.setAttribute('aria-pressed', String(c.dataset.size === size))
    })
    const lbl = el('size-label')
    if (lbl) lbl.textContent = SIZE_DIMS[size] ? `${sizeName(size)} · ${SIZE_DIMS[size]}` : ''
}

/* ─── Reflect all config ───────────────────────────────────────────── */
function reflectConfig() {
    if (!state.config) return
    el('speak-input').value = format(state.config.speak_shortcut)
    el('speed').value = String(state.config.speed)
    el('speed-value').textContent = speedLabel(state.config.speed)
    populatePiperVoices()
    reflectEngineCards()
    reflectPosition()
    reflectSize()
}

/* ─── Shortcut recording ───────────────────────────────────────────── */
function startRecording() {
    state.recording = true
    const input = el('speak-input')
    input.classList.add('recording')
    input.classList.remove('error')
    input.value = t('pressCombination')
}

function stopRecording() {
    if (!state.recording) return
    state.recording = false
    el('speak-input').classList.remove('recording')
    if (state.config) el('speak-input').value = format(state.config.speak_shortcut)
}

async function saveShortcut(combo) {
    try {
        state.config = await invoke('set_speak_shortcut', { speakShortcut: combo })
        reflectConfig()
        setStatus(t('shortcutSaved'), 'ok')
    } catch (err) {
        const input = el('speak-input')
        input.classList.add('error')
        setTimeout(() => input.classList.remove('error'), 1500)
        setStatus(String(err), 'err')
        reflectConfig()
    }
}

async function saveEngine(engine) {
    try {
        state.config = await invoke('set_engine', { engine })
        reflectEngineCards()
        setStatus(t('engineSaved', { engine: engine === 'piper' ? 'Piper' : 'Rafael' }), 'ok')
    } catch (err) {
        setStatus(String(err), 'err')
    }
}

async function savePiperVoice(voice) {
    try {
        state.config = await invoke('set_piper_voice', { piperVoice: voice })
        updatePiperStatus()
        setStatus(t('voiceSaved'), 'ok')
    } catch (err) {
        setStatus(String(err), 'err')
    }
}

async function saveSpeed(speed) {
    try {
        state.config = await invoke('set_speed', { speed })
    } catch (err) {
        setStatus(String(err), 'err')
    }
}

async function savePosition(position) {
    try {
        state.config = await invoke('set_player_position', { playerPosition: position })
        reflectPosition()
        setStatus(t('positionSaved', { position: positionName(position).toLowerCase() }), 'ok')
    } catch (err) {
        setStatus(String(err), 'err')
    }
}

async function saveSize(size) {
    try {
        state.config = await invoke('set_player_size', { playerSize: size })
        reflectSize()
        setStatus(t('sizeSaved', { size: sizeName(size).toLowerCase() }), 'ok')
    } catch (err) {
        setStatus(String(err), 'err')
    }
}

async function refreshPiperVoices() {
    try {
        state.piperVoices = await invoke('list_piper_voices')
        populatePiperVoices()
        updatePiperStatus()
    } catch (err) {
        console.error(err)
    }
}

async function downloadPiper() {
    const meta = currentPiperVoiceMeta()
    if (!meta) return
    state.downloading = true
    updatePiperStatus()
    try {
        await invoke('download_piper_voice', { voiceId: meta.id })
        setStatus(t('voiceDownloaded'), 'ok')
    } catch (err) {
        setStatus(t('error', { error: err }), 'err')
    } finally {
        state.downloading = false
        await refreshPiperVoices()
    }
}

/* ─── Voice testing ────────────────────────────────────────────────── */
function base64ToBytes(b64) {
    const bin = atob(b64)
    const out = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
    return out
}

function stopTest() {
    if (state.testAudio) {
        try { state.testAudio.pause() } catch {}
        state.testAudio = null
    }
    setTestButtonPlaying(false)
}

function setTestButtonPlaying(playing) {
    const lbl = el('test-label')
    const icon = el('test-icon')
    if (lbl) lbl.textContent = playing ? t('stopTest') : t('testVoice')
    if (icon) icon.setAttribute('href', `icons.svg#${playing ? 'player-stop' : 'player-play'}`)
}

async function testVoice(piper = false) {
    if (state.testAudio) {
        stopTest()
        return
    }
    const cfg = state.config
    if (!cfg) return
    const text = TEST_TEXT
    setTestButtonPlaying(true)
    try {
        let result
        if (piper) {
            result = await invoke('synthesize_piper', { text, voice: cfg.piper_voice, speed: cfg.speed })
        } else {
            result = await invoke('synthesize', { text, speed: cfg.speed })
        }
        const bytes = base64ToBytes(result.audio_b64)
        const blob = new Blob([bytes], { type: result.mime })
        const url = URL.createObjectURL(blob)
        const audio = new Audio(url)
        state.testAudio = audio
        audio.addEventListener('ended', () => {
            URL.revokeObjectURL(url)
            stopTest()
        })
        await audio.play()
    } catch (err) {
        setStatus(String(err), 'err')
        stopTest()
    }
}

/* ─── Keyboard ─────────────────────────────────────────────────────── */
function onKeyDown(e) {
    if (!state.recording) return
    if (e.key === 'Escape') {
        e.preventDefault()
        stopRecording()
        return
    }
    e.preventDefault()
    const combo = captureFromEvent(e)
    if (!combo) return
    state.recording = false
    el('speak-input').classList.remove('recording')
    el('speak-input').value = format(combo)
    saveShortcut(combo)
}

async function renderAutoLaunch() {
    try {
        el('auto-launch').setAttribute('aria-checked', String(await invoke('get_auto_launch')))
    } catch {}
}

async function toggleAutoLaunch() {
    const next = el('auto-launch').getAttribute('aria-checked') !== 'true'
    try {
        const isOn = await invoke('set_auto_launch', { enabled: next })
        el('auto-launch').setAttribute('aria-checked', String(isOn))
        setStatus(isOn ? t('opensAtLogin') : t('noLongerOpensAtLogin'), 'ok')
    } catch (err) {
        setStatus(t('error', { error: err }), 'err')
    }
}

/* ─── Load ─────────────────────────────────────────────────────────── */
async function load() {
    try {
        state.config = await invoke('get_config')
        await refreshPiperVoices()
        reflectConfig()
    } catch (err) {
        setStatus(t('error', { error: err }), 'err')
    }
}

function bind() {
    // Tabs
    document.querySelectorAll('.groups button[data-tab]').forEach(b => {
        b.addEventListener('click', () => activateTab(b.dataset.tab))
    })

    // Shortcut
    el('speak-input').addEventListener('click', startRecording)
    el('reset-shortcut').addEventListener('click', () => saveShortcut(DEFAULT_SHORTCUT))

    // Engine cards
    document.querySelectorAll('[data-engine]').forEach(c => {
        c.addEventListener('click', () => saveEngine(c.dataset.engine))
    })

    // Voice
    el('piper-voice').addEventListener('change', e => savePiperVoice(e.target.value))
    el('test-voice').addEventListener('click', () => testVoice(state.config?.engine === 'piper'))
    el('piper-download').addEventListener('click', downloadPiper)

    // Speed
    el('speed').addEventListener('input', e => {
        const v = parseFloat(e.target.value)
        el('speed-value').textContent = speedLabel(v)
    })
    el('speed').addEventListener('change', e => saveSpeed(parseFloat(e.target.value)))

    // Position picker
    document.querySelectorAll('#position-grid button').forEach(b => {
        b.addEventListener('click', () => savePosition(b.dataset.pos))
    })

    // Size picker
    document.querySelectorAll('[data-size]').forEach(c => {
        c.addEventListener('click', () => saveSize(c.dataset.size))
    })

    // System
    el('auto-launch').addEventListener('click', toggleAutoLaunch)

    // Keyboard
    window.addEventListener('keydown', onKeyDown, true)
    window.addEventListener('blur', stopRecording)
}

window.addEventListener('DOMContentLoaded', async () => {
    await initLanguage(invoke)
    applyTranslations()
    el('speed-hint').textContent = t('speedHint', { speed: formatSpeed(1) })
    setTestButtonPlaying(false)
    bind()
    let saved = null
    try { saved = localStorage.getItem('tts.activeTab') } catch {}
    if (saved) activateTab(saved)
    invoke('startup_tab').then(tab => { if (tab) activateTab(tab) }).catch(() => {})
    showVersion()
    watchAccessibility()
    el('status-line').addEventListener('click', () => {
        if (el('status-line').classList.contains('off')) invoke('request_accessibility')
    })
    window.addEventListener('focus', renderAccessibility)
    window.addEventListener('focus', renderAutoLaunch)
    renderAutoLaunch()
    load()
})
