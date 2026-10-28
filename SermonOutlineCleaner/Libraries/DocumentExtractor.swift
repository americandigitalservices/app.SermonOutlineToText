import Foundation
import PDFKit
import AppKit

//
//  DocumentExtractor.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

nonisolated enum SermonCleanerError: LocalizedError, Sendable {
    case unreadablePDF(URL)
    case unreadablePowerPoint(URL)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url):
            return "Could not read PDF file \"\(url.lastPathComponent)\"."
        case .unreadablePowerPoint:
            return "Could not extract text from PowerPoint file. If this is an older .ppt file, please re-save it as .pptx."
        }
    }
}

/// Extracts raw text lines, document author metadata, and fallback titles from `.docx`, `.pptx`, `.ppt`, `.pdf`, `.eml`, and `.txt` files.
nonisolated enum DocumentExtractor {

    // MARK: - Document Author Metadata Extraction & Name Flipping

    static func extractDocumentAuthor(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var rawAuthor: String? = nil

        // 1. OpenXML (.docx / .pptx): Read <dc:creator> directly from docProps/core.xml
        if ext == "docx" || ext == "pptx" {
            let coreXML = runUnzipPipe(zipURL: url, entryPath: "docProps/core.xml")
            if let match = RegexCache.firstMatch(coreXML, pattern: "(?s)<dc:creator[^>]*>(.*?)</dc:creator>") {
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

        // 4. Legacy PowerPoint (.ppt) or general fallback via Spotlight NSMetadataItem metadata
        if rawAuthor == nil,
           let metadataItem = NSMetadataItem(url: url),
           let authors = metadataItem.value(forAttribute: NSMetadataItemAuthorsKey) as? [String],
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

        // Ignore generic/system placeholder author names or raw email addresses
        let ignoredAuthors: Set<String> = [
            "microsoft office user", "windows user", "user", "admin", "administrator",
            "owner", "preferred customer", "authorized user", "default"
        ]
        if name.isEmpty || name.contains("@") || ignoredAuthors.contains(name.lowercased()) {
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

        return RegexCache.replace(name, pattern: "\\s+", template: " ")
    }

    // MARK: - File Extraction (.docx, .pptx, .ppt, .pdf, .eml, .txt)

    static func extractLines(from url: URL) throws -> [String] {
        if EmailMimeParser.isEmlFile(url) {
            return mergeOrphanVerseNumberLines(try EmailMimeParser.extractLinesFromEml(url))
        }

        let ext = url.pathExtension.lowercased()
        var rawLines: [String] = []

        if ext == "docx" {
            let attrStr = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            let normalized = attrStr.string
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            for line in normalized.components(separatedBy: "\n") {
                let s = line
                    .replacingOccurrences(of: "\u{2028}", with: " ")
                    .replacingOccurrences(of: "\u{2029}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { rawLines.append(s) }
            }
        } else if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else {
                throw SermonCleanerError.unreadablePDF(url)
            }
            var pdfPageLines: [String] = []
            for i in 0..<pdf.pageCount {
                if let pageText = pdf.page(at: i)?.string {
                    let normalized = pageText
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                    for line in normalized.components(separatedBy: "\n") {
                        let s = line
                            .replacingOccurrences(of: "\u{2028}", with: " ")
                            .replacingOccurrences(of: "\u{2029}", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { pdfPageLines.append(s) }
                    }
                }
            }
            rawLines = reflowPdfLines(pdfPageLines)
        } else if ext == "pptx" || ext == "ppt" {
            rawLines = try extractLinesFromPowerPoint(url)
        } else {
            let text = try String(contentsOf: url, encoding: .utf8)
            let normalized = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            for line in normalized.components(separatedBy: "\n") {
                let s = line
                    .replacingOccurrences(of: "\u{2028}", with: " ")
                    .replacingOccurrences(of: "\u{2029}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { rawLines.append(s) }
            }
        }

        return mergeOrphanVerseNumberLines(rawLines)
    }

    /// Joins hard-wrapped PDF lines that were broken mid-sentence or mid-quote by PDF column layout.
    static func reflowPdfLines(_ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }
        var result: [String] = []
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let prev = result.last else {
                result.append(trimmed)
                continue
            }
            let prevClean = TypographyAndWrapping.cleanBasicTypography(prev)
            let currClean = TypographyAndWrapping.cleanBasicTypography(trimmed)

            let prevIsStandaloneRef = RegexCache.firstMatch(prevClean, pattern: ScriptureReferenceKit.standaloneRefPattern) != nil
            let currIsStandaloneRef = RegexCache.firstMatch(currClean, pattern: ScriptureReferenceKit.standaloneRefPattern) != nil
            let currStartsWithRef = RegexCache.firstMatch(currClean, pattern: "^\\(?(\(ScriptureReferenceKit.booksRegex))\\.?\\s*\(ScriptureReferenceKit.chapterVersePattern)") != nil
            let currIsOutlineHeading = RegexCache.firstMatch(currClean, pattern: "^(?:[IVX]{1,4}|[A-Z]|\\d{1,2})[.)]\\s+", caseInsensitive: false) != nil
            let currStartsWithBullet = RegexCache.firstMatch(trimmed, pattern: TypographyAndWrapping.leadingBulletPattern) != nil

            if prevIsStandaloneRef || currIsStandaloneRef || currStartsWithRef || currIsOutlineHeading || currStartsWithBullet {
                result.append(trimmed)
                continue
            }

            let prevQuoteCount = prevClean.filter { $0 == "\"" }.count
            let hasUnclosedQuote = (prevQuoteCount % 2 == 1)
            let endsWithTerminalPunct = RegexCache.firstMatch(prevClean, pattern: "[.?!][\"')\\]]*$") != nil

            if hasUnclosedQuote || !endsWithTerminalPunct {
                result[result.count - 1] = "\(prev) \(trimmed)"
            } else {
                result.append(trimmed)
            }
        }
        return result
    }

    static func extractLinesFromPowerPoint(_ url: URL) throws -> [String] {
        let ext = url.pathExtension.lowercased()

        if ext == "pptx" {
            let listTask = Process()
            let listPipe = Pipe()
            listTask.executableURL = URL(filePath: "/usr/bin/unzip")
            listTask.arguments = ["-Z1", url.path(percentEncoded: false)]
            listTask.standardOutput = listPipe
            try listTask.run()
            // Read pipe data before waitUntilExit to avoid 64KB pipe buffer deadlock
            let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
            listTask.waitUntilExit()

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
                extracted.append(TypographyAndWrapping.slideBreakMarker)
            }

            if !extracted.isEmpty {
                return extracted
            }
        }

        if let metadataItem = NSMetadataItem(url: url),
           let textContent = metadataItem.value(forAttribute: NSMetadataItemTextContentKey) as? String {
            let lines = textContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return lines }
        }

        throw SermonCleanerError.unreadablePowerPoint(url)
    }

    static func runUnzipPipe(zipURL: URL, entryPath: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(filePath: "/usr/bin/unzip")
        task.arguments = ["-p", zipURL.path(percentEncoded: false), entryPath]
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            return ""
        }
        // Always drain stdout before waitUntilExit so entries larger than 64KB never deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func parsePowerPointXMLParagraphs(_ xml: String) -> [String] {
        let withLineBreaks = RegexCache.replace(xml, pattern: "<a:br\\s*/?>", template: "\n")
        let paragraphs = RegexCache.matches(withLineBreaks, pattern: "(?s)<a:p\\b[^>]*>(.*?)</a:p>")
        var lines: [String] = []

        for para in paragraphs {
            let paraContent = para[1]
            for subSegment in paraContent.components(separatedBy: "\n") {
                let textRuns = RegexCache.matches(subSegment, pattern: "(?s)<a:t\\b[^>]*>(.*?)</a:t>")
                let joined = textRuns.map { decodeXMLEntities($0[1]) }.joined()
                let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, Int(trimmed) == nil {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }

    static func decodeXMLEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    static func mergeOrphanVerseNumberLines(_ lines: [String]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < lines.count {
            let curr = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if curr != TypographyAndWrapping.slideBreakMarker,
               RegexCache.firstMatch(curr, pattern: "^\\d{1,3}$") != nil,
               (i + 1) < lines.count,
               lines[i + 1] != TypographyAndWrapping.slideBreakMarker {
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

    static func extractTitleFromFilename(_ url: URL) -> String {
        var stem = url.lastPathComponent
        for ext in [".eml.txt", ".eml", ".docx", ".pptx", ".ppt", ".pdf", ".txt"] {
            if stem.lowercased().hasSuffix(ext) {
                stem = String(stem.dropLast(ext.count))
                break
            }
        }
        stem = RegexCache.replace(stem, pattern: "\\s*\\([^)]*\\)", template: "")
        stem = RegexCache.replace(stem, pattern: "\\s*[-_]\\s*OUTLINES?\\b.*$", template: "", caseInsensitive: true)
        stem = RegexCache.replace(stem, pattern: "[_.\\s-]+\\d{1,2}[._-]\\d{1,2}[._-]\\d{2,4}\\b.*$", template: "")
        if stem.contains(" - ") {
            let parts = stem.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
            let filtered = parts.filter { part in
                RegexCache.firstMatch(part, pattern: "^(?:outlines?|sermon.*notes.*)$", caseInsensitive: true) == nil
            }
            if let last = filtered.last, !last.isEmpty {
                stem = last
            }
        }
        stem = stem.replacingOccurrences(of: "_", with: " ")
        stem = RegexCache.replace(stem, pattern: "\\s{2,}", template: " ")
        let cleaned = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        if ["over head outline", "overhead outline", "sermon outline", "outline", "over head", "overhead"].contains(cleaned.lowercased()) {
            return ""
        }
        return TypographyAndWrapping.smartTitleCase(cleaned)
    }
}
