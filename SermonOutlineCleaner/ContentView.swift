import SwiftUI
import UniformTypeIdentifiers
import AppKit

//
//  ContentView.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct ContentView: View {
    @Bindable var viewModel: SermonWorkspaceViewModel

    init(viewModel: SermonWorkspaceViewModel = SermonWorkspaceViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            MailAwareDropView(isTargeted: $viewModel.isTargetedForDrop) { droppedURL in
                handleIncomingFile(droppedURL)
            }

            VStack(spacing: 14) {
                headerControlsSection
                previewPanesSection
                footerStatusBar
            }
            .padding(16)

            if viewModel.isTargetedForDrop {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 12)))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .task {
            let cacheDir = URL.cachesDirectory.appending(path: "SermonOutlineCleanerDrops", directoryHint: .isDirectory)
            await SermonWorkspaceViewModel.pruneOldCacheFiles(in: cacheDir)
        }
        .sheet(item: $viewModel.pendingLoad) { pending in
            SpeakerPromptSheet(
                filename: pending.fileURL.lastPathComponent,
                speakerName: Binding(
                    get: { viewModel.pendingLoad?.speakerInput ?? pending.speakerInput },
                    set: { viewModel.pendingLoad?.speakerInput = $0 }
                ),
                onConfirm: { confirmedSpeaker in
                    let url = pending.fileURL
                    let fallback = pending.fallbackTitle
                    viewModel.pendingLoad = nil
                    viewModel.speaker = confirmedSpeaker
                    runSermonProcessor(url: url, speakerOverride: confirmedSpeaker, fallbackTitle: fallback)
                },
                onCancel: {
                    viewModel.pendingLoad = nil
                }
            )
        }
        .alert("Automation Permissions Reset", isPresented: $viewModel.showingResetPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AppleEvents permissions for Sermon Outline Cleaner have been reset. Click \"Import to ProPresenter\" to be prompted for permission again.")
        }
        .alert("ProPresenter Automation Permission Disabled", isPresented: $viewModel.showingAutomationDeniedAlert) {
            Button("Open System Settings & Reset") {
                viewModel.resetAppleEventsPermission(showConfirmationAlert: false)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Reset Permission Only") {
                viewModel.resetAppleEventsPermission(showConfirmationAlert: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS blocked Sermon Outline Cleaner from controlling ProPresenter (Error -1743). Click \"Open System Settings & Reset\" to re-enable it.")
        }
        .alert("Accessibility Permission Required", isPresented: $viewModel.showingAccessibilitySettingsAlert) {
            Button("Open Accessibility Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To click ProPresenter's File → Import menu automatically, please enable \"SermonOutlineCleaner\" in System Settings → Privacy & Security → Accessibility, then click Import again.")
        }
    }

    // MARK: - Top Controls

    private var headerControlsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Save Directory:")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 105, alignment: .trailing)

                TextField("Output folder path", text: $viewModel.saveDirectoryPath)
                    .textFieldStyle(.roundedBorder)

                Button("Browse…") {
                    selectOutputDirectory()
                }

                Button("Open File…") {
                    openFilePicker()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                Text("Main Speaker:")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 105, alignment: .trailing)

                TextField("Speaker (MainSpeaker.txt)", text: $viewModel.speaker)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 230)
                    .onSubmit { writeFilesToDisk() }

                Text("Sermon Title:")
                    .font(.subheadline.weight(.medium))

                TextField("Title (SermonTitle.txt)", text: $viewModel.title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { writeFilesToDisk() }
            }

            HStack(spacing: 12) {
                Text("Max Line Length:")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 105, alignment: .trailing)

                Slider(value: $viewModel.maxLineLength, in: 65...150, step: 1) {
                    Text("Max Line Length")
                } onEditingChanged: { editing in
                    if !editing, let lastURL = viewModel.lastLoadedFileURL {
                        runSermonProcessor(
                            url: lastURL,
                            speakerOverride: viewModel.speaker,
                            fallbackTitle: viewModel.lastLoadedFallbackTitle
                        )
                    }
                }
                .frame(maxWidth: 260)

                Text("\(Int(viewModel.maxLineLength)) chars")
                    .font(.system(.subheadline, design: .monospaced))
                    .frame(width: 75, alignment: .leading)

                Spacer()

                Button {
                    writeFilesToDisk()
                } label: {
                    Label("Save All Files", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.sermonTextBody.isEmpty && viewModel.title.isEmpty)

                Button {
                    importToProPresenter()
                } label: {
                    Label("Import to ProPresenter", systemImage: "play.rectangle.on.rectangle.fill")
                }
                .disabled(viewModel.sermonTextBody.isEmpty && viewModel.title.isEmpty)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Split Previews

    private var previewPanesSection: some View {
        HSplitView {
            PreviewCard(
                title: "Sermon Outline (\(viewModel.sermonTextFilename()))",
                subtitle: "\(nonEmptyLineCount(viewModel.sermonTextBody)) lines",
                icon: "doc.text",
                text: viewModel.sermonTextBody
            )
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            PreviewCard(
                title: "Scripture References (SermonScriptures.txt)",
                subtitle: "\(nonEmptyLineCount(viewModel.scripturesBody)) refs",
                icon: "book.closed",
                text: viewModel.scripturesBody
            )
            .frame(minWidth: 240, idealWidth: 290, maxWidth: 380, maxHeight: .infinity)
        }
    }

    // MARK: - Footer Status Bar

    private var footerStatusBar: some View {
        HStack {
            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(viewModel.isErrorStatus ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Writes: MainSpeaker.txt • SermonTitle.txt • \(viewModel.sermonTextFilename()) • SermonScriptures.txt")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func nonEmptyLineCount(_ s: String) -> Int {
        s.split(whereSeparator: \.isNewline).count
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        panel.directoryURL = URL(filePath: viewModel.saveDirectoryPath)
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveDirectoryPath = url.path(percentEncoded: false)
            if !viewModel.sermonTextBody.isEmpty || !viewModel.title.isEmpty {
                writeFilesToDisk()
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "pptx") ?? .presentation,
            UTType(filenameExtension: "ppt") ?? .presentation,
            .pdf,
            .emailMessage,
            .plainText
        ]
        if panel.runModal() == .OK, let url = panel.url {
            handleIncomingFile(url)
        }
    }

    private func handleIncomingFile(_ url: URL) {
        if SermonCleanerEngine.isEmlFile(url) {
            let info = SermonCleanerEngine.inspectEmlFile(url)
            let defaultSpk = info.sender
                ?? (viewModel.speaker.isEmpty ? SermonCleanerEngine.defaultSpeaker : viewModel.speaker)

            if !info.attachments.isEmpty {
                promptForEmlSource(emlURL: url, info: info, defaultSpeaker: defaultSpk)
                return
            }

            viewModel.pendingLoad = PendingOutlineLoad(
                fileURL: url,
                fallbackTitle: info.subject,
                speakerInput: defaultSpk
            )
            return
        }

        let detectedAuthor = SermonCleanerEngine.extractDocumentAuthor(from: url)
        let currentSpk = detectedAuthor
            ?? (viewModel.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SermonCleanerEngine.defaultSpeaker
                : viewModel.speaker)
        viewModel.pendingLoad = PendingOutlineLoad(
            fileURL: url,
            fallbackTitle: nil,
            speakerInput: currentSpk
        )
    }

    private func promptForEmlSource(emlURL: URL, info: EmlInspection, defaultSpeaker: String) {
        let alert = NSAlert()
        alert.messageText = "Email Attachment Detected"
        let names = info.attachments.map(\.filename).joined(separator: ", ")
        alert.informativeText = "This email contains: \(names)\n\nWould you like to extract the sermon outline from the attachment or from the email body?"
        alert.alertStyle = .informational

        for att in info.attachments {
            alert.addButton(withTitle: "Use Attachment (\(att.filename))")
        }
        alert.addButton(withTitle: "Use Email Body")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let firstButtonRaw = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let index = response.rawValue - firstButtonRaw

        if index >= 0 && index < info.attachments.count {
            let chosen = info.attachments[index]
            let tempDir = URL.cachesDirectory.appending(path: "SermonOutlineCleanerDrops", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let savedURL = tempDir.appending(path: chosen.filename)
            do {
                try chosen.data.write(to: savedURL, options: .atomic)
                let attachmentAuthor = SermonCleanerEngine.extractDocumentAuthor(from: savedURL) ?? defaultSpeaker
                viewModel.pendingLoad = PendingOutlineLoad(
                    fileURL: savedURL,
                    fallbackTitle: info.subject,
                    speakerInput: attachmentAuthor
                )
            } catch {
                viewModel.statusMessage = "Error saving attachment: \(error.localizedDescription)"
                viewModel.isErrorStatus = true
            }
        } else if index == info.attachments.count {
            viewModel.pendingLoad = PendingOutlineLoad(
                fileURL: emlURL,
                fallbackTitle: info.subject,
                speakerInput: defaultSpk(defaultSpeaker)
            )
        }
    }

    private func defaultSpk(_ spk: String) -> String { spk }

    private func runSermonProcessor(url: URL, speakerOverride: String, fallbackTitle: String?) {
        viewModel.isProcessing = true
        viewModel.isErrorStatus = false
        viewModel.lastLoadedFileURL = url
        viewModel.lastLoadedFallbackTitle = fallbackTitle
        viewModel.statusMessage = "Processing \(url.lastPathComponent)…"

        let maxChars = Int(viewModel.maxLineLength)
        let spk = speakerOverride

        Task {
            do {
                let hasSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                }

                let result = try await SermonWorkspaceViewModel.processOutlineInBackground(
                    fileURL: url,
                    speaker: spk,
                    maxLineChars: maxChars,
                    fallbackTitle: fallbackTitle
                )

                viewModel.speaker = result.speaker
                viewModel.title = result.title
                viewModel.sermonTextBody = result.lines.joined(separator: "\n")
                viewModel.scripturesBody = result.scriptures.joined(separator: "\n")
                viewModel.isProcessing = false

                writeFilesToDisk(loadedFromFilename: url.lastPathComponent)
            } catch {
                viewModel.isProcessing = false
                viewModel.isErrorStatus = true
                viewModel.statusMessage = "Error processing \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func writeFilesToDisk(loadedFromFilename: String? = nil) -> Bool {
        do {
            let written = try SermonFileWriter.writeOutputFiles(
                to: viewModel.saveDirectoryPath,
                speaker: viewModel.speaker,
                title: viewModel.title,
                textBody: viewModel.sermonTextBody,
                scripturesBody: viewModel.scripturesBody,
                previousSermonTextURL: viewModel.lastWrittenSermonTextURL
            )
            viewModel.lastWrittenSermonTextURL = written.fileURL
            viewModel.isErrorStatus = false

            if let src = loadedFromFilename {
                viewModel.statusMessage = "✓ Processed \"\(src)\" → Saved \(written.filename) + 3 files to \(viewModel.saveDirectoryPath)"
            } else {
                viewModel.statusMessage = "✓ Saved MainSpeaker.txt, SermonTitle.txt, \(written.filename), SermonScriptures.txt to \(viewModel.saveDirectoryPath)"
            }
            return true
        } catch {
            viewModel.isErrorStatus = true
            viewModel.statusMessage = "Failed to write output files: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - ProPresenter Import Automation

    private func importToProPresenter() {
        // 1. Ensure all 4 sermon files are saved to disk first
        guard writeFilesToDisk() else { return }

        // 2. Check Accessibility permission first (required for System Events menu/keystroke automation)
        guard ProPresenterAutomator.isAccessibilityTrusted(promptIfNeeded: true) else {
            viewModel.isErrorStatus = true
            viewModel.statusMessage = "⚠️ Accessibility permission required to automate ProPresenter's Import dialog."
            viewModel.showingAccessibilitySettingsAlert = true
            return
        }

        let targetFilename = viewModel.sermonTextFilename()
        let outDir = URL(filePath: viewModel.saveDirectoryPath, directoryHint: .isDirectory)
        let sermonFileURL = outDir.appending(path: targetFilename)
        let sermonFilePath = sermonFileURL.path(percentEncoded: false)

        // 3. Locate ProPresenter.app
        guard let proAppURL = ProPresenterAutomator.locateProPresenterApplication() else {
            viewModel.isErrorStatus = true
            viewModel.statusMessage = "⚠️ ProPresenter.app was not found in /Applications."
            return
        }

        viewModel.isErrorStatus = false
        viewModel.statusMessage = "Launching ProPresenter and importing \(targetFilename)…"

        Task {
            let outcome = await ProPresenterAutomator.importSermonFile(
                at: sermonFilePath,
                filename: targetFilename,
                proAppURL: proAppURL
            )
            switch outcome {
            case .success(let message):
                viewModel.isErrorStatus = false
                viewModel.statusMessage = message
            case .automationPermissionDenied:
                viewModel.isErrorStatus = true
                viewModel.statusMessage = "⚠️ macOS Automation permission is disabled for System Events."
                viewModel.showingAutomationDeniedAlert = true
            case .message(let errorMessage):
                viewModel.isErrorStatus = true
                viewModel.statusMessage = errorMessage
            }
        }
    }
}

#Preview {
    ContentView()
}
