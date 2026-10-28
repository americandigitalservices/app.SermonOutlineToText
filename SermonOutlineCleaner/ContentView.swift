import SwiftUI
import Observation
import UniformTypeIdentifiers
import AppKit
import ApplicationServices

//
//  SermonOutlineCleaner
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
        let safeTitle = sanitizeFilenameComponent(
            title.isEmpty ? "Untitled" : title,
            maxLength: 15
        )
        return "Sermon-\(safeTitle).txt"
    }

    func sanitizeFilenameComponent(_ value: String, maxLength: Int = 15) -> String {
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

    func resetAppleEventsPermission(showConfirmationAlert: Bool = false) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.danielhorning.SermonOutlineCleaner"
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/tccutil")
        task.arguments = ["reset", "AppleEvents", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
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
        var errorDict: NSDictionary?
        guard let scriptObject = NSAppleScript(source: source) else {
            return (errorCode: -1, errorMessage: "Could not compile AppleScript.")
        }
        scriptObject.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            return (errorCode: code, errorMessage: msg)
        }
        return nil
    }
}

struct ContentView: View {

    @AppStorage("saveDirectoryPath") private var saveDirectoryPath: String = URL.homeDirectory
        .appending(path: "Desktop", directoryHint: .isDirectory)
        .path(percentEncoded: false)

    @AppStorage("maxLineChars") private var maxLineChars: Int = SermonCleanerEngine.defaultMaxLineChars

    @Bindable var viewModel = SermonWorkspaceViewModel()

    var body: some View {
        VStack(spacing: 14) {
            // 1. Settings Bar: Save Location, Speaker Name (starts blank) & Column Limit
            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("Save Location:")
                            .fontWeight(.semibold)
                            .frame(width: 105, alignment: .leading)
                        TextField("Output Directory", text: $saveDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button("Browse…", action: selectOutputDirectory)
                            .frame(width: 110)
                    }
                    GridRow {
                        Text("Speaker Name:")
                            .fontWeight(.semibold)
                            .frame(width: 105, alignment: .leading)
                        HStack(spacing: 12) {
                            TextField("Leave blank to prompt on file load…", text: $viewModel.speakerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(applySpeakerChangeIfLoaded)

                            Divider().frame(height: 18)

                            Text("Column Limit:")
                                .fontWeight(.semibold)

                            TextField("105", value: $maxLineChars, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 52)
                                .multilineTextAlignment(.center)
                                .onSubmit(reprocessIfLoaded)

                            Stepper("", value: $maxLineChars, in: 45...250, step: 5)
                                .labelsHidden()
                                .onChange(of: maxLineChars) { _, _ in
                                    reprocessIfLoaded()
                                }
                        }
                        Button("Update Speaker", action: applySpeakerChangeIfLoaded)
                            .frame(width: 110)
                            .disabled(viewModel.currentFileURL == nil)
                    }
                }
                .padding(6)
            }

            // 2. Drag & Drop Zone / File Picker (Visual Banner)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        viewModel.isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                    )

                HStack(spacing: 16) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.statusMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text("Supports Word (.docx), PowerPoint (.pptx), PDF (.pdf), Apple Mail (.eml), and Text (.txt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.currentFileURL != nil {
                        Button("Re-Wrap (\(maxLineChars) ch)", action: reprocessIfLoaded)
                            .controlSize(.large)
                    }

                    Button("Select Outline…", action: openFilePicker)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 68)

