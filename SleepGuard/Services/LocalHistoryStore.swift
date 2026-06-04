import Foundation

struct LocalHistoryStore {
    var fileURL: URL
    private let maxRecords = 200

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("SleepGuard/history.json")
        }
    }

    func load() -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryRecord].self, from: data)) ?? []
    }

    func append(_ record: HistoryRecord) {
        var records = load()
        records.append(record)
        records = Array(records.suffix(maxRecords))
        save(records)
    }

    func save(_ records: [HistoryRecord]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save history: \(error)")
        }
    }
}
