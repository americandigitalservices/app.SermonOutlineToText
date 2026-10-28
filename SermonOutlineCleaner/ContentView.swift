import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ApplicationServices

//
//  SermonOutlineCleaner
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct PendingOutlineLoad: Identifiable {
    let id = UUID()
    let targetURL: URL
    let suggestedSpeaker: String
    let fallbackTitle: String?
}

struct ContentView: View {

    @AppStorage("saveDirectoryPath") private var saveDirectoryPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")

    @AppStorage("maxLineChars") private var maxLineChars: Int = SermonCleanerEngine.defaultMaxLineChars

    // Speaker Name starts blank on every launch
    @State private var speakerName: String = ""

    @State private var currentFileURL: URL? = nil
    @State private var currentFallbackTitle: String? = nil
    @State private var lastSavedSermonTextURL: URL? = nil

    // Drives the native SwiftUI Speaker Name sheet
    @State private var pendingLoad: PendingOutlineLoad? = nil

    @State private var previewSpeaker: String = ""
    @State private var previewTitle: String = ""
    @State private var previewText: String = ""
    @State private var previewScriptures: String = ""

    @State private var lineCount: Int = 0
    @State private var scriptureCount: Int = 0
    @State private var statusMessage: String = "Drop a Sermon Outline (.docx, .pptx, .pdf, .eml, .txt) or click Select Outline"
    @State private var isTargeted: Bool = false

    private var currentSermonTextFilename: String {
        guard !previewText.isEmpty || !previewTitle.isEmpty else {
            return "Sermon.txt"
        }
        return sermonTextFilename(title: previewTitle)
    }

    private func sermonTextFilename(title: String) -> String {
        let safeTitle = sanitizeFilenameComponent(
            title.isEmpty ? "Untitled" : title,
            maxLength: 15
        )
        return "Sermon-\(safeTitle).txt"
    }

