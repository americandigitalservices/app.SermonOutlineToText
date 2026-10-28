import Foundation
import Testing
@testable import SermonOutlineCleaner

struct SermonOutlineCleanerTests {

    private static var testFilesDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestFiles", directoryHint: .isDirectory)
    }

    static func allTestFileURLs() -> [URL] {
        let dir = testFilesDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("Smart title case preserves contractions, Roman numerals, and dotted acronyms")
    func smartTitleCaseFormatting() {
        #expect(SermonCleanerEngine.smartTitleCase("GOD'S GRACE - PART II") == "God's Grace - Part II")
        #expect(SermonCleanerEngine.smartTitleCase("DON'T STEP BACK") == "Don't Step Back")
        #expect(SermonCleanerEngine.smartTitleCase("THE WALK OF THE SPIRIT") == "The Walk Of The Spirit")
        #expect(SermonCleanerEngine.smartTitleCase("HOW TO L.I.S.T.E.N. TO GOD'S VOICE") == "How To L.I.S.T.E.N. To God's Voice")
    }

    @Test("Scripture book, comma-separated verses, and translation year canonicalization")
    func scriptureNormalization() {
        #expect(SermonCleanerEngine.formatRefPrefix("1 cor.", "13 : 4 - 7", "amplified bible, classic edition") == "1 Corinthians 13:4-7 (AMPC)")
        #expect(SermonCleanerEngine.formatRefPrefix("1 cor", "3 : 9 , 11", nil) == "1 Corinthians 3:9,11")
        #expect(SermonCleanerEngine.formatRefPrefix("1 john", "5:4-5", "KJV 1900") == "1 John 5:4-5 (KJV)")
        #expect(SermonCleanerEngine.formatRefPrefix("ii tim", "1:7", "nkjv") == "2 Timothy 1:7 (NKJV)")
        #expect(SermonCleanerEngine.formatRefPrefix("psalm", "23:1", nil) == "Psalm 23:1")
        #expect(SermonCleanerEngine.standardizeRefsInText("Read rom 8:28 (esv) today") == "Read Romans 8:28 (ESV) today")
    }

    @Test("Author name normalization flips Last, First and ignores placeholders or emails")
    func authorNameNormalization() {
        #expect(SermonCleanerEngine.normalizeAuthorName("Fink, Ernest") == "Ernest Fink")
        #expect(SermonCleanerEngine.normalizeAuthorName("Smith, Jr., John") == "Smith, Jr., John")
        #expect(SermonCleanerEngine.normalizeAuthorName("Windows User") == nil)
        #expect(SermonCleanerEngine.normalizeAuthorName("hinaymasih@gmail.com") == nil)
        #expect(SermonCleanerEngine.normalizeAuthorName("  Sarah   Masih ; Other ") == "Sarah Masih")
    }

    @Test("Typography and CotEditor cleanup rules")
    func typographyAndCotEditorCleanup() {
        let dirty = "  • \u{200B}“God’s Word”[a] — 1—3  ; "
        let basicCleaned = SermonCleanerEngine.cleanBasicTypography(dirty)
        #expect(basicCleaned == "\"God's Word\" - 1-3 ;")

        // Attached BibleGateway footnotes like way[b] or land,[c] and dotted acronyms like L.I.S.T.E.N.
        let footnoteAndAcronym = "a long way[b] from the land,[c] HOW TO L.I.S.T.E.N. TO GOD"
        #expect(SermonCleanerEngine.cleanBasicTypography(footnoteAndAcronym) == "a long way from the land, HOW TO L.I.S.T.E.N. TO GOD")

        // Angle-bracketed hyperlink URLs from plain-text email conversion
        let hyperlinkedRef = "*2 Corinthians 12:10* <http://www.crossbooks.com/verse.asp?ref=2Co+12%3A10>"
        #expect(SermonCleanerEngine.cleanBasicTypography(hyperlinkedRef) == "2 Corinthians 12:10")

        let finalCleaned = SermonCleanerEngine.applyFinalCotEditorCleanup([basicCleaned])
        #expect(finalCleaned == ["\"God's Word\" - 1-3"])
    }

    @Test("Smart line wrapping respects column limit and bracketed tokens")
    func smartWrapping() {
        let verse = "For God so loved the world that He gave His only begotten Son [Jesus Christ the righteous], that whoever believes in Him should not perish but have everlasting life."
        let wrapped = SermonCleanerEngine.smartWrapText(verse, maxLen: 80)
        #expect(wrapped.count >= 2)
        for line in wrapped {
            #expect(line.count <= 80)
        }
        #expect(wrapped.joined(separator: " ").contains("[Jesus Christ the righteous],"))
    }

    @Test("ViewModel filename sanitization produces compact PascalCase filenames")
    @MainActor
    func filenameSanitization() {
        let vm = SermonWorkspaceViewModel()
        #expect(vm.sermonTextFilename(title: "The Walk of the Spirit") == "Sermon-TheWalkOfTheSpi.txt")
        #expect(vm.sermonTextFilename(title: "") == "Sermon-Untitled.txt")
    }

    @Test("TestFiles directory contains all 12 sample files and processes each without errors", arguments: allTestFileURLs())
    func processEveryFileInTestFilesDirectory(fileURL: URL) throws {
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))

        if SermonCleanerEngine.isEmlFile(fileURL) {
            let inspection = SermonCleanerEngine.inspectEmlFile(fileURL)
            #expect(inspection.sender == "Ernest Fink")

            if !inspection.attachments.isEmpty {
                for attachment in inspection.attachments {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appending(path: "TestAttachment-\(UUID().uuidString)-\(attachment.filename)")
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    try attachment.data.write(to: tempURL, options: .atomic)

                    let author = SermonCleanerEngine.extractDocumentAuthor(from: tempURL)
                    let result = try SermonCleanerEngine.processSermonFile(
                        url: tempURL,
                        speaker: author ?? inspection.sender ?? SermonCleanerEngine.defaultSpeaker,
                        maxLineChars: 105,
                        fallbackTitle: inspection.subject
                    )
                    #expect(!result.title.isEmpty)
                    #expect(!result.lines.isEmpty)
                    #expect(!result.scriptures.isEmpty)
                    #expect(result.lines.allSatisfy { $0.count <= 105 })
                }
                return
            }
        }

        let author = SermonCleanerEngine.extractDocumentAuthor(from: fileURL)
        let result = try SermonCleanerEngine.processSermonFile(
            url: fileURL,
            speaker: author ?? SermonCleanerEngine.defaultSpeaker,
            maxLineChars: 105
        )
        #expect(!result.title.isEmpty)
        #expect(!result.lines.isEmpty)
        #expect(!result.scriptures.isEmpty)
        #expect(result.lines.allSatisfy { $0.count <= 105 })
    }

    @Test("Over Head 4 EML parses hyperlinked scriptures, indented continuations, and all 10 references")
    func overHead4EmlParsing() throws {
        let emlURL = Self.testFilesDirectory.appending(path: "[CHFC Media] Over Head 4.eml")
        let inspection = SermonCleanerEngine.inspectEmlFile(emlURL)
        #expect(inspection.sender == "Ernest Fink")
        #expect(inspection.subject == nil) // "[CHFC Media] Over Head" is a generic subject
        #expect(inspection.attachments.isEmpty)

        let result = try SermonCleanerEngine.processSermonFile(
            url: emlURL,
            speaker: inspection.sender ?? SermonCleanerEngine.defaultSpeaker,
            maxLineChars: 105,
            fallbackTitle: inspection.subject
        )

        #expect(result.speaker == "Ernest Fink")
        #expect(result.title == "Strength That Never Fails")

        // Hyperlinked scripture "*2 Corinthians 12:10* <http://www.crossbooks.com/verse.asp?ref=2Co+12%3A10>"
        // must be parsed as its own scripture reference, without leaking the URL or merging into Philippians 4:13
        #expect(result.lines.contains("2 Corinthians 12:10 - For when I am weak, then am I strong"))
        #expect(!result.lines.contains(where: { $0.contains("crossbooks.com") || $0.contains("http") }))

        // Wrapped outline point across blank line ("*2. We Believe God's Promises even when we Cannot see them  *\n\n*    Fulfilled.*")
        #expect(result.lines.contains("2. We Believe God's Promises even when we Cannot see them Fulfilled."))
        #expect(!result.lines.contains("Fulfilled."))

        // Multi-line indented scripture ("*Hebrews 11:1\n\n   *Now *Faith* is...")
        #expect(result.lines.contains("Hebrews 11:1 - Now Faith is the substance of things Hoped for, the Evidence of things Not seen."))

        // Parenthesized translation with colon ("*2 Corinthians 4:17* (*KJV): *")
        #expect(result.lines.contains("2 Corinthians 4:17 (KJV) - For our light affliction, which is but for a moment,"))
        #expect(result.lines.contains("2 Corinthians 4:17 (KJV) - worketh for us a far more exceeding and eternal weight of glory."))

        #expect(result.scriptures == [
            "Psalm 73:26 (ESV)",
            "2 Corinthians 4:16 (NKJV)",
            "2 Corinthians 4:18 (NKJV)",
            "Philippians 4:13 (ESV)",
            "2 Corinthians 12:10",
            "Romans 10:17",
            "2 Corinthians 5:7",
            "Hebrews 11:1",
            "2 Corinthians 4:17 (KJV)",
            "Colossians 3:2 (KJV)"
        ])
    }

    @Test("TestFiles regression checks for all parsing improvements")
    func testFilesSpecificParsingImprovements() throws {
        let dir = Self.testFilesDirectory

        // 1. Overcoming Faith: (KJV 1900) year suffix, filename underscore date stripping, and multi-line Isaiah 43:1-3
        let overcomingURL = dir.appending(path: "Overcoming Faith in difficult times_7.12.26.CHFC.docx")
        let overcoming = try SermonCleanerEngine.processSermonFile(url: overcomingURL, speaker: "Robert Fyan")
        #expect(overcoming.title == "Overcoming Faith In Difficult Times")
        #expect(overcoming.scriptures.contains("1 John 5:4-5 (KJV)"))
        #expect(overcoming.scriptures.contains("Daniel 3:24-25 (KJV)"))
        #expect(!overcoming.lines.contains(where: { $0.contains("1900)") }))
        #expect(overcoming.lines.contains(where: { $0.hasPrefix("Isaiah 43:1-3 (NKJV) - Nor shall the flame scorch you.") }))

        // 2. Sarah Masih: speaker byline removal, comma-separated ref (1 Corinthians 3:9,11), and period-numbered verses (6. / 7.)
        let sarahURL = dir.appending(path: "Sarah Masih - Sermon slide notes Sep 25 2026 - THE WALK OF THE SPIRIT.docx")
        let sarah = try SermonCleanerEngine.processSermonFile(url: sarahURL, speaker: "Sarah Masih")
        #expect(sarah.title == "The Walk Of The Spirit")
        #expect(!sarah.lines.contains("Sarah Y Masih"))
        #expect(sarah.scriptures.contains("1 Corinthians 3:9,11"))
        #expect(sarah.lines.contains(where: { $0.hasPrefix("1 Corinthians 3:6-7 - I have planted") }))
        #expect(sarah.lines.contains(where: { $0.hasPrefix("1 Corinthians 3:9,11 - For we are God's fellow workers") }))
        #expect(sarah.lines.contains(where: { $0.hasPrefix("Hebrews 11:6 - But without faith") }))

        // 3. Renewing Your Mind PDF: hard-wrapped PDF line reflow, whole-chapter Psalm 13, and attached footnote removal
        let renewingURL = dir.appending(path: "Renewing Your Mind  (scriptures for media team).pdf")
        let renewing = try SermonCleanerEngine.processSermonFile(url: renewingURL, speaker: "Pastor John")
        #expect(renewing.title == "Renewing Your Mind")
        #expect(renewing.scriptures.contains("Psalm 13"))
        #expect(!renewing.lines.contains(where: { $0.contains("[b]") || $0.contains("[c]") || $0.contains("[d]") }))
        #expect(renewing.lines.contains(where: { $0.hasPrefix("Acts 16:19-36 - (26) Suddenly there was such a violent earthquake") }))
        #expect(renewing.lines.contains(where: { $0.hasPrefix("Psalm 13 - How long, O LORD?") }))

        // 4. The Invisible Kingdom: Roman numeral outline point I is not consumed as title
        let kingdomURL = dir.appending(path: "The Invisible Kingdom.9.1.26.CHFC.docx")
        let kingdom = try SermonCleanerEngine.processSermonFile(url: kingdomURL, speaker: "Robert Fyan")
        #expect(kingdom.title == "The Invisible Kingdom")
        #expect(kingdom.lines.first == "I. The Nature of Christ's Kingdom")

        // 5. OVER HEAD 3 EML attachment (LISTEN OVERHEAD.docx): L.I.S.T.E.N. acronym preserved without extra spaces
        let emlURL = dir.appending(path: "[CHFC Media] OVER HEAD 3.eml")
        let inspection = SermonCleanerEngine.inspectEmlFile(emlURL)
        let att = try #require(inspection.attachments.first)
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "Test-\(UUID().uuidString)-\(att.filename)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try att.data.write(to: tempURL, options: .atomic)
        let listen = try SermonCleanerEngine.processSermonFile(url: tempURL, speaker: "Ernest Fink")
        #expect(listen.title == "How To L.I.S.T.E.N. To God's Voice")
        #expect(listen.lines.contains("L.I.S.T.E.N."))

        // 6. Bible Quiz PPTX: email address in <dc:creator> metadata is ignored
        let quizURL = dir.appending(path: "Bible Quiz  Fri. 19Dec2025.pptx")
        #expect(SermonCleanerEngine.extractDocumentAuthor(from: quizURL) == nil)
    }
}
