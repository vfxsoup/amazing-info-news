import Foundation

/// A news source the app checks each morning.
struct FeedSource {
    let name: String
    let url: String
    /// Section used when the headline doesn't clearly belong elsewhere.
    let defaultSection: String
    /// General-interest feeds only contribute items that mention AI.
    let aiOnly: Bool
    /// How many hours back to look (trade/VFX outlets post less often).
    var window: Double = 36
    var weight: Double = 1.0
}

enum Sources {
    static let all: [FeedSource] = [
        FeedSource(name: "The Verge", url: "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", defaultSection: "Industry", aiOnly: false, weight: 1.3),
        FeedSource(name: "TechCrunch", url: "https://techcrunch.com/category/artificial-intelligence/feed/", defaultSection: "Industry", aiOnly: false, weight: 1.2),
        FeedSource(name: "Ars Technica", url: "https://arstechnica.com/ai/feed/", defaultSection: "Industry", aiOnly: false, weight: 1.2),
        FeedSource(name: "Wired", url: "https://www.wired.com/feed/tag/ai/latest/rss", defaultSection: "Industry", aiOnly: false, weight: 1.1),
        FeedSource(name: "MIT Technology Review", url: "https://www.technologyreview.com/topic/artificial-intelligence/feed", defaultSection: "Research", aiOnly: false, window: 48, weight: 1.2),
        FeedSource(name: "The Decoder", url: "https://the-decoder.com/feed/", defaultSection: "Models", aiOnly: false, weight: 1.0),
        FeedSource(name: "OpenAI", url: "https://openai.com/news/rss.xml", defaultSection: "Models", aiOnly: false, window: 48, weight: 1.4),
        FeedSource(name: "Google", url: "https://blog.google/technology/ai/rss/", defaultSection: "Models", aiOnly: false, window: 48, weight: 1.3),
        FeedSource(name: "Google DeepMind", url: "https://deepmind.google/blog/rss.xml", defaultSection: "Research", aiOnly: false, window: 72, weight: 1.3),
        FeedSource(name: "Hugging Face", url: "https://huggingface.co/blog/feed.xml", defaultSection: "Tools", aiOnly: false, window: 48, weight: 0.8),
        FeedSource(name: "NVIDIA", url: "https://blogs.nvidia.com/feed/", defaultSection: "Industry", aiOnly: true, window: 48, weight: 0.9),
        FeedSource(name: "Engadget", url: "https://www.engadget.com/rss.xml", defaultSection: "Tools", aiOnly: true, weight: 0.9),
        FeedSource(name: "404 Media", url: "https://www.404media.co/rss", defaultSection: "Policy", aiOnly: true, weight: 1.0),
        FeedSource(name: "Simon Willison", url: "https://simonwillison.net/atom/everything/", defaultSection: "Tools", aiOnly: true, weight: 0.8),
        FeedSource(name: "befores & afters", url: "https://beforesandafters.com/feed/", defaultSection: "VFX & Film", aiOnly: false, window: 120, weight: 1.2),
        FeedSource(name: "fxguide", url: "https://www.fxguide.com/feed/", defaultSection: "VFX & Film", aiOnly: false, window: 168, weight: 1.2),
        FeedSource(name: "Cartoon Brew", url: "https://www.cartoonbrew.com/feed", defaultSection: "VFX & Film", aiOnly: true, window: 120, weight: 1.1),
        FeedSource(name: "IndieWire", url: "https://www.indiewire.com/t/artificial-intelligence/feed/", defaultSection: "VFX & Film", aiOnly: false, window: 96, weight: 1.0),
        FeedSource(name: "The Hollywood Reporter", url: "https://www.hollywoodreporter.com/t/artificial-intelligence/feed/", defaultSection: "VFX & Film", aiOnly: false, window: 120, weight: 1.0),
    ]
}

struct FeedItem {
    var source: FeedSource
    var title = ""
    var link = ""
    var date: Date?
    var summary = ""
    var imageURL: String?
}

// MARK: - Parsing (RSS 2.0, RSS 1.0 and Atom)

final class FeedParser: NSObject, XMLParserDelegate {
    private let source: FeedSource
    private var items: [FeedItem] = []
    private var current: FeedItem?
    private var text = ""
    private var contentHTML = ""

    init(source: FeedSource) { self.source = source }

    static func parse(_ data: Data, source: FeedSource) -> [FeedItem] {
        let p = FeedParser(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.shouldProcessNamespaces = false
        parser.parse()
        return p.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        text = ""
        if name == "item" || name == "entry" {
            current = FeedItem(source: source)
            contentHTML = ""
            return
        }
        guard current != nil else { return }
        switch name {
        case "link":
            // Atom: <link rel="alternate" href="..."/>
            if let href = a["href"], (a["rel"] ?? "alternate") == "alternate", current!.link.isEmpty {
                current!.link = href
            }
        case "media:content", "media:thumbnail":
            if current!.imageURL == nil, let u = a["url"], (a["medium"] ?? "image") == "image" || name == "media:thumbnail" {
                current!.imageURL = u
            }
        case "enclosure":
            if current!.imageURL == nil, let u = a["url"], (a["type"] ?? "").hasPrefix("image") {
                current!.imageURL = u
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item", "entry":
            if current!.imageURL == nil { current!.imageURL = TextUtil.firstImage(in: contentHTML) }
            if !current!.title.isEmpty && !current!.link.isEmpty { items.append(current!) }
            current = nil
        case "title":
            current!.title = TextUtil.clean(value)
        case "link":
            if current!.link.isEmpty, !value.isEmpty { current!.link = value }
        case "pubDate", "published", "dc:date", "updated":
            if current!.date == nil { current!.date = TextUtil.date(value) }
        case "description", "summary":
            contentHTML += value
            if current!.summary.isEmpty { current!.summary = TextUtil.clean(value) }
        case "content:encoded", "content":
            contentHTML += value
            if current!.summary.isEmpty { current!.summary = TextUtil.clean(value) }
        default: break
        }
        text = ""
    }
}

// MARK: - Text helpers

enum TextUtil {
    static func clean(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Strip feed boilerplate like "The post X appeared first on Y."
        if let r = s.range(of: "The post .* appeared first on .*", options: .regularExpression) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
                     "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities: &#8217; and &#x2019;
        let re = try! NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            let num = ns.substring(with: m.range(at: 2))
            if let code = UInt32(num, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result += String(Character(scalar))
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func firstImage(in html: String) -> String? {
        guard let r = html.range(of: "<img[^>]+src=[\"']([^\"']+)[\"']", options: .regularExpression) else { return nil }
        let tag = String(html[r])
        guard let s = tag.range(of: "src=[\"']([^\"']+)", options: .regularExpression) else { return nil }
        return decodeEntities(String(tag[s].dropFirst(5)))
    }

    /// First two sentences, capped at ~320 characters.
    static func summary(_ s: String) -> String {
        var out = ""
        var count = 0
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, stop in
            guard let sub else { return }
            out += sub
            count += 1
            if count >= 2 || out.count > 220 { stop = true }
        }
        out = out.trimmingCharacters(in: .whitespaces)
        if out.isEmpty { out = s }
        if out.count > 320 { out = String(out.prefix(317)).trimmingCharacters(in: .whitespaces) + "…" }
        return out
    }

    private static let rfc822: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z",
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func date(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        for f in rfc822 { if let d = f.date(from: s) { return d } }
        return nil
    }
}
