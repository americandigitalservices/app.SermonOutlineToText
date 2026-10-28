import Foundation
import Testing
@testable import SermonOutlineCleaner

struct SermonOutlineCleanerTests {

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

    @Test("End-to-end processing of sample TestFiles")
    func sampleFilesProcessing() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testFilesDir = repoRoot.appending(path: "TestFiles", directoryHint: .isDirectory)

        guard FileManager.default.fileExists(atPath: testFilesDir.path(percentEncoded: false)) else {
            return
        }

        // 1. Word (.docx)
        let docxURL = testFilesDir.appending(path: "We will not step back - OUTLINES.docx")
        let docxResult = try SermonCleanerEngine.processSermonFile(url: docxURL, speaker: "Pastor John", maxLineChars: 105)
        #expect(!docxResult.title.isEmpty)
        #expect(!docxResult.lines.isEmpty)
        #expect(!docxResult.scriptures.isEmpty)
        #expect(docxResult.lines.allSatisfy { $0.count <= 105 })

        // 2. PowerPoint (.pptx)
        let pptxURL = testFilesDir.appending(path: "7 Aspects of Manifestation of Holy Spirit.pptx")
        let pptxResult = try SermonCleanerEngine.processSermonFile(url: pptxURL, speaker: "Pastor John", maxLineChars: 105)
        #expect(!pptxResult.lines.isEmpty)

        // 3. PDF (.pdf)
        let pdfURL = testFilesDir.appending(path: "Renewing Your Mind  (scriptures for media team).pdf")
        let pdfResult = try SermonCleanerEngine.processSermonFile(url: pdfURL, speaker: "Pastor John", maxLineChars: 105)
        #expect(!pdfResult.lines.isEmpty)
        #expect(!pdfResult.scriptures.isEmpty)

        // 4. Apple Mail (.eml)
        let emlURL = testFilesDir.appending(path: "[CHFC Media] OVER HEAD.eml")
        #expect(SermonCleanerEngine.isEmlFile(emlURL))
        let inspection = SermonCleanerEngine.inspectEmlFile(emlURL)
        #expect(inspection.sender != nil)
        let emlResult = try SermonCleanerEngine.processSermonFile(url: emlURL, speaker: inspection.sender ?? "Pastor John", maxLineChars: 105)
        #expect(!emlResult.lines.isEmpty)
    }
}
