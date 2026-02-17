import SwiftUI

struct ClipboardView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var clipboardStore: ClipboardStore = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var copiedEntryID: UUID?
    @State private var showClearConfirmation = false

    private var themeBackground: Color {
        let theme = EditorTheme.current(for: settings.appearanceOverride)
        return Color(theme.background)
    }

    private var themeForeground: Color {
        let theme = EditorTheme.current(for: settings.appearanceOverride)
        return Color(theme.foreground)
    }

    private var filteredEntries: [ClipboardEntry] {
        clipboardStore.search(query: searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty
                            ? String(localized: "clipboard.empty.title", defaultValue: "No clipboard history")
                            : String(localized: "clipboard.no_results.title", defaultValue: "No results"),
                        systemImage: searchText.isEmpty ? "clipboard" : "magnifyingglass",
                        description: searchText.isEmpty
                            ? Text(String(localized: "clipboard.empty.description", defaultValue: "Copy text on your Mac or tap Paste to capture from this device."))
                            : Text(verbatim: String(localized: "clipboard.no_results.description", defaultValue: "No entries match the search query."))
                    )
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            ClipboardCardView(
                                entry: entry,
                                themeBackground: themeBackground,
                                themeForeground: themeForeground
                            )
                            .onTapGesture {
                                clipboardStore.copyToClipboard(entry)
                                withAnimation {
                                    copiedEntryID = entry.id
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    withAnimation {
                                        if copiedEntryID == entry.id {
                                            copiedEntryID = nil
                                        }
                                    }
                                }
                            }
                            .overlay {
                                if copiedEntryID == entry.id {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Label(String(localized: "clipboard.copied", defaultValue: "Copied"), systemImage: "checkmark.circle.fill")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(.green)
                                        }
                                        .transition(.opacity)
                                }
                            }
                            .contextMenu {
                                Button {
                                    clipboardStore.copyToClipboard(entry)
                                } label: {
                                    Label(String(localized: "clipboard.context.copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    clipboardStore.deleteEntry(id: entry.id)
                                } label: {
                                    Label(String(localized: "clipboard.context.delete", defaultValue: "Delete"), systemImage: "trash")
                                }
                            } preview: {
                                ScrollView {
                                    Text(entry.text)
                                        .font(.system(size: 13, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                }
                                .frame(idealWidth: 320, maxHeight: 400)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    clipboardStore.deleteEntry(id: entry.id)
                                } label: {
                                    Label(String(localized: "clipboard.context.delete", defaultValue: "Delete"), systemImage: "trash")
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "clipboard.title", defaultValue: "Clipboard"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            clipboardStore.captureFromPasteboard()
                        } label: {
                            Label(String(localized: "clipboard.paste_from", defaultValue: "Paste from clipboard"), systemImage: "clipboard")
                        }
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label(String(localized: "clipboard.clear_all", defaultValue: "Clear all"), systemImage: "trash")
                        }
                        .disabled(clipboardStore.entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .alert(String(localized: "clipboard.clear_alert.title", defaultValue: "Clear clipboard history?"), isPresented: $showClearConfirmation) {
                Button(String(localized: "clipboard.clear_all", defaultValue: "Clear all"), role: .destructive) {
                    clipboardStore.clearAll()
                }
                Button(String(localized: "alert.save_changes.cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                if SettingsStore.shared.icloudSync {
                    Text(String(localized: "clipboard.clear_alert.message_sync", defaultValue: "This will remove all clipboard entries on all your synced devices."))
                } else {
                    Text(String(localized: "clipboard.clear_alert.message_local", defaultValue: "This will remove all clipboard entries on this device."))
                }
            }
        }
    }
}
