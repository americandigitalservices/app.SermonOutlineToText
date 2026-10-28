import SwiftUI
import AppKit

//
//  MailAwareDropView.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct MailAwareDropView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onFileURL: (URL) -> Void

    func makeNSView(context: Context) -> DropReceivingNSView {
        let view = DropReceivingNSView()
        view.onTargetChanged = { targeted in
            Task { @MainActor in
                self.isTargeted = targeted
            }
        }
        view.onFileReceived = { url in
            Task { @MainActor in
                self.onFileURL(url)
            }
        }
        return view
    }

    func updateNSView(_ nsView: DropReceivingNSView, context: Context) {}
}

final class DropReceivingNSView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onFileReceived: ((URL) -> Void)?

    private static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        types.append(NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeMessageTransfer"))
        types.append(NSPasteboard.PasteboardType("com.apple.mail.message"))
        types.append(NSPasteboard.PasteboardType("public.eml"))
        types.append(NSPasteboard.PasteboardType("com.apple.mail.eml"))
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        let pboard = sender.draggingPasteboard

        // 1. Direct file URLs (Finder drops)
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            onFileReceived?(first)
            return true
        }

        let tempDir = URL.cachesDirectory.appending(path: "SermonOutlineCleanerDrops", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 2. File promises (Apple Mail attachment or message drags)
        if let receivers = pboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           let firstReceiver = receivers.first {
            firstReceiver.receivePromisedFiles(atDestination: tempDir, options: [:], operationQueue: Self.promiseQueue) { [weak self] fileURL, error in
                guard error == nil else { return }
                Task { @MainActor in
                    self?.onFileReceived?(fileURL)
                }
            }
            return true
        }

        // 3. Raw RFC822 / EML data on pasteboard
        for item in pboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type),
                   let str = String(data: data, encoding: .utf8),
                   str.contains("Subject:") && (str.contains("From:") || str.contains("MIME-Version:")) {
                    let outURL = tempDir.appending(path: "DroppedMail-\(UUID().uuidString).eml")
                    try? data.write(to: outURL)
                    onFileReceived?(outURL)
                    return true
                }
            }
        }

        // 4. Apple Mail whole-email drag fallback via AppleScript
        if let types = pboard.types,
           types.contains(where: { $0.rawValue.lowercased().contains("mail") }) {
            let callback = self.onFileReceived
            Task.detached(priority: .userInitiated) {
                if let emlURL = Self.fetchSelectedAppleMailMessageAsEml(into: tempDir) {
                    await MainActor.run {
                        callback?(emlURL)
                    }
                }
            }
            return true
        }

        return false
    }

    nonisolated private static func fetchSelectedAppleMailMessageAsEml(into dir: URL) -> URL? {
        let scriptSource = """
        tell application "Mail"
            set sel to selection
            if (count of sel) is 0 then return ""
            set msg to item 1 of sel
            return source of msg
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        guard err == nil, let rawSource = desc.stringValue, !rawSource.isEmpty else { return nil }
        let outURL = dir.appending(path: "AppleMail-\(UUID().uuidString).eml")
        try? rawSource.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }
}
