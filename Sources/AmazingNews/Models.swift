import Foundation
import ServiceManagement
import AppKit
import UserNotifications

struct Story: Codable, Identifiable, Hashable {
    var title: String
    var summary: String
    var why: String?
    var section: String
    var source: String
    var url: String
    var published: String?
    var image: String?          // path relative to editions/

    var id: String { url + title }
}

struct Figure: Codable, Hashable {
    var figure: String
    var label: String
}

/// The editor's original strip: two recurring characters riffing on the day's news.
struct Comic: Codable {
    struct Line: Codable, Hashable { var who: String; var say: String }
    struct Panel: Codable, Hashable { var caption: String?; var lines: [Line] }
    var title: String
    var panels: [Panel]
}

/// A strip from another cartoonist (credited and linked).
struct Funny: Codable, Hashable, Identifiable {
    var name: String
    var credit: String
    var title: String
    var caption: String?
    var url: String
    var image: String?
    var id: String { url }
}

struct Edition: Codable {
    var date: String
    var brief: String?
    var stories: [Story]
    var numbers: [Figure]?
    var comic: Comic?
    var funnies: [Funny]?

    static let sectionOrder = ["Models", "Image & Video", "VFX & Film", "Tools", "Industry", "Research", "Policy"]

    var lead: Story? { stories.first }

    /// Everything after the lead, grouped by section (the reader's pinned section first).
    func sections(pinned: String? = nil) -> [(name: String, stories: [Story])] {
        let rest = Array(stories.dropFirst())
        var order = Edition.sectionOrder
        if let pinned, let i = order.firstIndex(of: pinned) { order.insert(order.remove(at: i), at: 0) }
        let known = order.compactMap { name -> (String, [Story])? in
            let s = rest.filter { $0.section == name }
            return s.isEmpty ? nil : (name, s)
        }
        let other = rest.filter { !Edition.sectionOrder.contains($0.section) }
        return known + (other.isEmpty ? [] : [("More", other)])
    }
}

@MainActor
final class EditionStore: ObservableObject {
    static let shared = EditionStore()

    /// Editions this app builds itself (every install).
    let appDir: URL = ProcessInfo.processInfo.environment["AIN_EDITIONS_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ai.N/editions")
    /// Testing: AIN_EDITIONS_DIR makes this copy behave like a fresh install elsewhere.
    private let isolated = ProcessInfo.processInfo.environment["AIN_EDITIONS_DIR"] != nil
    /// Optional richer editions written by a Claude scheduled task (the publisher's own Mac).
    let claudeBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("claude_code/amazing-news")
    var claudeDir: URL { claudeBase.appendingPathComponent("editions") }
    var hasClaudeEditions: Bool { !isolated && FileManager.default.fileExists(atPath: claudeDir.path) }
    /// Search order: Claude-written editions win over app-built ones for the same day.
    var dirs: [URL] { hasClaudeEditions ? [claudeDir, appDir] : [appDir] }
    var editionsURL: URL { currentDir ?? appDir }
    private var pausedURL: URL { claudeBase.appendingPathComponent("PAUSED") }

    @Published private(set) var dates: [String] = []          // sorted ascending
    @Published private(set) var selectedKey: String?
    @Published private(set) var edition: Edition?
    @Published private(set) var loadError: String?
    @Published private(set) var paused = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var lastSeenKey: String? = UserDefaults.standard.string(forKey: "lastSeenEdition")
    @Published private(set) var building = false
    @Published private(set) var status: String?
    @Published private(set) var hasAPIKey = KeyStore.load() != nil
    /// Sections the reader has switched off, and the one they want first.
    @Published private(set) var hiddenSections = Set(UserDefaults.standard.stringArray(forKey: "hiddenSections") ?? [])
    @Published private(set) var pinnedSection = UserDefaults.standard.string(forKey: "pinnedSection")
    @Published private(set) var notifyEnabled = UserDefaults.standard.object(forKey: "notify") as? Bool ?? true
    /// How many days of past editions to keep (-1 = always, 0 = only today's).
    @Published private(set) var keepDays = UserDefaults.standard.object(forKey: "keepDays") as? Int ?? -1
    static let keepOptions: [(label: String, days: Int)] = [
        ("Always", -1), ("1 year", 365), ("6 months", 182), ("1 month", 30), ("1 week", 7), ("3 days", 3), ("Never (today only)", 0),
    ]
    /// On Sundays: the week's top stories, newest day first.
    @Published private(set) var weekInReview: [(day: String, story: Story)] = []
    /// Today's edition as printed (before section preferences are applied).
    private var rawEdition: Edition?
    private var currentDir: URL?

