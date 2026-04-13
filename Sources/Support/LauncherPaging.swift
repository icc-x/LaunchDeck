import Foundation

enum LauncherPaging {
    static func chunked<Item>(_ items: [Item], pageSize: Int) -> [ArraySlice<Item>] {
        guard !items.isEmpty else { return [] }
        guard pageSize > 0 else { return [items[items.startIndex..<items.endIndex]] }

        var chunks: [ArraySlice<Item>] = []
        chunks.reserveCapacity((items.count + pageSize - 1) / pageSize)

        var index = 0
        while index < items.count {
            let end = min(index + pageSize, items.count)
            chunks.append(items[index..<end])
            index = end
        }

        return chunks
    }
}
