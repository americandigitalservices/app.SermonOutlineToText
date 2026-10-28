import Foundation

//
//  SermonCleanerEngine.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

nonisolated struct SermonProcessingResult: Sendable, Equatable {
    var speaker: String
    var title: String
    var lines: [String]
    var scriptures: [String]
}

/// Core state-machine parser that orchestrates document extraction, scripture canonicalization,
/// typography cleanup, and smart line wrapping to produce ProPresenter-ready sermon files.
nonisolated final class SermonCleanerEngine: Sendable {

    static let defaultMaxLineChars = 105
    static let defaultSpeaker = "Pastor John"
    static let slideBreakMarker = TypographyAndWrapping.slideBreakMarker

    // MARK: - Main Sermon Line Processor

    static func processSermonFile(
        url: URL,
        speaker: String,
        maxLineChars: Int = defaultMaxLineChars,
        fallbackTitle: String? = nil
    ) throws -> SermonProcessingResult {
        let clampedLimit = max(45, min(250, maxLineChars))
        let rawLines = try DocumentExtractor.extractLines(from: url)
        let cleanSpk = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSpeaker = cleanSpk.isEmpty ? defaultSpeaker : cleanSpk

        var sermonTitle = ""
        var emailSubjectFallback = fallbackTitle ?? ""
        var outputLines: [String] = []
        var scriptureList: [String] = []

        var activeHeaderRef: String? = nil
        var activeHeaderHasVerse = false
        var activeHeaderReachedEndVerse = false
        var prevVerseContinues = false
        var seenFirstContentLine = false

        var idx = 0
        while idx < rawLines.count {
            let rawLine = rawLines[idx]
            let line = TypographyAndWrapping.cleanBasicTypography(rawLine)
            idx += 1
            if line.isEmpty { continue }

            if line == slideBreakMarker {
                activeHeaderRef = nil
                activeHeaderHasVerse = false
                activeHeaderReachedEndVerse = false
                prevVerseContinues = false
                continue
            }

            if EmailMimeParser.cleanEmailSender(line) != nil {
                continue
            }

            if let subjMatch = RegexCache.firstMatch(line, pattern: "^Subject\\s*:\\s*(.+)$") {
                let cleanedSubj = EmailMimeParser.cleanEmailSubject(subjMatch[1])
                if !cleanedSubj.isEmpty {
                    emailSubjectFallback = TypographyAndWrapping.smartTitleCase(cleanedSubj)
                }
                continue
            }

            if RegexCache.firstMatch(line, pattern: "^(?:Date|Sent|To|Cc)\\s*:\\s*") != nil { continue }

            if ["SERMON:", "TITLE:"].contains(line.uppercased()), idx < rawLines.count {
                sermonTitle = TypographyAndWrapping.smartTitleCase(
                    TypographyAndWrapping.cleanBasicTypography(rawLines[idx])
                )
                seenFirstContentLine = true
                idx += 1
                continue
            } else if RegexCache.firstMatch(line, pattern: "^(?:SERMON|TITLE)\\s*:") != nil {
                let rawTitle = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                sermonTitle = TypographyAndWrapping.smartTitleCase(rawTitle)
                seenFirstContentLine = true
                continue
            }

            if !seenFirstContentLine {
                seenFirstContentLine = true
                let isOutlinePoint = RegexCache.firstMatch(line, pattern: "^(?:[IVX]{1,4}|[A-Z]|\\d{1,2})[.)]\\s+", caseInsensitive: false) != nil
                if sermonTitle.isEmpty && line.count < 65 && !isOutlinePoint {
                    if RegexCache.firstMatch(line, pattern: ScriptureReferenceKit.refCorePattern) == nil && !line.hasSuffix(":") {
                        sermonTitle = TypographyAndWrapping.smartTitleCase(line)
                        continue
                    }
                }
            }

            // Skip speaker byline at the top of the outline (e.g. "Sarah Y Masih" right under the sermon title)
            if outputLines.isEmpty && isSpeakerByline(line, speaker: effectiveSpeaker) {
                continue
            }

            if ["TOPIC:", "TOPIC"].contains(line.uppercased()) { continue }

            // Standalone scripture reference line (including trailing "says:" or ":")
            if let standalone = RegexCache.firstMatch(line, pattern: ScriptureReferenceKit.standaloneRefPattern) {
                let bookRaw = standalone[1]
                let numsRaw = standalone[2]
                var transRaw: String? = standalone[3].isEmpty ? nil : standalone[3]

                if transRaw == nil && idx < rawLines.count {
                    let nextClean = TypographyAndWrapping.cleanBasicTypography(rawLines[idx])
                    if nextClean != slideBreakMarker,
                       RegexCache.firstMatch(nextClean, pattern: "^\\(?(\(ScriptureReferenceKit.translationsRegex))\\)?(?:\\s*(?:says|reads))?\\s*[:;,]?$") != nil {
                        transRaw = RegexCache.replace(nextClean, pattern: "(?:\\s*(?:says|reads))?\\s*[:;,]?$", template: "", caseInsensitive: true)
                        idx += 1
                    }
                }

                let formattedRef = ScriptureReferenceKit.formatRefPrefix(bookRaw, numsRaw, transRaw)
                activeHeaderRef = formattedRef
                activeHeaderHasVerse = false
                activeHeaderReachedEndVerse = false
                prevVerseContinues = false
                ScriptureReferenceKit.addScriptureRef(&scriptureList, formattedRef)
                continue
            }

            if let activeRef = activeHeaderRef {
                if isVerseContinuation(
                    line,
                    hasSeenVerse: activeHeaderHasVerse,
                    activeRef: activeRef,
                    prevLineContinues: prevVerseContinues,
                    hasReachedEndVerse: activeHeaderReachedEndVerse
                ) {
                    outputLines.append(contentsOf: TypographyAndWrapping.splitLongVerse(refPrefix: activeRef, body: line, maxTotalLen: clampedLimit))
                    activeHeaderHasVerse = true
                    let trimmedRaw = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    prevVerseContinues = RegexCache.firstMatch(trimmedRaw, pattern: "[,;:]$") != nil
                    if !prevVerseContinues && lineContainsEndVerse(line, activeRef: activeRef) {
                        activeHeaderReachedEndVerse = true
                    }
                    continue
                } else {
                    activeHeaderRef = nil
                    activeHeaderHasVerse = false
                    activeHeaderReachedEndVerse = false
                    prevVerseContinues = false
                }
            }

            let subLines = ScriptureReferenceKit.splitInlineParenRefs(line)

            for sub in subLines {
                if let topicColon = RegexCache.firstMatch(sub, pattern: "^([A-Za-z\\s]+?)\\s*:\\s*\(ScriptureReferenceKit.refCorePattern)\\s*$") {
                    let topicName = TypographyAndWrapping.formatTopicLine(topicColon[1].trimmingCharacters(in: .whitespaces))
                    let refLine = ScriptureReferenceKit.formatRefPrefix(topicColon[2], topicColon[3], topicColon[4].isEmpty ? nil : topicColon[4])
                    outputLines.append(contentsOf: TypographyAndWrapping.splitPlainLine(topicName, maxLen: clampedLimit))
                    outputLines.append(refLine)
                    ScriptureReferenceKit.addScriptureRef(&scriptureList, refLine)
                    continue
                }

                let leadPattern = "^\\(?(\(ScriptureReferenceKit.booksRegex))\\.?\\s*(\(ScriptureReferenceKit.chapterVersePattern))\\s*\\(?(\(ScriptureReferenceKit.translationsRegex))?\\)?\\)?(?:\\s*(?:says|reads)\\s*,?)?\\s*(?:[:\\-]\\s*)?(.*)$"
                if let leadMatch = RegexCache.firstMatch(sub, pattern: leadPattern),
                   !leadMatch[4].isEmpty {
                    let bookRaw = leadMatch[1]
                    var numsRaw = leadMatch[2]
                    var leadTrans: String? = leadMatch[3].isEmpty ? nil : leadMatch[3]
                    var body = leadMatch[4].trimmingCharacters(in: .whitespaces)

                    if !body.hasPrefix(";") {
                        let trailPattern = "\\s*\\(?(\(ScriptureReferenceKit.translationsRegex))\\)?\\.?\\s*$"
                        if let trailMatch = RegexCache.firstMatch(body, pattern: trailPattern) {
                            if leadTrans == nil { leadTrans = trailMatch[1] }
                            body = RegexCache.replace(body, pattern: trailPattern, template: "", caseInsensitive: true)
                        }

                        (numsRaw, leadTrans) = mergeWithPreviousStandaloneRef(
                            outputLines: &outputLines,
                            scriptureList: &scriptureList,
                            bookRaw: bookRaw,
                            numsRaw: numsRaw,
                            leadTrans: leadTrans
                        )

                        let refPrefix = ScriptureReferenceKit.formatRefPrefix(bookRaw, numsRaw, leadTrans)
                        ScriptureReferenceKit.addScriptureRef(&scriptureList, refPrefix)
                        outputLines.append(contentsOf: TypographyAndWrapping.splitLongVerse(refPrefix: refPrefix, body: body, maxTotalLen: clampedLimit))
                        continue
                    }
                }

                let formattedTopic = ScriptureReferenceKit.standardizeRefsInText(TypographyAndWrapping.formatTopicLine(sub))

                let multiRefMatch = RegexCache.firstMatch(
                    formattedTopic,
                    pattern: "^(\(ScriptureReferenceKit.booksRegex)\\s+\(ScriptureReferenceKit.chapterVersePattern)(?:\\s*;\\s*\(ScriptureReferenceKit.booksRegex)\\s+\(ScriptureReferenceKit.chapterVersePattern))+)"
                )
                let inlineCite = RegexCache.firstMatch(
                    formattedTopic,
                    pattern: "\\((\(ScriptureReferenceKit.booksRegex)\\s+\(ScriptureReferenceKit.chapterVersePattern))\\)\\s+[A-Z\"]"
                )

                outputLines.append(contentsOf: TypographyAndWrapping.splitPlainLine(formattedTopic, maxLen: clampedLimit))

                if let multi = multiRefMatch {
                    let refs = multi[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    outputLines.append(contentsOf: refs)
                    for r in refs {
                        ScriptureReferenceKit.addScriptureRef(&scriptureList, r)
                    }
                    continue
                }

                if let cite = inlineCite {
                    outputLines.append(cite[1])
                    ScriptureReferenceKit.addScriptureRef(&scriptureList, cite[1])
                    continue
                }

                for m in RegexCache.matches(formattedTopic, pattern: ScriptureReferenceKit.refCorePattern) {
                    let extractedRef = ScriptureReferenceKit.formatRefPrefix(m[1], m[2], m[3].isEmpty ? nil : m[3])
                    ScriptureReferenceKit.addScriptureRef(&scriptureList, extractedRef)
                }
            }
        }

        if sermonTitle.isEmpty {
            sermonTitle = !emailSubjectFallback.isEmpty ? emailSubjectFallback : DocumentExtractor.extractTitleFromFilename(url)
        }

        let finalCleanedLines = TypographyAndWrapping.applyFinalCotEditorCleanup(outputLines)

        return SermonProcessingResult(
            speaker: effectiveSpeaker,
            title: sermonTitle,
            lines: finalCleanedLines,
            scriptures: scriptureList
        )
    }

    // MARK: - State-Machine Helpers

    private static func isSpeakerByline(_ line: String, speaker: String) -> Bool {
        var cleaned = RegexCache.replace(line, pattern: "^(?:by|speaker|pastor|rev\\.?|reverend|minister|dr\\.?)\\s*:?\\s+", template: "", caseInsensitive: true)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 40 else { return false }

        if cleaned.lowercased() == speaker.lowercased() {
            return true
        }

        let speakerTokens = speaker.lowercased().split(separator: " ").map(String.init)
        let lineTokens = cleaned.lowercased().replacingOccurrences(of: ".", with: "").split(separator: " ").map(String.init)
        if speakerTokens.count >= 2,
           lineTokens.count >= 2 && lineTokens.count <= 4,
           lineTokens.allSatisfy({ $0.allSatisfy(\.isLetter) }),
           lineTokens.first == speakerTokens.first,
           lineTokens.last == speakerTokens.last {
            return true
        }
        return false
    }

    private static func lineContainsEndVerse(_ line: String, activeRef: String) -> Bool {
        let verses = ScriptureReferenceKit.verseNumbersInReference(activeRef)
        guard verses.count >= 2, let maxVerse = verses.max() else { return false }
        let pattern = "(?:^|(?<=[.?!;:,\"\\]])\\s+)\(maxVerse)[.)]?\\s+[A-Z\\[\"“]"
        return RegexCache.firstMatch(line, pattern: pattern, caseInsensitive: false) != nil
            && RegexCache.firstMatch(line, pattern: "[.?!][\"')\\]]*$") != nil
    }

    private static func mergeWithPreviousStandaloneRef(
        outputLines: inout [String],
        scriptureList: inout [String],
        bookRaw: String,
        numsRaw: String,
        leadTrans: String?
    ) -> (String, String?) {
        guard let prevLine = outputLines.last,
              let prevMatch = RegexCache.firstMatch(prevLine, pattern: "^\(ScriptureReferenceKit.refCorePattern)$") else {
            return (numsRaw, leadTrans)
        }
        let prevBook = prevMatch[1]
        let prevNums = prevMatch[2]
        let prevTrans: String? = prevMatch[3].isEmpty ? nil : prevMatch[3]

        let currChap = numsRaw.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)
        let prevChap = prevNums.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)

        if ScriptureReferenceKit.getCanonicalBook(bookRaw) == ScriptureReferenceKit.getCanonicalBook(prevBook)
            && currChap == prevChap
            && prevNums.contains(":") {
            let popped = outputLines.removeLast()
            if scriptureList.last == popped { scriptureList.removeLast() }
            let cleanPrev = prevNums.replacingOccurrences(of: " ", with: "")
            let cleanCurr = numsRaw.replacingOccurrences(of: " ", with: "")
            let bestNums = cleanPrev.count >= cleanCurr.count ? cleanPrev : cleanCurr
            return (bestNums, leadTrans ?? prevTrans)
        }
        return (numsRaw, leadTrans)
    }

    private static func isVerseContinuation(
        _ line: String,
        hasSeenVerse: Bool,
        activeRef: String? = nil,
        prevLineContinues: Bool = false,
        hasReachedEndVerse: Bool = false
    ) -> Bool {
        if RegexCache.firstMatch(line, pattern: "^\\(?(\(ScriptureReferenceKit.booksRegex))\\.?\\s*\(ScriptureReferenceKit.chapterVersePattern)") != nil {
            return false
        }
        if let numbered = RegexCache.firstMatch(line, pattern: "^(\\d{1,3})[.)]\\s+(.*)$", caseInsensitive: false) {
            if let num = Int(numbered[1]),
               ScriptureReferenceKit.verseNumbersInReference(activeRef).contains(num) {
                let remainder = numbered[2].trimmingCharacters(in: .whitespaces)
                if remainder != remainder.uppercased() {
                    return true
                }
            }
            return false
        }
        if RegexCache.firstMatch(line, pattern: "^(?:The\\s+Hebrew|The\\s+Greek|In\\s+[A-Z]|Key\\s+|This\\s+implies|The\\s+scripture|The\\s+verse|Know\\b)\\b", caseInsensitive: false) != nil {
            return false
        }
        if RegexCache.firstMatch(line, pattern: "\\bStrong's\\b|\\b(?:Greek|Hebrew)\\s*#?\\d+", caseInsensitive: true) != nil {
            return false
        }
        if RegexCache.firstMatch(line, pattern: "^\\d{1,3}\\s+[A-Z\\[\"“]", caseInsensitive: false) != nil {
            return true
        }
        if !hasSeenVerse && !line.hasSuffix(":") {
            return true
        }
        if prevLineContinues {
            return true
        }
        if RegexCache.firstMatch(line, pattern: "(?<=[.?!;:,\"\\]])\\s+\\d{1,2}[.)]?\\s+[A-Z\\[\"“]", caseInsensitive: false) != nil {
            return true
        }
        if let ref = activeRef {
            if (ref.contains("-") || !ref.contains(":")),
               RegexCache.firstMatch(line, pattern: "^(?:And|But|For|Nor|Or|Yet|When|While|Who|Whom|Whose|Which|That|To|Lest|Because|How\\s+long|I\\s+(?:have|will|am|keep)|You\\s+(?:are|have|will))\\b", caseInsensitive: false) != nil,
               !line.hasSuffix(":") {
                return true
            }
            if !hasReachedEndVerse, ref.contains("-"), line.count >= 50, !line.hasSuffix(":") {
                return true
            }
        }
        return false
    }

    // MARK: - Convenience Facades to Extracted Libraries

    static func smartTitleCase(_ input: String) -> String {
        TypographyAndWrapping.smartTitleCase(input)
    }

    static func cleanBasicTypography(_ input: String) -> String {
        TypographyAndWrapping.cleanBasicTypography(input)
    }

    static func applyFinalCotEditorCleanup(_ lines: [String]) -> [String] {
        TypographyAndWrapping.applyFinalCotEditorCleanup(lines)
    }

    static func smartWrapText(_ input: String, maxLen: Int) -> [String] {
        TypographyAndWrapping.smartWrapText(input, maxLen: maxLen)
    }

    static func formatRefPrefix(_ bookRaw: String, _ numbersRaw: String, _ transRaw: String? = nil) -> String {
        ScriptureReferenceKit.formatRefPrefix(bookRaw, numbersRaw, transRaw)
    }

    static func standardizeRefsInText(_ text: String) -> String {
        ScriptureReferenceKit.standardizeRefsInText(text)
    }

    static func isEmlFile(_ url: URL) -> Bool {
        EmailMimeParser.isEmlFile(url)
    }

    static func inspectEmlFile(_ url: URL) -> EmlInspection {
        EmailMimeParser.inspectEmlFile(url)
    }

    static func extractDocumentAuthor(from url: URL) -> String? {
        DocumentExtractor.extractDocumentAuthor(from: url)
    }

    static func normalizeAuthorName(_ raw: String) -> String? {
        DocumentExtractor.normalizeAuthorName(raw)
    }

    static func extractLines(from url: URL) throws -> [String] {
        try DocumentExtractor.extractLines(from: url)
    }
}