    nonisolated(unsafe) static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func longDate(_ key: String) -> String {
        guard let d = keyFormatter.date(from: key) else { return key }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    nonisolated static var todayKey: String { keyFormatter.string(from: Date()) }

    private var timer: Timer?
    private var imageCache: [String: NSImage] = [:]

    /// Loads an image stored next to the current edition (cached).
    func image(_ relPath: String?) -> NSImage? {
        guard let relPath, !relPath.isEmpty else { return nil }
        let url = editionsURL.appendingPathComponent(relPath)
        if let img = imageCache[url.path] { return img }
        let img = NSImage(contentsOf: url)
        if let img { imageCache[url.path] = img }
        return img
    }

    init() {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                EditionStore.shared.pruneOldEditions()
                EditionStore.shared.reload()
                EditionStore.shared.buildIfDue()
            }
        }
    }

    /// Call once the app has launched (not during snapshot/CLI runs).
    func start() {
        pruneOldEditions()
        Notifier.setUp()
        buildIfDue()
        notifyIfNew()
    }

    var latestKey: String? { dates.last }
    var hasUnread: Bool { latestKey != nil && latestKey != lastSeenKey }

    private func file(for key: String) -> URL? {
        dirs.map { $0.appendingPathComponent("\(key).json") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func reload() {
        var keys = Set<String>()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files where f.hasSuffix(".json") {
                let k = String(f.dropLast(5))
                if EditionStore.keyFormatter.date(from: k) != nil { keys.insert(k) }
            }
        }
        let sorted = keys.sorted()
        let previousLatest = dates.last
        dates = sorted
        paused = UserDefaults.standard.bool(forKey: "paused") || FileManager.default.fileExists(atPath: pausedURL.path)
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Follow the newest edition unless the reader has gone back in time.
        if selectedKey == nil || selectedKey == previousLatest || !sorted.contains(selectedKey!) {
            select(sorted.last)
        } else if let k = selectedKey {
            select(k)
        }
        notifyIfNew()
    }

    var isLatest: Bool { selectedKey != nil && selectedKey == latestKey }

    func goToLatest() { select(latestKey) }

    // MARK: Preferences

    func setSection(_ name: String, visible: Bool) {
        if visible { hiddenSections.remove(name) } else { hiddenSections.insert(name) }
        UserDefaults.standard.set(Array(hiddenSections), forKey: "hiddenSections")
        applyPrefs()
    }

    func setPinned(_ name: String?) {
        pinnedSection = name
        UserDefaults.standard.set(name, forKey: "pinnedSection")
        applyPrefs()
    }

    /// Hides switched-off sections; the pinned section's stories follow the lead.
    private func applyPrefs() {
        guard var e = rawEdition else { edition = nil; return }
        var stories = e.stories.filter { !hiddenSections.contains($0.section) }
        if let pin = pinnedSection, stories.count > 1 {
            let lead = stories.removeFirst()
            stories = [lead] + stories.filter { $0.section == pin } + stories.filter { $0.section != pin }
        }
        e.stories = removeRepeatedPictures(stories)
        edition = e
    }

    private var fingerprints: [String: ImageFingerprint?] = [:]

    private func fingerprint(_ rel: String) -> ImageFingerprint? {
        let url = editionsURL.appendingPathComponent(rel)
        if let cached = fingerprints[url.path] { return cached }
        let fp = ImageFingerprint(url: url)
        fingerprints[url.path] = fp
        return fp
    }

    /// Keeps each picture only the first time it (or a look-alike) appears in the edition.
    private func removeRepeatedPictures(_ stories: [Story]) -> [Story] {
        var kept: [(fp: ImageFingerprint, names: Set<String>)] = []
        return stories.map { story in
            guard let rel = story.image, let fp = fingerprint(rel) else { return story }
            let names = EditionBuilder.companies(in: story.title)
            if kept.contains(where: { fp.looksLike($0.fp, sameCompany: !$0.names.isDisjoint(with: names)) }) {
                var s = story
                s.image = nil
                return s
            }
            kept.append((fp, names))
            return story
        }
    }

    // MARK: Keeping old editions

    /// Editions that a "keep for `days`" setting would remove.
    func editionsOlder(thanDays days: Int) -> [String] {
        guard days >= 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())) else { return [] }
        let cutoffKey = EditionStore.keyFormatter.string(from: cutoff)
        return dates.filter { $0 < cutoffKey && $0 != EditionStore.todayKey }
    }

    func setKeepDays(_ days: Int) {
        keepDays = days
        UserDefaults.standard.set(days, forKey: "keepDays")
        pruneOldEditions()
    }

    /// Moves editions past the keep period (and their pictures) to the Trash.
    func pruneOldEditions() {
        let old = editionsOlder(thanDays: keepDays)
        guard !old.isEmpty else { return }
        let fm = FileManager.default
        for key in old {
            for dir in dirs {
                for url in [dir.appendingPathComponent("\(key).json"), dir.appendingPathComponent("images/\(key)")]
                where fm.fileExists(atPath: url.path) {
                    try? fm.trashItem(at: url, resultingItemURL: nil)
                }
            }
        }
        fingerprints.removeAll()
        imageCache.removeAll()
        reload()
    }

    // MARK: Notifications

    func setNotify(_ on: Bool) {
        notifyEnabled = on
        UserDefaults.standard.set(on, forKey: "notify")
        if on { Notifier.requestPermission() }
    }

    /// Posts one notification per day when that day's edition first appears.
    private func notifyIfNew() {
        let today = EditionStore.todayKey
        guard notifyEnabled, Notifier.available, latestKey == today, lastSeenKey != today,
              UserDefaults.standard.string(forKey: "lastNotified") != today,
              let url = file(for: today), let e = try? JSONDecoder().decode(Edition.self, from: Data(contentsOf: url)) else { return }
        UserDefaults.standard.set(today, forKey: "lastNotified")
        Notifier.post(lead: e.stories.first?.title, count: e.stories.count)
    }

    // MARK: Week in Review

    private func loadWeekInReview(endingOn key: String) {
        weekInReview = []
        guard let end = EditionStore.keyFormatter.date(from: key),
              Calendar.current.component(.weekday, from: end) == 1 else { return }
        var days: [(String, Edition)] = []
        for back in 0..<7 {
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: end) else { continue }
            let k = EditionStore.keyFormatter.string(from: d)
            if let url = file(for: k), let e = try? JSONDecoder().decode(Edition.self, from: Data(contentsOf: url)) {
                days.append((k, e))
            }
        }
        guard days.count >= 2 else { return }
        // Each day's lead first, then each day's next-best story, until we have ten.
        var picks: [(day: String, story: Story)] = []
        var seen = Set<String>()
        for rank in 0..<4 {
            for (k, e) in days where picks.count < 10 && e.stories.count > rank {
                let s = e.stories[rank]
                let key = s.title.lowercased()
                if hiddenSections.contains(s.section) || seen.contains(key) || seen.contains(s.url) { continue }
                seen.insert(key); seen.insert(s.url)
                picks.append((k, s))
            }
        }
        weekInReview = picks
    }

    func select(_ key: String?) {
        selectedKey = key
        loadError = nil
        guard let key, let url = file(for: key) else { rawEdition = nil; edition = nil; currentDir = nil; weekInReview = []; return }
        do {
            rawEdition = try JSONDecoder().decode(Edition.self, from: Data(contentsOf: url))
            currentDir = url.deletingLastPathComponent()
        } catch {
            rawEdition = nil
            loadError = "Couldn't read the \(key) edition."
        }
        applyPrefs()
        loadWeekInReview(endingOn: key)
    }

    func markSeen() {
        guard let k = latestKey, selectedKey == k else { return }
        lastSeenKey = k
        UserDefaults.standard.set(k, forKey: "lastSeenEdition")
    }

    func step(_ delta: Int) {
        guard let k = selectedKey, let i = dates.firstIndex(of: k) else { return }
        let j = i + delta
        if dates.indices.contains(j) { select(dates[j]) }
    }

    var canGoBack: Bool { selectedKey.flatMap { dates.firstIndex(of: $0) }.map { $0 > 0 } ?? false }
    var canGoForward: Bool { selectedKey.flatMap { dates.firstIndex(of: $0) }.map { $0 < dates.count - 1 } ?? false }

    // MARK: Daily delivery

    /// Builds today's edition once it's morning, unless paused or already printed.
    /// On a Mac that also gets Claude-written editions, waits until 10 a.m. for those first.
    func buildIfDue() {
        guard !paused, !building, file(for: EditionStore.todayKey) == nil else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let firstEver = dates.isEmpty
        guard firstEver || hour >= (hasClaudeEditions ? 10 : 6) else { return }
        buildToday()
    }

    /// Builds (or rebuilds) today's edition from the news feeds.
    func buildToday() {
        guard !building else { return }
        building = true
        status = "Printing today's edition…"
        let builder = EditionBuilder(outputDir: appDir, historyDirs: dirs, apiKey: KeyStore.load(), log: { msg in
            Task { @MainActor in EditionStore.shared.status = msg }
        })
        let key = EditionStore.todayKey
        Task {
            do {
                _ = try await builder.build(dateKey: key)
                self.status = nil
                self.imageCache.removeAll()
                self.reload()
                self.select(key)
            } catch {
                self.status = error.localizedDescription
            }
            self.building = false
        }
    }

    func setDelivery(on: Bool) {
        UserDefaults.standard.set(!on, forKey: "paused")
        if hasClaudeEditions {
            if on {
                try? FileManager.default.removeItem(at: pausedURL)
            } else {
                try? "Daily editions paused from the Ai.N menu.\n".write(to: pausedURL, atomically: true, encoding: .utf8)
            }
        }
        paused = !on
        if on { buildIfDue() }
    }

    func setAPIKey(_ key: String?) {
        if let key, !key.trimmingCharacters(in: .whitespaces).isEmpty {
            KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            KeyStore.delete()
        }
        hasAPIKey = KeyStore.load() != nil
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Ai.N: launch-at-login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}


// MARK: - Notifications

extension Notification.Name {
    static let ainOpenEdition = Notification.Name("ainOpenEdition")
}

/// Morning "today's edition is here" notifications. Clicking one opens the full edition.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Notifications need a real app bundle (not the bare command-line binary).
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func setUp() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = shared
        requestPermission()
    }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(lead: String?, count: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Today's Ai.N is here"
        c.subtitle = "\(count) stories"
        c.body = lead ?? "Your generative-AI newspaper is ready."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "edition-\(EditionStore.todayKey)", content: c, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .ainOpenEdition, object: nil)
            done()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
