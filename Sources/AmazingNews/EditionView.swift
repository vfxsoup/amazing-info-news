import SwiftUI
import AppKit

/// Reader display settings for the printed page (set by EditionView before drawing).
enum PaperStyle {
    static var scale: CGFloat = 1
    static var night = false
    /// True while rendering a PDF: hides on-screen-only controls.
    static var exporting = false
}

func sz(_ size: CGFloat) -> CGFloat { size * PaperStyle.scale }

let dayPaper = Color(red: 0.97, green: 0.95, blue: 0.90)
let dayInk = Color(red: 0.08, green: 0.08, blue: 0.08)
let dayAccent = Color(red: 0.70, green: 0.10, blue: 0.10)
var paper: Color { PaperStyle.night ? Color(red: 0.10, green: 0.10, blue: 0.11) : dayPaper }
var ink: Color { PaperStyle.night ? Color(red: 0.90, green: 0.88, blue: 0.84) : dayInk }
var accent: Color { PaperStyle.night ? Color(red: 0.96, green: 0.42, blue: 0.36) : dayAccent }

/// The full broadsheet window for the selected day.
struct EditionView: View {
    @EnvironmentObject var store: EditionStore
    @State private var showCalendar = false
    @AppStorage("textScale") private var textScale = 1.0
    @AppStorage("nightEdition") private var night = false

    var body: some View {
        let _ = { PaperStyle.scale = textScale; PaperStyle.night = night }()
        ScrollView {
            EditionPage()
                .id("\(textScale)-\(night)-\(store.selectedKey ?? "")-\(store.pinnedSection ?? "")-\(store.hiddenSections.count)")
        }
        .background(paper)
        .environment(\.colorScheme, night ? .dark : .light)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack).help("Previous edition")
                Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                    .help("Pick a day")
                    .popover(isPresented: $showCalendar) {
                        CalendarGrid(onDone: { showCalendar = false }).environmentObject(store).padding(12).frame(width: 260)
                    }
                Button { store.step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.canGoForward).help("Next edition")
                if !store.isLatest && store.latestKey != nil {
                    Button { store.goToLatest() } label: { Label("Today", systemImage: "arrow.uturn.forward") }
                        .help("Back to the newest edition")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { textScale = max(0.8, (textScale * 10 - 1).rounded() / 10) } label: { Image(systemName: "textformat.size.smaller") }
                    .help("Smaller text").disabled(textScale <= 0.8)
                Button { textScale = min(1.6, (textScale * 10 + 1).rounded() / 10) } label: { Image(systemName: "textformat.size.larger") }
                    .help("Larger text").disabled(textScale >= 1.6)
                Button { night.toggle() } label: { Image(systemName: night ? "sun.max" : "moon") }
                    .help(night ? "Day edition" : "Night edition")
                Button { exportPDF() } label: { Image(systemName: "arrow.down.doc") }
                    .help("Export this edition as a PDF").disabled(store.edition == nil)
            }
        }
        .onExitCommand { showCalendar = false }
        .navigationTitle(store.selectedKey.map(EditionStore.longDate) ?? "Amazing Info News")
    }

    private func exportPDF() {
        guard let key = store.selectedKey else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Ai.N \(key).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PDFExport.write(store: store, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Renders an edition to a paginated, letter-proportioned PDF in day colours.
@MainActor
enum PDFExport {
    static func write(store: EditionStore, to url: URL) {
        let saved = (PaperStyle.scale, PaperStyle.night)
        PaperStyle.scale = 1; PaperStyle.night = false; PaperStyle.exporting = true
        defer { (PaperStyle.scale, PaperStyle.night) = saved; PaperStyle.exporting = false }

        let width: CGFloat = 1120
        let pageHeight: CGFloat = (width * 11 / 8.5).rounded()
        let renderer = ImageRenderer(content: EditionPage().environmentObject(store).frame(width: width))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: width, height: pageHeight)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            var top: CGFloat = 0
            while top < size.height {
                ctx.beginPDFPage(nil)
                ctx.setFillColor(NSColor(dayPaper).cgColor)
                ctx.fill(box)
                ctx.saveGState()
                // Content is drawn bottom-up; shift so this page shows rows [top, top + pageHeight).
                ctx.translateBy(x: 0, y: pageHeight - (size.height - top))
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
                top += pageHeight
            }
            ctx.closePDF()
        }
    }
}

