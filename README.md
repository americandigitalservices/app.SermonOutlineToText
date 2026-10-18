# Sermon Outline Cleaner (macOS)

A native macOS app that converts sermon outlines (`.docx`, `.pptx`, `.ppt`, `.pdf`, `.eml`, or `.txt`) into formatted `.txt` files for ProPresenter lower thirds.

---

## Generated Files

Each time you load an outline, the app saves four files to your chosen folder (defaulting to `~/Desktop`):

* **`MainSpeaker.txt`** — The speaker's name (single line).
* **`SermonTitle.txt`** — The sermon title extracted from the document header, email subject, or filename.
* **`SermonText-<Title>-<Speaker>.txt`** — The full sermon outline and scripture verses, smart-wrapped to your column limit with standardized `Book Ch:V (TRANS) - ` prefixes.
* **`SermonScriptures.txt`** — An ordered list of all canonical scripture references and translations found in the outline.

---

## What It Cleans Automatically

* **Standardizes Scripture References:** Expands book abbreviations (`Luk` → `Luke`, `II Cor` → `2 Corinthians`) and translation names (`Amplified Bible, Classic Edition` → `AMPC`, `New Living Translation` → `NLT`) into a consistent `Book Ch:V (TRANS)` format.
* **Smart Line Wrapping:** Wraps both verses and commentary notes at natural clause breaks (`Column Limit`, default `105` characters) while keeping parenthetical `(…)` and bracketed `[…]` amplifications together.
* **Typography & List Cleanup:** Strips leading bullet points (`•`, `-`, `*`, `>`), removes BibleGateway footnote markers (`[a]`, `[b]`), converts smart quotes to straight quotes, normalizes dashes (` - `), and removes trailing colons/semicolons on topic headers.

---

## How to Use

1. **Set Your Preferences (Top Bar):**
   * **Save Location:** Click **Browse…** to choose where your `.txt` files are saved (remembered automatically between launches).
   * **Speaker Name:** Leave blank to be prompted when loading a file, or type a name beforehand. If you load an `.eml` email while this field is blank, the prompt automatically pre-fills the email's `From:` sender name.
   * **Column Limit:** Set the maximum characters per line (`45`–`250`, default `105`). Changing this value with a file loaded immediately re-wraps the text.

2. **Load an Outline:**
   * Drag and drop a `.docx`, `.pptx`, `.pdf`, `.eml`, or `.txt` file from Finder—or drag an email/attachment directly out of **Apple Mail**—into the drop zone, or click **Select Outline…**.
   * If an email contains attachments, a dialog lets you choose between parsing any attachment or the email body text.

3. **Review Previews & Import to ProPresenter:**
   * Inspect all four generated files in the read-only 2x2 preview grid.
   * Click **Import to ProPresenter** to launch/focus ProPresenter and automatically import the generated `SermonText-<Title>-<Speaker>.txt` file.

---

## First-Time macOS Permissions

To use the **Import to ProPresenter** button, macOS requires **Accessibility** and **Automation** permissions:

1. **Accessibility:** The first time you click **Import to ProPresenter**, open **System Settings > Privacy & Security > Accessibility** and toggle **SermonOutlineCleaner** ON.
2. **Automation:** When macOS displays the prompt stating *"SermonOutlineCleaner needs permission to launch ProPresenter and trigger the file import menu"*, click **Allow**.
3. **Resetting Permissions:** If Automation permission was accidentally denied, choose **SermonOutlineCleaner > Reset Permissions** from the top menu bar (or click **Reset Permissions** in the warning dialog) and click **Import to ProPresenter** again.