import { test, expect } from 'bun:test'
import { readFileSync } from 'node:fs'
import { STRINGS, formatSpeed, pickLanguage, setLanguage, t } from './i18n.js'

test('every key exists in English and in Brazilian Portuguese, none empty', () => {
    const en = Object.keys(STRINGS.en).sort()
    const pt = Object.keys(STRINGS['pt-BR']).sort()
    expect(pt).toEqual(en)
    for (const lang of ['en', 'pt-BR']) {
        for (const [key, text] of Object.entries(STRINGS[lang])) expect(`${key}:${text.trim().length > 0}`).toBe(`${key}:true`)
    }
})

test('every key the windows use exists', () => {
    const used = new Set()
    for (const file of ['index.html', 'settings.html']) {
        const html = readFileSync(new URL(file, import.meta.url), 'utf8')
        for (const m of html.matchAll(/data-i18n(?:-aria|-title)?="([^"]+)"/g)) used.add(m[1])
    }
    for (const file of ['main.js', 'settings.js']) {
        const js = readFileSync(new URL(file, import.meta.url), 'utf8')
        for (const m of js.matchAll(/\bt\('([^']+)'/g)) used.add(m[1])
    }
    expect(used.size).toBeGreaterThan(30)
    expect([...used].filter(key => !(key in STRINGS.en))).toEqual([])
})

test('Portuguese only when the first language is Portuguese', () => {
    expect(pickLanguage(['pt-BR', 'en-US'])).toBe('pt-BR')
    expect(pickLanguage(['pt-PT'])).toBe('pt-BR')
    expect(pickLanguage(['en-US', 'pt-BR'])).toBe('en')
    expect(pickLanguage(['fr'])).toBe('en')
    expect(pickLanguage([])).toBe('en')
})

test('a missing key falls back to English, never to the key name', () => {
    setLanguage('pt-BR')
    const saved = STRINGS['pt-BR'].nothingSelected
    delete STRINGS['pt-BR'].nothingSelected
    expect(t('nothingSelected')).toBe('Nothing selected')
    STRINGS['pt-BR'].nothingSelected = saved
    expect(t('nothingSelected')).toBe('Nada selecionado')
    expect(t('partOf', { n: 2, total: 5 })).toBe('trecho 2 de 5')
    setLanguage('en')
    expect(t('partOf', { n: 2, total: 5 })).toBe('part 2 of 5')
})

test('the speed follows the language: a point in English, a comma in Portuguese', () => {
    setLanguage('en')
    expect(formatSpeed(1.25)).toBe('1.25×')
    setLanguage('pt-BR')
    expect(formatSpeed(1)).toBe('1,00×')
    setLanguage('en')
})