/// The printed page itself: a broadsheet front page, then the inside pages.
struct EditionPage: View {
    @EnvironmentObject var store: EditionStore

    var body: some View {
        VStack(spacing: 0) {
            masthead
            if let e = store.edition {
                page(e)
            } else {
                Text(store.loadError ?? "No edition for this day yet.")
                    .font(.system(size: sz(20), design: .serif))
                    .padding(60)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(maxWidth: 1120)
        .frame(maxWidth: .infinity)
        .background(paper)
        .foregroundStyle(ink)
    }

    private var editionNumber: Int {
        (store.selectedKey.flatMap { store.dates.firstIndex(of: $0) } ?? 0) + 1
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 18) {
                Ear(top: "TODAY’S EDITION", big: "\(store.edition?.stories.count ?? 0) stories",
                    bottom: store.weekInReview.isEmpty ? "Generative AI, daily" : "+ The Week in Review")
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("Amazing Info News")
                        .font(.system(size: min(sz(64), 76), weight: .black, design: .serif))
                        .tracking(-1.5)
                        .lineLimit(1)
                        .fixedSize()
                    Text("— Ai.N —")
                        .font(.system(size: sz(12), weight: .heavy, design: .serif)).tracking(4)
                        .foregroundStyle(accent)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Ear(top: "ALL THE AI NEWS", big: "Fit to print", bottom: "Every morning")
            }
            .padding(.bottom, 4)
            Rectangle().fill(ink).frame(height: 3)
            HStack {
                Text("VOL. I · NO. \(editionNumber)")
                Spacer()
                Text(store.selectedKey.map(EditionStore.longDate)?.uppercased() ?? "")
                Spacer()
                Text("GENERATIVE AI DAILY")
            }
            .font(.system(size: sz(11), weight: .bold, design: .serif))
            .tracking(1.4)
            .padding(.vertical, 2)
            Rectangle().fill(ink).frame(height: 1)
        }
        .padding(.bottom, 18)
    }

    // MARK: Page

    @ViewBuilder
    private func page(_ e: Edition) -> some View {
        let stories = e.stories
        if stories.isEmpty {
            Text("Every story in this edition is in a section you've hidden. You can change that in Settings.")
                .font(.system(size: sz(16), design: .serif).italic())
                .padding(40)
        }
        if let brief = e.brief, !brief.isEmpty {
            Text(brief)
                .font(.system(size: sz(16), design: .serif).italic())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.bottom, 16)
        }
        // Above the fold: lead across two columns, a side column on the right.
        if let lead = stories.first {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    LeadStory(story: lead)
                    let indexed = Array(stories.dropFirst(1 + sideCount(e)))
                    if !indexed.isEmpty { IndexBox(stories: Array(indexed.prefix(8))) }
                }
                .padding(.trailing, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 16) {
                    if let numbers = e.numbers, !numbers.isEmpty { NumbersBox(numbers: numbers) }
                    ForEach(Array(stories.dropFirst().prefix(sideCount(e)).enumerated()), id: \.element.id) { i, s in
                        if i > 0 || e.numbers?.isEmpty == false { Rectangle().fill(ink.opacity(0.35)).frame(height: 1) }
                        StoryCard(story: s, style: .side)
                    }
                }
                .padding(.leading, 22)
                .frame(width: 340, alignment: .topLeading)
                .overlay(alignment: .leading) { ColumnRule() }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        let rowStart = 1 + sideCount(e)
        if stories.count > rowStart {
            Rectangle().fill(ink).frame(height: 2).padding(.top, 22).padding(.bottom, 18)
            ColumnRow(stories: Array(stories.dropFirst(rowStart).prefix(3))) { StoryCard(story: $0, style: .row) }
        }
        if !store.weekInReview.isEmpty {
            Rectangle().fill(ink).frame(height: 2).padding(.top, 22).padding(.bottom, 18)
            WeekInReviewBox(items: store.weekInReview)
        }
        let inside = Array(stories.dropFirst(rowStart + 3))
        if !inside.isEmpty {
            InsideHeader()
            Masonry(stories: orderedInside(inside, pinned: store.pinnedSection), columns: 3)
        }
        if e.comic != nil || !(e.funnies ?? []).isEmpty {
            Rectangle().fill(ink).frame(height: 2).padding(.top, 26).padding(.bottom, 14)
            FunniesPage(comic: e.comic, funnies: e.funnies ?? [])
        }
        Rectangle().fill(ink).frame(height: 1).padding(.top, 22)
        Text(e.comic != nil || e.stories.contains { $0.why != nil }
              ? "Ai.N is edited by Claude from the day's reporting. Click any headline to read the original. Comics © their creators."
              : "Ai.N gathers the day's AI news from publishers' feeds. Click any headline to read the original. Comics © their creators.")
            .font(.system(size: sz(11), design: .serif).italic())
            .foregroundStyle(ink.opacity(0.5))
            .padding(.top, 8)
    }

    /// Stories in the right-hand front-page column: one under By the numbers, otherwise two.
    private func sideCount(_ e: Edition) -> Int { (e.numbers?.isEmpty == false) ? 1 : 2 }

    /// Inside pages follow the section order (the reader's pinned section first).
    private func orderedInside(_ stories: [Story], pinned: String?) -> [Story] {
        var order = Edition.sectionOrder
        if let pinned, let i = order.firstIndex(of: pinned) { order.insert(order.remove(at: i), at: 0) }
        return stories.sorted { (order.firstIndex(of: $0.section) ?? 99) < (order.firstIndex(of: $1.section) ?? 99) }
    }
}

