import Domain
import Foundation

/// "export as plain files": writes every thought as a readable folder (Markdown, recording, transcript)
/// into a folder you choose, e.g. for Obsidian. Only on request.
public enum PlainExport {
    @discardableResult
    public static func export(_ files: EntryFileStore, to target: URL, calendar: Calendar = .current) throws -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        var count = 0
        for folder in try files.allEntryFolders() {
            let entry = try files.loadEntry(folder: folder).entry
            let destination = target.appendingPathComponent("\(formatter.string(from: entry.createdAt)) \(entry.id)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in ["entry.md", "recording.m4a", "transcript.json"] where files.storage.exists("\(folder)/\(name)")
            {
                try files.storage.read("\(folder)/\(name)").write(to: destination.appendingPathComponent(name))
            }
            count += 1
        }
        return count
    }
}
