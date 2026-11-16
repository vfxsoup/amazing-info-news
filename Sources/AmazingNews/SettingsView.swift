import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: EditionStore
    @State private var keyField = ""
    @State private var saved = false
    @State private var pendingKeep: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AiNBadge(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amazing Info News").font(.system(size: 20, weight: .black, design: .serif))
                    Text("Your daily generative-AI newspaper").font(.callout).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { !store.paused }, set: { store.setDelivery(on: $0) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daily delivery")
                            Text("Prints a fresh edition each morning from \(Sources.all.count) AI news sources.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: Binding(get: { store.notifyEnabled }, set: { store.setNotify($0) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Notify me when a new edition arrives")
                            Text("A morning notification with the lead headline. Click it to open the paper.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Toggle("Open Ai.N when I log in", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                    Picker("Keep yesterday's news:", selection: Binding(get: { store.keepDays }, set: { days in
                        if store.editionsOlder(thanDays: days).isEmpty { store.setKeepDays(days) } else { pendingKeep = days }
                    })) {
                        ForEach(EditionStore.keepOptions, id: \.days) { Text($0.label).tag($0.days) }
                    }
                    .frame(maxWidth: 320)
                    Text(store.keepDays == -1 ? "Every edition stays in the calendar."
                         : store.keepDays == 0 ? "Only today's edition is kept; older ones go to the Trash."
                         : "Older editions are moved to the Trash automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(store.building ? "Printing…" : "Reprint today's edition") { store.buildToday() }
                            .disabled(store.building)
                        if let status = store.status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Delivery") }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose which sections appear, and which one comes first.")
                        .font(.callout)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                        ForEach(Edition.sectionOrder, id: \.self) { name in
                            Toggle(name, isOn: Binding(get: { !store.hiddenSections.contains(name) },
                                                       set: { store.setSection(name, visible: $0) }))
                        }
                    }
                    Picker("Always put first:", selection: Binding(get: { store.pinnedSection ?? "" },
                                                                   set: { store.setPinned($0.isEmpty ? nil : $0) })) {
                        Text("Nothing — normal order").tag("")
                        ForEach(Edition.sectionOrder, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 320)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Sections") }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional: add your own Anthropic API key and Claude will edit each edition — sharper headlines, “Why it matters” notes, By the numbers, and a daily Pixel & Dez comic strip. Costs a few cents a day on your Anthropic account.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.hasAPIKey {
                        HStack {
                            Label("Claude editing is on", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Remove key") { store.setAPIKey(nil); keyField = "" }
                        }
                    } else {
                        HStack {
                            SecureField("sk-ant-…", text: $keyField)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                store.setAPIKey(keyField)
                                keyField = ""
                            }
                            .disabled(!keyField.hasPrefix("sk-ant-"))
                        }
                        Link("Get an API key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.caption)
                    }
                    Text("The key is stored in your Mac's Keychain and only ever sent to Anthropic.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Claude editor") }

            HStack {
                Button("Show editions in Finder") { NSWorkspace.shared.open(store.appDir) }
                Spacer()
                Text("Comics © their creators · Articles © their publishers")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 480)
        .confirmationDialog("Move older editions to the Trash?",
                            isPresented: Binding(get: { pendingKeep != nil }, set: { if !$0 { pendingKeep = nil } }),
                            titleVisibility: .visible) {
            if let days = pendingKeep {
                let n = store.editionsOlder(thanDays: days).count
                Button("Move \(n) edition\(n == 1 ? "" : "s") to the Trash", role: .destructive) {
                    store.setKeepDays(days)
                    pendingKeep = nil
                }
                Button("Cancel", role: .cancel) { pendingKeep = nil }
            }
        } message: {
            if let days = pendingKeep {
                Text("Keeping \(EditionStore.keepOptions.first { $0.days == days }?.label.lowercased() ?? "") of news means \(store.editionsOlder(thanDays: days).count) older edition(s) will be moved to the Trash now. You can restore them from the Trash.")
            }
        }
    }
}
