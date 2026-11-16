import Foundation

/// Assembles a day's edition from the news feeds, entirely on this Mac.
struct EditionBuilder {
    /// Where the new edition (and its images/) is written.
    let outputDir: URL
    /// Every folder holding earlier editions, so stories and comics aren't repeated.
    let historyDirs: [URL]
    var apiKey: String?
    var log: (String) -> Void = { print($0) }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        c.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept-Language": "en-US,en;q=0.9"]
        return URLSession(configuration: c)
    }()

    // MARK: Build

    func build(dateKey: String) async throws -> Edition {
        let history = previousEditions()
        let seenURLs = Set(history.prefix(5).flatMap { $0.stories.map(\.url) })
        let seenTitles = history.prefix(5).flatMap { $0.stories.map { Self.words($0.title) } }

        log("Checking \(Sources.all.count) news sources…")
        var items = await fetchAllFeeds()
        log("Found \(items.count) recent AI stories")

        items = items.filter { item in !seenURLs.contains(item.link) && !seenTitles.contains(where: { Self.similar(Self.words(item.title), $0) }) }
        let candidates = Self.rank(Self.dedupe(items))
        guard !candidates.isEmpty else { throw BuildError.noNews }

        var edition: Edition
        var picked: [FeedItem]
        if let key = apiKey, !key.isEmpty {
            do {
                log("Asking Claude to write the edition…")
                (edition, picked) = try await ClaudeWriter(apiKey: key)
                    .write(candidates: Array(candidates.prefix(30)), dateKey: dateKey,
                           recentComics: history.prefix(3).compactMap { $0.comic?.title })
            } catch {
                log("Claude couldn't write it (\(error.localizedDescription)); using the plain edition")
                (edition, picked) = Self.plainEdition(candidates, dateKey: dateKey)
            }
        } else {
            (edition, picked) = Self.plainEdition(candidates, dateKey: dateKey)
        }

        // Pictures
        let imgDir = outputDir.appendingPathComponent("images/\(dateKey)")
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        log("Collecting photos…")
        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, item) in picked.enumerated() {
                group.addTask {
                    let path = await self.picture(for: item, stem: imgDir.appendingPathComponent(String(format: "%02d", i + 1)))
                    return (i, path)
                }
            }
            for await (i, path) in group where i < edition.stories.count {
                edition.stories[i].image = path
            }
        }
        // Prefer a lead story with a picture.
        if edition.stories.first?.image == nil, let j = edition.stories.prefix(4).firstIndex(where: { $0.image != nil }) {
            edition.stories.swapAt(0, j)
        }

        log("Fetching the funnies…")
        edition.funnies = await funnies(imgDir: imgDir, seen: Set(history.flatMap { ($0.funnies ?? []).map(\.url) }))

        let data = try JSONEncoder.pretty.encode(edition)
        try data.write(to: outputDir.appendingPathComponent("\(dateKey).json"), options: .atomic)
        log("Printed \(edition.stories.count) stories")
        return edition
    }

    enum BuildError: LocalizedError {
        case noNews
        var errorDescription: String? { "Couldn't find any AI news — check your internet connection." }
    }

    // MARK: Feeds

    private func fetchAllFeeds() async -> [FeedItem] {
        let now = Date()
        return await withTaskGroup(of: [FeedItem].self) { group in
            for src in Sources.all {
                group.addTask {
                    guard let url = URL(string: src.url),
                          let (data, resp) = try? await Self.session.data(from: url),
                          (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return FeedParser.parse(data, source: src).filter { item in
                        guard let d = item.date, now.timeIntervalSince(d) < src.window * 3600, d < now.addingTimeInterval(3600) else { return false }
                        return !src.aiOnly || Self.mentionsAI(item.title + " " + item.summary)
                    }
                }
            }
            var all: [FeedItem] = []
            for await batch in group { all += batch.prefix(25) }
            return all
        }
    }

    private func previousEditions() -> [Edition] {
        var out: [(String, Edition)] = []
        for dir in historyDirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files where f.hasSuffix(".json") {
                if let d = try? Data(contentsOf: dir.appendingPathComponent(f)),
                   let e = try? JSONDecoder().decode(Edition.self, from: d) { out.append((e.date, e)) }
            }
        }
        return out.sorted { $0.0 > $1.0 }.map(\.1)
    }

    // MARK: Ranking & sections

    static func mentionsAI(_ s: String) -> Bool {
        s.range(of: #"\b(AI|A\.I\.|artificial intelligence|generative|machine learning|LLM|chatbot|OpenAI|ChatGPT|Anthropic|Claude|Gemini|Copilot|Midjourney|Runway|Sora|neural|deepfake|agentic|agents?)\b"#,
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let sectionRules: [(String, String)] = [
        ("VFX & Film", #"\b(vfx|visual effects|hollywood|film|films|movie|movies|studio|studios|animation|animated|cinema|director|actors?|sag-aftra|netflix|disney|pixar|post-production|compositing|nuke|houdini|unreal engine|weta|ilm|dneg|framestore|filmmak\w*|screen|tv series|television)\b"#),
        ("Image & Video", #"\b(image generat\w*|video generat\w*|text-to-video|text-to-image|midjourney|runway|sora|veo|kling|luma|pika|firefly|stable diffusion|flux|imagen|3d model\w*|music generat\w*|elevenlabs|suno|udio|voice clon\w*|video model)\b"#),
        ("Policy", #"\b(law|laws|lawsuit|sues?|sued|court|copyright|regulat\w*|congress|senate|ai act|policy|ban|bans|government|legal|ftc|judge|settlement|lawmakers|bill)\b"#),
        ("Research", #"\b(research|researchers|paper|study|benchmark|arxiv|scientists|breakthrough|alphafold|alphagenome)\b"#),
        ("Industry", #"\b(funding|raises|raised|valuation|ipo|acquir\w*|acquisition|deal|billion|revenue|stock|shares|layoffs|ceo|hires|partnership|chips?|data cent\w*|investors?)\b"#),
        ("Models", #"\b(model|models|gpt[-\w.]*|claude|gemini|llama|grok|mistral|deepseek|qwen|open-weight|llm|reasoning)\b"#),
        ("Tools", #"\b(app|feature|agent|agents|coding|copilot|plugin|api|developers?|rolls out|chrome|assistant|browser|extension|update)\b"#),
    ]

    static func section(for item: FeedItem) -> String {
        if item.source.defaultSection == "VFX & Film" { return "VFX & Film" }
        let t = item.title
        for (name, pattern) in sectionRules where t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return name
        }
        let s = item.summary
        for (name, pattern) in sectionRules where s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return name
        }
        return item.source.defaultSection
    }

    static func score(_ item: FeedItem) -> Double {
        let hours = item.date.map { -$0.timeIntervalSinceNow / 3600 } ?? 48
        var s = max(0, 1 - hours / 48) * 3 + item.source.weight
        let t = item.title
        if t.range(of: #"\b(OpenAI|Anthropic|Claude|Gemini|GPT|Google|Meta|Llama|Nvidia|Midjourney|Runway|Sora|Veo|Kling|Adobe|Firefly|Apple|Microsoft|xAI|Grok|Mistral|DeepSeek)\b"#, options: .regularExpression) != nil { s += 1.5 }
        if t.range(of: #"\b(launch\w*|release\w*|unveil\w*|announc\w*|introduc\w*|debut\w*|new)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { s += 1 }
        if section(for: item) == "VFX & Film" { s += 1.5 }
        if item.imageURL != nil { s += 0.4 }
        if item.summary.count < 60 { s -= 0.8 }
        // It's an AI paper: favour headlines that are about AI, sink ones that aren't.
        if mentionsAI(t) { s += 1 } else if !mentionsAI(item.summary) { s -= 2.5 } else { s -= 0.8 }
        return s
    }

    static func rank(_ items: [FeedItem]) -> [FeedItem] {
        items.sorted { score($0) > score($1) }
    }

    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
    }

    static func similar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count)) >= 0.6
    }

    private static let commonCaps: Set<String> = ["The", "A", "An", "How", "Why", "What", "New", "AI", "It", "Its", "This", "That", "Is", "In", "On", "For", "With", "And", "Now", "Can", "Will", "Here", "Your", "You", "Our", "Is", "Inside", "After", "Before"]

    /// Distinctive capitalised words in a headline (product and company names).
    static func names(_ s: String) -> Set<String> {
        Set(s.components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count > 2 && $0.first!.isUppercase && !commonCaps.contains($0) })
    }

    /// Same story from two outlets: overlapping words, or two shared names (e.g. "ChatGPT" + "Wallet").
    static func sameStory(_ a: FeedItem, _ b: FeedItem) -> Bool {
        let wa = words(a.title), wb = words(b.title)
        return a.link == b.link || similar(wa, wb) || wa.intersection(wb).count >= 3
            || names(a.title).intersection(names(b.title)).count >= 2
    }

    /// Company a headline is about, grouping product names under their maker
    /// (so "Claude" and "Anthropic" stories count as the same company).
    static func companies(in title: String) -> Set<String> {
        let map: [String: String] = ["Anthropic": "Anthropic", "Claude": "Anthropic", "OpenAI": "OpenAI", "ChatGPT": "OpenAI",
                                     "Sora": "OpenAI", "GPT": "OpenAI", "Google": "Google", "Gemini": "Google", "DeepMind": "Google",
                                     "Veo": "Google", "Nvidia": "Nvidia", "NVIDIA": "Nvidia", "Meta": "Meta", "Llama": "Meta",
                                     "Adobe": "Adobe", "Firefly": "Adobe", "Microsoft": "Microsoft", "Copilot": "Microsoft",
                                     "Apple": "Apple", "xAI": "xAI", "Grok": "xAI", "Runway": "Runway", "Midjourney": "Midjourney"]
        return Set(names(title).compactMap { map[$0] })
    }

    private static func dedupe(_ items: [FeedItem]) -> [FeedItem] {
        var kept: [FeedItem] = []
        for item in rank(items) {
            if kept.contains(where: { sameStory($0, item) }) { continue }
            kept.append(item)
        }
        return kept
    }

    /// Without Claude: top stories with section and source caps for variety.
    static func plainEdition(_ ranked: [FeedItem], dateKey: String) -> (Edition, [FeedItem]) {
        var picked: [FeedItem] = []
        var perSection: [String: Int] = [:]
        var perSource: [String: Int] = [:]
        for item in ranked where picked.count < 14 {
            let sec = section(for: item)
            if perSection[sec, default: 0] >= 4 || perSource[item.source.name, default: 0] >= 3 { continue }
            perSection[sec, default: 0] += 1
            perSource[item.source.name, default: 0] += 1
            picked.append(item)
        }
        let stories = picked.map { item in
            Story(title: item.title, summary: TextUtil.summary(item.summary), why: nil, section: section(for: item),
                  source: item.source.name, url: item.link, published: item.date.map { EditionStore.keyFormatter.string(from: $0) })
        }
        var brief: String?
        if stories.count >= 3 {
            brief = "Leading today: \(stories[0].title). Also in this edition: \(stories[1].title); and \(stories[2].title)."
        }
        return (Edition(date: dateKey, brief: brief, stories: stories), picked)
    }

    // MARK: Pictures

    /// Saves the story's picture next to the edition and returns its relative path.
    private func picture(for item: FeedItem, stem: URL) async -> String? {
        var src = item.imageURL
        if src == nil { src = await Self.ogImage(for: item.link) }
        guard let src = src, let url = URL(string: src, relativeTo: URL(string: item.link))?.absoluteURL,
              let saved = await Self.download(url, to: stem) else { return nil }
        return relativePath(saved)
    }

    private func relativePath(_ file: URL) -> String {
        String(file.path.dropFirst(outputDir.path.count + 1))
    }

    static func ogImage(for page: String) async -> String? {
        guard let url = URL(string: page), let (data, _) = try? await session.data(from: url), data.count < 4_000_000 else { return nil }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        let re = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: .caseInsensitive)
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            guard tag.range(of: #"(property|name)\s*=\s*["'](og:image|og:image:url|og:image:secure_url|twitter:image|twitter:image:src)["']"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let c = tag.range(of: #"content\s*=\s*["'][^"']+"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let value = tag[c].split(separator: "\"", maxSplits: 1).last.map(String.init)
                ?? tag[c].split(separator: "'", maxSplits: 1).last.map(String.init)
            if let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                return URL(string: TextUtil.decodeEntities(v), relativeTo: url)?.absoluteString
            }
        }
        return nil
    }

    static func download(_ url: URL, to stem: URL) async -> URL? {
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 2_000, data.count < 12_000_000 else { return nil }
        let ext: String
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { ext = "jpg" }
        else if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { ext = "png" }
        else if data.starts(with: Array("GIF8".utf8)) { ext = "gif" }
        else if data.starts(with: Array("RIFF".utf8)) { ext = "webp" }
        else { return nil }
        let file = stem.appendingPathExtension(ext)
        do { try data.write(to: file, options: .atomic) } catch { return nil }
        return file
    }

    // MARK: Funnies

    private func funnies(imgDir: URL, seen: Set<String>) async -> [Funny] {
        var out: [Funny] = []
        for (tag, get) in [("xkcd", Self.latestXKCD), ("joyoftech", Self.latestJoyOfTech)] as [(String, () async -> (Funny, URL)?)] {
            guard var (f, src) = await get(), !seen.contains(f.url),
                  let file = await Self.download(src, to: imgDir.appendingPathComponent("comic-\(tag)")) else { continue }
            f.image = relativePath(file)
            out.append(f)
        }
        return out
    }

    static func latestXKCD() async -> (Funny, URL)? {
        struct X: Decodable { let num: Int; let safe_title: String; let alt: String; let img: String }
        guard let (d, _) = try? await session.data(from: URL(string: "https://xkcd.com/info.0.json")!),
              let x = try? JSONDecoder().decode(X.self, from: d), let img = URL(string: x.img) else { return nil }
        return (Funny(name: "xkcd", credit: "Randall Munroe", title: x.safe_title, caption: x.alt,
                      url: "https://xkcd.com/\(x.num)/"), img)
    }

    static func latestJoyOfTech() async -> (Funny, URL)? {
        guard let (feed, _) = try? await session.data(from: URL(string: "https://www.joyoftech.com/joyoftech/jotblog/index.xml")!) else { return nil }
        let xml = String(decoding: feed, as: UTF8.self)
        guard let r = xml.range(of: #"rdf:li rdf:resource="[^"]+""#, options: .regularExpression) else { return nil }
        let link = String(xml[r].dropFirst(#"rdf:li rdf:resource=""#.count).dropLast())
        guard let pageURL = URL(string: link), let (page, _) = try? await session.data(from: pageURL),
              let numR = link.range(of: #"\d+b?(?=\.html)"#, options: .regularExpression) else { return nil }
        let num = String(link[numR])
        let html = String(decoding: page, as: UTF8.self)
        guard let ir = html.range(of: #"src="[^"]*joyimages/\#(num)\.(png|gif|jpg)""#, options: .regularExpression) else { return nil }
        let src = String(html[ir].dropFirst(5).dropLast())
        var title = "The Joy of Tech"
        if let tr = html.range(of: #"(?<=<title>The Joy of Tech comic\.\.\.).*?(?=</title>)"#, options: .regularExpression) {
            title = TextUtil.decodeEntities(String(html[tr])).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        }
        guard let img = URL(string: src, relativeTo: pageURL)?.absoluteURL else { return nil }
        return (Funny(name: "The Joy of Tech", credit: "Nitrozac & Snaggy", title: title, caption: nil, url: link), img)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
