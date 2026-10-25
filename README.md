# Sermon Outline Cleaner (macOS)

A native macOS utility built for church media and production teams that instantly transforms raw sermon outlines (`.docx`, `.pptx`, `.ppt`, `.pdf`, `.eml`, or `.txt`) into clean, smart-wrapped `.txt` files ready for **ProPresenter** lower thirds and live broadcast slides.

---

## Summary

Preparing a pastor's sermon notes for live lower-third presentation traditionally requires tedious manual cleanup: stripping bullet points, fixing smart quotes, standardizing scripture abbreviations, splitting long verses across multiple slides, and repeating scripture references on every wrapped line.

**Sermon Outline Cleaner** automates that entire workflow in a single drag-and-drop step:

* **Accepts Any Sermon Source:** Drag and drop files from Finder or drag emails and attachments directly out of **Apple Mail** anywhere onto the app window (`.docx`, `.pptx`, `.ppt`, `.pdf`, `.eml`, `.txt`).
* **Intelligent Scripture & Verse Formatting:** Automatically expands book abbreviations (`Luk` → `Luke`, `II Cor` → `2 Corinthians`) and Bible translations (`Amplified Bible, Classic Edition` → `AMPC`, `New Living Translation` → `NLT`) into a standardized `Book Ch:V (TRANS) - ` prefix on every wrapped verse line.
* **Clause-Aware Smart Wrapping:** Splits long verses and commentary notes at natural punctuation and clause boundaries (`Column Limit`, default `105` characters) while keeping parenthetical `(…)` and bracketed `[…]` amplifications intact.
* **One-Click ProPresenter Import:** Generates four structured `.txt` files on disk and imports the formatted sermon text directly into **ProPresenter** at the click of a button.

### Video Walkthrough

