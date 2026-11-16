import SwiftUI
import AppKit

@main
struct AmazingNewsApp: App {
    @StateObject private var store = EditionStore.shared

    init() {
        // Menu bar only: no Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
        // Developer check: `AmazingNews --snapshot <dir>` renders the views to PNG and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            Snapshot.run(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--icon"), args.count > i + 1 {
            Snapshot.icon(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        // Developer check: `AmazingNews --image-report <dir>...` prints how alike the pictures are.
        if let i = args.firstIndex(of: "--image-report") {
            let files = args[(i + 1)...].flatMap { dir -> [URL] in
                let e = FileManager.default.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)
                return (e?.allObjects as? [URL] ?? []).filter { ["jpg", "png", "webp", "gif"].contains($0.pathExtension) && !$0.lastPathComponent.hasPrefix("comic") }
            }
            let fps = files.compactMap { u in ImageFingerprint(url: u).map { (u, $0) } }
            var rows: [(Int, Double, String)] = []
            for a in 0..<fps.count { for b in (a + 1)..<fps.count {
                let (ua, fa) = fps[a], (ub, fb) = fps[b]
                let name = { (u: URL) in u.deletingLastPathComponent().lastPathComponent + "/" + u.lastPathComponent }
                rows.append((fa.structureDistance(fb), fa.colorDistance(fb), "\(name(ua)) ~ \(name(ub))\(fa.looksLike(fb) ? "  <== REPEAT" : "")"))
            } }
            for r in rows.sorted(by: { $0.0 * 10 + Int($0.1) < $1.0 * 10 + Int($1.1) }).prefix(25) {
                print(String(format: "struct %2d  colour %5.1f  ", r.0, r.1) + r.2)
            }
            exit(0)
        }
        // Developer check: `AmazingNews --build-into <dir>` prints today's edition into <dir> and exits.
        if let i = args.firstIndex(of: "--build-into"), args.count > i + 1 {
            Snapshot.buildInto(URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        DispatchQueue.main.async { EditionStore.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("Amazing Info News", id: "edition") {
            EditionView()
                .environmentObject(store)
        }
        .defaultSize(width: 1000, height: 1000)

        Window("Ai.N Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon. It's always on screen, so it also listens for notification clicks
/// and opens the full edition.
struct MenuBarLabel: View {
    @EnvironmentObject var store: EditionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(unread: store.hasUnread))
            .onReceive(NotificationCenter.default.publisher(for: .ainOpenEdition)) { _ in
                store.goToLatest()
                openWindow(id: "edition")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// The black-block logo as a menu-bar template image (it follows the menu bar's colour).
/// Unread: solid block with the letters cut out. Read: outlined block.
enum MenuBarIcon {
    static func image(unread: Bool, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let inset = rect.insetBy(dx: size * 0.03, dy: size * 0.03)
            let block = NSBezierPath(roundedRect: inset, xRadius: size * 0.2, yRadius: size * 0.2)
            NSColor.black.set()
            if unread { block.fill() } else { block.lineWidth = max(1, size * 0.07); block.stroke() }
            let serif = NSFont.systemFont(ofSize: size * 0.43, weight: .black).fontDescriptor.withDesign(.serif)
            let font = serif.flatMap { NSFont(descriptor: $0, size: size * 0.43) } ?? NSFont.boldSystemFont(ofSize: size * 0.43)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            NSGraphicsContext.current?.compositingOperation = unread ? .destinationOut : .sourceOver
            ("Ai" as NSString).draw(at: NSPoint(x: size * 0.16, y: size * 0.00), withAttributes: attrs)
            (".N" as NSString).draw(at: NSPoint(x: size * 0.16, y: size * 0.40), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }
}
