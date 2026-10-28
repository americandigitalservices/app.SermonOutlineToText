import SwiftUI
import Observation
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
            .fixedSize(horizontal: false, vertical: true)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        let written = try SermonFileWriter.writeOutputFiles(
            to: saveDirectoryPath,
            speaker: speaker,
            title: title,
            textBody: textBody,
            scripturesBody: scripturesBody,
            previousSermonTextURL: viewModel.lastSavedSermonTextURL
        )
        viewModel.lastSavedSermonTextURL = written.fileURL
        return written.filename
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
        guard ProPresenterAutomator.isAccessibilityTrusted(promptIfNeeded: true) else {
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

        guard let proAppURL = ProPresenterAutomator.locateProPresenterApplication() else {
            viewModel.statusMessage = "⚠️ Could not find ProPresenter.app in /Applications."
            return
        }

        viewModel.statusMessage = "⏳ Launching ProPresenter and waiting for main window…"

        Task {
            let outcome = await ProPresenterAutomator.importSermonFile(
                at: sermonFilePath,
                filename: targetFilename,
                proAppURL: proAppURL
            )
            switch outcome {
            case .success(let message):
                viewModel.statusMessage = message
            case .automationPermissionDenied:
                viewModel.statusMessage = "⚠️ Automation permission denied (-1743)."
                viewModel.showAutomationBlockedAlert = true
            case .message(let errorMessage):
                viewModel.statusMessage = errorMessage
            }
        }
    }
}

#Preview {
    ContentView()
}
