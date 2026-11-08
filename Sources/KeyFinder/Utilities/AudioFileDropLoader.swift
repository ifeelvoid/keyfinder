import Foundation
import UniformTypeIdentifiers

/// Waits for every provider, preserving drop order even when callbacks finish out of order.
enum AudioFileDropLoader {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                            guard error == nil else {
                                continuation.resume(returning: nil)
                                return
                            }
                            let url: URL?
                            if let value = item as? URL {
                                url = value
                            } else if let data = item as? Data {
                                url = URL(dataRepresentation: data, relativeTo: nil)
                            } else {
                                url = nil
                            }
                            continuation.resume(returning: url.flatMap {
                                $0.isFileURL && (isDirectory($0) || isSupported($0)) ? $0 : nil
                            })
                        }
                    }
                    return (index, url)
                }
            }
            var results: [(Int, URL)] = []
            for await (index, url) in group {
                if let url = url { results.append((index, url)) }
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    static let supportedExtensions: Set<String> = ["mp3", "wav", "m4a", "flac", "aiff", "aif"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Replaces folders with the supported audio files inside them (recursively, sorted by path,
    /// skipping hidden files and packages); plain files pass through in order.
    static func expandingFolders(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard isDirectory(url) else { return isSupported(url) ? [url] : [] }
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            let files = (enumerator?.allObjects as? [URL] ?? []).filter(isSupported)
            return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }
}
