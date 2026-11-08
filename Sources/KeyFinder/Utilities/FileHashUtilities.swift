import Foundation
import CryptoKit

/// Fingerprints a source file for persisted analysis invalidation.
struct FileHasher {
    /// Fingerprint using the source path, size, modification time and analysis version
    static func quickHash(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64,
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        // Combine file size and modification date for quick check
        let quickString = "2.1-\(url.standardizedFileURL.path)-\(fileSize)-\(modDate.timeIntervalSince1970)"
        let data = Data(quickString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

}
