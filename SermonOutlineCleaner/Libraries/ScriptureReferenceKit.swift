import Foundation

//
//  ScriptureReferenceKit.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

/// Canonicalizes Bible book names, translation codes, and scripture reference strings.
nonisolated enum ScriptureReferenceKit {

    static let bookMap: [String: String] = [
        "genesis": "Genesis", "gen": "Genesis",
        "exodus": "Exodus", "exod": "Exodus", "exo": "Exodus",
        "leviticus": "Leviticus", "lev": "Leviticus",
        "numbers": "Numbers", "num": "Numbers",
        "deuteronomy": "Deuteronomy", "deut": "Deuteronomy", "deu": "Deuteronomy",
        "joshua": "Joshua", "josh": "Joshua", "jos": "Joshua",
        "judges": "Judges", "judg": "Judges", "jdg": "Judges",
        "ruth": "Ruth", "rut": "Ruth",
        "1 samuel": "1 Samuel", "1 sam": "1 Samuel", "1sam": "1 Samuel", "i samuel": "1 Samuel", "i sam": "1 Samuel",
        "2 samuel": "2 Samuel", "2 sam": "2 Samuel", "2sam": "2 Samuel", "ii samuel": "2 Samuel", "ii sam": "2 Samuel",
        "1 kings": "1 Kings", "1 kgs": "1 Kings", "1kgs": "1 Kings", "i kings": "1 Kings", "i kgs": "1 Kings",
        "2 kings": "2 Kings", "2 kgs": "2 Kings", "2kgs": "2 Kings", "ii kings": "2 Kings", "ii kgs": "2 Kings",
        "1 chronicles": "1 Chronicles", "1 chr": "1 Chronicles", "1 chron": "1 Chronicles", "1chr": "1 Chronicles", "i chronicles": "1 Chronicles", "i chr": "1 Chronicles",
        "2 chronicles": "2 Chronicles", "2 chr": "2 Chronicles", "2 chron": "2 Chronicles", "2chr": "2 Chronicles", "ii chronicles": "2 Chronicles", "ii chr": "2 Chronicles",
        "ezra": "Ezra", "ezr": "Ezra",
        "nehemiah": "Nehemiah", "neh": "Nehemiah",
        "esther": "Esther", "esth": "Esther", "est": "Esther",
        "job": "Job",
        "psalms": "Psalm", "psalm": "Psalm", "ps": "Psalm", "psa": "Psalm",
        "proverbs": "Proverbs", "prov": "Proverbs", "pro": "Proverbs",
        "ecclesiastes": "Ecclesiastes", "eccl": "Ecclesiastes", "ecc": "Ecclesiastes",
        "song of solomon": "Song of Solomon", "song of songs": "Song of Solomon", "song": "Song of Solomon", "sos": "Song of Solomon",
        "isaiah": "Isaiah", "isa": "Isaiah",
        "jeremiah": "Jeremiah", "jer": "Jeremiah",
        "lamentations": "Lamentations", "lam": "Lamentations",
        "ezekiel": "Ezekiel", "ezek": "Ezekiel", "eze": "Ezekiel",
        "daniel": "Daniel", "dan": "Daniel",
        "hosea": "Hosea", "hos": "Hosea",
        "joel": "Joel", "joe": "Joel",
        "amos": "Amos", "amo": "Amos",
        "obadiah": "Obadiah", "obad": "Obadiah", "oba": "Obadiah",
        "jonah": "Jonah", "jon": "Jonah",
        "micah": "Micah", "mic": "Micah",
        "nahum": "Nahum", "nah": "Nahum",
        "habakkuk": "Habakkuk", "hab": "Habakkuk",
        "zephaniah": "Zephaniah", "zeph": "Zephaniah", "zep": "Zephaniah",
        "haggai": "Haggai", "hag": "Haggai",
        "zechariah": "Zechariah", "zech": "Zechariah", "zec": "Zechariah",
        "malachi": "Malachi", "mal": "Malachi",
        "matthew": "Matthew", "matt": "Matthew", "mat": "Matthew",
        "mark": "Mark", "mrk": "Mark", "mk": "Mark",
        "luke": "Luke", "luk": "Luke", "lk": "Luke",
        "john": "John", "joh": "John", "jn": "John",
        "acts": "Acts", "act": "Acts",
        "romans": "Romans", "rom": "Romans",
        "1 corinthians": "1 Corinthians", "1 cor": "1 Corinthians", "1cor": "1 Corinthians", "i corinthians": "1 Corinthians", "i cor": "1 Corinthians",
        "2 corinthians": "2 Corinthians", "2 cor": "2 Corinthians", "2cor": "2 Corinthians", "ii corinthians": "2 Corinthians", "ii cor": "2 Corinthians",
        "galatians": "Galatians", "gal": "Galatians",
        "ephesians": "Ephesians", "eph": "Ephesians",
        "philippians": "Philippians", "philip": "Philippians", "phil": "Philippians", "php": "Philippians",
        "colossians": "Colossians", "col": "Colossians",
        "1 thessalonians": "1 Thessalonians", "1 thess": "1 Thessalonians", "1 the": "1 Thessalonians", "1thess": "1 Thessalonians", "i thessalonians": "1 Thessalonians", "i thess": "1 Thessalonians",
        "2 thessalonians": "2 Thessalonians", "2 thess": "2 Thessalonians", "2 the": "2 Thessalonians", "2thess": "2 Thessalonians", "ii thessalonians": "2 Thessalonians", "ii thess": "2 Thessalonians",
        "1 timothy": "1 Timothy", "1 tim": "1 Timothy", "1tim": "1 Timothy", "i timothy": "1 Timothy", "i tim": "1 Timothy",
        "2 timothy": "2 Timothy", "2 tim": "2 Timothy", "2tim": "2 Timothy", "ii timothy": "2 Timothy", "ii tim": "2 Timothy",
        "titus": "Titus", "tit": "Titus",
        "philemon": "Philemon", "phlm": "Philemon", "phm": "Philemon",
        "hebrews": "Hebrews", "heb": "Hebrews",
        "james": "James", "jas": "James", "jam": "James",
        "1 peter": "1 Peter", "1 pet": "1 Peter", "1pet": "1 Peter", "i peter": "1 Peter", "i pet": "1 Peter",
        "2 peter": "2 Peter", "2 pet": "2 Peter", "2pet": "2 Peter", "ii peter": "2 Peter", "ii pet": "2 Peter",
        "1 john": "1 John", "1 joh": "1 John", "1 jn": "1 John", "1john": "1 John", "i john": "1 John", "i jn": "1 John",
        "2 john": "2 John", "2 joh": "2 John", "2 jn": "2 John", "2john": "2 John", "ii john": "2 John", "ii jn": "2 John",
        "3 john": "3 John", "3 joh": "3 John", "3 jn": "3 John", "3john": "3 John", "iii john": "3 John", "iii jn": "3 John",
        "jude": "Jude", "jud": "Jude",
        "revelation": "Revelation", "revelations": "Revelation", "rev": "Revelation"
    ]

    static let translationMap: [String: String] = [
        "amplified bible, classic edition": "AMPC",
        "amplified bible classic edition": "AMPC",
        "amplified bible": "AMP",
        "amplified": "AMP",
        "ampc": "AMPC",
        "amp": "AMP",
        "new living translation": "NLT",
        "nlt2": "NLT",
        "nlt": "NLT",
        "english standard version": "ESV",
        "esv": "ESV",
        "new king james version": "NKJV",
        "nkjv": "NKJV",
        "king james version": "KJV",
        "kjv 1900": "KJV",
        "kjv": "KJV",
        "new international version": "NIV",
        "niv 1984": "NIV",
        "niv 2011": "NIV",
        "niv": "NIV",
        "new american standard bible": "NASB",
        "nasb 1995": "NASB",
        "nasb 2020": "NASB",
        "nasb": "NASB",
        "christian standard bible": "CSB",
        "csb": "CSB",
        "god's word translation": "GW",
        "gods word translation": "GW",
        "gw": "GW",
        "the message": "MSG",
        "msg": "MSG",
        "new revised standard version": "NRSV",
        "nrsv": "NRSV"
    ]

    static let booksRegex: String = {
        let sortedKeys = bookMap.keys.sorted { $0.count > $1.count }
        let patterns = sortedKeys.map { key in
            NSRegularExpression.escapedPattern(for: key).replacingOccurrences(of: " ", with: "[\\s\\-]*")
        }
        return "(?:" + patterns.joined(separator: "|") + ")"
    }()

    static let translationsRegex: String = {
        let sortedKeys = translationMap.keys.sorted { $0.count > $1.count }
        let patterns = sortedKeys.map { NSRegularExpression.escapedPattern(for: $0) }
        return "(?:" + patterns.joined(separator: "|") + ")(?:\\s+\\d{4})?"
    }()

    static let chapterVersePattern = "\\d+\\s*:\\s*\\d+(?:\\s*[-,]\\s*\\d+)*"

    static let refCorePattern: String = {
        return "(\(booksRegex))\\.?\\s*(\(chapterVersePattern))(?:\\s*\\(?(\(translationsRegex))\\)?)?"
    }()

    /// Matches standalone reference lines even if followed by "says:", "reads:", or ":"
    static let standaloneRefPattern: String = {
        return "^\\(?(\(booksRegex))\\.?\\s*(\(chapterVersePattern)|\\d+(?:\\s*-\\s*\\d+)?)\\s*\\(?(\(translationsRegex))?\\)?\\)?(?:\\s*(?:says|reads))?\\s*[:;\\-]?\\s*$"
    }()

    // MARK: - Canonicalization & Formatting

    static func getCanonicalBook(_ bookRaw: String) -> String {
        let trimmed = bookRaw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var cleanKey = RegexCache.replace(trimmed, pattern: "[\\s\\-]+", template: " ")
        cleanKey = RegexCache.replace(cleanKey, pattern: "^([1-3])([a-z])", template: "$1 $2")
        return bookMap[cleanKey] ?? TypographyAndWrapping.smartTitleCase(bookRaw)
    }

    static func getCanonicalTrans(_ transRaw: String?) -> String? {
        guard let raw = transRaw, !raw.isEmpty else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ."))
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        let singleSpaced = RegexCache.replace(cleaned, pattern: "\\s+", template: " ")
        let withoutYear = RegexCache.replace(singleSpaced, pattern: "\\s+\\d{4}$", template: "")
        return translationMap[singleSpaced]
            ?? translationMap[withoutYear]
            ?? withoutYear.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    }

    static func normalizeBookAndNumbers(_ bookRaw: String, _ numbersRaw: String) -> String {
        let canonicalBook = getCanonicalBook(bookRaw)
        var cleanNums = RegexCache.replace(numbersRaw.trimmingCharacters(in: .whitespaces), pattern: "\\s*:\\s*", template: ":")
        cleanNums = RegexCache.replace(cleanNums, pattern: "\\s*-\\s*", template: "-")
        cleanNums = RegexCache.replace(cleanNums, pattern: "\\s*,\\s*", template: ",")
        return "\(canonicalBook) \(cleanNums)"
    }

    static func formatRefPrefix(_ bookRaw: String, _ numbersRaw: String, _ transRaw: String? = nil) -> String {
        let baseRef = normalizeBookAndNumbers(bookRaw, numbersRaw)
        if let normTrans = getCanonicalTrans(transRaw), !normTrans.isEmpty {
            return "\(baseRef) (\(normTrans))"
        }
        return baseRef
    }

    static func standardizeRefsInText(_ text: String) -> String {
        guard let rx = RegexCache.compiled(pattern: refCorePattern, options: [.caseInsensitive]) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = rx.matches(in: text, options: [], range: nsRange)
        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result) else { continue }
            let book = Range(match.range(at: 1), in: result).map { String(result[$0]) } ?? ""
            let nums = Range(match.range(at: 2), in: result).map { String(result[$0]) } ?? ""
            let trans = Range(match.range(at: 3), in: result).map { String(result[$0]) }
            let replacement = formatRefPrefix(book, nums, trans)
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    static func addScriptureRef(_ list: inout [String], _ refStr: String) {
        let trimmed = refStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = list.last {
            if last == trimmed { return }
            if trimmed.hasPrefix(last + " (") {
                list[list.count - 1] = trimmed
                return
            }
        }
        list.append(trimmed)
    }

    static func splitInlineParenRefs(_ line: String) -> [String] {
        let pattern = "(?=\\(\(booksRegex)\\.?\\s*\(chapterVersePattern)\\s+\(translationsRegex)\\))"
        let marked = RegexCache.replace(line, pattern: pattern, template: "\u{0000}", caseInsensitive: true)
        let parts = marked.components(separatedBy: "\u{0000}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [line] : parts
    }

    static func verseNumbersInReference(_ ref: String?) -> Set<Int> {
        guard let ref, let colonIdx = ref.firstIndex(of: ":") else { return [] }
        let afterColon = ref[ref.index(after: colonIdx)...]
        let verseSpec = afterColon.split(separator: "(").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        var numbers = Set<Int>()
        for part in verseSpec.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] <= 200 {
                    for n in bounds[0]...bounds[1] {
                        numbers.insert(n)
                    }
                }
            } else if let n = Int(trimmed) {
                numbers.insert(n)
            }
        }
        return numbers
    }
}
