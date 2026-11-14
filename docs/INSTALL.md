# Installing viewMD

viewMD is a quick, clean Markdown viewer and editor for the Mac. This guide
explains how to install it on a Mac and how to make it the app that opens
when you double-click a Markdown (`.md`) file.

## What you need

- A Mac running **macOS 15 (Sequoia) or later**, with Apple silicon or Intel.
- The file **viewMD.zip**.

## 1. Install the app

1. Copy **viewMD.zip** to the Mac by AirDrop, a USB drive, email or a file
   share. Copy the zip file, not the app by itself: the zip keeps the app's
   signature intact.
2. Double-click **viewMD.zip** to unzip it. **viewMD.app** appears next to it.
3. Drag **viewMD.app** into your **Applications** folder.

## 2. Open it the first time

viewMD isn't distributed through the App Store, so the first time you open it,
macOS shows a warning that it can't verify the app. This only happens once.

1. In **Applications**, double-click **viewMD**. When the warning appears,
   click **Done** (or **Cancel**).
2. Open **System Settings** and choose **Privacy & Security**.
3. Scroll down to the **Security** section. You'll see a message saying
   viewMD was blocked. Click **Open Anyway**, and confirm with your password
   or Touch ID if asked.
4. viewMD opens. From now on it opens normally, with no warning.

> **Tip:** Opening viewMD once also registers it with macOS as an app that
> can open Markdown files, which you need for the next step.

## 3. Make viewMD the default for Markdown files

The steps below make *every* `.md` file open in viewMD when you double-click
it.

1. In Finder, find any file that ends in **.md**.
2. Select it and choose **File ▸ Get Info**, or press **⌘I**.
3. In the Info window, open the **Open with** section if it's collapsed (click
   its arrow).
4. Choose **viewMD** from the pop-up menu. If viewMD isn't listed, choose
   **Other…**, then select **viewMD** in **Applications** and click **Add**.
5. Click **Change All…**, then click **Continue** to confirm.

Double-clicking any `.md` file now opens it in viewMD. Finder updates the
files' icons to match.

> **Files ending in `.markdown`:** macOS treats `.markdown` as a separate
> extension. To make viewMD its default too, repeat these steps with a
> `.markdown` file.

### Opening a single file in viewMD

To open just one file in viewMD without changing the default for every file,
use this instead:

- **Right-click** (or Control-click) the file, choose **Open With**, then
  choose **viewMD**. That opens it in viewMD once.
- To always open *that file* in viewMD, right-click it and hold down the
  **Option** key. **Open With** changes to **Always Open With**; choose
  **viewMD**.

## Troubleshooting

| Problem | What to do |
|---------|------------|
| viewMD isn't in the **Open with** list | Open viewMD from Applications once, then try again. |
| macOS says viewMD "can't be opened" | Follow step 2 above (**Privacy & Security ▸ Open Anyway**). |
| Some `.md` files still open in another app | Those files were set individually. Select one, open **Get Info**, choose **viewMD** and click **Change All…** again. |
| Images next to a document don't show | Click **Grant Access…** in the bar above the rendered view and choose the document's folder. viewMD remembers it. |

## Using viewMD

The window has two panes: the **rendered** document on the left and the
Markdown **source** on the right. You can edit in either pane, and each updates
the other as you type.

| To | Do this |
|----|---------|
| Show or hide the source | Press **⌥⌘S** or click the sidebar button in the toolbar. |
| Add a heading, list, table, link and more | Use the toolbar pull-downs or the **Format** menu. |
| Bold / italic | **⌘B** / **⌘I** |
| Export as a web page or PDF | **File ▸ Export as HTML…** (⇧⌘E) or **Export as PDF…** (⇧⌘P) |
| Open a link in the rendered view | **⌘-click** it |

## Credits

- **Idea and design:** Stephen Hicks, N5AC
- **Code:** written by Claude (Anthropic)
- viewMD uses Apple's swift-markdown and highlight.js. The Markdown mark in
  the app icon is by Dustin Curtis (public domain).
