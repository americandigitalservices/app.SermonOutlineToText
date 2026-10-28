import Foundation

//
//  SermonFileWriter.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

/// Handles PascalCase filename sanitization and writing the 4 ProPresenter text files to disk.
nonisolated enum SermonFileWriter {

    static func sermonTextFilename(title: String) -> String {
        let safeTitle = sanitizeFilenameComponent(
            title.isEmpty ? "Untitled" : title,
            maxLength: 15
        )
        return "Sermon-\(safeTitle).txt"
    }

    static func sanitizeFilenameComponent(_ value: String, maxLength: Int = 15) -> String {
        let words = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "Untitled" }

        let joined = words.map { word -> String in
            guard let first = word.first else { return "" }
            return String(first).uppercased() + word.dropFirst()
        }.joined()

        guard !joined.isEmpty else { return "Untitled" }
        if joined.count <= maxLength {
            return joined
        }
        return String(joined.prefix(maxLength))
    }

    @discardableResult
    static func writeOutputFiles(
        to saveDirectoryPath: String,
        speaker: String,
        title: String,
        textBody: String,
        scripturesBody: String,
        previousSermonTextURL: URL?
    ) throws -> (filename: String, fileURL: URL) {
        let outDir = URL(filePath: saveDirectoryPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let cleanSpeaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetFilename = sermonTextFilename(title: cleanTitle)
        let newSermonTextURL = outDir.appending(path: targetFilename)

        if let previousURL = previousSermonTextURL,
           previousURL != newSermonTextURL,
           FileManager.default.fileExists(atPath: previousURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: previousURL)
        }

        try cleanSpeaker
            .write(to: outDir.appending(path: "MainSpeaker.txt"), atomically: true, encoding: .utf8)

        try cleanTitle
            .write(to: outDir.appending(path: "SermonTitle.txt"), atomically: true, encoding: .utf8)

        let trimmedText = textBody.trimmingCharacters(in: .whitespacesAndNewlines)
        try (trimmedText.isEmpty ? "" : trimmedText + "\n")
            .write(to: newSermonTextURL, atomically: true, encoding: .utf8)

        let trimmedScrip = scripturesBody.trimmingCharacters(in: .whitespacesAndNewlines)
        try (trimmedScrip.isEmpty ? "" : trimmedScrip + "\n")
            .write(to: outDir.appending(path: "SermonScriptures.txt"), atomically: true, encoding: .utf8)

        return (filename: targetFilename, fileURL: newSermonTextURL)
    }
}
