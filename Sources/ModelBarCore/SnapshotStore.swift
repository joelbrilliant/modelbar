import Foundation

public actor SnapshotStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> ModelBarSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(ModelBarSnapshot.self, from: data)
    }

    @discardableResult
    public func saveIfDisplayChanged(_ snapshot: ModelBarSnapshot) throws -> Bool {
        if let existing = load(), snapshot.hasSameDisplayContent(as: existing) {
            return false
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        return true
    }
}
