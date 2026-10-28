import SwiftUI
import UniformTypeIdentifiers
import AppKit

//
//  MailAwareDropView.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

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
