import SwiftUI
import AppKit

/// Renders the main views to PNGs for a quick visual check without clicking through the UI.
@MainActor
enum Snapshot {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = EditionStore.shared
        let env = ProcessInfo.processInfo.environment
        PaperStyle.night = env["AIN_NIGHT"] == "1"
        PaperStyle.scale = env["AIN_SCALE"].flatMap { Double($0) }.map { CGFloat($0) } ?? 1
        if let e = store.edition {
            print("lead:", e.lead?.section ?? "-", "| sections:", e.sections(pinned: store.pinnedSection).map(\.name).joined(separator: ", "),
                  "| week in review:", store.weekInReview.count,
                  "| pictures:", e.stories.filter { $0.image != nil }.count, "of", e.stories.count)
        }
        if env["AIN_KEEP_REPORT"] == "1" {
            for o in EditionStore.keepOptions { print("keep \(o.label): would remove \(store.editionsOlder(thanDays: o.days))") }
        }
        if let pdf = env["AIN_PDF"] { PDFExport.write(store: store, to: URL(fileURLWithPath: pdf)); print("wrote \(pdf)") }

        let page = EditionPage().environmentObject(store).frame(width: 1120)
        save(page, dir.appendingPathComponent("edition.png"))

        let headlines = VStack(alignment: .leading, spacing: 10) {
            HStack { AiNBadge(size: 30); Text("Ai.N").font(.system(size: 22, weight: .black, design: .serif)) }
            CalendarGrid().environmentObject(store)
            ForEach(Array((store.edition?.stories ?? []).prefix(6).enumerated()), id: \.element.id) { i, s in
                HeadlineRow(story: s, isLead: i == 0).environmentObject(store)
            }
        }
        .padding(14).frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        save(headlines, dir.appendingPathComponent("menu.png"))
    }

    /// Builds today's edition into `dir` synchronously (for testing the feed pipeline).
    static func buildInto(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = ProcessInfo.processInfo.environment["AIN_TEST_KEY"]
        let builder = EditionBuilder(outputDir: dir, historyDirs: [dir], apiKey: key)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let e = try await builder.build(dateKey: EditionStore.todayKey)
                for s in e.stories { print(" [\(s.section)] \(s.title) — \(s.source)\(s.image == nil ? "" : " 📷")") }
                print("funnies: \((e.funnies ?? []).map(\.name)) comic: \(e.comic?.title ?? "none")")
            } catch { print("build failed: \(error)") }
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Renders the 1024px app icon.
    static func icon(to url: URL) {
        // macOS icon grid: 824pt artwork centred on a 1024 canvas.
        let view = AiNBadge(size: 824).padding(100)
        save(view, url)
        // Also preview the menu-bar icon (both states) at 4× for checking.
        for (name, unread) in [("menubar-unread", true), ("menubar-read", false)] {
            let img = MenuBarIcon.image(unread: unread, size: 72)
            if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url.deletingLastPathComponent().appendingPathComponent("\(name).png"))
            }
        }
    }

    private static func save<V: View>(_ view: V, _ url: URL) {
        let r = ImageRenderer(content: view)
        r.proposedSize = ProposedViewSize(width: nil, height: nil)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("snapshot failed: \(url.lastPathComponent)"); return
        }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
