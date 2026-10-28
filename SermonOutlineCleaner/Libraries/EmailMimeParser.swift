import Foundation
import AppKit

//
//  EmailMimeParser.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

nonisolated struct EmlAttachment: Sendable, Equatable {
    let filename: String
    let data: Data
}

nonisolated struct EmlInspection: Sendable, Equatable {
    let sender: String?
    let subject: String?
    let attachments: [EmlAttachment]
}

/// Parses RFC-822 `.eml` messages, RFC-2047 headers, Quoted-Printable/Base64 MIME parts, and attachments.
nonisolated enum EmailMimeParser {

    static func isEmlFile(_ url: URL) -> Bool {
        let nameLower = url.lastPathComponent.lowercased()
        if nameLower.hasSuffix(".eml") || nameLower.hasSuffix(".eml.txt") { return true }
        if url.pathExtension.lowercased() == "txt",
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let head = String(content.prefix(1024))
            if RegexCache.firstMatch(head, pattern: "(?m)^(?:Delivered-To|Return-Path|Received|MIME-Version|Content-Type):") != nil {
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
        let unfoldedHeader = RegexCache.replace(rawHeader, pattern: "\\n[ \\t]+", template: " ")

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
                    subject = TypographyAndWrapping.smartTitleCase(cleaned)
                }
            }
        }

        let attachments = extractSupportedAttachments(from: normalized, headerBlock: unfoldedHeader)
        return EmlInspection(sender: sender, subject: subject, attachments: attachments)
    }

    static func decodeRFC2047Words(_ input: String) -> String {
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]+)\\?="
        guard let rx = RegexCache.compiled(pattern: pattern) else { return input }
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

    static func extractSupportedAttachments(from fullNormalizedEml: String, headerBlock: String) -> [EmlAttachment] {
        let boundaryMatches = RegexCache.matches(fullNormalizedEml, pattern: "boundary=\"?([^\"\\s;]+)\"?")
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
            let unfoldedPartHeader = decodeRFC2047Words(RegexCache.replace(rawPartHeader, pattern: "\\n[ \\t]+", template: " "))

            let filenameMatch = RegexCache.firstMatch(unfoldedPartHeader, pattern: "(?:filename|name)\\*?=\\\"?([^\\\"\\r\\n;]+)\\\"?")
            guard var filename = filenameMatch?[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"';")) else {
                continue
            }
            if let utf8PrefixRange = filename.range(of: "UTF-8''", options: .caseInsensitive) {
                filename = String(filename[utf8PrefixRange.upperBound...])
            }
            filename = filename.removingPercentEncoding ?? filename

            let ext = URL(filePath: filename).pathExtension.lowercased()
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

    static func decodeQuotedPrintable(_ input: String) -> String {
        let softStripped = input
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        let utf8 = Array(softStripped.utf8)
        bytes.reserveCapacity(utf8.count)
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
        let headerBlock = RegexCache.replace(rawHeader, pattern: "\\n[ \\t]+", template: " ")
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

        let boundaryMatches = RegexCache.matches(normalized, pattern: "boundary=\"?([^\"\\s;]+)\"?")
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
        let paragraphs = RegexCache.replace(bodyText, pattern: "\\n\\s*\\n", template: "\u{0000}").components(separatedBy: "\u{0000}")
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

                let currIsRef = RegexCache.firstMatch(currClean, pattern: ScriptureReferenceKit.standaloneRefPattern) != nil
                let nxtIsRef = RegexCache.firstMatch(nxtClean, pattern: ScriptureReferenceKit.standaloneRefPattern) != nil
                let startsWithVerseNum = RegexCache.firstMatch(nxtClean, pattern: "^\\d{1,3}\\s+[A-Z\"“]", caseInsensitive: false) != nil

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
        var subj = RegexCache.replace(subjectRaw, pattern: "\\s+", template: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        subj = RegexCache.replace(
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

    static func cleanEmailSender(_ line: String) -> String? {
        guard let m = RegexCache.firstMatch(line, pattern: "^From\\s*:\\s*(.+)$") else { return nil }
        var val = m[1].trimmingCharacters(in: .whitespaces)
        val = RegexCache.replace(val, pattern: "\\s*<[^>]+>", template: "")
        val = RegexCache.replace(val, pattern: "\\s*\\[mailto:[^\\]]+\\]", template: "")
        val = RegexCache.replace(val, pattern: "\\s*\\b[\\w.\\-+]+@[\\w.\\-]+\\.\\w+\\b", template: "")
        return val.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}
