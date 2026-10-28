import SwiftUI
import AppKit

//
//  PreviewCard.swift
//  SermonOutlineCleaner
//
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

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
