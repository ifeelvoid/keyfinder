import AppKit
import KeyFinderEngine
import SwiftUI

/// Settings → AI Assistant: which folders ChatGPT, Claude and other MCP assistants may read
/// through `keyfinder-mcp`, plus copy-ready setup for each assistant.
struct AIAssistantSettingsView: View {
    private let access = AIFolderAccess()

    @State private var folders: [String] = []
    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var copiedNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            foldersSection
            Divider()
            setupSection
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .onAppear { folders = access.effectiveFolders() }
        .alert("Could not save folders", isPresented: Binding(get: { errorMessage != nil },
                                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folders AI assistants can read")
                .font(.headline)
            Text("KeyFinder analyzes audio on this Mac. Assistants only see results (file names, keys, tempos), never the audio, and only from these folders. Changes apply to the next request.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(folders, id: \.self, selection: $selection) { folder in
                HStack {
                    Image(systemName: FileManager.default.fileExists(atPath: folder) ? "folder" : "exclamationmark.triangle")
                    Text(folder).lineLimit(1).truncationMode(.middle)
                }
                .help(FileManager.default.fileExists(atPath: folder) ? folder : "\(folder) is not available right now")
            }
            .frame(minHeight: 140)
            .overlay {
                if folders.isEmpty {
                    Text("No folders: assistants cannot read any audio.").foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Add Folder…", action: addFolders)
                Button("Remove", action: removeSelected).disabled(selection == nil)
                Spacer()
                Button("Reset to Music Folder") { save(AIFolderAccess.defaultFolders) }
            }
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.title = "Allow AI assistants to read these folders"
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        save(folders + panel.urls.map(\.path))
    }

    private func removeSelected() {
        guard let selected = selection else { return }
        selection = nil
        save(folders.filter { $0 != selected })
    }

    private func save(_ updated: [String]) {
        do {
            try access.save(updated)
            folders = access.effectiveFolders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setup

    private var serverURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/keyfinder-mcp")
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect an assistant")
                .font(.headline)
            if FileManager.default.isExecutableFile(atPath: serverURL.path) {
                Text(serverURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack {
                    Button("Copy ChatGPT Setup") { copy(chatGPTSetup, note: "ChatGPT setup copied: paste into ~/.codex/config.toml, then restart ChatGPT.") }
                    Button("Copy Claude Setup") { copy(claudeSetup, note: "Claude setup copied: paste into claude_desktop_config.json, then restart Claude.") }
                }
            } else {
                Text("The AI assistant server is not bundled in this build of KeyFinder.")
                    .foregroundColor(.secondary)
            }
            if let note = copiedNote {
                Text(note).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var chatGPTSetup: String {
        """
        [mcp_servers.keyfinder]
        command = "\(serverURL.path)"
        """
    }

    private var claudeSetup: String {
        """
        {
          "mcpServers": {
            "keyfinder": { "command": "\(serverURL.path)" }
          }
        }
        """
    }

    private func copy(_ text: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedNote = note
    }
}
