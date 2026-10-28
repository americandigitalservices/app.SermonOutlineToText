import Foundation

//
//  TypographyAndWrapping.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

/// Handles smart title-casing, CotEditor typography cleanup rules, and heuristic line wrapping.
nonisolated enum TypographyAndWrapping {

    static let slideBreakMarker = "__SLIDE_BREAK__"

    /// All bullet/list characters including middle dot (· \u{00B7}) from Word/Gmail
    static let leadingBulletPattern = "^\\h*[•·∙‣◦⁃\\-_–—*>»▪▫~+]+\\h*"

    static let danglingEndWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with", "from",
        "into", "unto", "upon", "about", "as", "is", "are", "was", "were", "be",
        "has", "have", "had", "will", "shall", "may", "can", "who", "whom", "whose",
        "which", "that", "this", "these", "those", "his", "her", "their", "our", "your",
        "my", "its", "so", "very", "too", "not", "no", "every", "all", "both", "each"
    ]

    static let clauseStarters: Set<String> = [
        "and", "but", "or", "nor", "for", "yet", "so", "because", "since", "although",
        "though", "while", "where", "when", "whenever", "wherever", "whether", "if",
        "unless", "until", "before", "after", "that", "which", "who", "whom", "whose",
        "what", "whatever", "how", "whereby", "therefore", "thus", "hence", "let",
        "looking", "despising", "ignoring", "bringing", "giving", "removing", "exchanging",
        "trading", "soaring", "running", "walking", "symbolizing", "allowing"
    ]

    private static let preservedUppercaseTokens: Set<String> = [
        "II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII",
        "OT", "NT", "KJV", "NKJV", "ESV", "NIV", "NLT", "NASB", "CSB", "AMP", "AMPC"
    ]

    // MARK: - Smart Title Case

    /// Formats a title or heading in Title Case while preserving contractions (e.g. "God's"),
    /// dotted acronyms (e.g. "L.I.S.T.E.N."), and Roman numerals/acronyms (e.g. "Part II").
    static func smartTitleCase(_ input: String) -> String {
        let words = input.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return "" }

        return words.map { wordSub -> String in
            let rawWord = String(wordSub)
            let strippedPunct = rawWord.trimmingCharacters(in: .punctuationCharacters).uppercased()
            if preservedUppercaseTokens.contains(strippedPunct) {
                return rawWord.uppercased()
            }
            // Preserve dotted acronyms such as "L.I.S.T.E.N." or "U.S.A."
            if RegexCache.firstMatch(rawWord, pattern: "^(?:[A-Za-z]\\.){2,}[A-Za-z]?\\.?$", caseInsensitive: false) != nil {
                return rawWord.uppercased()
            }
            // Capitalize the first letter of each hyphenated segment while lowercasing the rest
            // (including letters after apostrophes like "God's").
            return rawWord.split(separator: "-", omittingEmptySubsequences: false).map { segment -> String in
                var result = ""
                var capitalizedFirstLetter = false
                for ch in segment {
                    if !capitalizedFirstLetter && ch.isLetter {
                        result.append(contentsOf: ch.uppercased())
                        capitalizedFirstLetter = true
                    } else {
                        result.append(contentsOf: ch.lowercased())
                    }
                }
                return result
            }.joined(separator: "-")
        }.joined(separator: " ")
    }

    // MARK: - Typography & CotEditor Rules

    static func cleanBasicTypography(_ input: String) -> String {
        if input == slideBreakMarker { return slideBreakMarker }
        var text = input
        // 1. CotEditor rule: Strip zero-width spaces, joiners, BOM, and soft hyphens
        text = RegexCache.replace(text, pattern: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}\\u{00AD}]", template: "")
        // 2. Non-breaking spaces, Unicode line/paragraph separators, and tabs to normal spaces
        text = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        // 3. Smart quotes to straight quotes
        text = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        text = text.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        // 4. Remove any asterisks first so "* · Text" or "· *Text" exposes the leading bullet
        text = text.replacingOccurrences(of: "*", with: "")
        // 5. CotEditor rule: Strip leading bullets (including middle dot · \u{00B7}), hyphens, dashes, arrows, and list markers
        text = RegexCache.replace(text, pattern: leadingBulletPattern, template: "")
        // 6. Strip BibleGateway footnote markers like [a], [b] (even when attached to words like way[b] or commas like land,[c])
        text = RegexCache.replace(text, pattern: "\\[[a-zA-Z]\\]", template: "")
        // 7. Normalize number ranges with em/en dashes (e.g., 1—3 -> 1-3)
        text = RegexCache.replace(text, pattern: "(?<=\\d)\\s*[—–]\\s*(?=\\d)", template: "-")
        // 8. Normalize remaining em/en dashes to spaced hyphens ( - )
        text = RegexCache.replace(text, pattern: "\\s*[—–]\\s*", template: " - ")
        // 9. Fix missing space after sentence-ending punctuation while preserving dotted acronyms (e.g. L.I.S.T.E.N.)
        text = RegexCache.replace(text, pattern: "(?<!\\.)(?<!\\b[A-Z])\\.([A-Z\\[])", template: ". $1")
        text = RegexCache.replace(text, pattern: "([?!;])([A-Z\\[])", template: "$1 $2")
        text = RegexCache.replace(text, pattern: "(?<!\\.)([.?!;][\"')\\]]*)(\\d+\\s+[A-Z\\[\"])", template: "$1 $2")
        text = RegexCache.replace(text, pattern: "([a-z\\]])([A-Z])", template: "$1 $2")
        // 10. Collapse multiple horizontal spaces
        text = RegexCache.replace(text, pattern: "\\h{2,}", template: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the exact CotEditor AppleScript regex cleanup pass on every final output line
    static func applyFinalCotEditorCleanup(_ lines: [String]) -> [String] {
        var cleanedLines: [String] = []
        cleanedLines.reserveCapacity(lines.count)
        for rawLine in lines {
            var line = rawLine
            // 1. Strip zero-width spaces, joiners, BOM, soft hyphens
            line = RegexCache.replace(line, pattern: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}\\u{00AD}]", template: "")
            // 2. Smart double and single quotes
            line = line.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            line = line.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            // 3. Non-breaking spaces to normal spaces
            line = line.replacingOccurrences(of: "\u{00A0}", with: " ")
            // 4. Leading bullets/hyphens/markers (^\h*[\•\·\-\_\–\—\*\>\»\▪\~\+]+\h*)
            line = RegexCache.replace(line, pattern: leadingBulletPattern, template: "")
            // 5. Trailing colons or semicolons ((:|;)\h*$)
            line = RegexCache.replace(line, pattern: "[:;]\\h*$", template: "")
            // 6. Collapse multiple horizontal spaces (\h\h+ -> " ")
            line = RegexCache.replace(line, pattern: "\\h{2,}", template: " ")
            // 7. Trim leading and trailing horizontal whitespace (^\h+|\h+$)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if !line.isEmpty {
                cleanedLines.append(line)
            }
        }
        return cleanedLines
    }

    static func cleanVerseBody(_ input: String) -> String {
        var body = RegexCache.replace(input, pattern: "(?<=[.?!;:,\"\\]])\\s+(\\d{1,3})[.)]?\\s+(?=[A-Z\\[\"“])", template: " ($1) ")
        body = RegexCache.replace(body, pattern: "^\\d{1,3}[.)]?\\s+(?=[A-Z\\[\"“])", template: "")
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        let quoteCount = body.filter { $0 == "\"" }.count
        if quoteCount == 1 {
            if body.hasSuffix("\"") && !body.hasPrefix("\"") {
                body = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
            } else if !body.hasSuffix("\""), RegexCache.firstMatch(body, pattern: "[.?!]$") != nil {
                body += "\""
            }
        } else if quoteCount % 2 == 1 && !body.hasSuffix("\""), RegexCache.firstMatch(body, pattern: "[.?!]$") != nil {
            body += "\""
        }
        return body
    }

    static func formatTopicLine(_ input: String) -> String {
        var text = RegexCache.replace(input, pattern: leadingBulletPattern, template: "")
        text = RegexCache.replace(text, pattern: "[:;]\\h*$", template: "").trimmingCharacters(in: .whitespaces)

        if text == text.uppercased() && text.count > 3 {
            text = smartTitleCase(text)
        } else if let colonIdx = text.firstIndex(of: ":") {
            let prefix = String(text[..<colonIdx])
            let rest = String(text[text.index(after: colonIdx)...])
            if prefix == prefix.uppercased() && prefix.count > 3 {
                text = "\(smartTitleCase(prefix)):\(rest)"
            }
        }
        return text
    }

    // MARK: - Smart Line Wrapping

    static func tokenizePreservingBrackets(_ text: String, maxLen: Int) -> [String] {
        var tokens: [String] = []
        let chars = Array(text)
        let n = chars.count
        let maxAtomicLen = min(45, max(28, Int(Double(maxLen) * 0.52)))
        var i = 0

        while i < n {
            while i < n && chars[i].isWhitespace { i += 1 }
            if i >= n { break }

            if chars[i] == "(" || chars[i] == "[" {
                let closeChar: Character = (chars[i] == "(") ? ")" : "]"
                if let closeIdx = chars[i..<n].firstIndex(of: closeChar) {
                    var endIdx = closeIdx + 1
                    while endIdx < n && !chars[endIdx].isWhitespace { endIdx += 1 }
                    let bracketToken = String(chars[i..<endIdx])
                    if bracketToken.count <= maxAtomicLen {
                        tokens.append(bracketToken)
                        i = endIdx
                        continue
                    }
                }
            }

            var endIdx = i
            while endIdx < n && !chars[endIdx].isWhitespace { endIdx += 1 }
            tokens.append(String(chars[i..<endIdx]))
            i = endIdx
        }
        return tokens
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c == "'"
    }

    private static func extractLastAlphaWord(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let prev = text.index(before: end)
            if isWordCharacter(text[prev]) { break }
            end = prev
        }
        var start = end
        while start > text.startIndex {
            let prev = text.index(before: start)
            if !isWordCharacter(text[prev]) { break }
            start = prev
        }
        return text[start..<end].lowercased()
    }

    private static func extractFirstAlphaWord(_ text: String) -> String {
        var start = text.startIndex
        while start < text.endIndex && !isWordCharacter(text[start]) {
            start = text.index(after: start)
        }
        var end = start
        while end < text.endIndex && isWordCharacter(text[end]) {
            end = text.index(after: end)
        }
        return text[start..<end].lowercased()
    }

    static func scoreSplitPoint(left: String, right: String, maxLen: Int) -> Double {
        var score = 0.0
        let leftLen = left.count
        let rightLen = right.count

        let fillRatio = Double(leftLen) / Double(maxLen)
        if fillRatio >= 0.55 {
            score += fillRatio * 25.0
        } else {
            score -= (0.55 - fillRatio) * 60.0
        }

        if rightLen <= maxLen && Double(rightLen) < Double(maxLen) * 0.30 {
            score -= 45.0
        } else if rightLen > maxLen && Double(rightLen) < Double(maxLen) * 1.25 {
            score -= 20.0
        }

        if [".", "!", "?", ".\"", "!\"", "?\""].contains(where: { left.hasSuffix($0) }) {
            score += 55.0
        } else if [";", ":"].contains(where: { left.hasSuffix($0) }) {
            score += 48.0
        } else if [",", ",\"", "],", "),"].contains(where: { left.hasSuffix($0) }) {
            score += 38.0
        } else if ["]", ")"].contains(where: { left.hasSuffix($0) }) {
            score += 32.0
        }

        let lastWord = extractLastAlphaWord(left)
        let firstWord = extractFirstAlphaWord(right)

        if danglingEndWords.contains(lastWord) && ![",", ";", ".", "]", ")"].contains(where: { left.hasSuffix($0) }) {
            score -= 45.0
        }

        if right.hasPrefix("[") {
            score += 22.0
        } else if right.hasPrefix("(") && fillRatio >= 0.72 {
            score += 12.0
        } else if right.hasPrefix("- ") {
            score += 35.0
        } else if clauseStarters.contains(firstWord) {
            if firstWord == "and" || firstWord == "or" {
                let nextWords = right.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).prefix(3).map { $0.lowercased() }
                let strongFollow: Set<String> = ["let", "that", "is", "was", "shall", "will", "he", "we", "they", "do", "to", "not", "nothing", "over", "refreshment"]
                if nextWords.count >= 2 && strongFollow.contains(nextWords[1]) {
                    score += 28.0
                } else {
                    score += 10.0
                }
            } else {
                score += 24.0
            }
        }
        return score
    }

    static func smartWrapText(_ input: String, maxLen: Int) -> [String] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }
        if text.count <= maxLen { return [text] }

        var tokens = tokenizePreservingBrackets(text, maxLen: maxLen)
        var lines: [String] = []

        while !tokens.isEmpty {
            let remaining = tokens.joined(separator: " ")
            if remaining.count <= maxLen {
                lines.append(remaining)
                break
            }

            var bestIdx = 1
            var bestScore = -9999.0
            var runningLeftLen = 0

            for i in 1..<tokens.count {
                runningLeftLen += (i == 1 ? tokens[0].count : 1 + tokens[i - 1].count)
                if runningLeftLen > maxLen { break }

                let left = tokens[..<i].joined(separator: " ")
                let right = tokens[i...].joined(separator: " ")
                let sc = scoreSplitPoint(left: left, right: right, maxLen: maxLen)
                if sc >= bestScore {
                    bestScore = sc
                    bestIdx = i
                }
            }

            let firstCandidate = tokens[..<bestIdx].joined(separator: " ")
            if firstCandidate.count > maxLen {
                var rawWords = remaining.split(separator: " ").map(String.init)
                var cur: [String] = []
                while let firstWord = rawWords.first, (cur + [firstWord]).joined(separator: " ").count <= maxLen {
                    cur.append(rawWords.removeFirst())
                }
                if cur.isEmpty, !rawWords.isEmpty {
                    cur.append(rawWords.removeFirst())
                }
                lines.append(cur.joined(separator: " "))
                tokens = tokenizePreservingBrackets(rawWords.joined(separator: " "), maxLen: maxLen)
                continue
            }

            let cleanedLine = RegexCache.replace(firstCandidate, pattern: "[ \\-]+$", template: "")
            lines.append(cleanedLine)
            tokens = Array(tokens[bestIdx...])
            if tokens.first == "-" { tokens.removeFirst() }
        }

        return lines
    }

    static func splitPlainLine(_ text: String, maxLen: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        if let match = RegexCache.firstMatch(trimmed, pattern: "^([^\\x00-\\x7F].*?)\\.\\.\\.([a-zA-Z'].*?)\\.\\.\\.(\".*)$") {
            var res: [String] = []
            res.append(contentsOf: smartWrapText(match[1], maxLen: maxLen))
            res.append(contentsOf: smartWrapText("...\(match[2].trimmingCharacters(in: .whitespaces))...", maxLen: maxLen))
            res.append(contentsOf: smartWrapText(match[3], maxLen: maxLen))
            return res
        }

        return smartWrapText(trimmed, maxLen: maxLen)
    }

    static func splitLongVerse(refPrefix: String, body: String, maxTotalLen: Int) -> [String] {
        let cleanedBody = cleanVerseBody(body)
        let fullPrefix = "\(refPrefix) - "
        let availLen = max(45, maxTotalLen - fullPrefix.count)

        let marked = RegexCache.replace(cleanedBody, pattern: "\\s*(?=\\(\\d{1,3}\\)\\s)", template: "\u{0000}")
        let segments = marked.components(separatedBy: "\u{0000}")
        var finalLines: [String] = []

        for rawSeg in segments {
            var seg = rawSeg.trimmingCharacters(in: .whitespacesAndNewlines)
            if seg.hasSuffix(";") || seg.hasSuffix(":") { seg.removeLast() }
            seg = RegexCache.replace(seg, pattern: "^\\(([1-9]|1\\d)\\)\\s+", template: "")
            if seg.isEmpty { continue }

            for chunk in smartWrapText(seg, maxLen: availLen) {
                let cleanedChunk = RegexCache.replace(chunk, pattern: "[:;]\\h*$", template: "")
                finalLines.append("\(fullPrefix)\(cleanedChunk)")
            }
        }
        return finalLines
    }
}
