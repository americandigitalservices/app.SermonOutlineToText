import SwiftUI
import AppKit

//
//  SpeakerPromptSheet.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

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
