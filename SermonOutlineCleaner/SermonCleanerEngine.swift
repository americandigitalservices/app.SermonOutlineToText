import Foundation
import PDFKit
import AppKit
import CoreServices

//
//  SermonOutlineCleaner
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct SermonProcessingResult {
    var speaker: String
    var title: String
    var lines: [String]
    var scriptures: [String]
}

struct EmlAttachment {
    let filename: String
    let data: Data
}

struct EmlInspection {
    let sender: String?
    let subject: String?
    let attachments: [EmlAttachment]
}

final class SermonCleanerEngine {
    static let defaultMaxLineChars = 105
    static let defaultSpeaker = "Pastor Ernest Fink"
    static let slideBreakMarker = "__SLIDE_BREAK__"
    
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
    
    // Matches standalone reference lines even if followed by "says:", "reads:", or ":"
    static let standaloneRefPattern: String = {
        return "^\\(?(\(booksRegex))\\.?\\s*(\\d+\\s*:\\s*\\d+(?:\\s*-\\s*\\d+)?)\\s*\\(?(\(translationsRegex))?\\)?\\)?(?:\\s*(?:says|reads))?\\s*[:;\\-]?\\s*$"
    }()
    
    // All bullet/list characters including middle dot (· \u{00B7}) from Word/Gmail
    static let leadingBulletPattern = "^\\h*[•·∙‣◦⁃\\-_–—*>»▪▫~+]+\\h*"
    
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
    
    // MARK: - EML Inspection & Attachment Extraction
    
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
    
    static func inspectEmlFile(_ url: URL) -> EmlInspection {
        let rawText = (try? String(contentsOf: url, encoding: .utf8))
        ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        ?? ""
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let rawHeader = parts.first ?? ""
        let unfoldedHeader = regexReplace(rawHeader, pattern: "\\n[ \\t]+", template: " ")
        
        var sender: String? = nil
        var subject: String? = nil
        
        for line in unfoldedHeader.components(separatedBy: "\n") {
            let decodedLine = decodeRFC2047Words(line)
            if let s = cleanEmailSender(decodedLine), !s.isEmpty {
                sender = s
            } else if decodedLine.lowercased().hasPrefix("subject:") {
                let rawSubj = String(decodedLine.dropFirst("subject:".count))
                let cleaned = cleanEmailSubject(rawSubj)
                if !cleaned.isEmpty {
                    subject = cleaned.capitalized
                }
            }
        }
        
        let attachments = extractSupportedAttachments(from: normalized, headerBlock: unfoldedHeader)
        return EmlInspection(sender: sender, subject: subject, attachments: attachments)
    }
    
