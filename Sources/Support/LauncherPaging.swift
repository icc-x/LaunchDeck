import Foundation

enum LauncherPaging {
    static func chunked<Item>(_ items: [Item], pageSize: Int) -> [[Item]] {
        guard !items.isEmpty else { return [] }
        guard pageSize > 0 else { return [items] }

        var chunks: [[Item]] = []
        chunks.reserveCapacity((items.count + pageSize - 1) / pageSize)

        var index = 0
        while index < items.count {
            let end = min(index + pageSize, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }

        return chunks
    }
}
