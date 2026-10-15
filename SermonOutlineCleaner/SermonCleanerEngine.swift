import Foundation
import PDFKit
import AppKit

struct SermonProcessingResult {
    var speaker: String
    var title: String
    var lines: [String]
    var scriptures: [String]
}

final class SermonCleanerEngine {
    static let defaultMaxLineChars = 105
    static let defaultSpeaker = "Pastor Ernest Fink"

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
        "kjv": "KJV",
        "new international version": "NIV",
        "niv": "NIV",
        "new american standard bible": "NASB",
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
        return "(?:" + patterns.joined(separator: "|") + ")"
    }()

    static let refCorePattern: String = {
        return "(\(booksRegex))\\.?\\s*(\\d+(?:\\s*:\\s*\\d+)?(?:\\s*-\\s*\\d+)?)(?:\\s*\\(?(\(translationsRegex))\\)?)?"
    }()

    // MARK: - Regex Helpers

    private static func regexReplace(_ text: String, pattern: String, template: String, caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let rx = try? NSRegularExpression(pattern: pattern, options: opts) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return rx.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func regexMatches(_ text: String, pattern: String, caseInsensitive: Bool = true) -> [[String]] {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let rx = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return rx.matches(in: text, options: [], range: nsRange).map { match in
            (0..<match.numberOfRanges).map { idx in
                let r = match.range(at: idx)
                guard r.location != NSNotFound, let range = Range(r, in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func regexFirstMatch(_ text: String, pattern: String, caseInsensitive: Bool = true) -> [String]? {
        return regexMatches(text, pattern: pattern, caseInsensitive: caseInsensitive).first
    }

    private static func splitInlineParenRefs(_ line: String) -> [String] {
        let pattern = "(?=\\(\(booksRegex)\\.?\\s*\\d+:\\s*\\d+(?:-\\d+)?\\s+\(translationsRegex)\\))"
        let marked = regexReplace(line, pattern: pattern, template: "\u{0000}", caseInsensitive: true)
        let parts = marked.components(separatedBy: "\u{0000}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [line] : parts
    }

    // MARK: - Normalization

    static func getCanonicalBook(_ bookRaw: String) -> String {
        let trimmed = bookRaw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var cleanKey = regexReplace(trimmed, pattern: "[\\s\\-]+", template: " ")
        cleanKey = regexReplace(cleanKey, pattern: "^([1-3])([a-z])", template: "$1 $2")
        return bookMap[cleanKey] ?? bookRaw.capitalized
    }

    static func getCanonicalTrans(_ transRaw: String?) -> String? {
        guard let raw = transRaw, !raw.isEmpty else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ."))
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        let singleSpaced = regexReplace(cleaned, pattern: "\\s+", template: " ")
        return translationMap[singleSpaced] ?? raw.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    }

    static func normalizeBookAndNumbers(_ bookRaw: String, _ numbersRaw: String) -> String {
        let canonicalBook = getCanonicalBook(bookRaw)
        var cleanNums = regexReplace(numbersRaw.trimmingCharacters(in: .whitespaces), pattern: "\\s*:\\s*", template: ":")
        cleanNums = regexReplace(cleanNums, pattern: "\\s*-\\s*", template: "-")
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
        guard let rx = try? NSRegularExpression(pattern: refCorePattern, options: [.caseInsensitive]) else { return text }
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

    // MARK: - File Extraction (.docx, .pdf, .eml, .txt)

    static func isEmlFile(_ url: URL) -> Bool {
        let nameLower = url.lastPathComponent.lowercased()
        if nameLower.hasSuffix(".eml") || nameLower.hasSuffix(".eml.txt") { return true }
        if url.pathExtension.lowercased() == "txt",
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let head = String(content.prefix(1024))
            if regexFirstMatch(head, pattern: "(?m)^(?:Delivered-To|Return-Path|Received|MIME-Version|Content-Type):") != nil {
                return true
            }
        }
        return false
    }

    static func extractLines(from url: URL) throws -> [String] {
        if isEmlFile(url) {
            return mergeOrphanVerseNumberLines(try extractLinesFromEml(url))
        }

        let ext = url.pathExtension.lowercased()
        var rawLines: [String] = []

        if ext == "docx" {
            let attrStr = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            let normalized = attrStr.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            for line in normalized.components(separatedBy: "\n") {
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { rawLines.append(s) }
            }
        } else if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else {
                throw NSError(domain: "SermonCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read PDF file."])
            }
            for i in 0..<pdf.pageCount {
                if let pageText = pdf.page(at: i)?.string {
                    let normalized = pageText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                    for line in normalized.components(separatedBy: "\n") {
                        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { rawLines.append(s) }
                    }
                }
            }
        } else {
            let text = try String(contentsOf: url, encoding: .utf8)
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            for line in normalized.components(separatedBy: "\n") {
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { rawLines.append(s) }
            }
        }

        return mergeOrphanVerseNumberLines(rawLines)
    }

    static func decodeQuotedPrintable(_ input: String) -> String {
        let softStripped = input
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        let utf8 = Array(softStripped.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "="), i + 2 < utf8.count,
               let h1 = Character(UnicodeScalar(utf8[i + 1])).hexDigitValue,
               let h2 = Character(UnicodeScalar(utf8[i + 2])).hexDigitValue {
                bytes.append(UInt8(h1 * 16 + h2))
                i += 3
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func decodeMimePartBody(_ part: String) -> String {
        let subParts = part.components(separatedBy: "\n\n")
        let partHeader = subParts.first?.lowercased() ?? ""
        let rawPayload = subParts.dropFirst().joined(separator: "\n\n")

        if partHeader.contains("content-transfer-encoding: base64") {
            let cleanedBase64 = rawPayload.components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: cleanedBase64),
               let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                return decoded
            }
        }
        return decodeQuotedPrintable(rawPayload)
    }

    static func extractLinesFromEml(_ url: URL) throws -> [String] {
        let rawText = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            ?? ""
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let headerBlock = parts.first ?? ""
        var bodyBlock = parts.dropFirst().joined(separator: "\n\n")

        var extracted: [String] = []
        for line in headerBlock.components(separatedBy: "\n") {
            if line.lowercased().hasPrefix("from:") {
                extracted.append(line)
            } else if line.lowercased().hasPrefix("subject:") {
                let rawSubj = String(line.dropFirst("subject:".count))
                let cleaned = cleanEmailSubject(rawSubj)
                if !cleaned.isEmpty {
                    extracted.append("Subject: \(cleaned)")
                }
            }
        }

        var cleanBody = ""
        if let boundaryMatch = regexFirstMatch(headerBlock, pattern: "boundary=\"?([^\"\\s;]+)\"?") {
            let boundary = "--" + boundaryMatch[1]
            let mimeParts = bodyBlock.components(separatedBy: boundary)
            if let plainPart = mimeParts.first(where: { $0.lowercased().contains("content-type: text/plain") }) {
                cleanBody = decodeMimePartBody(plainPart)
            } else if let htmlPart = mimeParts.first(where: { $0.lowercased().contains("content-type: text/html") }) {
                cleanBody = decodeMimePartBody(htmlPart)
            } else {
                cleanBody = decodeQuotedPrintable(bodyBlock)
            }
        } else {
            cleanBody = decodeMimePartBody(normalized)
        }

        if cleanBody.lowercased().contains("<html") || cleanBody.lowercased().contains("<div") || cleanBody.lowercased().contains("<p") {
            if let data = cleanBody.data(using: .utf8),
               let attr = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.html,
                             .characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                for line in attr.string.components(separatedBy: .newlines) {
                    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { extracted.append(s) }
                }
                return extracted
            }
        }

        extracted.append(contentsOf: unwrapEmailPlainParagraphs(cleanBody))
        return extracted
    }

    static func unwrapEmailPlainParagraphs(_ bodyText: String) -> [String] {
        let paragraphs = regexReplace(bodyText, pattern: "\\n\\s*\\n", template: "\u{0000}").components(separatedBy: "\u{0000}")
        var logicalLines: [String] = []

        for para in paragraphs {
            let sublines = para.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("--") && !$0.hasPrefix("Content-") }
            guard let first = sublines.first else { continue }

            var current = first
            for nxt in sublines.dropFirst() {
                let currClean = current.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
                let nxtClean = nxt.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)

                let currIsRef = regexFirstMatch(currClean, pattern: "^\\(?\(refCorePattern)\\)?$") != nil
                let nxtIsRef = regexFirstMatch(nxtClean, pattern: "^\\(?\(refCorePattern)\\)?$") != nil
                let startsWithVerseNum = regexFirstMatch(nxtClean, pattern: "^\\d{1,3}\\s+[A-Z\"“]", caseInsensitive: false) != nil

                if currIsRef || nxtIsRef || startsWithVerseNum {
                    logicalLines.append(current)
                    current = nxt
                } else {
                    current = "\(current) \(nxt)"
                }
            }
            if !current.isEmpty { logicalLines.append(current) }
        }
        return logicalLines
    }

    static func cleanEmailSubject(_ subjectRaw: String) -> String {
        var subj = regexReplace(subjectRaw, pattern: "\\s+", template: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        subj = regexReplace(
            subj,
            pattern: "^(?:\\[[^\\]]+\\]\\s*|(?=\\b(?:Re|Fwd|Fw)\\s*:\\s*))+",
            template: "",
            caseInsensitive: true
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let genericSubjects: Set<String> = [
            "over head outline", "overhead outline", "sermon outline", "sermon notes",
            "outline", "notes", "sunday sermon", "sunday outline", "message outline"
        ]
        let check = subj.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .:-_"))
        return genericSubjects.contains(check) ? "" : subj
    }

    static func mergeOrphanVerseNumberLines(_ lines: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < lines.count {
            let curr = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if regexFirstMatch(curr, pattern: "^\\d{1,3}$") != nil, (i + 1) < lines.count {
                let nextLine = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                merged.append("\(curr) \(nextLine)")
                i += 2
            } else {
                merged.append(curr)
                i += 1
            }
        }
        return merged
    }

    // MARK: - Typography, CotEditor Rules & Smart Wrapping

    static func cleanBasicTypography(_ input: String) -> String {
        var text = input
        // 1. CotEditor rule: Strip zero-width spaces, joiners, BOM, and soft hyphens
        text = regexReplace(text, pattern: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}\\u{00AD}]", template: "")
        // 2. Non-breaking spaces and tabs to normal spaces
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\t", with: " ")
        // 3. Smart quotes to straight quotes
        text = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        text = text.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        // 4. CotEditor rule: Strip leading bullets, hyphens, dashes, arrows, and list markers at start of line
        text = regexReplace(text, pattern: "^\\h*[•\\-_–—*>»▪~+]+\\h*", template: "")
        // 5. Remove any remaining asterisks
        text = text.replacingOccurrences(of: "*", with: "")
        // 6. Strip BibleGateway footnote markers like [a], [b]
        text = regexReplace(text, pattern: "(?<!\\w)\\[[a-zA-Z]\\]\\s*", template: "")
        // 7. Normalize number ranges with em/en dashes (e.g., 1—3 -> 1-3)
        text = regexReplace(text, pattern: "(?<=\\d)\\s*[—–]\\s*(?=\\d)", template: "-")
        // 8. Normalize remaining em/en dashes to spaced hyphens ( - )
        text = regexReplace(text, pattern: "\\s*[—–]\\s*", template: " - ")
        // 9. Fix missing space after sentence-ending punctuation
        text = regexReplace(text, pattern: "(?<!\\.)([.?!;])([A-Z\\[])", template: "$1 $2")
        text = regexReplace(text, pattern: "(?<!\\.)([.?!;])(\\d+\\s+[A-Z\\[\"“])", template: "$1 $2")
        text = regexReplace(text, pattern: "([a-z\\]])([A-Z])", template: "$1 $2")
        // 10. Collapse multiple horizontal spaces
        text = regexReplace(text, pattern: "\\h{2,}", template: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanVerseBody(_ input: String) -> String {
        var body = regexReplace(input, pattern: "(?<=[.?!;:,\"\\]])\\s+(\\d{1,3})\\s+(?=[A-Z\\[\"“])", template: " ($1) ")
        body = regexReplace(body, pattern: "^\\d{1,3}\\s+(?=[A-Z\\[\"“])", template: "")
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        let quoteCount = body.filter { $0 == "\"" }.count
        if quoteCount == 1 {
            if body.hasSuffix("\"") && !body.hasPrefix("\"") {
                body = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
            } else if !body.hasSuffix("\"") {
                body += "\""
            }
        } else if quoteCount % 2 == 1 && !body.hasSuffix("\"") {
            body += "\""
        }
        return body
    }

    static func formatTopicLine(_ input: String) -> String {
        // CotEditor rule: Strip trailing colons or semicolons at end of line
        var text = regexReplace(input, pattern: "[:;]\\h*$", template: "").trimmingCharacters(in: .whitespaces)

        if text == text.uppercased() && text.count > 3 {
            text = text.capitalized
        } else if let colonIdx = text.firstIndex(of: ":") {
            let prefix = String(text[..<colonIdx])
            let rest = String(text[text.index(after: colonIdx)...])
            if prefix == prefix.uppercased() && prefix.count > 3 {
                text = "\(prefix.capitalized):\(rest)"
            }
        }
        return text
    }

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

        let lastWord = regexFirstMatch(left, pattern: "([A-Za-z']+)[^A-Za-z']*$")?[1].lowercased() ?? ""
        let firstWord = regexFirstMatch(right, pattern: "^[^A-Za-z']*([A-Za-z']+)")?[1].lowercased() ?? ""

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
                let nextWords = right.split(separator: " ").prefix(3).map { $0.lowercased() }
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

            for i in 1..<tokens.count {
                let left = tokens[..<i].joined(separator: " ")
                if left.count > maxLen { break }
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

            let cleanedLine = firstCandidate.replacingOccurrences(of: "[ \\-]+$", with: "", options: .regularExpression)
            lines.append(cleanedLine)
            tokens = Array(tokens[bestIdx...])
            if tokens.first == "-" { tokens.removeFirst() }
        }

        return lines
    }

    static func splitPlainLine(_ text: String, maxLen: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        if let match = regexFirstMatch(trimmed, pattern: "^([^\\x00-\\x7F].*?)\\.\\.\\.([a-zA-Z'].*?)\\.\\.\\.(\".*)$") {
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

        let marked = regexReplace(cleanedBody, pattern: "\\s*(?=\\(\\d{1,3}\\)\\s)", template: "\u{0000}")
        let segments = marked.components(separatedBy: "\u{0000}")
        var finalLines: [String] = []

        for rawSeg in segments {
            var seg = rawSeg.trimmingCharacters(in: .whitespacesAndNewlines)
            if seg.hasSuffix(";") { seg.removeLast() }
            seg = regexReplace(seg, pattern: "^\\(([1-9]|1\\d)\\)\\s+", template: "")
            if seg.isEmpty { continue }

            for chunk in smartWrapText(seg, maxLen: availLen) {
                finalLines.append("\(fullPrefix)\(chunk)")
            }
        }
        return finalLines
    }

    // MARK: - Main Sermon Line Processor

    static func processSermonFile(
        url: URL,
        fallbackSpeaker: String,
        maxLineChars: Int = defaultMaxLineChars
    ) throws -> SermonProcessingResult {
        let clampedLimit = max(45, min(250, maxLineChars))
        let rawLines = try extractLines(from: url)
        var sermonTitle = ""
        var emailSubjectFallback = ""
        var extractedSpeaker: String? = nil
        var outputLines: [String] = []
        var scriptureList: [String] = []

        var activeHeaderRef: String? = nil
        var activeHeaderHasVerse = false
        var seenFirstContentLine = false

        var idx = 0
        while idx < rawLines.count {
            let line = cleanBasicTypography(rawLines[idx])
            idx += 1
            if line.isEmpty { continue }

            if let sender = cleanEmailSender(line) {
                if !sender.isEmpty { extractedSpeaker = sender }
                continue
            }

            if let subjMatch = regexFirstMatch(line, pattern: "^Subject\\s*:\\s*(.+)$") {
                let cleanedSubj = cleanEmailSubject(subjMatch[1])
                if !cleanedSubj.isEmpty { emailSubjectFallback = cleanedSubj.capitalized }
                continue
            }

            if regexFirstMatch(line, pattern: "^(?:Date|Sent|To|Cc)\\s*:\\s*") != nil { continue }

            if ["SERMON:", "TITLE:"].contains(line.uppercased()), idx < rawLines.count {
                sermonTitle = cleanBasicTypography(rawLines[idx]).capitalized
                seenFirstContentLine = true
                idx += 1
                continue
            } else if regexFirstMatch(line, pattern: "^(?:SERMON|TITLE)\\s*:") != nil {
                sermonTitle = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces).capitalized
                seenFirstContentLine = true
                continue
            }

            if !seenFirstContentLine {
                seenFirstContentLine = true
                if sermonTitle.isEmpty && line.count < 65 {
                    if regexFirstMatch(line, pattern: refCorePattern) == nil && !line.hasSuffix(":") {
                        sermonTitle = line.capitalized
                        continue
                    }
                }
            }

            if ["TOPIC:", "TOPIC"].contains(line.uppercased()) { continue }

            // Standalone scripture reference line
            if let standalone = regexFirstMatch(line, pattern: "^\\(?(\(booksRegex))\\.?\\s*(\\d+\\s*:\\s*\\d+(?:\\s*-\\s*\\d+)?)\\s*\\(?(\(translationsRegex))?\\)?\\)?$") {
                let bookRaw = standalone[1]
                let numsRaw = standalone[2]
                var transRaw: String? = standalone[3].isEmpty ? nil : standalone[3]

                if transRaw == nil && idx < rawLines.count {
                    let nextClean = cleanBasicTypography(rawLines[idx])
                    if regexFirstMatch(nextClean, pattern: "^\\(?(\(translationsRegex))\\)?$") != nil {
                        transRaw = nextClean
                        idx += 1
                    }
                }

                let formattedRef = formatRefPrefix(bookRaw, numsRaw, transRaw)
                activeHeaderRef = formattedRef
                activeHeaderHasVerse = false
                addScriptureRef(&scriptureList, formattedRef)
                continue
            }

            if let activeRef = activeHeaderRef {
                if isVerseContinuation(line, hasSeenVerse: activeHeaderHasVerse) {
                    outputLines.append(contentsOf: splitLongVerse(refPrefix: activeRef, body: line, maxTotalLen: clampedLimit))
                    activeHeaderHasVerse = true
                    continue
                } else {
                    activeHeaderRef = nil
                    activeHeaderHasVerse = false
                }
            }

            // Split inline parenthetical references into sub-lines
            let subLines = splitInlineParenRefs(line)

            for sub in subLines {
                // 1. Topic: Ref on single line
                if let topicColon = regexFirstMatch(sub, pattern: "^([A-Za-z\\s]+?)\\s*:\\s*\(refCorePattern)\\s*$") {
                    let topicName = formatTopicLine(topicColon[1].trimmingCharacters(in: .whitespaces))
                    let refLine = formatRefPrefix(topicColon[2], topicColon[3], topicColon[4].isEmpty ? nil : topicColon[4])
                    outputLines.append(contentsOf: splitPlainLine(topicName, maxLen: clampedLimit))
                    outputLines.append(refLine)
                    addScriptureRef(&scriptureList, refLine)
                    continue
                }

                // 2. Leading verse reference + body on single line
                if let leadMatch = regexFirstMatch(sub, pattern: "^\\(?(\(booksRegex))\\.?\\s*(\\d+\\s*:\\s*\\d+(?:\\s*-\\s*\\d+)?)\\s*\\(?(\(translationsRegex))?\\)?\\)?\\s*(?:-\\s*)?(.*)$"),
                   !leadMatch[4].isEmpty {
                    let bookRaw = leadMatch[1]
                    var numsRaw = leadMatch[2]
                    var leadTrans: String? = leadMatch[3].isEmpty ? nil : leadMatch[3]
                    var body = leadMatch[4].trimmingCharacters(in: .whitespaces)

                    if !body.hasPrefix(";") {
                        if let trailMatch = regexFirstMatch(body, pattern: "\\s*\\(?(\(translationsRegex))\\)?\\.?\\s*$") {
                            if leadTrans == nil { leadTrans = trailMatch[1] }
                            body = regexReplace(body, pattern: "\\s*\\(?(\(translationsRegex))\\)?\\.?\\s*$", template: "", caseInsensitive: true)
                        }

                        (numsRaw, leadTrans) = mergeWithPreviousStandaloneRef(
                            outputLines: &outputLines,
                            scriptureList: &scriptureList,
                            bookRaw: bookRaw,
                            numsRaw: numsRaw,
                            leadTrans: leadTrans
                        )

                        let refPrefix = formatRefPrefix(bookRaw, numsRaw, leadTrans)
                        addScriptureRef(&scriptureList, refPrefix)
                        outputLines.append(contentsOf: splitLongVerse(refPrefix: refPrefix, body: body, maxTotalLen: clampedLimit))
                        continue
                    }
                }

                // 3. Topic / commentary line + multi_ref_match & inline_cite
                let formattedTopic = standardizeRefsInText(formatTopicLine(sub))

                let multiRefMatch = regexFirstMatch(
                    formattedTopic,
                    pattern: "^(\(booksRegex)\\s+\\d+:\\d+(?:-\\d+)?(?:\\s*;\\s*\(booksRegex)\\s+\\d+:\\d+(?:-\\d+)?)+)"
                )
                let inlineCite = regexFirstMatch(
                    formattedTopic,
                    pattern: "\\((\(booksRegex)\\s+\\d+:\\d+(?:-\\d+)?)\\)\\s+[A-Z\"]"
                )

                outputLines.append(contentsOf: splitPlainLine(formattedTopic, maxLen: clampedLimit))

                if let multi = multiRefMatch {
                    let refs = multi[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    outputLines.append(contentsOf: refs)
                    for r in refs {
                        addScriptureRef(&scriptureList, r)
                    }
                    continue
                }

                if let cite = inlineCite {
                    outputLines.append(cite[1])
                    addScriptureRef(&scriptureList, cite[1])
                    continue
                }

                for m in regexMatches(formattedTopic, pattern: refCorePattern) {
                    let extractedRef = formatRefPrefix(m[1], m[2], m[3].isEmpty ? nil : m[3])
                    addScriptureRef(&scriptureList, extractedRef)
                }
            }
        }

        if sermonTitle.isEmpty {
            sermonTitle = !emailSubjectFallback.isEmpty ? emailSubjectFallback : extractTitleFromFilename(url)
        }

        let finalSpeaker = (extractedSpeaker?.isEmpty == false) ? extractedSpeaker! : fallbackSpeaker
        return SermonProcessingResult(
            speaker: finalSpeaker,
            title: sermonTitle,
            lines: outputLines,
            scriptures: scriptureList
        )
    }

    private static func mergeWithPreviousStandaloneRef(
        outputLines: inout [String],
        scriptureList: inout [String],
        bookRaw: String,
        numsRaw: String,
        leadTrans: String?
    ) -> (String, String?) {
        guard let prevLine = outputLines.last,
              let prevMatch = regexFirstMatch(prevLine, pattern: "^\(refCorePattern)$") else {
            return (numsRaw, leadTrans)
        }
        let prevBook = prevMatch[1]
        let prevNums = prevMatch[2]
        let prevTrans: String? = prevMatch[3].isEmpty ? nil : prevMatch[3]

        let currChap = numsRaw.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)
        let prevChap = prevNums.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)

        if getCanonicalBook(bookRaw) == getCanonicalBook(prevBook) && currChap == prevChap && prevNums.contains(":") {
            let popped = outputLines.removeLast()
            if scriptureList.last == popped { scriptureList.removeLast() }
            let cleanPrev = prevNums.replacingOccurrences(of: " ", with: "")
            let cleanCurr = numsRaw.replacingOccurrences(of: " ", with: "")
            let bestNums = cleanPrev.count >= cleanCurr.count ? cleanPrev : cleanCurr
            return (bestNums, leadTrans ?? prevTrans)
        }
        return (numsRaw, leadTrans)
    }

    private static func isVerseContinuation(_ line: String, hasSeenVerse: Bool) -> Bool {
        if regexFirstMatch(line, pattern: "^\\d{1,3}\\s+[A-Z\\[\"“]", caseInsensitive: false) != nil { return true }
        if regexFirstMatch(line, pattern: "^(?:The\\s+Hebrew|The\\s+Greek|In\\s+[A-Z]|Key\\s+|This\\s+implies|The\\s+scripture|The\\s+verse|Know\\b)\\b", caseInsensitive: false) != nil {
            return false
        }
        if !hasSeenVerse && !line.hasSuffix(":") { return true }
        if line.count < 95 && regexFirstMatch(line, pattern: "^[A-Za-z\\s\"']+:", caseInsensitive: false) == nil { return true }
        if regexFirstMatch(line, pattern: "\\b\\d{1,2}\\s+[A-Z\\[]", caseInsensitive: false) != nil { return true }
        return false
    }

    private static func extractTitleFromFilename(_ url: URL) -> String {
        var stem = url.lastPathComponent
        for ext in [".eml.txt", ".eml", ".docx", ".pdf", ".txt"] {
            if stem.lowercased().hasSuffix(ext) {
                stem = String(stem.dropLast(ext.count))
                break
            }
        }
        stem = regexReplace(stem, pattern: "\\s*[-_]\\s*OUTLINES?\\b.*$", template: "", caseInsensitive: true)
        stem = regexReplace(stem, pattern: "\\.\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\b.*$", template: "")
        let cleaned = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        if ["over head outline", "overhead outline", "sermon outline", "outline"].contains(cleaned.lowercased()) {
            return ""
        }
        return cleaned
    }

    private static func cleanEmailSender(_ line: String) -> String? {
        guard let m = regexFirstMatch(line, pattern: "^From\\s*:\\s*(.+)$") else { return nil }
        var val = m[1].trimmingCharacters(in: .whitespaces)
        val = regexReplace(val, pattern: "\\s*<[^>]+>", template: "")
        val = regexReplace(val, pattern: "\\s*\\[mailto:[^\\]]+\\]", template: "")
        val = regexReplace(val, pattern: "\\s*\\b[\\w.\\-+]+@[\\w.\\-]+\\.\\w+\\b", template: "")
        return val.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}
