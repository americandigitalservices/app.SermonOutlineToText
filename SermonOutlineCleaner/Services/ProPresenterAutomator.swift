import Foundation
import AppKit
import ApplicationServices

//
//  ProPresenterAutomator.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

/// Manages Accessibility trust checks, AppleEvents permission resets, and ProPresenter import automation.
enum ProPresenterAutomator {

    enum ImportOutcome: Sendable {
        case success(String)
        case automationPermissionDenied
        case message(String)
    }

    static func isAccessibilityTrusted(promptIfNeeded: Bool = true) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func resetAppleEventsPermission() throws {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.danielhorning.SermonOutlineCleaner"
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/tccutil")
        task.arguments = ["reset", "AppleEvents", bundleID]
        try task.run()
        task.waitUntilExit()
    }

    static func locateProPresenterApplication() -> URL? {
        let proBundleID = "com.renewedvision.propresenter"
        let proAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: proBundleID)
            ?? URL(filePath: "/Applications/ProPresenter.app")

        guard FileManager.default.fileExists(atPath: proAppURL.path(percentEncoded: false)) else {
            return nil
        }
        return proAppURL
    }

    static func importSermonFile(at sermonFilePath: String, filename: String, proAppURL: URL) async -> ImportOutcome {
        // Set the file path on the clipboard natively in Swift (avoids AppleScript string escaping issues)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sermonFilePath, forType: .string)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        do {
            let runningApp = try await NSWorkspace.shared.openApplication(at: proAppURL, configuration: config)
            NSApp.deactivate()
            runningApp.activate()

            if let scriptError = await executeAppleScriptInBackground(importAppleScriptSource) {
                if scriptError.errorCode == -1743 {
                    return .automationPermissionDenied
                } else {
                    return .message("⚠️ ProPresenter Import Error (\(scriptError.errorCode)): \(scriptError.errorMessage)")
                }
            } else {
                runningApp.activate()
                return .success("✓ Imported \(filename) into ProPresenter")
            }
        } catch {
            return .message("⚠️ Failed to launch ProPresenter: \(error.localizedDescription)")
        }
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

    private static let importAppleScriptSource = """
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
}
