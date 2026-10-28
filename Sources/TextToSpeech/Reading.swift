// The reading's pure logic, ported rule for rule from the Tauri build's src/reading.js (its
// tests are reading.test.js; scripts/check.sh runs both on the same texts and compares): how a
// selection becomes parts, which word is being spoken, and the clock.
import Foundation

enum Reading {
    /// A paragraph longer than this many words is divided at its sentences.
    static let paragraphMax = 80
    /// The first part: the first sentence if it has up to 12 words.
    static let firstPartMax = 12
    /// Then whole sentences, up to 25 words, then up to 45 (Ciro, 16/10/2026).
    static let startRamp = [25, 45]

    private static let clauseEnd = try! NSRegularExpression(pattern: "[,;:—)]$")
    private static let lineEndsSentence = try! NSRegularExpression(pattern: "[.!?…:;][\"'”’»)\\]]*$")
    private static let startsUpper = try! NSRegularExpression(pattern: "^[\"'“‘«(\\[—–-]*[A-ZÀ-ÖØ-Þ0-9]")
    private static let titleEnd = try! NSRegularExpression(pattern: "[,\\-–—]$")
    private static let sentenceSplit = try! NSRegularExpression(pattern: "(?<=[.!?…])\\s+")

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Sentences of a paragraph: split after . ! ? … followed by space.
    private static func sentences(_ paragraph: String) -> [String] {
        var out: [String] = []
        var last = paragraph.startIndex
        for m in sentenceSplit.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
            guard let r = Range(m.range, in: paragraph) else { continue }
            out.append(String(paragraph[last..<r.lowerBound]))
            last = r.upperBound
        }
        out.append(String(paragraph[last...]))
        return out
    }

    /// Where to cut a sentence longer than `limit` words: after the last comma-like mark that
    /// leaves at least `shortest` words, or at the limit.
    private static func cutAt(_ words: [String], _ limit: Int, _ shortest: Int) -> Int {
        var i = limit
        while i >= shortest {
            if i - 1 < words.count, matches(clauseEnd, words[i - 1]) { return i }
            i -= 1
        }
        return limit
    }

    /// Each paragraph read whole; short ones in a row go together, up to `max` words, each on its
    /// own line. A longer paragraph is divided at sentence ends into pieces of about the same
    /// size; a single sentence longer than `max` is cut at its last comma.
    static func splitIntoParagraphs(_ text: String, max: Int = paragraphMax) -> [String] {
        var parts: [String] = []
        var packed: [String] = []
        var packedWords = 0
        func flushPacked() {
            if !packed.isEmpty { parts.append(packed.joined(separator: "\n")) }
            packed = []
            packedWords = 0
        }
        let paragraphs = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for paragraph in paragraphs {
            let total = words(paragraph).count
            if total <= max {
                if packedWords + total > max { flushPacked() }
                packed.append(paragraph)
                packedWords += total
                continue
            }
            flushPacked()
            var pieces: [[String]] = []
            for sentence in sentences(paragraph) {
                var w = words(sentence)
                while w.count > max {
                    let cut = cutAt(w, max, Int((Double(max) / 2).rounded(.up)))
                    pieces.append(Array(w[0..<cut]))
                    w = Array(w[cut...])
                }
                if !w.isEmpty { pieces.append(w) }
            }
            let target = Int((Double(total) / (Double(total) / Double(max)).rounded(.up)).rounded(.up))
            var current: [String] = []
            for sentence in pieces {
                if !current.isEmpty && (current.count + sentence.count > max || current.count >= target) {
                    parts.append(current.joined(separator: " "))
                    current = []
                }
                current += sentence
            }
            if !current.isEmpty { parts.append(current.joined(separator: " ")) }
        }
        flushPacked()
        return parts
    }

    private static func firstClause(_ words: [String]) -> Int {
        if words.count <= firstPartMax { return words.count }
        for i in 5...firstPartMax where matches(clauseEnd, words[i - 1]) { return i }
        if words.count <= 20 { return words.count }
        for i in (firstPartMax + 1)...20 where matches(clauseEnd, words[i - 1]) { return i }
        return firstPartMax
    }

    /// A text copied from a PDF breaks its lines in the middle of sentences. A line joins the
    /// next unless it ends a sentence, or it is a short line, like a title, followed by one that
    /// starts with a capital.
    static func unwrapLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var out = ""
        for i in lines.indices {
            let line = lines[i]
            if line.isEmpty {
                if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                continue
            }
            out += line
            guard i + 1 < lines.count else { break }
            let next = lines[i + 1]
            let isTitle = words(line).count <= 6 && matches(startsUpper, next) && !matches(titleEnd, line)
            out += next.isEmpty || matches(lineEndsSentence, line) || isTitle ? "\n" : " "
        }
        while out.contains("\n\n") { out = out.replacingOccurrences(of: "\n\n", with: "\n") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The selection → parts in reading order: a short first part so the voice starts in seconds,
    /// then whole sentences up to 25 and 45 words, then whole paragraphs.
    static func split(_ text: String, max: Int = paragraphMax) -> [String] {
        struct Sentence { var words: [String]; var ends: Bool }
        var list: [Sentence] = []
        for paragraph in unwrapLines(text).components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !paragraph.isEmpty {
            let own = sentences(paragraph).map { words($0) }.filter { !$0.isEmpty }
            for (i, w) in own.enumerated() { list.append(Sentence(words: w, ends: i == own.count - 1)) }
        }
        guard !list.isEmpty else { return [] }
        func join(_ part: [Sentence]) -> String {
            part.enumerated().map { i, x in x.words.joined(separator: " ") + (i < part.count - 1 ? (x.ends ? "\n" : " ") : "") }.joined()
        }
        let head = list.removeFirst()
        let cut = firstClause(head.words)
        var parts = [head.words[0..<cut].joined(separator: " ")]
        if cut < head.words.count { list.insert(Sentence(words: Array(head.words[cut...]), ends: head.ends), at: 0) }
        for limit in startRamp {
            guard !list.isEmpty else { break }
            var part: [Sentence] = []
            var size = 0
            while !list.isEmpty && (part.isEmpty || size + list[0].words.count <= limit) {
                let next = list.removeFirst()
                part.append(next)
                size += next.words.count
            }
            parts += size > max ? splitIntoParagraphs(join(part), max: max) : [join(part)]
        }
        var rest: [String] = []
        var paragraph: [String] = []
        for x in list {
            paragraph.append(x.words.joined(separator: " "))
            if x.ends {
                rest.append(paragraph.joined(separator: " "))
                paragraph = []
            }
        }
        if !paragraph.isEmpty { rest.append(paragraph.joined(separator: " ")) }
        return parts + splitIntoParagraphs(rest.joined(separator: "\n"), max: max)
    }

    // MARK: - Words and time

    struct Word: Equatable { let text: String; let start: Double }

    private static func letters(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    /// The part's own words, each with the second it starts. With Fish's timings the words are
    /// matched in order by their letters ("tomá-la." is Fish's "tomá" and "la"); past the last
    /// one matched, the start is the word's place in the text times the audio's length.
    static func wordTimes(_ text: String, spoken: [(text: String, start: Double)], duration: Double) -> [Word] {
        let tokens = words(text)
        let total = Double(max(1, tokens.reduce(0) { $0 + $1.utf16.count + 1 }))
        var offset = 0.0, j = 0, last = 0.0
        return tokens.map { token in
            let estimate = offset / total * duration
            offset += Double(token.utf16.count + 1)
            let target = letters(token)
            var start: Double
            if !target.isEmpty && j < spoken.count {
                start = spoken[j].start
                var heard = ""
                while j < spoken.count && heard.count < target.count { heard += letters(spoken[j].text); j += 1 }
            } else if target.isEmpty {
                start = last
            } else {
                start = Swift.max(estimate, last)
            }
            last = Swift.max(start, last)
            return Word(text: token, start: last)
        }
    }

    static func wordsSpoken(_ times: [Word], at seconds: Double) -> Int {
        var n = 0
        while n < times.count && times[n].start <= seconds { n += 1 }
        return n
    }

    static func clock(_ seconds: Double) -> String {
        let s = Swift.max(0, Int(seconds.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
