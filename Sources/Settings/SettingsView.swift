import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Mode", selection: $settings.appearanceOverride) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }

                    Picker("Syntax theme", selection: $settings.syntaxTheme) {
                        ForEach(SyntaxThemeRegistry.themes, id: \.id) { theme in
                            Text(theme.displayName).tag(theme.id)
                        }
                    }

                    HStack {
                        Text("Font size")
                        Spacer()
                        Stepper("\(Int(settings.editorFontSize))", value: $settings.editorFontSize, in: 8...32, step: 1)
                    }
                }

                Section("Indentation") {
                    Toggle("Indent using spaces", isOn: $settings.indentUsingSpaces)

                    Stepper("Tab width: \(settings.tabWidth)", value: $settings.tabWidth, in: 1...8)
                }

                Section("Lists") {
                    Toggle("Bullet lists", isOn: $settings.bulletListsEnabled)
                    Toggle("Numbered lists", isOn: $settings.numberedListsEnabled)
                    Toggle("Checklists", isOn: $settings.checklistsEnabled)
                }

                Section("Editor") {
                    Toggle("Clickable links", isOn: $settings.clickableLinks)
                }

                Section("Sync") {
                    Toggle("iCloud sync", isOn: Binding(
                        get: { settings.icloudSync },
                        set: { settings.setICloudSync($0) }
                    ))
                }

                Section {
                    Link(destination: URL(string: "https://itsypad.app")!) {
                        HStack {
                            Text("itsypad.app")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Itsypad \(appVersion) (\(appBuild))")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
