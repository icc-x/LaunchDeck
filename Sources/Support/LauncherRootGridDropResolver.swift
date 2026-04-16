import Foundation

enum LauncherRootGridDropResolver {
    static func canGroup(
        allEntries: [LauncherEntry],
        draggingEntryID: String,
        targetEntry: LauncherEntry
    ) -> Bool {
        LauncherLayoutEditor(entries: allEntries).canGroup(
            draggedID: draggingEntryID,
            targetID: targetEntry.id
        )
    }

    static func globalInsertionIndex(
        allEntries: [LauncherEntry],
        visibleEntries: ArraySlice<LauncherEntry>,
        draggingEntryID: String,
        localInsertionIndex: Int
    ) -> Int {
        let remainingCount = max(0, allEntries.count - 1)
        let draggedIndex = allEntries.firstIndex(where: { $0.id == draggingEntryID }) ?? allEntries.endIndex
        let shiftedPageStart = visibleEntries.startIndex - (draggedIndex < visibleEntries.startIndex ? 1 : 0)
        let absoluteIndex = shiftedPageStart + localInsertionIndex
        return max(0, min(absoluteIndex, remainingCount))
    }
}
