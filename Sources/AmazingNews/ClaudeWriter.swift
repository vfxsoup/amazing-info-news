import Foundation
import Security

/// Optional: with the reader's own Anthropic API key, Claude edits the day's paper —
/// picks the stories, rewrites headlines and summaries, adds "why it matters",
/// By the numbers, and a Pixel & Dez strip. Raw HTTP (there's no Swift SDK).
struct ClaudeWriter {
    let apiKey: String
    static let model = "claude-opus-5-5"

    enum WriterError: LocalizedError {
        case http(Int, String), refused, unusable
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return code == 401 ? "the API key was rejected" : "API error \(code): \(msg)"
            case .refused: return "Claude declined the request"
            case .unusable: return "the reply couldn't be used"
            }
        }
    }

    // Shape of Claude's reply (enforced with structured outputs).
    private struct Reply: Decodable {
        struct S: Decodable { let index: Int; let title: String; let summary: String; let why: String; let section: String }
        let brief: String
        let stories: [S]
        let numbers: [Figure]
        let comic: Comic
    }

    func write(candidates: [FeedItem], dateKey: String, recentComics: [String]) async throws -> (Edition, [FeedItem]) {
        let list = candidates.enumerated().map { i, c in
            """
            [\(i)] \(c.source.name) — \(c.title)
            Published: \(c.date.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown")
            Section guess: \(EditionBuilder.section(for: c))
            Text: \(c.summary.prefix(900))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        You are the editor of Amazing Info News (Ai.N), a daily generative-AI newspaper whose readers include filmmakers and VFX artists. Today is \(dateKey).

        Below are today's candidate stories from news feeds. Build today's edition:
        - Pick 10–14 stories (fewer if the pool is thin). Skip duplicates of the same news, minor items, and ads. Put the most important story first; it is the front-page lead.
        - For each, give its [index], a crisp headline under 12 words, a 2–3 sentence summary, and one "why it matters" sentence (with a film/VFX angle only when there honestly is one).
        - Use ONLY facts stated in the candidate text. Never add numbers, names or claims that aren't there. If the text is thin, keep the summary short.
        - section is one of: Models, Image & Video, VFX & Film, Tools, Industry, Research, Policy.
        - brief: a 2–3 sentence editor's note summing up the day.
        - numbers: 3–4 striking figures copied exactly from the candidate text, each with a label under 15 words. Return an empty list if there are none.
        - comic: an original 3-panel strip riffing on one of today's stories. Cast: Pixel (the studio's eager, overconfident AI assistant) and Dez (a dry, seen-it-all VFX compositor); optionally Boss (the VFX supervisor) and Client. Gentle workplace humour VFX people would recognise, punchline in panel 3. Each panel has a short caption (or "") and 1–3 lines under 20 words. Never put real people in the strip.\(recentComics.isEmpty ? "" : " Recent strips (don't repeat these jokes): \(recentComics.joined(separator: "; ")).")

        Candidates:

        \(list)
        """

        let line: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["who", "say"],
                                   "properties": ["who": ["type": "string", "enum": ["Pixel", "Dez", "Boss", "Client"]], "say": ["type": "string"]]]
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["brief", "stories", "numbers", "comic"],
            "properties": [
                "brief": ["type": "string"],
                "stories": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["index", "title", "summary", "why", "section"],
                    "properties": ["index": ["type": "integer"], "title": ["type": "string"], "summary": ["type": "string"], "why": ["type": "string"],
                                   "section": ["type": "string", "enum": Edition.sectionOrder]]]],
                "numbers": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["figure", "label"],
                    "properties": ["figure": ["type": "string"], "label": ["type": "string"]]]],
                "comic": ["type": "object", "additionalProperties": false, "required": ["title", "panels"],
                          "properties": ["title": ["type": "string"], "panels": ["type": "array", "items": [
                            "type": "object", "additionalProperties": false, "required": ["caption", "lines"],
                            "properties": ["caption": ["type": "string"], "lines": ["type": "array", "items": line]]]]]],
            ],
        ]

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": schema]],
            "fallbacks": "default",
            "messages": [["role": "user", "content": prompt]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            throw WriterError.http(status, msg)
        }
        if json["stop_reason"] as? String == "refusal" { throw WriterError.refused }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(text.utf8)) else { throw WriterError.unusable }

        var stories: [Story] = []
        var picked: [FeedItem] = []
        var used = Set<Int>()
        for s in reply.stories where candidates.indices.contains(s.index) && !used.contains(s.index) {
            used.insert(s.index)
            let c = candidates[s.index]
            stories.append(Story(title: s.title, summary: s.summary, why: s.why, section: s.section,
                                 source: c.source.name, url: c.link,
                                 published: c.date.map { EditionStore.keyFormatter.string(from: $0) }))
            picked.append(c)
        }
        guard stories.count >= 4 else { throw WriterError.unusable }

        // Keep only figures that really appear in the source text.
        let corpus = candidates.map { $0.title + " " + $0.summary }.joined(separator: " ")
        let numbers = reply.numbers.filter { n in
            let core = n.figure.trimmingCharacters(in: CharacterSet(charactersIn: "$€£%+~ ")).replacingOccurrences(of: ",", with: "")
            return !core.isEmpty && corpus.replacingOccurrences(of: ",", with: "").contains(core.prefix(3))
        }
        let comic = reply.comic.panels.count >= 2 ? reply.comic : nil

        return (Edition(date: dateKey, brief: reply.brief, stories: stories, numbers: numbers.isEmpty ? nil : numbers, comic: comic), picked)
    }
}

/// Stores the reader's API key in their login Keychain.
enum KeyStore {
    private static let service = "com.millwoodpictures.amazingnews"
    private static let account = "anthropic-api-key"

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ key: String) {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