/// Front-page index of what's further in, like a newspaper's "Inside" box.
struct IndexBox: View {
    let stories: [Story]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ALSO IN TODAY’S EDITION")
                .font(.system(size: sz(11), weight: .heavy, design: .serif)).tracking(2)
                .padding(.bottom, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .topLeading),
                                GridItem(.flexible(), spacing: 22, alignment: .topLeading)],
                      alignment: .leading, spacing: 10) {
                ForEach(stories) { s in
                    Button { openStory(s) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.section.uppercased())
                                .font(.system(size: sz(8.5), weight: .heavy)).tracking(1.2)
                                .foregroundStyle(accent)
                            Text(s.title)
                                .font(.system(size: sz(14), weight: .semibold, design: .serif))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(ink.opacity(0.05))
        .overlay(Rectangle().stroke(ink.opacity(0.5), lineWidth: 1))
    }
}

/// The small boxes either side of the nameplate.
struct Ear: View {
    let top: String, big: String, bottom: String
    var body: some View {
        VStack(spacing: 2) {
            Text(top).font(.system(size: sz(8), weight: .heavy)).tracking(1.2)
            Text(big).font(.system(size: sz(15), weight: .bold, design: .serif).italic())
            Text(bottom).font(.system(size: sz(9), design: .serif)).foregroundStyle(ink.opacity(0.7))
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .frame(width: 130)
        .overlay(Rectangle().stroke(ink, lineWidth: 1))
    }
}

struct ColumnRule: View {
    var body: some View { Rectangle().fill(ink.opacity(0.3)).frame(width: 1) }
}

struct InsideHeader: View {
    var body: some View {
        VStack(spacing: 4) {
            Rectangle().fill(ink).frame(height: 2)
            HStack {
                Text("INSIDE TODAY’S EDITION")
                    .font(.system(size: sz(13), weight: .heavy, design: .serif)).tracking(2.5)
                    .foregroundStyle(accent)
                Spacer()
            }
            Rectangle().fill(ink.opacity(0.4)).frame(height: 1)
        }
        .padding(.top, 26).padding(.bottom, 14)
    }
}

/// Equal columns separated by thin vertical rules.
struct ColumnRow<Content: View>: View {
    let stories: [Story]
    @ViewBuilder let content: (Story) -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stories.enumerated()), id: \.element.id) { i, s in
                if i > 0 { ColumnRule().padding(.horizontal, 18) }
                content(s).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            ForEach(0..<max(0, 3 - stories.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).padding(.leading, 37)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Newspaper-style flow: each story drops into the shortest column.
struct Masonry: View {
    let stories: [Story]
    let columns: Int

    private var split: [[Story]] {
        var cols = Array(repeating: [Story](), count: columns)
        var heights = Array(repeating: 0.0, count: columns)
        for s in stories {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[i].append(s)
            heights[i] += (s.image != nil ? 170 : 0) + Double(s.title.count) * 0.9 + Double(s.summary.count) * 0.45
                + Double((s.why ?? "").count) * 0.4 + 70
        }
        return cols
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(split.enumerated()), id: \.offset) { c, col in
                if c > 0 { ColumnRule().padding(.horizontal, 18) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(col.enumerated()), id: \.element.id) { j, s in
                        if j > 0 { Rectangle().fill(ink.opacity(0.25)).frame(height: 1).padding(.vertical, 14) }
                        StoryCard(story: s, style: .inside)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pieces

/// The Ai.N "black block" logo: "Ai" over a red ".N" on a black rounded square.
struct AiNBadge: View {
    var size: CGFloat
    static let red = Color(red: 0.88, green: 0.27, blue: 0.23)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(dayInk)
            VStack(alignment: .leading, spacing: -size * 0.17) {
                Text("Ai").foregroundStyle(dayPaper)
                Text(".N").foregroundStyle(Self.red)
            }
            .font(.system(size: size * 0.5, weight: .black, design: .serif))
            .fixedSize()
            .offset(x: -size * 0.02, y: -size * 0.01)
        }
        .frame(width: size, height: size)
    }
}

struct SectionHeader: View {
    let name: String
    var body: some View {
        HStack(spacing: 10) {
            Text(name.uppercased())
                .font(.system(size: sz(13), weight: .heavy, design: .serif))
                .tracking(2)
                .foregroundStyle(accent)
            Rectangle().fill(ink.opacity(0.3)).frame(height: 1)
        }
    }
}

/// A photo cropped to fill a fixed height. Draws nothing when there's no image.
struct StoryPicture: View {
    @EnvironmentObject var store: EditionStore
    let path: String?
    let height: CGFloat
    var credit: String? = nil

    var body: some View {
        if let img = store.image(path) {
            VStack(alignment: .trailing, spacing: 3) {
                Color.clear
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                    .clipped()
                    .overlay(Rectangle().stroke(ink.opacity(0.15), lineWidth: 1))
                if let credit {
                    Text("Image: \(credit)")
                        .font(.system(size: sz(8.5), design: .serif).italic())
                        .foregroundStyle(ink.opacity(0.5))
                }
            }
        }
    }
}

func openStory(_ s: Story) {
    if let url = URL(string: s.url) { NSWorkspace.shared.open(url) }
}

func openURL(_ string: String) {
    if let url = URL(string: string) { NSWorkspace.shared.open(url) }
}

struct LeadStory: View {
    let story: Story
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP STORY · \(story.section.uppercased())")
                .font(.system(size: sz(11), weight: .heavy)).tracking(1.5)
                .foregroundStyle(accent)
            Button { openStory(story) } label: {
                Text(story.title)
                    .font(.system(size: sz(44), weight: .black, design: .serif))
                    .tracking(-0.5)
                    .lineSpacing(-2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
            if let why = story.why, !why.isEmpty {
                Text(why)
                    .font(.system(size: sz(19), design: .serif).italic())
                    .foregroundStyle(ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            StoryPicture(path: story.image, height: sz(380), credit: story.source)
                .padding(.vertical, 4)
            Text(story.summary)
                .font(.system(size: sz(17), design: .serif))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            JargonRow(story: story)
            Byline(story: story)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NumbersBox: View {
    let numbers: [Figure]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BY THE NUMBERS")
                .font(.system(size: sz(12), weight: .heavy, design: .serif)).tracking(2)
                .foregroundStyle(paper)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(ink)
            ForEach(numbers, id: \.self) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.figure)
                        .font(.system(size: sz(30), weight: .black, design: .serif))
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(n.label)
                        .font(.system(size: sz(13), design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                if n != numbers.last { Rectangle().fill(ink.opacity(0.2)).frame(height: 1).padding(.horizontal, 10) }
            }
        }
        .padding(.bottom, 12)
        .overlay(Rectangle().stroke(ink, lineWidth: 2))
    }
}

struct StoryCard: View {
    enum Style { case side, row, inside }
    let story: Story
    var style: Style = .inside

    private var headlineSize: CGFloat {
        let hasPic = story.image != nil
        switch style {
        case .side: return hasPic ? 21 : 25
        case .row: return hasPic ? 20 : 24
        case .inside: return hasPic ? 18 : (story.title.count < 60 ? 22 : 19)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(story.section.uppercased())
                .font(.system(size: sz(9), weight: .heavy)).tracking(1.3)
                .foregroundStyle(accent)
            if style != .inside {
                StoryPicture(path: story.image, height: sz(style == .side ? 150 : 140), credit: story.source)
                    .padding(.bottom, 2)
            }
            Button { openStory(story) } label: {
                Text(story.title)
                    .font(.system(size: sz(headlineSize), weight: .bold, design: .serif))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
            if style == .inside {
                StoryPicture(path: story.image, height: sz(150), credit: story.source)
                    .padding(.vertical, 2)
            }
            Text(story.summary)
                .font(.system(size: sz(13.5), design: .serif))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let why = story.why, !why.isEmpty {
                (Text("Why it matters: ").bold() + Text(why))
                    .font(.system(size: sz(12.5), design: .serif))
                    .foregroundStyle(ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            JargonRow(story: story)
            Byline(story: story)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Byline: View {
    let story: Story
    var body: some View {
        HStack(spacing: 14) {
            Button { openStory(story) } label: {
                HStack(spacing: 4) {
                    Text(story.source.uppercased()).font(.system(size: sz(10), weight: .bold)).tracking(1)
                    Image(systemName: "arrow.up.right").font(.system(size: sz(9), weight: .bold))
                }
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            if !PaperStyle.exporting, let url = URL(string: story.url) {
                ShareLink(item: url, subject: Text(story.title), message: Text(story.title)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: sz(10), weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.55))
                .help("Share this story")
                Button { copyLink(story) } label: {
                    Image(systemName: "link").font(.system(size: sz(10), weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.55))
                .help("Copy link")
            }
        }
    }
}

func copyLink(_ s: Story) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s.url, forType: .string)
}

/// Small "?" chips explaining jargon found in a story. Hover for a tooltip, click for a popover.
struct JargonRow: View {
    let story: Story
    var body: some View {
        let terms = Glossary.terms(in: story)
        if !terms.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(terms, id: \.term) { JargonChip(term: $0.term, meaning: $0.meaning).fixedSize() }
            }
        }
    }
}

private struct JargonChip: View {
    let term: String
    let meaning: String
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "questionmark.circle").font(.system(size: sz(9), weight: .bold))
                Text(term).font(.system(size: sz(10), weight: .semibold))
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().stroke(ink.opacity(0.3), lineWidth: 1))
            .foregroundStyle(ink.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help(meaning)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(term).font(.system(size: 14, weight: .bold, design: .serif))
                Text(meaning).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 280)
        }
    }
}

/// Sundays: the week's biggest stories in one box.
struct WeekInReviewBox: View {
    let items: [(day: String, story: Story)]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE WEEK IN REVIEW")
                    .font(.system(size: sz(13), weight: .heavy, design: .serif)).tracking(2)
                Spacer()
                Text("TOP \(items.count) STORIES OF THE WEEK")
                    .font(.system(size: sz(10), weight: .bold)).tracking(1.2)
            }
            .foregroundStyle(paper)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(ink)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: sz(26), weight: .black, design: .serif))
                        .foregroundStyle(accent)
                        .frame(width: sz(36), alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Button { openStory(item.story) } label: {
                            Text(item.story.title)
                                .font(.system(size: sz(16), weight: .bold, design: .serif))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        Text("\(Self.weekday(item.day)) · \(item.story.section) · \(item.story.source)".uppercased())
                            .font(.system(size: sz(9), weight: .bold)).tracking(1)
                            .foregroundStyle(ink.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                if i < items.count - 1 { Rectangle().fill(ink.opacity(0.15)).frame(height: 1).padding(.horizontal, 12) }
            }
        }
        .overlay(Rectangle().stroke(ink, lineWidth: 2))
    }

    static func weekday(_ key: String) -> String {
        guard let d = EditionStore.keyFormatter.date(from: key) else { return key }
        return d.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - The Funnies

struct FunniesPage: View {
    @EnvironmentObject var store: EditionStore
    let comic: Comic?
    let funnies: [Funny]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(name: "The Funnies")
            if let comic { ComicStrip(comic: comic) }
            ForEach(funnies) { f in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(f.title).font(.system(size: sz(17), weight: .bold, design: .serif))
                        Spacer()
                        Button { openURL(f.url) } label: {
                            HStack(spacing: 4) {
                                Text("\(f.name.uppercased()) · \(f.credit.uppercased())")
                                    .font(.system(size: sz(10), weight: .bold)).tracking(1)
                                Image(systemName: "arrow.up.right").font(.system(size: sz(9), weight: .bold))
                            }
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    if let img = store.image(f.image) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: min(img.size.width * 1.4, 900))
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(ink.opacity(0.2), lineWidth: 1))
                            .onTapGesture { openURL(f.url) }
                    }
                    if let cap = f.caption, !cap.isEmpty {
                        Text(cap)
                            .font(.system(size: sz(13), design: .serif).italic())
                            .foregroundStyle(ink.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Renders the editor's original strip as newspaper panels.
struct ComicStrip: View {
    let comic: Comic

    static let cast: [String: String] = ["Pixel": "🤖", "Dez": "🧑‍🎨", "Boss": "🧔", "Client": "🕴️"]
    static let tints: [Color] = [
        Color(red: 1.00, green: 0.93, blue: 0.75),
        Color(red: 0.82, green: 0.92, blue: 0.97),
        Color(red: 0.98, green: 0.84, blue: 0.82),
        Color(red: 0.86, green: 0.95, blue: 0.84),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("PIXEL & DEZ").font(.system(size: sz(11), weight: .heavy)).tracking(1.5).foregroundStyle(accent)
                Text(comic.title).font(.system(size: sz(17), weight: .bold, design: .serif))
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(comic.panels.enumerated()), id: \.offset) { i, p in
                    panel(p, tint: Self.tints[i % Self.tints.count])
                }
            }
            Text("An Ai.N original. Pixel is the studio's eager AI; Dez is the compositor who has seen it all.")
                .font(.system(size: sz(11), design: .serif).italic())
                .foregroundStyle(ink.opacity(0.6))
        }
    }

    private func panel(_ p: Comic.Panel, tint: Color) -> some View {
        let speakers = p.lines.map(\.who).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 8) {
            if let cap = p.caption, !cap.isEmpty {
                Text(cap.uppercased())
                    .font(.system(size: sz(10), weight: .bold, design: .rounded))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.86, blue: 0.35))
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
            }
            ForEach(Array(p.lines.enumerated()), id: \.offset) { _, line in
                Bubble(line: line, leading: speakers.first == line.who)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 300, alignment: .top)
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom) {
                ForEach(speakers, id: \.self) { who in
                    VStack(spacing: 0) {
                        Text(Self.cast[who] ?? "🙂").font(.system(size: sz(54)))
                        Text(who.uppercased()).font(.system(size: sz(9), weight: .heavy)).tracking(1)
                    }
                    if who != speakers.last { Spacer() }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        }
        .foregroundStyle(Color.black)
        .background(tint)
        .overlay(Rectangle().stroke(ink, lineWidth: 2.5))
    }
}

private struct Bubble: View {
    let line: Comic.Line
    let leading: Bool
    var body: some View {
        Text(line.say)
            .font(.system(size: sz(13), weight: .medium, design: .rounded))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 1.5))
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}

/// Lays children out left to right, wrapping onto new lines like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
