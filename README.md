# Sermon Outline Cleaner (macOS)

A native macOS app that converts sermon outlines (`.docx`, `.pdf`, `.eml`, or `.txt`) into formatted `.txt` files for ProPresenter lower thirds[cite: 2, 12].

---

## Generated Files

Each time you load an outline, the app saves four files to your chosen folder (defaulting to `~/Desktop`)[cite: 12]:

* **`MainSpeaker.txt`** — The speaker's name (single line)[cite: 2, 12].
* **`SermonTitle.txt`** — The sermon title extracted from the document header, email subject, or filename[cite: 2, 13].
* **`SermonText-<Title>-<Speaker>.txt`** — The full sermon outline and scripture verses, smart-wrapped to your column limit with standardized `Book Ch:V (TRANS) - ` prefixes[cite: 2, 12, 13].
* **`SermonScriptures.txt`** — An ordered list of all canonical scripture references and translations found in the outline[cite: 2, 13].

---

## What It Cleans Automatically

* **Standardizes Scripture References:** Expands book abbreviations (`Luk` → `Luke`, `II Cor` → `2 Corinthians`) and translation names (`Amplified Bible, Classic Edition` → `AMPC`, `New Living Translation` → `NLT`) into a consistent `Book Ch:V (TRANS)` format[cite: 2, 13].
* **Smart Line Wrapping:** Wraps both verses and commentary notes at natural clause breaks (`Column Limit`, default `105` characters) while keeping parenthetical `(…)` and bracketed `[…]` amplifications together[cite: 2, 12, 13].
* **Typography & List Cleanup:** Strips leading bullet points (`•`, `-`, `*`, `>`), removes BibleGateway footnote markers (`[a]`, `[b]`), converts smart quotes to straight quotes, normalizes dashes (` - `), and removes trailing colons/semicolons on topic headers[cite: 2, 7, 13].

---

## How to Use

1. **Set Your Preferences (Top Bar):**
   * **Save Location:** Click **Browse…** to choose where your `.txt` files are saved (remembered automatically between launches)[cite: 12].
   * **Speaker Name:** Enter the speaker's name[cite: 12]. Check **Use .eml Sender** only if you want `.eml` email files to automatically overwrite this field with the email's `From:` name[cite: 12].
   * **Column Limit:** Set the maximum characters per line (`45`–`250`, default `105`)[cite: 12, 13]. Changing this value with a file loaded immediately re-wraps the text[cite: 12].

2. **Load an Outline:**
   * Drag and drop a `.docx`, `.pdf`, `.eml`, or `.txt` file into the drop zone (or onto the app's Dock icon), or click **Select Outline…**[cite: 2, 12].

3. **Review or Edit Previews:**
   * Inspect all four generated files directly in the 2x2 preview grid[cite: 12].
   * You can type or make quick changes inside any preview box and click **Save Edits** (or **Sync Preview Edits to Disk**) to update the files on disk[cite: 12].

4. **Import to ProPresenter:**
   * Click **Import to ProPresenter** to launch/focus ProPresenter and automatically import the generated `SermonText-<Title>-<Speaker>.txt` file[cite: 12].

---

## First-Time macOS Permission Note

To use the **Import to ProPresenter** button, macOS requires **Accessibility** permission so the app can trigger ProPresenter's file import shortcut[cite: 12]:

1. The first time you click **Import to ProPresenter**, macOS will prompt you to grant access[cite: 12].
2. Open **System Settings > Privacy & Security > Accessibility** and toggle **SermonOutlineCleaner** ON[cite: 12].