    private static func decodeRFC2047Words(_ input: String) -> String {
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]+)\\?="
        guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = rx.matches(in: input, options: [], range: nsRange)
        var result = input
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let modeRange = Range(match.range(at: 2), in: result),
                  let payloadRange = Range(match.range(at: 3), in: result) else { continue }
            let mode = String(result[modeRange]).uppercased()
            let payload = String(result[payloadRange])
            var decoded: String? = nil
            if mode == "B" {
                if let data = Data(base64Encoded: payload) {
                    decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                }
            } else if mode == "Q" {
                let qPrepared = payload.replacingOccurrences(of: "_", with: " ")
                decoded = decodeQuotedPrintable(qPrepared)
            }
            if let dec = decoded {
                result.replaceSubrange(fullRange, with: dec)
            }
        }
        return result
    }
    
    private static func extractSupportedAttachments(from fullNormalizedEml: String, headerBlock: String) -> [EmlAttachment] {
        let boundaryMatches = regexMatches(fullNormalizedEml, pattern: "boundary=\"?([^\"\\s;]+)\"?")
        var boundaries: [String] = []
        for m in boundaryMatches {
            let b = "--" + m[1]
            if !boundaries.contains(b) { boundaries.append(b) }
        }
        guard !boundaries.isEmpty else { return [] }
        
        var segments: [String] = [fullNormalizedEml]
        for b in boundaries {
            segments = segments.flatMap { $0.components(separatedBy: b) }
        }
        
        let supportedExts: Set<String> = ["docx", "pptx", "ppt", "pdf", "txt", "eml"]
        var attachments: [EmlAttachment] = []
        
        for seg in segments {
            let subParts = seg.components(separatedBy: "\n\n")
            guard subParts.count >= 2 else { continue }
            let rawPartHeader = subParts[0]
            let unfoldedPartHeader = decodeRFC2047Words(regexReplace(rawPartHeader, pattern: "\\n[ \\t]+", template: " "))
            
            let filenameMatch = regexFirstMatch(unfoldedPartHeader, pattern: "(?:filename|name)\\*?=\"?([^\"\\r\\n;]+)\"?")
            guard var filename = filenameMatch?[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"';")) else {
                continue
            }
            if let utf8PrefixRange = filename.range(of: "UTF-8''", options: .caseInsensitive) {
                filename = String(filename[utf8PrefixRange.upperBound...])
            }
            filename = filename.removingPercentEncoding ?? filename
            
            let ext = (filename as NSString).pathExtension.lowercased()
            guard supportedExts.contains(ext) else { continue }
            
            let payload = subParts.dropFirst().joined(separator: "\n\n")
            let headerLower = unfoldedPartHeader.lowercased()
            
            var fileData: Data? = nil
            if headerLower.contains("content-transfer-encoding: base64") {
                let cleanedBase64 = payload
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.hasPrefix("--") }
                    .joined()
                fileData = Data(base64Encoded: cleanedBase64, options: .ignoreUnknownCharacters)
            } else if headerLower.contains("content-transfer-encoding: quoted-printable") {
                let decodedStr = decodeQuotedPrintable(payload)
                fileData = decodedStr.data(using: .utf8)
            } else {
                fileData = payload.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
            }
            
            if let validData = fileData, !validData.isEmpty {
                attachments.append(EmlAttachment(filename: filename, data: validData))
            }
        }
        
        return attachments
    }
    
    // MARK: - Document Author Metadata Extraction & Name Flipping
    
    static func extractDocumentAuthor(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var rawAuthor: String? = nil
        
        // 1. OpenXML (.docx / .pptx): Read <dc:creator> directly from docProps/core.xml
        if ext == "docx" || ext == "pptx" {
            let coreXML = runUnzipPipe(zipURL: url, entryPath: "docProps/core.xml")
            if let match = regexFirstMatch(coreXML, pattern: "(?s)<dc:creator[^>]*>(.*?)</dc:creator>") {
                let decoded = decodeXMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty {
                    rawAuthor = decoded
                }
            }
        }
        
        // 2. Word (.docx) fallback via NSAttributedString documentAttributes (.author)
        if rawAuthor == nil && ext == "docx" {
            var docAttrs: NSDictionary? = nil
            _ = try? NSAttributedString(url: url, options: [:], documentAttributes: &docAttrs)
            if let dict = docAttrs,
               let author = dict[NSAttributedString.DocumentAttributeKey.author] as? String {
                let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    rawAuthor = trimmed
                }
            }
        }
        
        // 3. PDF (.pdf) via PDFDocument.documentAttributes
        if rawAuthor == nil && ext == "pdf" {
            if let pdf = PDFDocument(url: url),
               let attrs = pdf.documentAttributes,
               let author = attrs[PDFDocumentAttribute.authorAttribute] as? String {
                let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    rawAuthor = trimmed
                }
            }
        }
        
        // 4. Legacy PowerPoint (.ppt) or general fallback via Spotlight MDItem metadata
        if rawAuthor == nil,
           let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let cfAttr = MDItemCopyAttribute(mdItem, kMDItemAuthors),
           let authors = cfAttr as? [String],
           let firstAuthor = authors.first {
            let trimmed = firstAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                rawAuthor = trimmed
            }
        }
        
        guard let validAuthor = rawAuthor else { return nil }
        return normalizeAuthorName(validAuthor)
    }
    
    static func normalizeAuthorName(_ raw: String) -> String? {
        // Take the first author if multiple are separated by semicolons
        var name = raw.components(separatedBy: ";").first ?? raw
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
        
        // Ignore generic/system placeholder author names
        let ignoredAuthors: Set<String> = [
            "microsoft office user", "windows user", "user", "admin", "administrator",
            "owner", "preferred customer", "authorized user", "default"
        ]
        if name.isEmpty || ignoredAuthors.contains(name.lowercased()) {
            return nil
        }
        
        // Flip "Last, First" (e.g. "Fink, Ernest" -> "Ernest Fink")
        if name.contains(",") {
            let parts = name.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count == 2 {
                let lastName = parts[0]
                let firstName = parts[1]
                // Only flip if the second part isn't a suffix like Jr., Sr., III
                let suffixes: Set<String> = ["jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "md", "phd", "dmin"]
                if !suffixes.contains(firstName.lowercased()) {
                    name = "\(firstName) \(lastName)"
                }
            }
        }
        
        return regexReplace(name, pattern: "\\s+", template: " ")
    }
    
    // MARK: - File Extraction (.docx, .pptx, .ppt, .pdf, .eml, .txt)
    
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
        } else if ext == "pptx" || ext == "ppt" {
            rawLines = try extractLinesFromPowerPoint(url)
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
    
    static func extractLinesFromPowerPoint(_ url: URL) throws -> [String] {
        let ext = url.pathExtension.lowercased()
        
        if ext == "pptx" {
            let listTask = Process()
            let listPipe = Pipe()
            listTask.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            listTask.arguments = ["-Z1", url.path]
            listTask.standardOutput = listPipe
            try listTask.run()
            listTask.waitUntilExit()
            
            let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
            let entries = (String(data: listData, encoding: .utf8) ?? "")
                .components(separatedBy: .newlines)
            
            let slideFiles = entries
                .filter { $0.range(of: "^ppt/slides/slide\\d+\\.xml$", options: .regularExpression) != nil }
                .sorted { a, b in
                    let numA = Int(a.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)) ?? 0
                    let numB = Int(b.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)) ?? 0
                    return numA < numB
                }
            
            var extracted: [String] = []
            for slidePath in slideFiles {
                let xmlString = runUnzipPipe(zipURL: url, entryPath: slidePath)
                extracted.append(contentsOf: parsePowerPointXMLParagraphs(xmlString))
                
                let slideNum = slidePath.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
                let notePath = "ppt/notesSlides/notesSlide\(slideNum).xml"
                if entries.contains(notePath) {
                    let noteXML = runUnzipPipe(zipURL: url, entryPath: notePath)
                    extracted.append(contentsOf: parsePowerPointXMLParagraphs(noteXML))
                }
                extracted.append(slideBreakMarker)
            }
            
            if !extracted.isEmpty {
                return extracted
            }
        }
        
        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let textContent = MDItemCopyAttribute(mdItem, kMDItemTextContent) as? String {
            let lines = textContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return lines }
        }
        
        throw NSError(
            domain: "SermonCleaner",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not extract text from PowerPoint file. If this is an older .ppt file, please re-save it as .pptx."]
        )
    }
    
    private static func runUnzipPipe(zipURL: URL, entryPath: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-p", zipURL.path, entryPath]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private static func parsePowerPointXMLParagraphs(_ xml: String) -> [String] {
        let withLineBreaks = regexReplace(xml, pattern: "<a:br\\s*/?>", template: "\n")
        let paragraphs = regexMatches(withLineBreaks, pattern: "(?s)<a:p\\b[^>]*>(.*?)</a:p>")
        var lines: [String] = []
        
        for para in paragraphs {
            let paraContent = para[1]
            for subSegment in paraContent.components(separatedBy: "\n") {
                let textRuns = regexMatches(subSegment, pattern: "(?s)<a:t\\b[^>]*>(.*?)</a:t>")
                let joined = textRuns.map { decodeXMLEntities($0[1]) }.joined()
                let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, Int(trimmed) == nil {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }
    
    private static func decodeXMLEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
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
        let rawHeader = parts.first ?? ""
        let headerBlock = regexReplace(rawHeader, pattern: "\\n[ \\t]+", template: " ")
        let bodyBlock = parts.dropFirst().joined(separator: "\n\n")
        
        var extracted: [String] = []
        for line in headerBlock.components(separatedBy: "\n") {
            let decodedLine = decodeRFC2047Words(line)
            if decodedLine.lowercased().hasPrefix("from:") {
                extracted.append(decodedLine)
            } else if decodedLine.lowercased().hasPrefix("subject:") {
                let rawSubj = String(decodedLine.dropFirst("subject:".count))
                let cleaned = cleanEmailSubject(rawSubj)
                if !cleaned.isEmpty {
                    extracted.append("Subject: \(cleaned)")
                }
            }
        }
        
        let boundaryMatches = regexMatches(normalized, pattern: "boundary=\"?([^\"\\s;]+)\"?")
        var cleanBody = ""
        
        if !boundaryMatches.isEmpty {
            var segments: [String] = [bodyBlock]
            for m in boundaryMatches {
                let b = "--" + m[1]
                segments = segments.flatMap { $0.components(separatedBy: b) }
            }
            
            let nonAttachmentSegments = segments.filter { seg in
                let hdr = (seg.components(separatedBy: "\n\n").first ?? "").lowercased()
                return !hdr.contains("content-disposition: attachment") && !hdr.contains("filename=")
            }
            
            if let plainPart = nonAttachmentSegments.first(where: { $0.lowercased().contains("content-type: text/plain") }) {
                cleanBody = decodeMimePartBody(plainPart)
            } else if let htmlPart = nonAttachmentSegments.first(where: { $0.lowercased().contains("content-type: text/html") }) {
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
                
                let currIsRef = regexFirstMatch(currClean, pattern: standaloneRefPattern) != nil
                let nxtIsRef = regexFirstMatch(nxtClean, pattern: standaloneRefPattern) != nil
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
            "outline", "notes", "sunday sermon", "sunday outline", "message outline", "over head", "overhead"
        ]
        let check = subj.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .:-_"))
        return genericSubjects.contains(check) ? "" : subj
    }
    
    static func mergeOrphanVerseNumberLines(_ lines: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < lines.count {
            let curr = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if curr != slideBreakMarker,
               regexFirstMatch(curr, pattern: "^\\d{1,3}$") != nil,
               (i + 1) < lines.count,
               lines[i + 1] != slideBreakMarker {
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
        if input == slideBreakMarker { return slideBreakMarker }
        var text = input
        // 1. CotEditor rule: Strip zero-width spaces, joiners, BOM, and soft hyphens
        text = regexReplace(text, pattern: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}\\u{00AD}]", template: "")
        // 2. Non-breaking spaces and tabs to normal spaces
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\t", with: " ")
        // 3. Smart quotes to straight quotes
        text = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        text = text.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        // 4. Remove any asterisks first so "* · Text" or "· *Text" exposes the leading bullet
        text = text.replacingOccurrences(of: "*", with: "")
        // 5. CotEditor rule: Strip leading bullets (including middle dot · \u{00B7}), hyphens, dashes, arrows, and list markers
        text = regexReplace(text, pattern: leadingBulletPattern, template: "")
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
    
    /// Runs the exact CotEditor AppleScript regex cleanup pass on every final output line
    static func applyFinalCotEditorCleanup(_ lines: [String]) -> [String] {
        var cleanedLines: [String] = []
        for rawLine in lines {
            var line = rawLine
            // 1. Strip zero-width spaces, joiners, BOM, soft hyphens
            line = regexReplace(line, pattern: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}\\u{00AD}]", template: "")
            // 2. Smart double and single quotes
            line = line.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            line = line.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            // 3. Non-breaking spaces to normal spaces
            line = line.replacingOccurrences(of: "\u{00A0}", with: " ")
            // 4. Leading bullets/hyphens/markers (^\h*[\•\·\-\_\–\—\*\>\»\▪\~\+]+\h*)
            line = regexReplace(line, pattern: leadingBulletPattern, template: "")
            // 5. Trailing colons or semicolons ((:|;)\h*$)
            line = regexReplace(line, pattern: "[:;]\\h*$", template: "")
            // 6. Collapse multiple horizontal spaces (\h\h+ -> " ")
            line = regexReplace(line, pattern: "\\h{2,}", template: " ")
            // 7. Trim leading and trailing horizontal whitespace (^\h+|\h+$)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !line.isEmpty {
                cleanedLines.append(line)
            }
        }
        return cleanedLines
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
        var text = regexReplace(input, pattern: leadingBulletPattern, template: "")
        text = regexReplace(text, pattern: "[:;]\\h*$", template: "").trimmingCharacters(in: .whitespaces)
        
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
            if seg.hasSuffix(";") || seg.hasSuffix(":") { seg.removeLast() }
            seg = regexReplace(seg, pattern: "^\\(([1-9]|1\\d)\\)\\s+", template: "")
            if seg.isEmpty { continue }
            
            for chunk in smartWrapText(seg, maxLen: availLen) {
                let cleanedChunk = regexReplace(chunk, pattern: "[:;]\\h*$", template: "")
                finalLines.append("\(fullPrefix)\(cleanedChunk)")
            }
        }
        return finalLines
    }
    
    // MARK: - Main Sermon Line Processor
    
    static func processSermonFile(
        url: URL,
        speaker: String,
        maxLineChars: Int = defaultMaxLineChars,
        fallbackTitle: String? = nil
    ) throws -> SermonProcessingResult {
        let clampedLimit = max(45, min(250, maxLineChars))
        let rawLines = try extractLines(from: url)
        var sermonTitle = ""
        var emailSubjectFallback = fallbackTitle ?? ""
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
            
            if line == slideBreakMarker {
                activeHeaderRef = nil
                activeHeaderHasVerse = false
                continue
            }
            
            if cleanEmailSender(line) != nil {
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
            
            // Standalone scripture reference line (including trailing "says:" or ":")
            if let standalone = regexFirstMatch(line, pattern: standaloneRefPattern) {
                let bookRaw = standalone[1]
                let numsRaw = standalone[2]
                var transRaw: String? = standalone[3].isEmpty ? nil : standalone[3]
                
                if transRaw == nil && idx < rawLines.count {
                    let nextClean = cleanBasicTypography(rawLines[idx])
                    if nextClean != slideBreakMarker,
                       regexFirstMatch(nextClean, pattern: "^\\(?(\(translationsRegex))\\)?(?:\\s*(?:says|reads))?\\s*[:;]?$") != nil {
                        transRaw = regexReplace(nextClean, pattern: "(?:\\s*(?:says|reads))?\\s*[:;]?$", template: "", caseInsensitive: true)
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
                if isVerseContinuation(line, hasSeenVerse: activeHeaderHasVerse, activeRef: activeRef) {
                    outputLines.append(contentsOf: splitLongVerse(refPrefix: activeRef, body: line, maxTotalLen: clampedLimit))
                    activeHeaderHasVerse = true
                    continue
                } else {
                    activeHeaderRef = nil
                    activeHeaderHasVerse = false
                }
            }
            
            let subLines = splitInlineParenRefs(line)
            
            for sub in subLines {
                if let topicColon = regexFirstMatch(sub, pattern: "^([A-Za-z\\s]+?)\\s*:\\s*\(refCorePattern)\\s*$") {
                    let topicName = formatTopicLine(topicColon[1].trimmingCharacters(in: .whitespaces))
                    let refLine = formatRefPrefix(topicColon[2], topicColon[3], topicColon[4].isEmpty ? nil : topicColon[4])
                    outputLines.append(contentsOf: splitPlainLine(topicName, maxLen: clampedLimit))
                    outputLines.append(refLine)
                    addScriptureRef(&scriptureList, refLine)
                    continue
                }
                
                if let leadMatch = regexFirstMatch(sub, pattern: "^\\(?(\(booksRegex))\\.?\\s*(\\d+\\s*:\\s*\\d+(?:\\s*-\\s*\\d+)?)\\s*\\(?(\(translationsRegex))?\\)?\\)?(?:\\s*(?:says|reads))?\\s*(?:[:\\-]\\s*)?(.*)$"),
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
        
        // Run final CotEditor cleanup pass across all output lines
        let finalCleanedLines = applyFinalCotEditorCleanup(outputLines)
        let cleanSpk = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return SermonProcessingResult(
            speaker: cleanSpk.isEmpty ? defaultSpeaker : cleanSpk,
            title: sermonTitle,
            lines: finalCleanedLines,
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
    
    private static func isVerseContinuation(_ line: String, hasSeenVerse: Bool, activeRef: String? = nil) -> Bool {
        if regexFirstMatch(line, pattern: "^\\d{1,3}[.)]\\s+", caseInsensitive: false) != nil {
            return false
        }
        if regexFirstMatch(line, pattern: "^(?:The\\s+Hebrew|The\\s+Greek|In\\s+[A-Z]|Key\\s+|This\\s+implies|The\\s+scripture|The\\s+verse|Know\\b)\\b", caseInsensitive: false) != nil {
            return false
        }
        if regexFirstMatch(line, pattern: "^\\d{1,3}\\s+[A-Z\\[\"“]", caseInsensitive: false) != nil {
            return true
        }
        if !hasSeenVerse && !line.hasSuffix(":") {
            return true
        }
        if regexFirstMatch(line, pattern: "(?<=[.?!;:,\"\\]])\\s+\\d{1,2}\\s+[A-Z\\[\"“]", caseInsensitive: false) != nil {
            return true
        }
        if let ref = activeRef, ref.contains("-"), line.count >= 50, !line.hasSuffix(":") {
            return true
        }
        return false
    }
    
    private static func extractTitleFromFilename(_ url: URL) -> String {
        var stem = url.lastPathComponent
        for ext in [".eml.txt", ".eml", ".docx", ".pptx", ".ppt", ".pdf", ".txt"] {
            if stem.lowercased().hasSuffix(ext) {
                stem = String(stem.dropLast(ext.count))
                break
            }
        }
        stem = regexReplace(stem, pattern: "\\s*[-_]\\s*OUTLINES?\\b.*$", template: "", caseInsensitive: true)
        stem = regexReplace(stem, pattern: "\\.\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\b.*$", template: "")
        let cleaned = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        if ["over head outline", "overhead outline", "sermon outline", "outline", "over head", "overhead"].contains(cleaned.lowercased()) {
            return ""
        }
        return cleaned
    }
    
    static func cleanEmailSender(_ line: String) -> String? {
        guard let m = regexFirstMatch(line, pattern: "^From\\s*:\\s*(.+)$") else { return nil }
        var val = m[1].trimmingCharacters(in: .whitespaces)
        val = regexReplace(val, pattern: "\\s*<[^>]+>", template: "")
        val = regexReplace(val, pattern: "\\s*\\[mailto:[^\\]]+\\]", template: "")
        val = regexReplace(val, pattern: "\\s*\\b[\\w.\\-+]+@[\\w.\\-]+\\.\\w+\\b", template: "")
        return val.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}
