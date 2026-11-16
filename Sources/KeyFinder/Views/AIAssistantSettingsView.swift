import AppKit
import KeyFinderEngine
import SwiftUI

/// Settings → AI Assistant: which folders ChatGPT, Claude and other MCP assistants may read
/// through `keyfinder-mcp`, plus one-click connection to each installed assistant.
struct AIAssistantSettingsView: View {
    private let access = AIFolderAccess()

    @State private var folders: [String] = []
    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var connectNote: String?
    @State private var statuses: [AssistantConnector.Assistant: AssistantConnector.Status] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            foldersSection
            Divider()
            setupSection
        }
        .padding(20)
        .frame(width: 560, height: 600)
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
            .frame(minHeight: 110)
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

    // MARK: - Connect

    private var serverURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/keyfinder-mcp")
    }

    private var connector: AssistantConnector {
        AssistantConnector(home: FileManager.default.homeDirectoryForCurrentUser, serverPath: serverURL.path,
                           isAppInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect your AI assistants")
                .font(.headline)
            if FileManager.default.isExecutableFile(atPath: serverURL.path) {
                Text("One click adds KeyFinder to the assistant's settings. Nothing else in them changes, and the original is backed up.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AssistantConnector.Assistant.allCases) { assistant in
                    assistantRow(assistant)
                }
            } else {
                Text("The AI assistant server is not bundled in this build of KeyFinder.")
                    .foregroundColor(.secondary)
            }
            if let note = connectNote {
                Text(note).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshStatuses() }
    }

    private func assistantRow(_ assistant: AssistantConnector.Assistant) -> some View {
        let status = statuses[assistant] ?? .notInstalled
        return HStack {
            Image(systemName: icon(for: status))
                .foregroundColor(status == .connected ? .green : .secondary)
                .frame(width: 18)
            Text(assistant.name)
            Text(label(for: status)).font(.caption).foregroundColor(.secondary)
            Spacer()
            switch status {
            case .notConnected:
                Button("Connect") { run(assistant, connect: true) }
            case .outdated:
                Button("Update") { run(assistant, connect: true) }
            case .connected:
                Button("Disconnect") { run(assistant, connect: false) }
            case .notInstalled, .unreadable:
                EmptyView()
            }
        }
        .help(help(for: status, assistant: assistant))
    }

    private func icon(for status: AssistantConnector.Status) -> String {
        switch status {
        case .connected: return "checkmark.circle.fill"
        case .outdated, .unreadable: return "exclamationmark.triangle"
        case .notConnected: return "circle"
        case .notInstalled: return "minus.circle"
        }
    }

    private func label(for status: AssistantConnector.Status) -> String {
        switch status {
        case .connected: return "Connected"
        case .outdated: return "Connected to another copy of KeyFinder"
        case .unreadable: return "Settings file needs a manual edit"
        case .notConnected: return ""
        case .notInstalled: return "Not installed"
        }
    }

    private func help(for status: AssistantConnector.Status, assistant: AssistantConnector.Assistant) -> String {
        let path = assistant.configURL(home: FileManager.default.homeDirectoryForCurrentUser).path
        switch status {
        case let .outdated(old): return "Currently points at \(old)"
        case .unreadable: return "\(path) has comments or formatting KeyFinder will not rewrite. See docs/AI-ASSISTANT.md."
        default: return path
        }
    }

    private func run(_ assistant: AssistantConnector.Assistant, connect: Bool) {
        do {
            if connect {
                try connector.connect(assistant)
                connectNote = "KeyFinder is connected to \(assistant.name). \(assistant.finishStep)"
            } else {
                try connector.disconnect(assistant)
                connectNote = "KeyFinder was removed from \(assistant.name)."
            }
        } catch {
            connectNote = error.localizedDescription
        }
        refreshStatuses()
    }

    private func refreshStatuses() {
        let current = connector
        statuses = Dictionary(uniqueKeysWithValues: AssistantConnector.Assistant.allCases.map { ($0, current.status($0)) })
    }
}
