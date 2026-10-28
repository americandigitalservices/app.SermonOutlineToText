import SwiftUI

//
//  SpeakerPromptSheet.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

struct SpeakerPromptSheet: View {
    let filename: String
    @Binding var speakerName: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Main Speaker")
                        .font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text("Who is the speaker for this sermon outline?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Speaker Name", text: $speakerName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submit()
                }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Process Outline") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 390)
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        onConfirm(trimmed.isEmpty ? SermonCleanerEngine.defaultSpeaker : trimmed)
    }
}
