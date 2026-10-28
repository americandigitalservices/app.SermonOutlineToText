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

    @Test("Smart title case preserves contractions and Roman numerals")
    func smartTitleCaseFormatting() {
        #expect(SermonCleanerEngine.smartTitleCase("GOD'S GRACE - PART II") == "God's Grace - Part II")
        #expect(SermonCleanerEngine.smartTitleCase("DON'T STEP BACK") == "Don't Step Back")
        #expect(SermonCleanerEngine.smartTitleCase("THE WALK OF THE SPIRIT") == "The Walk Of The Spirit")
    }

    @Test("Scripture book and translation canonicalization")
    func scriptureNormalization() {
        #expect(SermonCleanerEngine.formatRefPrefix("1 cor.", "13 : 4 - 7", "amplified bible, classic edition") == "1 Corinthians 13:4-7 (AMPC)")
        #expect(SermonCleanerEngine.formatRefPrefix("ii tim", "1:7", "nkjv") == "2 Timothy 1:7 (NKJV)")
        #expect(SermonCleanerEngine.formatRefPrefix("psalm", "23:1", nil) == "Psalm 23:1")
        #expect(SermonCleanerEngine.standardizeRefsInText("Read rom 8:28 (esv) today") == "Read Romans 8:28 (ESV) today")
    }

    @Test("Author name normalization flips Last, First and ignores placeholders")
    func authorNameNormalization() {
        #expect(SermonCleanerEngine.normalizeAuthorName("Fink, Ernest") == "Ernest Fink")
        #expect(SermonCleanerEngine.normalizeAuthorName("Smith, Jr., John") == "Smith, Jr., John")
        #expect(SermonCleanerEngine.normalizeAuthorName("Windows User") == nil)
        #expect(SermonCleanerEngine.normalizeAuthorName("  Sarah   Masih ; Other ") == "Sarah Masih")
    }

    @Test("Typography and CotEditor cleanup rules")
    func typographyAndCotEditorCleanup() {
        let dirty = "  • \u{200B}“God’s Word”[a] — 1—3  ; "
        let basicCleaned = SermonCleanerEngine.cleanBasicTypography(dirty)
        #expect(basicCleaned == "\"God's Word\" - 1-3 ;")

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

    @Test("TestFiles directory contains all 11 sample files and processes each without errors", arguments: allTestFileURLs())
    func processEveryFileInTestFilesDirectory(fileURL: URL) throws {
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))

        if SermonCleanerEngine.isEmlFile(fileURL) {
            let inspection = SermonCleanerEngine.inspectEmlFile(fileURL)
            #expect(inspection.sender == "Ernest Fink")

            if !inspection.attachments.isEmpty {
                // EML with attachment (e.g., [CHFC Media] OVER HEAD 3.eml -> LISTEN OVERHEAD.docx)
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
}
