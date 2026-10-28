import SwiftUI

//
//  SermonWorkspaceViewModel.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct PendingOutlineLoad: Identifiable {
    let id = UUID()
    let fileURL: URL
    let fallbackTitle: String?
    var speakerInput: String
}

@Observable
final class SermonWorkspaceViewModel {
    var saveDirectoryPath: String = {
        if let saved = UserDefaults.standard.string(forKey: "SermonCleanerSaveDirectoryPath"), !saved.isEmpty {
            return saved
        }
        return URL.documentsDirectory
            .appending(path: "Sermon Outline to Text")
            .path(percentEncoded: false)
    }() {
        didSet {
            UserDefaults.standard.set(saveDirectoryPath, forKey: "SermonCleanerSaveDirectoryPath")
        }
    }

    var speaker: String = ""
    var title: String = ""
    var sermonTextBody: String = ""
    var scripturesBody: String = ""
    var maxLineLength: Double = Double(SermonCleanerEngine.defaultMaxLineChars)
    var lastLoadedFileURL: URL?
    var lastLoadedFallbackTitle: String?
    var lastWrittenSermonTextURL: URL?
    var pendingLoad: PendingOutlineLoad?

    var statusMessage: String = "Drop an outline (.docx, .pptx, .pdf, .eml, .txt) or email anywhere to begin"
    var isErrorStatus: Bool = false
    var isProcessing: Bool = false
    var isTargetedForDrop: Bool = false
    var showingResetPermissionAlert: Bool = false
    var showingAutomationDeniedAlert: Bool = false
    var showingAccessibilitySettingsAlert: Bool = false

    func sermonTextFilename(title: String? = nil) -> String {
        let rawTitle = (title ?? self.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return SermonFileWriter.sermonTextFilename(title: rawTitle)
    }

    func sanitizeFilenameComponent(_ value: String, maxLength: Int = 15) -> String {
        SermonFileWriter.sanitizeFilenameComponent(value, maxLength: maxLength)
    }

    func resetAppleEventsPermission(showConfirmationAlert: Bool = true) {
        do {
            try ProPresenterAutomator.resetAppleEventsPermission()
            statusMessage = "✓ Reset Automation permissions. macOS will ask for permission again on the next import."
            isErrorStatus = false
            if showConfirmationAlert {
                showingResetPermissionAlert = true
            }
        } catch {
            statusMessage = "⚠️ Could not reset permissions: \(error.localizedDescription)"
            isErrorStatus = true
        }
    }

    @concurrent
    static func pruneOldCacheFiles(in cacheDir: URL) async {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        for fileURL in urls {
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < cutoff {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    @concurrent
    static func processOutlineInBackground(
        fileURL: URL,
        speaker: String,
        maxLineChars: Int,
        fallbackTitle: String?
    ) async throws -> SermonProcessingResult {
        try SermonCleanerEngine.processSermonFile(
            url: fileURL,
            speaker: speaker,
            maxLineChars: maxLineChars,
            fallbackTitle: fallbackTitle
        )
    }

    @concurrent
    static func executeAppleScriptInBackground(_ source: String) async -> (errorCode: Int, errorMessage: String)? {
        await ProPresenterAutomator.executeAppleScriptInBackground(source)
    }
}
