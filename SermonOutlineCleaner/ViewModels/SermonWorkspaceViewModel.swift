import SwiftUI
import Observation

//
//  SermonWorkspaceViewModel.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct PendingOutlineLoad: Identifiable, Sendable {
    let id = UUID()
    let targetURL: URL
    let suggestedSpeaker: String
    let fallbackTitle: String?
}

@Observable
final class SermonWorkspaceViewModel {
    var speakerName: String = ""
    var currentFileURL: URL?
    var currentFallbackTitle: String?
    var lastSavedSermonTextURL: URL?

    var pendingLoad: PendingOutlineLoad?

    var previewSpeaker: String = ""
    var previewTitle: String = ""
    var previewText: String = ""
    var previewScriptures: String = ""

    var lineCount: Int = 0
    var scriptureCount: Int = 0
    var statusMessage: String = "Drop a Sermon Outline (.docx, .pptx, .pdf, .eml, .txt) or click Select Outline"
    var isTargeted: Bool = false

    var showPermissionsResetAlert: Bool = false
    var showAutomationBlockedAlert: Bool = false

    init() {
        Self.pruneStaleDropCacheDirectories()
    }

    var currentSermonTextFilename: String {
        guard !previewText.isEmpty || !previewTitle.isEmpty else {
            return "Sermon.txt"
        }
        return sermonTextFilename(title: previewTitle)
    }

    func sermonTextFilename(title: String) -> String {
        SermonFileWriter.sermonTextFilename(title: title)
    }

    func sanitizeFilenameComponent(_ value: String, maxLength: Int = 15) -> String {
        SermonFileWriter.sanitizeFilenameComponent(value, maxLength: maxLength)
    }

    func resetAppleEventsPermission(showConfirmationAlert: Bool = false) {
        do {
            try ProPresenterAutomator.resetAppleEventsPermission()
            statusMessage = "✓ Permissions reset. Click 'Import to ProPresenter' to be prompted again."
            if showConfirmationAlert {
                showPermissionsResetAlert = true
            }
        } catch {
            statusMessage = "⚠️ Could not reset permissions: \(error.localizedDescription)"
        }
    }

    static func pruneStaleDropCacheDirectories() {
        let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let baseDropDir = cachesBase.appending(path: "SermonCleanerDrops", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: baseDropDir)
    }

    @concurrent
    static func processOutlineInBackground(
        url: URL,
        speaker: String,
        maxLineChars: Int,
        fallbackTitle: String?
    ) async throws -> SermonProcessingResult {
        try SermonCleanerEngine.processSermonFile(
            url: url,
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
