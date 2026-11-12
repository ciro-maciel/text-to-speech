// What gets said: the selection without the marks that are not words. A selection copied from
// Markdown or HTML (a chat answer, a README) carries `**`, `#`, backticks, table pipes, list
// bullets, `[text](url)` and HTML comments; Fish skipped most of them, Phonon reads them
// ("barra", "asterisco"). An HTML comment is not on screen, so it is not read at all.
import Foundation

enum Speakable {
    static func clean(_ text: String) -> String {
        var s = text
        func replace(_ pattern: String, _ template: String, _ options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        replace("<!--[\\s\\S]*?-->", "")                                  // HTML comments, unseen
        replace("^[ \\t]*```[^\\n]*$", "", .anchorsMatchLines)                // code fence lines
        replace("!?\\[([^\\]]*)\\]\\([^)]*\\)", "$1")                     // [text](url) and images
        replace("<[^<>\\n]{1,80}>", " ")                                  // HTML tags
        replace("^[ \\t]*#{1,6}[ \\t]+", "", .anchorsMatchLines)                 // headings
        replace("^[ \\t]*>[ \\t]?", "", .anchorsMatchLines)                      // quotes
        replace("^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+", "", .anchorsMatchLines)     // list bullets and numbers
        replace("^[ \\t]*\\|?[ \\t]*:?-{3,}:?([ \\t]*\\|[ \\t]*:?-{3,}:?)*[ \\t]*\\|?[ \\t]*$", "", .anchorsMatchLines) // table rules
        replace("^[ \\t]*(?:-{3,}|\\*{3,}|_{3,})[ \\t]*$", "", .anchorsMatchLines) // horizontal rules
        replace("[ \\t]*\\|[ \\t]*", ", ")                                      // table cells
        replace("(\\*\\*|__|~~|`)", "")                                    // bold, strike, code marks
        replace("(?<![\\w*])\\*(?=\\S)([^*\\n]+?)\\*(?![\\w*])", "$1")    // *italic*
        replace("^[ \\t,]+|[ \\t,]+$", "", .anchorsMatchLines)              // what a cell or bullet left
        replace("(, ){2,}", ", ")
        replace("\\n{3,}", "\n\n")
        // A heading, a list item or a table row ends without a stop; short lines are read together
        // in one part, so without one the voice ran "Como ficou O colar" into a single breath.
        s = s.components(separatedBy: "\n").map { line in
            guard let last = line.last, !".!?:;…".contains(last) else { return line }
            return line + "."
        }.joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
