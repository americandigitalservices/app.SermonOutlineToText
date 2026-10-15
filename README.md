# Sermon Outline Cleaner (macOS)

A native macOS app that converts sermon outlines (`.docx`, `.pdf`, `.eml`, or `.txt`) into formatted `.txt` files for ProPresenter lower thirds.

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
   * **Speaker Name:** Enter the speaker's name. Check **Use .eml Sender** only if you want `.eml` email files to automatically overwrite this field with the email's `From:` name.
   * **Column Limit:** Set the maximum characters per line (`45`–`250`, default `105`). Changing this value with a file loaded immediately re-wraps the text.

2. **Load an Outline:**
   * Drag and drop a `.docx`, `.pdf`,`.pptx`, `.eml`, or `.txt` file into the drop zone (or onto the app's Dock icon), or click **Select Outline…**.

3. **Review or Edit Previews:**
   * Inspect all four generated files directly in the 2x2 preview grid.
   * You can type or make quick changes inside any preview box and click **Save Edits** (or **Sync Preview Edits to Disk**) to update the files on disk.

4. **Import to ProPresenter:**
   * Click **Import to ProPresenter** to launch/focus ProPresenter and automatically import the generated `SermonText-<Title>-<Speaker>.txt` file.

---

## First-Time macOS Permission Note

To use the **Import to ProPresenter** button, macOS requires **Accessibility** permission so the app can trigger ProPresenter's file import shortcut:

1. The first time you click **Import to ProPresenter**, macOS will prompt you to grant access.
2. Open **System Settings > Privacy & Security > Accessibility** and toggle **SermonOutlineCleaner** ON.
