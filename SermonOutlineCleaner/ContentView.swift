import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ApplicationServices

struct ContentView: View {
    @AppStorage("saveDirectoryPath") private var saveDirectoryPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    @AppStorage("maxLineChars") private var maxLineChars: Int = SermonCleanerEngine.defaultMaxLineChars

    // Speaker Name starts blank on every launch
    @State private var speakerName: String = ""

    @State private var currentFileURL: URL? = nil
    @State private var currentFallbackTitle: String? = nil
    @State private var lastSavedSermonTextURL: URL? = nil

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
            return "SermonText.txt"
        }
        return sermonTextFilename(title: previewTitle, speaker: previewSpeaker)
    }

    private func sermonTextFilename(title: String, speaker: String) -> String {
        let safeTitle = sanitizeFilenameComponent(
            title.isEmpty ? "Untitled" : title,
            maxLength: 45
        )
        let safeSpeaker = sanitizeFilenameComponent(
            speaker.isEmpty ? SermonCleanerEngine.defaultSpeaker : speaker,
            maxLength: 30
        )
        return "SermonText-\(safeTitle)-\(safeSpeaker).txt"
    }

    private func sanitizeFilenameComponent(_ value: String, maxLength: Int = 45) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value
            .components(separatedBy: invalidChars)
            .joined(separator: "-")
            .replacingOccurrences(of: "[\\s\\-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !cleaned.isEmpty else { return "Untitled" }
        guard cleaned.count > maxLength else { return cleaned }

        let words = cleaned.components(separatedBy: "-")
        var truncated = ""
        for word in words {
            let candidate = truncated.isEmpty ? word : "\(truncated)-\(word)"
            if candidate.count <= maxLength {
                truncated = candidate
            } else {
                break
            }
        }

        if truncated.isEmpty {
            truncated = String(cleaned.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return truncated.isEmpty ? "Untitled" : truncated
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

            // 2. Drag & Drop Zone / File Picker
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
            .onDrop(
                of: [
                    .fileURL,
                    .emailMessage,
                    UTType("com.apple.mail.email") ?? .emailMessage,
                    .pdf,
                    .presentation,
                    .plainText,
                    UTType(filenameExtension: "docx") ?? .data,
                    UTType(filenameExtension: "pptx") ?? .data,
                    UTType(filenameExtension: "eml") ?? .data,
                    .data
                ],
                isTargeted: $isTargeted
            ) { providers in
                handleDrop(providers: providers)
            }

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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        commitActiveTextFields()
        guard let provider = providers.first else { return false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SermonCleanerDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. Check if Apple Mail is dropping a whole email message (.eml stream)
        let mailTypes = ["com.apple.mail.email", UTType.emailMessage.identifier]
        for mailType in mailTypes where provider.hasItemConformingToTypeIdentifier(mailType) {
            provider.loadFileRepresentation(forTypeIdentifier: mailType) { tempURL, _ in
                if let tempURL = tempURL {
                    let fileName = tempURL.lastPathComponent.hasSuffix(".eml")
                        ? tempURL.lastPathComponent
                        : "\(tempURL.lastPathComponent).eml"
                    let destURL = tempDir.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: destURL)
                    if (try? FileManager.default.copyItem(at: tempURL, to: destURL)) != nil {
                        DispatchQueue.main.async {
                            handleIncomingFile(destURL)
                        }
                        return
                    }
                }

                provider.loadDataRepresentation(forTypeIdentifier: mailType) { data, _ in
                    guard let data = data, !data.isEmpty else { return }
                    let destURL = tempDir.appendingPathComponent("DroppedEmail.eml")
                    try? data.write(to: destURL, options: .atomic)
                    DispatchQueue.main.async {
                        handleIncomingFile(destURL)
                    }
                }
            }
            return true
        }

        // 2. Standard Finder file drop
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    handleIncomingFile(url)
                }
            }
            return true
        }

        // 3. Attachment dragged directly out of an Apple Mail message body
        let attachmentTypes: [UTType] = [
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            .pdf,
            .presentation,
            .plainText,
            .item
        ]

        for type in attachmentTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { tempURL, _ in
                guard let tempURL = tempURL else { return }
                let destURL = tempDir.appendingPathComponent(tempURL.lastPathComponent)
                try? FileManager.default.removeItem(at: destURL)
                do {
                    try FileManager.default.copyItem(at: tempURL, to: destURL)
                    DispatchQueue.main.async {
                        handleIncomingFile(destURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        statusMessage = "⚠️ Could not read dropped Mail attachment: \(error.localizedDescription)"
                    }
                }
            }
            return true
        }

        return false
    }

    private func handleIncomingFile(_ fileURL: URL) {
        commitActiveTextFields()

        var targetURL = fileURL
        var suggestedSpeaker = SermonCleanerEngine.defaultSpeaker
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

        var resolvedSpeaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedSpeaker.isEmpty {
            guard let enteredSpeaker = promptForSpeakerName(defaultName: suggestedSpeaker) else {
                statusMessage = "Cancelled speaker name prompt."
                return
            }
            resolvedSpeaker = enteredSpeaker
            speakerName = enteredSpeaker
        }

        lastSavedSermonTextURL = nil
        runSermonProcessor(url: targetURL, speaker: resolvedSpeaker, fallbackTitle: fallbackTitle)
    }

    private func promptForSpeakerName(defaultName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Enter Speaker Name"
        alert.informativeText = "Confirm or enter the speaker's name for this sermon outline:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
        inputField.stringValue = defaultName
        inputField.placeholderString = SermonCleanerEngine.defaultSpeaker
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let entered = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? defaultName : entered
    }

    private func promptForEmlSource(emlURL: URL, attachments: [EmlAttachment]) -> URL? {
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
        let targetFilename = sermonTextFilename(title: cleanTitle, speaker: cleanSpeaker)
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

        let proBundleID = "com.renewedvision.propresenter"
        let proAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: proBundleID)
            ?? URL(fileURLWithPath: "/Applications/ProPresenter.app")

        guard FileManager.default.fileExists(atPath: proAppURL.path) else {
            statusMessage = "⚠️ Could not find ProPresenter.app in /Applications."
            return
        }

        statusMessage = "⏳ Launching ProPresenter and waiting for main window…"

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false

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
                    set the clipboard to "\(sermonFilePath)"
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
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "—" : text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
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
