import AppKit
import Foundation

struct IconPadTrimmer {
    private let fileManager = FileManager.default

    func run(sourceIconsetPath: String, destinationIconsetPath: String) throws {
        let sourceURL = URL(fileURLWithPath: sourceIconsetPath, isDirectory: true)
        let destinationURL = URL(fileURLWithPath: destinationIconsetPath, isDirectory: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let names = try fileManager.contentsOfDirectory(atPath: sourceURL.path)
            .sorted()

        for name in names {
            let sourceFileURL = sourceURL.appendingPathComponent(name)
            let destinationFileURL = destinationURL.appendingPathComponent(name)

            guard sourceFileURL.pathExtension.lowercased() == "png" else {
                try? fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
                continue
            }

            try trimSinglePNG(from: sourceFileURL, to: destinationFileURL, displayName: name)
        }
    }

    private func trimSinglePNG(from sourceURL: URL, to destinationURL: URL, displayName: String) throws {
        let data = try Data(contentsOf: sourceURL)
        guard let bitmap = NSBitmapImageRep(data: data) else {
            try data.write(to: destinationURL)
            return
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > 0.001 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            try data.write(to: destinationURL)
            return
        }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard let cgImage = bitmap.cgImage?.cropping(to: cropRect) else {
            try data.write(to: destinationURL)
            return
        }

        guard let outBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            try data.write(to: destinationURL)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outBitmap)

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        let croppedImage = NSImage(cgImage: cgImage, size: NSSize(width: cropRect.width, height: cropRect.height))
        croppedImage.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: NSRect(origin: .zero, size: croppedImage.size),
            operation: .sourceOver,
            fraction: 1
        )

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = outBitmap.representation(using: .png, properties: [:]) else {
            try data.write(to: destinationURL)
            return
        }

        try pngData.write(to: destinationURL)

        let leftPad = minX
        let rightPad = (width - 1) - maxX
        let bottomPad = minY
        let topPad = (height - 1) - maxY
        print("[trim] \(displayName): left=\(leftPad), right=\(rightPad), bottom=\(bottomPad), top=\(topPad)")
    }
}

func main() throws {
    guard CommandLine.arguments.count == 3 else {
        fputs("usage: trim_icon_padding.swift <source.iconset> <destination.iconset>\n", stderr)
        exit(2)
    }

    let trimmer = IconPadTrimmer()
    try trimmer.run(
        sourceIconsetPath: CommandLine.arguments[1],
        destinationIconsetPath: CommandLine.arguments[2]
    )
}

do {
    try main()
} catch {
    fputs("trim failed: \(error)\n", stderr)
    exit(1)
}