Watch a quick demonstration of how the app works in action:
* **[Watch the Sermon Outline Cleaner Demo on YouTube](https://youtu.be/h7rZM4KHUfE)** *(Note: Filmed on an earlier build; core layout and visual workflow remain the same.)*

---

## Installation

1. **Download & Unzip:** Download the latest release `.zip` archive and double-click it in Finder to extract **`SermonOutlineCleaner.app`**.
2. **Move to Applications:** Drag **`SermonOutlineCleaner.app`** into your **`/Applications`** folder.
3. **Launch:** Open **SermonOutlineCleaner** from `/Applications` (or Spotlight) and optionally drag its icon to your Dock for quick Sunday-morning access.

### First-Time macOS Permissions

To use the **Import to ProPresenter** button, macOS requires **Accessibility** and **Automation** permissions so the app can trigger ProPresenter's file import menu:

1. **Accessibility:** The first time you click **Import to ProPresenter**, macOS will prompt you to grant access. Open **System Settings > Privacy & Security > Accessibility** and toggle **SermonOutlineCleaner** ON.
2. **Automation:** When macOS displays the prompt stating *"SermonOutlineCleaner needs permission to launch ProPresenter and trigger the file import menu"*, click **Allow**.
3. **Resetting Permissions (If Needed):** If Automation permission was accidentally denied, choose **SermonOutlineCleaner > Reset Permissions** from the top macOS menu bar (or click **Reset Permissions** in the warning dialog) and click **Import to ProPresenter** again.

---

## Guide for Media Team & Regular Users

### 1. Configure Your Top-Bar Preferences
* **Save Location:** Click **Browse…** to choose where your output `.txt` files are saved (defaults to `~/Desktop` and is remembered automatically between launches).
* **Speaker Name:** Displays the current speaker's name. Whenever you load a file, a prompt will appear so you can confirm or edit the speaker's name (automatically pre-filled from the email's `From:` sender or the document's `Author` metadata). You can also edit this field after loading a file and click **Update Speaker**.
* **Column Limit:** Sets the maximum characters per line (`45`–`250`, default `105`). Adjusting the stepper or typing a new number immediately re-wraps the loaded outline.

### 2. Load a Sermon Outline
* **Drag & Drop Anywhere:** Drag a `.docx`, `.pptx`, `.ppt`, `.pdf`, `.eml`, or `.txt` file from Finder—or drag an email or attachment directly out of **Apple Mail**—and drop it anywhere on the app window.
* **Or Browse:** Click **Select Outline…** to pick a file using the macOS file chooser.
* **Emails with Attachments:** If you load an `.eml` email that contains attachments, a dialog will ask whether you want to parse one of the attachments or the email body text.
* **Confirm Speaker:** Press **Return** (or click **Continue**) in the Speaker Name sheet to confirm the speaker.

### 3. Review Previews & Import to ProPresenter
* **Inspect the 2x2 Preview Grid:** Immediately review the exact contents and line counts of all four generated files:
  * **`MainSpeaker.txt`** — The speaker's name (single line).
  * **`SermonTitle.txt`** — The sermon title extracted from the document header, email subject, or filename.
  * **`SermonText-<Title>-<Speaker>.txt`** — The full sermon outline and scripture verses, smart-wrapped to your column limit.
  * **`SermonScriptures.txt`** — An ordered list of all canonical scripture references and translations found in the outline.
* **Import to ProPresenter:** Click **Import to ProPresenter** in the bottom-right corner to automatically launch/focus ProPresenter and import `SermonText-<Title>-<Speaker>.txt`.
* **Reveal in Finder:** Click **Reveal in Finder** at any time to highlight the generated `.txt` files in your output directory.

---

## Technical Architecture & Developer Guide

### How the Cleaning & Parsing Engine Works (`SermonCleanerEngine.swift`)
* **Multi-Format Extraction:**
  * **Word (`.docx`):** Extracted via `NSAttributedString` document loading and OpenXML `docProps/core.xml` metadata inspection.
  * **PowerPoint (`.pptx` / `.ppt`):** Parses OpenXML slide paragraphs (`ppt/slides/slide*.xml`) and speaker notes (`ppt/notesSlides/notesSlide*.xml`) in numerical slide order via `/usr/bin/unzip`, inserting internal `__SLIDE_BREAK__` markers so standalone scripture headers never bleed across slides. Falls back to Spotlight `MDItem` text extraction for legacy binary `.ppt` files.
  * **PDF (`.pdf`):** Extracted page-by-page via `PDFKit` (`PDFDocument`).
  * **Apple Mail (`.eml`):** Parses RFC-822 headers, decodes RFC-2047 encoded words, unfolds multipart MIME boundaries, decodes `base64` and `quoted-printable` parts, extracts embedded attachments, and unwraps hard-wrapped plain-text or HTML bodies.
* **AppKit `NSFilePromiseReceiver` Bridge (`MailAwareDropView`):**
  * Wraps an AppKit `NSView` drag destination over the SwiftUI window to fulfill `NSFilePromiseReceiver` file promises dragged directly out of Apple Mail while passing normal mouse clicks and scroll events through to underlying SwiftUI controls.
* **Smart Line Wrapping & Scoring:**
  * Tokenizes text while keeping short parenthetical `(…)` and bracketed `[…]` expressions atomic.
  * Evaluates candidate split points using fill ratio, punctuation weights (`.`, `;`, `:`, `,`), clause starters (`and`, `but`, `that`, `which`, participles), and penalties for dangling prepositions/articles (`the`, `of`, `to`, `in`).
* **Typography & Final CotEditor Cleanup Pass:**
  * Strips zero-width spaces (`\u{200B}`–`\u{200D}`, `\u{FEFF}`), soft hyphens (`\u{00AD}`), BibleGateway footnote markers (`[a]`, `[b]`), leading bullet/list markers (`•`, `·`, `∙`, `‣`, `◦`, `-`, `*`, `>`), and trailing colons/semicolons (`:` / `;`), while normalizing smart quotes and dashes.

### Project Structure
```text
SermonOutlineCleaner/
├── SermonOutlineCleaner.xcodeproj/      # Xcode project & shared build scheme
├── SermonOutlineCleaner/
│   ├── SermonOutlineCleanerApp.swift    # App entry point & "Reset Permissions" menu command
│   ├── ContentView.swift                # Main SwiftUI UI, MailAwareDropView & ProPresenter automation
│   └── SermonCleanerEngine.swift        # Extraction, scripture normalization & smart-wrap engine
└── README.md

```

### How to Build on Your Own

#### Requirements

* **macOS:** macOS 15.6+ (Sequoia / Tahoe)


* **Xcode:** Xcode 16.0+ (Swift 5 / Swift 6 language mode with `MainActor` default isolation)



#### 1. Clone & Open in Xcode

```bash
git clone <your-repo-url>
cd app.SermonOutlineToText
open SermonOutlineCleaner.xcodeproj

```

#### 2. Configure Signing

1. In Xcode's Project Navigator, select **SermonOutlineCleaner** at the top and choose the **SermonOutlineCleaner** target.


2. Open the **Signing & Capabilities** tab.
3. Check **Automatically manage signing** and select your **Team** (or choose **Sign to Run Locally** for local ad-hoc builds).


4. Press **`Cmd + R`** to build and run in Debug mode.



#### 3. Command-Line Release Build

You can also compile a Release build directly from Terminal using `xcodebuild`:

```bash
xcodebuild \
  -project SermonOutlineCleaner.xcodeproj \
  -scheme SermonOutlineCleaner \
  -configuration Release \
  -derivedDataPath build

```

The compiled application bundle will be located at:

```text
build/Build/Products/Release/SermonOutlineCleaner.app

```

#### 4. Archiving & Notarizing for Distribution (Optional)

To distribute the app to other Macs without Gatekeeper warnings:

1. In **Signing & Capabilities**, click **`+ Capability`**, add **Hardened Runtime**, and check **Apple Events** under *Resource Access*.
2. Select **Product > Destination > Any Mac (arm64, x86_64)** and choose **Product > Archive**.


3. In the Xcode Organizer, click **Distribute App > Direct Distribution** to sign with your **Developer ID Application** certificate and automatically notarize with Apple.

---

## License & Attribution

Copyright © 2026 Daniel Horning.

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
You are free to use, modify, and distribute this software under the terms of the GPL-3.0, provided that:
1. Any modifications or derivative works are also distributed under the **GPL-3.0** with full source code made available.
2. Original copyright and author attribution notices (**Dan Horning**) are preserved in all source files, documentation, and application "About" panels.

See the [LICENSE](LICENSE) file for the full license text.