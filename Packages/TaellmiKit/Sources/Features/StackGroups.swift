import Domain
import Foundation

/// What stack shows: one of your folders, the thoughts naming a concept, or the thoughts in no folder.
nonisolated public enum StackGroup: Hashable, Sendable {
    case loose
    case folder(String)
    case concept(String)
}

/// A folder of yours with how many thoughts it holds.
nonisolated public struct FolderSummary: Sendable, Equatable, Identifiable {
    public var folder: ThoughtFolder
    public var count: Int
    public var id: String { folder.id }

    public init(folder: ThoughtFolder, count: Int) {
        self.folder = folder
        self.count = count
    }
}

/// The index beside stack: your folders, every concept, and how many thoughts are in no folder.
nonisolated public struct StackIndex: Sendable, Equatable {
    public var folders: [FolderSummary]
    public var concepts: [ConceptSummary]
    public var looseCount: Int

    public init(folders: [FolderSummary], concepts: [ConceptSummary], looseCount: Int) {
        self.folders = folders
        self.concepts = concepts
        self.looseCount = looseCount
    }

    public static let empty = StackIndex(folders: [], concepts: [], looseCount: 0)
}

extension ExploreViewModel {
    /// Shows a group in stack, with its newest thought open.
    public func chooseGroup(_ group: StackGroup) async {
        stackGroup = group
        await select(nil)
        await refresh()
        await openNewestIfNothingOpen()
    }

    /// Makes a folder and opens it.
    public func createFolder(named name: String) async {
        do {
            let folder = try await library.createFolder(named: name)
            await chooseGroup(.folder(folder.id))
        } catch {
            errorMessage = "couldn't make that folder. try another name."
        }
    }

    public func renameFolder(_ id: String, to name: String) async {
        do {
            try await library.renameFolder(id, to: name)
            await refresh()
        } catch {
            errorMessage = "couldn't rename that folder. try another name."
        }
    }

    /// Its thoughts become loose; nothing is deleted.
    public func deleteFolder(_ id: String) async {
        do {
            try await library.deleteFolder(id)
            if stackGroup == .folder(id) {
                await chooseGroup(.loose)
            } else {
                await refresh()
            }
        } catch {
            errorMessage = "couldn't remove that folder. try again."
        }
    }

    /// Files a thought in a folder, or makes it loose with `nil`.
    public func file(_ entryID: String, in folderID: String?) async {
        do {
            try await library.file(entryID, in: folderID)
            await refresh()
        } catch {
            errorMessage = "couldn't move the thought. try again."
        }
    }
}