    private func sanitizeFilenameComponent(_ value: String, maxLength: Int = 15) -> String {
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
                            TextField("Leave blank to prompt on file load…", text: $speakerName)
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
                            .disabled(currentFileURL == nil)
                    }
                }
                .padding(6)
            }

            // 2. Drag & Drop Zone / File Picker (Visual Banner)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                    )

                HStack(spacing: 16) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text("Supports Word (.docx), PowerPoint (.pptx), PDF (.pdf), Apple Mail (.eml), and Text (.txt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if currentFileURL != nil {
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
                        badge: previewSpeaker.isEmpty ? "—" : "1 line",
                        text: previewSpeaker
                    )
                    PreviewCard(
                        title: "SermonTitle.txt",
                        badge: previewTitle.isEmpty ? "—" : "1 line",
                        text: previewTitle
                    )
                }
                .frame(height: 78)

                HStack(spacing: 12) {
                    PreviewCard(
                        title: currentSermonTextFilename,
                        badge: "\(lineCount) lines • max \(maxLineChars) ch",
                        text: previewText
                    )
                    PreviewCard(
                        title: "SermonScriptures.txt",
                        badge: "\(scriptureCount) scriptures",
                        text: previewScriptures
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
                .disabled(previewText.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
        .overlay(
            MailAwareDropView(
                isTargeted: $isTargeted,
                onFileDropped: { url in
                    handleIncomingFile(url)
                },
                onError: { errMsg in
                    statusMessage = errMsg
                }
            )
        )
        .sheet(item: $pendingLoad) { item in
            SpeakerPromptSheet(
                defaultSpeaker: item.suggestedSpeaker,
                onConfirm: { enteredSpeaker in
                    speakerName = enteredSpeaker
                    lastSavedSermonTextURL = nil
                    pendingLoad = nil
                    runSermonProcessor(
                        url: item.targetURL,
                        speaker: enteredSpeaker,
                        fallbackTitle: item.fallbackTitle
                    )
                },
                onCancel: {
                    statusMessage = "Cancelled speaker name prompt."
                    pendingLoad = nil
                }
            )
        }
        .onOpenURL { url in
            handleIncomingFile(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetAppPermissions)) { _ in
            resetAppleEventsPermission(showConfirmationAlert: true)
        }
    }

    // MARK: - Actions & Dialogs

    private func commitActiveTextFields() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func resetAppleEventsPermission(showConfirmationAlert: Bool = false) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.danielhorning.SermonOutlineCleaner"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "AppleEvents", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            statusMessage = "✓ Permissions reset. Click 'Import to ProPresenter' to be prompted again."
            if showConfirmationAlert {
                let alert = NSAlert()
                alert.messageText = "Permissions Reset"
                alert.informativeText = "Automation permissions for SermonOutlineCleaner have been reset.\n\nNext time you click \"Import to ProPresenter\", macOS will ask for permission again."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            statusMessage = "⚠️ Could not reset permissions: \(error.localizedDescription)"
        }
    }

    private func showAutomationBlockedAlert() {
        let alert = NSAlert()
        alert.messageText = "ProPresenter Automation Blocked"
        alert.informativeText = "SermonOutlineCleaner needs permission to launch ProPresenter and trigger the file import menu.\n\nClick \"Reset Permissions\" below, then click \"Import to ProPresenter\" again and select \"Allow\" when macOS prompts you."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Permissions")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            resetAppleEventsPermission(showConfirmationAlert: false)
        } else if response == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func selectOutputDirectory() {
        commitActiveTextFields()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Save Location"
        panel.directoryURL = URL(fileURLWithPath: saveDirectoryPath)

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
            lastSavedSermonTextURL = nil
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
        let currentTypedSpeaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    statusMessage = "Cancelled outline selection."
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
        pendingLoad = PendingOutlineLoad(
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
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SermonCleanerAttachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFileURL = tempDir.appendingPathComponent(chosen.filename)
            do {
                try chosen.data.write(to: tempFileURL, options: .atomic)
                return tempFileURL
            } catch {
                statusMessage = "⚠️ Could not extract attachment: \(error.localizedDescription)"
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
        guard currentFileURL != nil else { return }
        reprocessIfLoaded()
    }

    private func reprocessIfLoaded() {
        commitActiveTextFields()
        guard let url = currentFileURL else { return }
        let activeSpeaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSpeaker = activeSpeaker.isEmpty
            ? (previewSpeaker.isEmpty ? SermonCleanerEngine.defaultSpeaker : previewSpeaker)
            : activeSpeaker
        runSermonProcessor(url: url, speaker: resolvedSpeaker, fallbackTitle: currentFallbackTitle)
    }

    private func runSermonProcessor(url: URL, speaker: String, fallbackTitle: String?) {
        do {
            currentFileURL = url
            currentFallbackTitle = fallbackTitle

            let result = try SermonCleanerEngine.processSermonFile(
                url: url,
                speaker: speaker,
                maxLineChars: maxLineChars,
                fallbackTitle: fallbackTitle
            )

            previewSpeaker = result.speaker
            previewTitle = result.title
            previewText = result.lines.joined(separator: "\n")
            previewScriptures = result.scriptures.joined(separator: "\n")

            lineCount = result.lines.count
            scriptureCount = result.scriptures.count

            let savedFilename = try writeFilesToDisk(
                speaker: result.speaker,
                title: result.title,
                textBody: previewText,
                scripturesBody: previewScriptures
            )
            statusMessage = "✓ Saved \(savedFilename) to \((saveDirectoryPath as NSString).abbreviatingWithTildeInPath)"
        } catch {
            statusMessage = "⚠️ Error: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func writeFilesToDisk(
        speaker: String,
        title: String,
        textBody: String,
        scripturesBody: String
    ) throws -> String {
        let outDir = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let cleanSpeaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetFilename = sermonTextFilename(title: cleanTitle)
        let newSermonTextURL = outDir.appendingPathComponent(targetFilename)

        if let previousURL = lastSavedSermonTextURL,
           previousURL != newSermonTextURL,
           FileManager.default.fileExists(atPath: previousURL.path) {
            try? FileManager.default.removeItem(at: previousURL)
        }

        try cleanSpeaker
            .write(to: outDir.appendingPathComponent("MainSpeaker.txt"), atomically: true, encoding: .utf8)

        try cleanTitle
            .write(to: outDir.appendingPathComponent("SermonTitle.txt"), atomically: true, encoding: .utf8)

        let trimmedText = textBody.trimmingCharacters(in: .whitespacesAndNewlines)
        try (trimmedText.isEmpty ? "" : trimmedText + "\n")
            .write(to: newSermonTextURL, atomically: true, encoding: .utf8)

        let trimmedScrip = scripturesBody.trimmingCharacters(in: .whitespacesAndNewlines)
        try (trimmedScrip.isEmpty ? "" : trimmedScrip + "\n")
            .write(to: outDir.appendingPathComponent("SermonScriptures.txt"), atomically: true, encoding: .utf8)

        lastSavedSermonTextURL = newSermonTextURL
        return targetFilename
    }

    private func revealInFinder() {
        let outDir = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        let sermonTextURL = outDir.appendingPathComponent(currentSermonTextFilename)
        if !previewText.isEmpty && FileManager.default.fileExists(atPath: sermonTextURL.path) {
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
            statusMessage = "⚠️ Please enable SermonOutlineCleaner in System Settings > Privacy & Security > Accessibility, then click Import again."
            return
        }

        let targetFilename = (try? writeFilesToDisk(
            speaker: previewSpeaker,
            title: previewTitle,
            textBody: previewText,
            scripturesBody: previewScriptures
        )) ?? currentSermonTextFilename

        let sermonFilePath = (saveDirectoryPath as NSString).appendingPathComponent(targetFilename)

        // Set the file path on the clipboard natively in Swift (avoids AppleScript string escaping issues)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sermonFilePath, forType: .string)

        let proBundleID = "com.renewedvision.propresenter"
        let proAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: proBundleID)
            ?? URL(fileURLWithPath: "/Applications/ProPresenter.app")

        guard FileManager.default.fileExists(atPath: proAppURL.path) else {
            statusMessage = "⚠️ Could not find ProPresenter.app in /Applications."
            return
        }

        statusMessage = "⏳ Launching ProPresenter and waiting for main window…"

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: proAppURL, configuration: config) { runningApp, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.statusMessage = "⚠️ Failed to launch ProPresenter: \(error.localizedDescription)"
                }
                return
            }

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

            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    NSApp.deactivate()
                    runningApp?.activate()
                }

                var errorDict: NSDictionary?
                if let scriptObject = NSAppleScript(source: scriptSource) {
                    scriptObject.executeAndReturnError(&errorDict)
                    DispatchQueue.main.async {
                        if let err = errorDict {
                            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
                            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                            if code == -1743 {
                                self.statusMessage = "⚠️ Automation permission denied (-1743)."
                                self.showAutomationBlockedAlert()
                            } else {
                                self.statusMessage = "⚠️ ProPresenter Import Error (\(code)): \(msg)"
                            }
                        } else {
                            runningApp?.activate()
                            self.statusMessage = "✓ Imported \(targetFilename) into ProPresenter"
                        }
                    }
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
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
            DispatchQueue.main.async {
                self.isTargeted = targeted
            }
        }
        view.onFileReceived = { url in
            DispatchQueue.main.async {
                self.onFileDropped(url)
            }
        }
        view.onError = { msg in
            DispatchQueue.main.async {
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

            // Create a fresh per-drop folder inside ~/Library/Caches so Apple Mail's sandboxed
            // file-promise daemon never collides with deleted/locked /var/folders directories.
            let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let baseDropDir = cachesBase.appendingPathComponent("SermonCleanerDrops", isDirectory: true)
            let uniqueDropDir = baseDropDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: uniqueDropDir, withIntermediateDirectories: true)

            // Snapshot any raw email data on the pasteboard BEFORE returning from performDragOperation
            let rawMailTypes = [
                NSPasteboard.PasteboardType("com.apple.mail.email"),
                NSPasteboard.PasteboardType(UTType.emailMessage.identifier)
            ]
            let snapshottedMailData: Data? = rawMailTypes.compactMap { pboard.data(forType: $0) }.first { !$0.isEmpty }

            // 1. Standard Finder File URLs (if a real file:// URL is already on the pasteboard, use it first!)
            if let urls = pboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], let firstFileURL = urls.first {
                onFileReceived?(firstFileURL)
                return true
            }

            // 2. Handle Apple Mail File Promises (Emails & Attachments dragged directly from Mail.app)
            if let receivers = pboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
               let firstReceiver = receivers.first {
                firstReceiver.receivePromisedFiles(
                    atDestination: uniqueDropDir,
                    options: [:],
                    operationQueue: promiseQueue
                ) { [weak self] fileURL, error in
                    guard let self = self else { return }
                    if error != nil {
                        // Fallback A: Use snapshotted raw RFC-822 data if present
                        if let data = snapshottedMailData {
                            let destURL = uniqueDropDir.appendingPathComponent("DroppedEmail.eml")
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
                        self.onError?("⚠️ Mail drop error: \(error!.localizedDescription)")
                    } else {
                        self.onFileReceived?(fileURL)
                    }
                }
                return true
            }

            // 3. Direct Raw RFC-822 / .eml data on the pasteboard
            if let data = snapshottedMailData {
                let destURL = uniqueDropDir.appendingPathComponent("DroppedEmail.eml")
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
            let destURL = directory.appendingPathComponent("DroppedEmail.eml")
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
