import SwiftUI

@main
struct KeyFinderApp: App {
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            EnhancedBatchView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .tint(themeManager.accentColor)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // File menu commands
            CommandGroup(after: .newItem) {
                Button("Add Audio Files...") {
                    NotificationCenter.default.post(name: .openFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Menu("Export") {
                    Button("Export to CSV...") {
                        NotificationCenter.default.post(name: .exportTracks, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    Divider()

                    Menu("DJ Software Formats") {
                        Button("Export to Rekordbox XML...") {
                            NotificationCenter.default.post(name: .exportRekordbox, object: nil)
                        }

                        Button("Serato Reference CSV...") {
                            NotificationCenter.default.post(name: .exportSerato, object: nil)
                        }

                        Button("Traktor NML (experimental)...") {
                            NotificationCenter.default.post(name: .exportTraktor, object: nil)
                        }

                        Button("Export to Engine DJ (JSON)...") {
                            NotificationCenter.default.post(name: .exportEngineDJ, object: nil)
                        }

                        Button("Export to Virtual DJ (XML)...") {
                            NotificationCenter.default.post(name: .exportVirtualDJ, object: nil)
                        }
                    }

                    Divider()

                    Button("Export to iTunes XML...") {
                        NotificationCenter.default.post(name: .exportiTunes, object: nil)
                    }

                    Divider()

                    Button("Export Metadata Plan...") {
                        NotificationCenter.default.post(name: .exportMetadataPlan, object: nil)
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }
            }

            CommandMenu("View") {
                Picker("Theme", selection: $themeManager.currentTheme) {
                    ForEach(ThemeManager.Theme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                Divider()

                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Show Analysis Log") {
                    NotificationCenter.default.post(name: .showAnalysisLog, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // Help menu
            CommandGroup(after: .help) {
                Button("KeyFinder Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // KeyFinder → Settings… (⌘,): folders AI assistants may read through keyfinder-mcp.
        Settings {
            TabView {
                AIAssistantSettingsView()
                    .tabItem { Label("AI Assistant", systemImage: "sparkles") }
            }
        }
    }
}
