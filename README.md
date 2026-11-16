<p align="center"><img src="Resources/icon-1024.png" width="128" alt="Ai.N logo"></p>

# Amazing Info News (Ai.N)

A daily generative-AI newspaper that lives in your Mac's menu bar. Every morning it prints a fresh broadsheet edition from 19 AI news sources, with photos, a calendar of past editions, and The Funnies.

## Download

1. Get **Ai.N for Mac.zip** from the [latest release](../../releases/latest) and unzip it.
2. Drag **Amazing Info News.app** into Applications and open it.
3. macOS will warn that it can't check the app (it isn't notarized). Open **System Settings › Privacy & Security**, click **Open Anyway**, and confirm. You only do this once.

Look for the black **Ai.N** block in the menu bar. Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## What you get

- **Menu-bar headlines:** the day's stories with thumbnails. The icon is solid when there's an edition you haven't opened.
- **Full broadsheet:** a front page with the lead story, By the numbers and an index, then three-column inside pages.
- **Calendar:** step through days or jump to any past edition; *Today* takes you back to the newest.
- **Sunday Week in Review:** the week's top 10 stories.
- **The Funnies:** the latest xkcd and Joy of Tech strips, credited and linked.
- **Jargon buster:** "?" tags explain terms like *agentic*, *open-weight* or *context window*.
- **Share and export:** share or copy a story link, or save an edition as a PDF.
- **Reading comfort:** text size, a night edition, and section filters (hide topics, or always put one first, such as VFX & Film).
- **Morning notification** with the lead headline.
- **Housekeeping:** choose how long to keep old editions, from Always to today only. Old ones go to the Trash.
- **Duplicate pictures** are shown only once per edition, even when two outlets use the same press photo.

## Optional: Claude as editor

Paste your own Anthropic API key into **Settings** and Claude will edit each edition: sharper headlines, "Why it matters" notes, By the numbers, and an original daily **Pixel & Dez** comic strip. It costs a few cents a day on your Anthropic account. The key is stored in your Mac's Keychain and only sent to Anthropic.

## How it works

- At 6 a.m. (or whenever the Mac is next awake), the app reads the feeds listed in [`Feeds.swift`](Sources/AmazingNews/Feeds.swift), keeps AI stories from the last day or two, removes duplicates, sorts them into sections, and downloads each article's lead photo.
- Editions are saved in `~/Library/Application Support/Ai.N/editions`.
- Articles, photos and comics belong to their publishers and creators. Every story links to the original.

## Turning it off

Switch off **Daily delivery** in the menu, or choose **Quit Ai.N**. To remove it, drag the app to the Trash.

## Building from source

Needs the Xcode Command Line Tools (Swift 5.9+).

```bash
./build.sh            # builds "Amazing Info News.app" (Apple silicon + Intel)
./build.sh --package  # also makes "Ai.N for Mac.zip"
```

## Advanced: Claude-written editions

The app also reads editions from `~/claude_code/amazing-news/editions` if that folder exists. There, a Claude Code scheduled task writes each day's edition by searching the web, then runs [`enrich.py`](enrich.py) to save article photos and comics. Those editions take priority, and the app prints its own feed edition only if none has arrived by 10 a.m.
