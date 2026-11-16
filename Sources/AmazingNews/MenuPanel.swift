import SwiftUI
import AppKit

struct MenuPanel: View {
    @EnvironmentObject var store: EditionStore
    @Environment(\.openWindow) private var openWindow
    @State private var showCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if showCalendar {
                CalendarGrid(onDone: { withAnimation(.snappy) { showCalendar = false } })
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onExitCommand { if showCalendar { withAnimation(.snappy) { showCalendar = false } } }
        .onAppear {
            store.reload()
            store.markSeen()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                AiNBadge(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ai.N")
                        .font(.system(size: 22, weight: .black, design: .serif))
                    Text("Amazing Info News")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canGoBack).help("Previous edition")
                Button { store.step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.canGoForward).help("Next edition")
                Button { withAnimation(.snappy) { showCalendar.toggle() } } label: {
                    Image(systemName: showCalendar ? "calendar.circle.fill" : "calendar")
                }
                .help("Pick a day")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 6) {
                Text(store.selectedKey.map(EditionStore.longDate) ?? "No editions yet")
                if store.isLatest {
                    Text("LATEST")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                } else if store.latestKey != nil {
                    Spacer()
                    Button { store.goToLatest() } label: {
                        Label("Back to today", systemImage: "arrow.uturn.forward")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Jump to the newest edition")
                }
            }
            .font(.system(.caption, design: .serif))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Headlines

    @ViewBuilder
    private var content: some View {
        if let e = store.edition {
            if let brief = e.brief, !brief.isEmpty {
                Text(brief)
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.weekInReview.isEmpty {
                Label("Sunday: The Week in Review is in the full edition", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if e.stories.isEmpty {
                Text("Every story today is in a section you've hidden. Change that in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(e.stories.enumerated()), id: \.element.id) { i, s in
                        HeadlineRow(story: s, isLead: i == 0)
                        if i < e.stories.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
            .frame(maxHeight: 380)

            Button {
                openWindow(id: "edition")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Read the full edition", systemImage: "newspaper")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        } else {
            VStack(spacing: 8) {
                if store.building {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "newspaper").font(.largeTitle).foregroundStyle(.tertiary)
                }
                Text(store.status ?? store.loadError ?? "The first edition hasn't been printed yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !store.building {
                    Button("Print today's edition") { store.buildToday() }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.building, store.edition != nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(store.status ?? "Printing…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let status = store.status, store.edition != nil {
                Text(status).font(.caption).foregroundStyle(.orange)
            }
            Toggle(isOn: Binding(get: { !store.paused }, set: { store.setDelivery(on: $0) })) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Daily delivery")
                    Text(store.paused ? "Paused — no new editions will be written" : "A new edition every morning")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle("Open at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)

            HStack {
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit Ai.N") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

struct HeadlineRow: View {
    @EnvironmentObject var store: EditionStore
    let story: Story
    let isLead: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: story.url) { NSWorkspace.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
            if isLead, let img = store.image(story.image) {
                Color.clear.frame(height: 150).frame(maxWidth: .infinity)
                    .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text((isLead ? "Top story" : story.section).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(isLead ? Color.red : Color.accentColor)
                Text(story.title)
                    .font(.system(size: isLead ? 15 : 13, weight: isLead ? .bold : .semibold, design: .serif))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(story.source)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isLead, let img = store.image(story.image) {
                Color.clear.frame(width: 58, height: 58)
                    .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            }
            }
            .padding(.vertical, 7).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(story.summary)
        .contextMenu {
            Button("Open Story") { openStory(story) }
            Button("Copy Link") { copyLink(story) }
            if let url = URL(string: story.url) {
                ShareLink("Share…", item: url, subject: Text(story.title), message: Text(story.title))
            }
        }
    }
}
