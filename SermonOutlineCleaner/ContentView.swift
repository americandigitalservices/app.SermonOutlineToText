import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ApplicationServices

struct ContentView: View {
    @AppStorage("saveDirectoryPath") private var saveDirectoryPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    @AppStorage("speakerName") private var speakerName: String = SermonCleanerEngine.defaultSpeaker
    @AppStorage("maxLineChars") private var maxLineChars: Int = SermonCleanerEngine.defaultMaxLineChars

    @State private var currentFileURL: URL? = nil
    @State private var previewSpeaker: String = ""
    @State private var previewTitle: String = ""
    @State private var previewText: String = ""
    @State private var previewScriptures: String = ""

    @State private var lineCount: Int = 0
    @State private var scriptureCount: Int = 0
    @State private var statusMessage: String = "Drop a Sermon Outline (.docx, .pdf, .eml, .txt) or click Select Outline"
    @State private var isTargeted: Bool = false

    private var sermonTextFilename: String {
        let safeTitle = sanitizeFilenameComponent(
            previewTitle.isEmpty ? "Untitled" : previewTitle,
            maxLength: 45
        )
        let rawSpeaker = previewSpeaker.isEmpty ? speakerName : previewSpeaker
        let safeSpeaker = sanitizeFilenameComponent(
            rawSpeaker.isEmpty ? SermonCleanerEngine.defaultSpeaker : rawSpeaker,
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
        
        // Truncate cleanly on word/dash boundaries if possible
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
        
        // Fallback if a single continuous string exceeds maxLength
        if truncated.isEmpty {
            truncated = String(cleaned.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        
        return truncated.isEmpty ? "Untitled" : truncated
    }

    var body: some View {
        VStack(spacing: 14) {
            // 1. Settings Bar: Save Location, Speaker Name & Column Limit
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
                            TextField("Pastor Ernest Fink", text: $speakerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveManualEditsToDisk)

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
                        Button("Save Edits", action: saveManualEditsToDisk)
                            .frame(width: 110)
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
                        Text("Supports Word (.docx), PDF (.pdf), Apple Mail (.eml), and Text (.txt)")
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
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            // 3. 2x2 Mini Previews of Latest Created Files
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    PreviewCard(
                        title: "MainSpeaker.txt",
                        badge: "1 line",
                        text: $previewSpeaker
                    )
                    PreviewCard(
                        title: "SermonTitle.txt",
                        badge: "1 line",
                        text: $previewTitle
                    )
                }
                .frame(height: 82)

                HStack(spacing: 12) {
                    PreviewCard(
                        title: sermonTextFilename,
                        badge: "\(lineCount) lines • max \(maxLineChars) ch",
                        text: $previewText
                    )
                    PreviewCard(
                        title: "SermonScriptures.txt",
                        badge: "\(scriptureCount) scriptures",
                        text: $previewScriptures
                    )
                }
            }

            // 4. Footer Actions
            HStack {
                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Spacer()

                Button {
                    saveManualEditsToDisk()
                } label: {
                    Label("Sync Preview Edits to Disk", systemImage: "square.and.arrow.down")
                }

                Button {
                    importToProPresenter()
                } label: {
                    Label("Import to ProPresenter", systemImage: "play.display")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear(perform: loadExistingPreviewsFromDisk)
        .onOpenURL { url in
            processFile(url)
        }
        .onChange(of: speakerName) { _, newValue in
            if previewSpeaker != newValue {
                previewSpeaker = newValue
            }
        }
        .onChange(of: previewSpeaker) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if speakerName != trimmed {
                speakerName = trimmed
            }
        }
    }

    // MARK: - Actions

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Save Location"
        panel.directoryURL = URL(fileURLWithPath: saveDirectoryPath)

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
            loadExistingPreviewsFromDisk()
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            .emailMessage,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "eml") ?? .data
        ]

        if panel.runModal() == .OK, let url = panel.url {
            processFile(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                processFile(url)
            }
        }
        return true
    }

    private func reprocessIfLoaded() {
        if let url = currentFileURL {
            processFile(url)
        }
    }

    private func processFile(_ fileURL: URL) {
        do {
            currentFileURL = fileURL
            let result = try SermonCleanerEngine.processSermonFile(
                url: fileURL,
                fallbackSpeaker: speakerName,
                maxLineChars: maxLineChars
            )

            speakerName = result.speaker
            previewSpeaker = result.speaker
            previewTitle = result.title
            previewText = result.lines.joined(separator: "\n")
            previewScriptures = result.scriptures.joined(separator: "\n")

            lineCount = result.lines.count
            scriptureCount = result.scriptures.count

            try writeFilesToDisk()
            statusMessage = "✓ Saved \(sermonTextFilename) to \((saveDirectoryPath as NSString).abbreviatingWithTildeInPath)"
        } catch {
            statusMessage = "⚠️ Error: \(error.localizedDescription)"
        }
    }