            // 3. 2x2 Read-Only Previews of Created Files
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    PreviewCard(
                        title: "MainSpeaker.txt",
                        badge: viewModel.previewSpeaker.isEmpty ? "—" : "1 line",
                        text: viewModel.previewSpeaker
                    )
                    PreviewCard(
                        title: "SermonTitle.txt",
                        badge: viewModel.previewTitle.isEmpty ? "—" : "1 line",
                        text: viewModel.previewTitle
                    )
                }
                .frame(height: 78)

                HStack(spacing: 12) {
                    PreviewCard(
                        title: viewModel.currentSermonTextFilename,
                        badge: "\(viewModel.lineCount) lines • max \(maxLineChars) ch",
                        text: viewModel.previewText
                    )
                    PreviewCard(
                        title: "SermonScriptures.txt",
                        badge: "\(viewModel.scriptureCount) scriptures",
                        text: viewModel.previewScriptures
                    )
                }
            }

            // 4. Footer Actions (Read-Only Previews)
            HStack {
                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Spacer()

                Button {
                    importToProPresenter()
                } label: {
                    Label("Import to ProPresenter", systemImage: "play.display")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.previewText.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
        .overlay(
            MailAwareDropView(
                isTargeted: $viewModel.isTargeted,
                onFileDropped: { url in
                    handleIncomingFile(url)
                },
                onError: { errMsg in
                    viewModel.statusMessage = errMsg
                }
            )
        )
        .sheet(item: $viewModel.pendingLoad) { item in
            SpeakerPromptSheet(
                defaultSpeaker: item.suggestedSpeaker,
                onConfirm: { enteredSpeaker in
                    viewModel.speakerName = enteredSpeaker
                    viewModel.lastSavedSermonTextURL = nil
                    viewModel.pendingLoad = nil
                    runSermonProcessor(
                        url: item.targetURL,
                        speaker: enteredSpeaker,
                        fallbackTitle: item.fallbackTitle
                    )
                },
                onCancel: {
                    viewModel.statusMessage = "Cancelled speaker name prompt."
                    viewModel.pendingLoad = nil
                }
            )
        }
        .alert("Permissions Reset", isPresented: $viewModel.showPermissionsResetAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Automation permissions for SermonOutlineCleaner have been reset.\n\nNext time you click \"Import to ProPresenter\", macOS will ask for permission again.")
        }
        .alert("ProPresenter Automation Blocked", isPresented: $viewModel.showAutomationBlockedAlert) {
            Button("Reset Permissions") {
                viewModel.resetAppleEventsPermission(showConfirmationAlert: false)
            }
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SermonOutlineCleaner needs permission to launch ProPresenter and trigger the file import menu.\n\nClick \"Reset Permissions\" below, then click \"Import to ProPresenter\" again and select \"Allow\" when macOS prompts you.")
        }
        .onOpenURL { url in
            handleIncomingFile(url)
        }
    }

    // MARK: - Actions & Dialogs

    private func commitActiveTextFields() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func selectOutputDirectory() {
        commitActiveTextFields()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Save Location"
        panel.directoryURL = URL(filePath: saveDirectoryPath, directoryHint: .isDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path(percentEncoded: false)
            viewModel.lastSavedSermonTextURL = nil
        }
    }

    private func openFilePicker() {
        commitActiveTextFields()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            .emailMessage,
            .presentation,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "eml") ?? .data
        ]

        if panel.runModal() == .OK, let url = panel.url {
            handleIncomingFile(url)
        }
    }

    private func handleIncomingFile(_ fileURL: URL) {
        commitActiveTextFields()
        NSApp.activate()
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

        var targetURL = fileURL
        let currentTypedSpeaker = viewModel.speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        var suggestedSpeaker = currentTypedSpeaker.isEmpty
            ? SermonCleanerEngine.defaultSpeaker
            : currentTypedSpeaker
        var fallbackTitle: String? = nil

        if SermonCleanerEngine.isEmlFile(fileURL) {
            let inspection = SermonCleanerEngine.inspectEmlFile(fileURL)
            if let sender = inspection.sender, !sender.isEmpty {
                suggestedSpeaker = sender
            }
            fallbackTitle = inspection.subject

            if !inspection.attachments.isEmpty {
                guard let chosenURL = promptForEmlSource(emlURL: fileURL, attachments: inspection.attachments) else {
                    viewModel.statusMessage = "Cancelled outline selection."
                    return
                }
                targetURL = chosenURL
            }
        }

        // If the target file is a Word/PowerPoint/PDF document with an Author metadata property,
        // use that Author (with "Last, First" flipped to "First Last") as the suggested speaker.
        if let docAuthor = SermonCleanerEngine.extractDocumentAuthor(from: targetURL), !docAuthor.isEmpty {
            suggestedSpeaker = docAuthor
        }

        // Always present the Speaker Name prompt sheet on every file drop or selection
        viewModel.pendingLoad = PendingOutlineLoad(
            targetURL: targetURL,
            suggestedSpeaker: suggestedSpeaker,
            fallbackTitle: fallbackTitle
        )
    }

    private func promptForEmlSource(emlURL: URL, attachments: [EmlAttachment]) -> URL? {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "Email Contains Attachments"
        alert.informativeText = "Choose which element from \"\(emlURL.lastPathComponent)\" to parse for the sermon text:"
        alert.alertStyle = .informational

        for attachment in attachments {
            alert.addButton(withTitle: "Attachment: \(attachment.filename)")
        }
        alert.addButton(withTitle: "Email Body Text")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

        if index >= 0 && index < attachments.count {
            let chosen = attachments[index]
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "SermonCleanerAttachments", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFileURL = tempDir.appending(path: chosen.filename)
            do {
                try chosen.data.write(to: tempFileURL, options: .atomic)
                return tempFileURL
            } catch {
                viewModel.statusMessage = "⚠️ Could not extract attachment: \(error.localizedDescription)"
                return nil
            }
        } else if index == attachments.count {
            return emlURL
        } else {
            return nil
        }
    }

    private func applySpeakerChangeIfLoaded() {
        commitActiveTextFields()
        guard viewModel.currentFileURL != nil else { return }
        reprocessIfLoaded()
    }

    private func reprocessIfLoaded() {
        commitActiveTextFields()
        guard let url = viewModel.currentFileURL else { return }
        let activeSpeaker = viewModel.speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSpeaker = activeSpeaker.isEmpty
            ? (viewModel.previewSpeaker.isEmpty ? SermonCleanerEngine.defaultSpeaker : viewModel.previewSpeaker)
            : activeSpeaker
        runSermonProcessor(url: url, speaker: resolvedSpeaker, fallbackTitle: viewModel.currentFallbackTitle)
    }

    private func runSermonProcessor(url: URL, speaker: String, fallbackTitle: String?) {
        viewModel.currentFileURL = url
        viewModel.currentFallbackTitle = fallbackTitle
        let limit = maxLineChars

        Task {
            do {
                let result = try await SermonWorkspaceViewModel.processOutlineInBackground(
                    url: url,
                    speaker: speaker,
                    maxLineChars: limit,
                    fallbackTitle: fallbackTitle
                )

                viewModel.previewSpeaker = result.speaker
                viewModel.previewTitle = result.title
                viewModel.previewText = result.lines.joined(separator: "\n")
                viewModel.previewScriptures = result.scriptures.joined(separator: "\n")

                viewModel.lineCount = result.lines.count
                viewModel.scriptureCount = result.scriptures.count

                let savedFilename = try writeFilesToDisk(
                    speaker: result.speaker,
                    title: result.title,
                    textBody: viewModel.previewText,
                    scripturesBody: viewModel.previewScriptures
                )
                let abbreviatedDir = (saveDirectoryPath as NSString).abbreviatingWithTildeInPath
                viewModel.statusMessage = "✓ Saved \(savedFilename) to \(abbreviatedDir)"
            } catch {
                viewModel.statusMessage = "⚠️ Error: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func writeFilesToDisk(
        speaker: String,
        title: String,
        textBody: String,
        scripturesBody: String
    ) throws -> String {
        let outDir = URL(filePath: saveDirectoryPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let cleanSpeaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetFilename = viewModel.sermonTextFilename(title: cleanTitle)
        let newSermonTextURL = outDir.appending(path: targetFilename)

        if let previousURL = viewModel.lastSavedSermonTextURL,
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

        viewModel.lastSavedSermonTextURL = newSermonTextURL
        return targetFilename
    }

    private func revealInFinder() {
        let outDir = URL(filePath: saveDirectoryPath, directoryHint: .isDirectory)
        let sermonTextURL = outDir.appending(path: viewModel.currentSermonTextFilename)
        if !viewModel.previewText.isEmpty && FileManager.default.fileExists(atPath: sermonTextURL.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([sermonTextURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: saveDirectoryPath)
        }
    }

    private func importToProPresenter() {
        commitActiveTextFields()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            viewModel.statusMessage = "⚠️ Please enable SermonOutlineCleaner in System Settings > Privacy & Security > Accessibility, then click Import again."
            return
        }

        let targetFilename = (try? writeFilesToDisk(
            speaker: viewModel.previewSpeaker,
            title: viewModel.previewTitle,
            textBody: viewModel.previewText,
            scripturesBody: viewModel.previewScriptures
        )) ?? viewModel.currentSermonTextFilename

        let sermonFilePath = URL(filePath: saveDirectoryPath, directoryHint: .isDirectory)
            .appending(path: targetFilename)
            .path(percentEncoded: false)

        // Set the file path on the clipboard natively in Swift (avoids AppleScript string escaping issues)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sermonFilePath, forType: .string)

        let proBundleID = "com.renewedvision.propresenter"
        let proAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: proBundleID)
            ?? URL(filePath: "/Applications/ProPresenter.app")

        guard FileManager.default.fileExists(atPath: proAppURL.path(percentEncoded: false)) else {
            viewModel.statusMessage = "⚠️ Could not find ProPresenter.app in /Applications."
            return
        }

        viewModel.statusMessage = "⏳ Launching ProPresenter and waiting for main window…"

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        Task {
            do {
                let runningApp = try await NSWorkspace.shared.openApplication(at: proAppURL, configuration: config)
                NSApp.deactivate()
                runningApp.activate()

                let scriptSource = """
                tell application "System Events"
                    set isReady to false
                    repeat 90 times
                        if exists process "ProPresenter" then
                            tell process "ProPresenter"
                                if (count of windows) > 0 and (exists menu bar item "File" of menu bar 1) then
                                    set isReady to true
                                    exit repeat
                                end if
                            end tell
                        end if
                        delay 0.5
                    end repeat
                    
                    if not isReady then
                        error "ProPresenter did not finish loading its main window in time."
                    end if
                    
                    delay 0.8
                    tell process "ProPresenter"
                        set frontmost to true
                        delay 0.5
                        try
                            click menu item "File…" of menu 1 of menu item "Import" of menu 1 of menu bar item "File" of menu bar 1
                        on error
                            try
                                click menu item "File..." of menu 1 of menu item "Import" of menu 1 of menu bar item "File" of menu bar 1
                            on error
                                keystroke "i" using {shift down, command down}
                            end try
                        end try
                        delay 0.8
                        keystroke "g" using {shift down, command down}
                        delay 0.6
                        keystroke "v" using {command down}
                        delay 0.4
                        key code 36
                        delay 0.5
                        key code 36
                        delay 0.9
                        key code 36
                    end tell
                end tell
                """

                if let scriptError = await SermonWorkspaceViewModel.executeAppleScriptInBackground(scriptSource) {
                    if scriptError.errorCode == -1743 {
                        viewModel.statusMessage = "⚠️ Automation permission denied (-1743)."
                        viewModel.showAutomationBlockedAlert = true
                    } else {
                        viewModel.statusMessage = "⚠️ ProPresenter Import Error (\(scriptError.errorCode)): \(scriptError.errorMessage)"
                    }
                } else {
                    runningApp.activate()
                    viewModel.statusMessage = "✓ Imported \(targetFilename) into ProPresenter"
                }
            } catch {
                viewModel.statusMessage = "⚠️ Failed to launch ProPresenter: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Native SwiftUI Speaker Prompt Sheet (Guaranteed TextField Cursor & Focus)

struct SpeakerPromptSheet: View {
    let defaultSpeaker: String
    var onConfirm: (String) -> Void
    var onCancel: () -> Void

    @State private var enteredName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Enter Speaker Name")
                    .font(.headline)
            }

            Text("Confirm or enter the speaker's name for this sermon outline:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(SermonCleanerEngine.defaultSpeaker, text: $enteredName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .defaultFocus($isTextFieldFocused, true)
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            enteredName = defaultSpeaker
            NSApp.activate()
            isTextFieldFocused = true
        }
    }

    private func submit() {
        let trimmed = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        onConfirm(trimmed.isEmpty ? defaultSpeaker : trimmed)
    }
}

struct PreviewCard: View {
    let title: String
    let badge: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            ReadOnlyMonospacedTextView(text: text.isEmpty ? "—" : text, isPlaceholder: text.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

struct ReadOnlyMonospacedTextView: NSViewRepresentable {
    let text: String
    let isPlaceholder: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            textView.textContainerInset = NSSize(width: 6, height: 8)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor

        if textView.string != text {
            textView.string = text
            // Always snap scroll position back to top-left when text updates
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }
}

// MARK: - AppKit NSFilePromiseReceiver Overlay for Direct Apple Mail Drag & Drop

struct MailAwareDropView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onFileDropped: (URL) -> Void
    var onError: (String) -> Void

    func makeNSView(context: Context) -> DropReceivingNSView {
        let view = DropReceivingNSView()
        view.onTargetChanged = { targeted in
            Task { @MainActor in
                self.isTargeted = targeted
            }
        }
        view.onFileReceived = { url in
            Task { @MainActor in
                self.onFileDropped(url)
            }
        }
        view.onError = { msg in
            Task { @MainActor in
                self.onError(msg)
            }
        }
        return view
    }

    func updateNSView(_ nsView: DropReceivingNSView, context: Context) {}

    final class DropReceivingNSView: NSView {
        var onTargetChanged: ((Bool) -> Void)?
        var onFileReceived: ((URL) -> Void)?
        var onError: ((String) -> Void)?

        private lazy var promiseQueue: OperationQueue = {
            let q = OperationQueue()
            q.qualityOfService = .userInitiated
            q.maxConcurrentOperationCount = 1
            return q
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupRegisteredTypes()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupRegisteredTypes()
        }

        private func setupRegisteredTypes() {
            var types: [NSPasteboard.PasteboardType] = [
                .fileURL,
                .URL,
                .string,
                NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeMessageTransfer"),
                NSPasteboard.PasteboardType("com.apple.mail.email"),
                NSPasteboard.PasteboardType(UTType.emailMessage.identifier),
                NSPasteboard.PasteboardType(UTType.item.identifier),
                NSPasteboard.PasteboardType(UTType.data.identifier)
            ]
            types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
            registerForDraggedTypes(types)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onTargetChanged?(true)
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onTargetChanged?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            onTargetChanged?(false)
            let pboard = sender.draggingPasteboard

            // 1. Standard Finder File URLs (if a real file:// URL is already on the pasteboard, use it first!)
            if let urls = pboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], let firstFileURL = urls.first {
                onFileReceived?(firstFileURL)
                return true
            }

            // Create a fresh per-drop folder inside ~/Library/Caches only when handling promised/raw Mail drops
            let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let baseDropDir = cachesBase.appending(path: "SermonCleanerDrops", directoryHint: .isDirectory)
            let uniqueDropDir = baseDropDir.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: uniqueDropDir, withIntermediateDirectories: true)

            // Snapshot any raw email data on the pasteboard BEFORE returning from performDragOperation
            let rawMailTypes = [
                NSPasteboard.PasteboardType("com.apple.mail.email"),
                NSPasteboard.PasteboardType(UTType.emailMessage.identifier)
            ]
            let snapshottedMailData: Data? = rawMailTypes.compactMap { pboard.data(forType: $0) }.first { !$0.isEmpty }

            // 2. Handle Apple Mail File Promises (Emails & Attachments dragged directly from Mail.app)
            if let receivers = pboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
               let firstReceiver = receivers.first {
                firstReceiver.receivePromisedFiles(
                    atDestination: uniqueDropDir,
                    options: [:],
                    operationQueue: promiseQueue
                ) { [weak self] fileURL, error in
                    guard let self else { return }
                    if let error {
                        // Fallback A: Use snapshotted raw RFC-822 data if present
                        if let data = snapshottedMailData {
                            let destURL = uniqueDropDir.appending(path: "DroppedEmail.eml")
                            if (try? data.write(to: destURL, options: .atomic)) != nil {
                                self.onFileReceived?(destURL)
                                return
                            }
                        }
                        // Fallback B: Fetch raw RFC-822 source of the selected email directly from Apple Mail
                        if let fallbackURL = self.fetchSelectedMailMessageViaAppleScript(into: uniqueDropDir) {
                            self.onFileReceived?(fallbackURL)
                            return
                        }
                        self.onError?("⚠️ Mail drop error: \(error.localizedDescription)")
                    } else {
                        self.onFileReceived?(fileURL)
                    }
                }
                return true
            }

            // 3. Direct Raw RFC-822 / .eml data on the pasteboard
            if let data = snapshottedMailData {
                let destURL = uniqueDropDir.appending(path: "DroppedEmail.eml")
                do {
                    try data.write(to: destURL, options: .atomic)
                    onFileReceived?(destURL)
                    return true
                } catch {
                    onError?("⚠️ Could not save dropped email: \(error.localizedDescription)")
                    return false
                }
            }

            // 4. Final Fallback: If Mail only placed a message:// URL or transfer token on the pasteboard
            if let fallbackURL = fetchSelectedMailMessageViaAppleScript(into: uniqueDropDir) {
                onFileReceived?(fallbackURL)
                return true
            }

            return false
        }

        /// Queries Apple Mail for the raw RFC-822 `.eml` source of the currently selected message
        /// if macOS 26's NSFilePromiseReceiver times out (-1001) on an IMAP/Exchange message.
        private func fetchSelectedMailMessageViaAppleScript(into directory: URL) -> URL? {
            let scriptSource = """
            tell application "Mail"
                set sel to selection
                if (count of sel) is 0 then return ""
                set msg to item 1 of sel
                return source of msg
            end tell
            """
            var errorDict: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else { return nil }
            let result = script.executeAndReturnError(&errorDict)
            guard errorDict == nil,
                  let rawSource = result.stringValue,
                  !rawSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let destURL = directory.appending(path: "DroppedEmail.eml")
            do {
                try rawSource.write(to: destURL, atomically: true, encoding: .utf8)
                return destURL
            } catch {
                return nil
            }
        }

        // Always return nil for hitTest so 100% of mouse clicks and scroll events pass
        // directly to the underlying SwiftUI buttons and preview views. AppKit's drag-and-drop
        // system still routes registered drag operations to this view across the full window.
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}