    private func writeFilesToDisk() throws {
        let outDir = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        try previewSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: outDir.appendingPathComponent("MainSpeaker.txt"), atomically: true, encoding: .utf8)

        try previewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: outDir.appendingPathComponent("SermonTitle.txt"), atomically: true, encoding: .utf8)

        let textBody = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        try (textBody.isEmpty ? "" : textBody + "\n")
            .write(to: outDir.appendingPathComponent(sermonTextFilename), atomically: true, encoding: .utf8)

        let scripBody = previewScriptures.trimmingCharacters(in: .whitespacesAndNewlines)
        try (scripBody.isEmpty ? "" : scripBody + "\n")
            .write(to: outDir.appendingPathComponent("SermonScriptures.txt"), atomically: true, encoding: .utf8)
    }

    private func saveManualEditsToDisk() {
        do {
            try writeFilesToDisk()
            lineCount = previewText.split(whereSeparator: \.isNewline).count
            scriptureCount = previewScriptures.split(whereSeparator: \.isNewline).count
            statusMessage = "✓ Updated \(sermonTextFilename) in \((saveDirectoryPath as NSString).abbreviatingWithTildeInPath)"
        } catch {
            statusMessage = "⚠️ Failed to write files: \(error.localizedDescription)"
        }
    }

    private func loadExistingPreviewsFromDisk() {
        let outDir = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        if let spk = try? String(contentsOf: outDir.appendingPathComponent("MainSpeaker.txt"), encoding: .utf8) {
            previewSpeaker = spk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !previewSpeaker.isEmpty { speakerName = previewSpeaker }
        }
        if let ttl = try? String(contentsOf: outDir.appendingPathComponent("SermonTitle.txt"), encoding: .utf8) {
            previewTitle = ttl.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Load matching "Sermon Text -TITLE-Speaker.txt", or fallback to the most recent "Sermon Text -*.txt"
        let expectedTextURL = outDir.appendingPathComponent(sermonTextFilename)
        if let txt = try? String(contentsOf: expectedTextURL, encoding: .utf8) {
            previewText = txt.trimmingCharacters(in: .whitespacesAndNewlines)
            lineCount = previewText.isEmpty ? 0 : previewText.components(separatedBy: .newlines).count
        } else if let latestURL = mostRecentSermonTextFile(in: outDir),
                  let txt = try? String(contentsOf: latestURL, encoding: .utf8) {
            previewText = txt.trimmingCharacters(in: .whitespacesAndNewlines)
            lineCount = previewText.isEmpty ? 0 : previewText.components(separatedBy: .newlines).count
        }

        if let scr = try? String(contentsOf: outDir.appendingPathComponent("SermonScriptures.txt"), encoding: .utf8) {
            previewScriptures = scr.trimmingCharacters(in: .whitespacesAndNewlines)
            scriptureCount = previewScriptures.isEmpty ? 0 : previewScriptures.components(separatedBy: .newlines).count
        }
    }

    private func mostRecentSermonTextFile(in directory: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        
        let matching = urls.filter { $0.lastPathComponent.hasPrefix("SermonText-") && $0.pathExtension == "txt" }
        return matching.max { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA < dateB
        }
    }

    private func revealInFinder() {
        let outDir = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        let sermonTextURL = outDir.appendingPathComponent(sermonTextFilename)
        if FileManager.default.fileExists(atPath: sermonTextURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([sermonTextURL])
        } else if let latestURL = mostRecentSermonTextFile(in: outDir) {
            NSWorkspace.shared.activateFileViewerSelecting([latestURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: saveDirectoryPath)
        }
    }

    private func importToProPresenter() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            statusMessage = "⚠️ Please enable SermonOutlineCleaner in System Settings > Privacy & Security > Accessibility, then click Import again."
            return
        }

        let sermonFilePath = (saveDirectoryPath as NSString).appendingPathComponent(sermonTextFilename)
        let scriptSource = """
        tell application "ProPresenter" to activate
        tell application "System Events"
            repeat 60 times
                if exists process "ProPresenter" then
                    tell process "ProPresenter"
                        set frontmost to true
                        if (count of windows) > 0 and (exists menu bar item "File" of menu bar 1) then
                            delay 0.5
                            exit repeat
                        end if
                    end tell
                end if
                delay 0.5
            end repeat

            tell process "ProPresenter"
                set frontmost to true
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
            var errorDict: NSDictionary?
            if let scriptObject = NSAppleScript(source: scriptSource) {
                scriptObject.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    DispatchQueue.main.async {
                        self.statusMessage = "⚠️ ProPresenter Import Error: \(msg)"
                    }
                }
            }
        }
    }
}

struct PreviewCard: View {
    let title: String
    let badge: String
    @Binding var text: String

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
            TextEditor(text: $text)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
    }
}
