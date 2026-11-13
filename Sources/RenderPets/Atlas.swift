import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Codex v2 pet atlas: 8 columns and 11 rows of 192 × 208 cells.
enum AtlasLayout {
    static let columns = 8
    static let rows = 11
    static let cellWidth = 192
    static let cellHeight = 208
    static let width = columns * cellWidth
    static let height = rows * cellHeight
    /// Codex reads the neutral, front-facing look frame from this cell.
    static let neutralCell = (row: 0, column: 6)
    /// Rows 9 and 10 hold 16 look directions, clockwise from up in 22.5 degree steps.
    static let lookDirections = (0..<16).map { Float($0) * 22.5 }

    /// The space between the robot and the cell edges, in cell pixels. The outlines use part of it.
    static let floorMargin = 8
    static let edgeMargin = 5

    /// Like the app's character stickers, each robot has an ink line and a paper border,
    /// so that it reads on both light and dark desktops. These are Pollen Pet's theme colors.
    static let ink: (red: UInt8, green: UInt8, blue: UInt8) = (0x10, 0x10, 0x18)
    static let paper: (red: UInt8, green: UInt8, blue: UInt8) = (0xFF, 0xF8, 0xE8)
}

/// Inclusive pixel coordinates, with y increasing downward.
typealias PixelBounds = (minX: Int, minY: Int, maxX: Int, maxY: Int)

/// A premultiplied RGBA bitmap, stored top row first.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(_ image: CGImage) {
        self.init(width: image.width, height: image.height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The smallest rectangle that holds every pixel with alpha above `threshold`.
    func opaqueBounds(threshold: UInt8 = 8) -> PixelBounds? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    /// Resamples the rectangle at (`x`, `y`) of size `cropWidth` × `cropHeight` to `width` × `height`.
    func resampled(x: Int, y: Int, cropWidth: Int, cropHeight: Int, width: Int, height: Int) -> Bitmap {
        // Pad the source so that the crop can extend past the canvas edges.
        var padded = Bitmap(width: cropWidth, height: cropHeight)
        for row in 0..<cropHeight {
            let sourceY = y + row
            guard sourceY >= 0, sourceY < self.height else { continue }
            for column in 0..<cropWidth {
                let sourceX = x + column
                guard sourceX >= 0, sourceX < self.width else { continue }
                let from = (sourceY * self.width + sourceX) * 4
                let to = (row * cropWidth + column) * 4
                padded.pixels.replaceSubrange(to..<to + 4, with: pixels[from..<from + 4])
            }
        }
        var result = Bitmap(width: width, height: height)
        padded.pixels.withUnsafeMutableBytes { source in
            result.pixels.withUnsafeMutableBytes { destination in
                var input = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(cropHeight),
                                          width: vImagePixelCount(cropWidth), rowBytes: cropWidth * 4)
                var output = vImage_Buffer(data: destination.baseAddress, height: vImagePixelCount(height),
                                           width: vImagePixelCount(width), rowBytes: width * 4)
                _ = vImageScale_ARGB8888(&input, &output, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        result.clean()
        return result
    }

    /// Keeps each pixel a valid premultiplied color after resampling, and clears faint haze
    /// so that fully transparent pixels hold no color.
    mutating func clean() {
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3] < 3 ? 0 : pixels[index + 3]
            pixels[index + 3] = alpha
            for channel in 0..<3 { pixels[index + channel] = min(pixels[index + channel], alpha) }
        }
    }

    /// Draws an antialiased outline of `radius` pixels in `color` behind the opaque pixels.
    func outlined(radius: Double, color: (red: UInt8, green: UInt8, blue: UInt8)) -> Bitmap {
        let reach = Int(radius.rounded(.up)) + 1
        var offsets: [(dx: Int, dy: Int, coverage: Double)] = []
        for dy in -reach...reach {
            for dx in -reach...reach {
                let coverage = min(1, max(0, radius + 0.5 - (Double(dx * dx + dy * dy)).squareRoot()))
                if coverage > 0 { offsets.append((dx, dy, coverage)) }
            }
        }
        var result = self
        for y in 0..<height {
            for x in 0..<width {
                var outline = 0.0
                for offset in offsets {
                    let sx = x + offset.dx, sy = y + offset.dy
                    guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                    outline = max(outline, Double(pixels[(sy * width + sx) * 4 + 3]) / 255 * offset.coverage)
                }
                guard outline > 0 else { continue }
                let index = (y * width + x) * 4
                let behind = outline * (1 - Double(pixels[index + 3]) / 255)
                for (channel, value) in [color.red, color.green, color.blue].enumerated() {
                    result.pixels[index + channel] = UInt8((Double(pixels[index + channel]) + Double(value) * behind).rounded())
                }
                result.pixels[index + 3] = UInt8((Double(pixels[index + 3]) + 255 * behind).rounded())
            }
        }
        result.clean()
        return result
    }

    mutating func paste(_ cell: Bitmap, atX left: Int, y top: Int) {
        for row in 0..<cell.height {
            let from = row * cell.width * 4
            let to = ((top + row) * width + left) * 4
            pixels.replaceSubrange(to..<to + cell.width * 4, with: cell.pixels[from..<from + cell.width * 4])
        }
    }

    var image: CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func writePNG(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}

/// One cell of the atlas and the pose it shows.
struct AtlasCell {
    let row: Int
    let column: Int
    let label: String
    let pose: Pose
}

@MainActor enum AtlasBuilder {
    /// Every used cell, in row order.
    static func cells(for choreography: any Choreography) -> [AtlasCell] {
        var cells: [AtlasCell] = []
        for state in PetState.allCases {
            for frame in 0..<state.frameCount {
                cells.append(.init(row: state.rawValue, column: frame, label: "\(state.name)-\(frame)",
                                   pose: choreography.pose(state, frame: frame)))
            }
        }
        cells.append(.init(row: AtlasLayout.neutralCell.row, column: AtlasLayout.neutralCell.column,
                           label: "neutral", pose: choreography.neutral))
        for (index, degrees) in AtlasLayout.lookDirections.enumerated() {
            cells.append(.init(row: PetState.allCases.count + index / AtlasLayout.columns,
                               column: index % AtlasLayout.columns,
                               label: String(format: "look-%05.1f", degrees),
                               pose: choreography.look(degrees)))
        }
        return cells
    }

    /// Renders every cell on a large canvas, then fits all of them into the atlas
    /// with one scale and one floor line, so that nothing pops between frames.
    static func build(stage: PetStage, choreography: any Choreography, renderer: OffscreenRenderer,
                      targetHeight: Double, framesDirectory: URL?, rawDirectory: URL? = nil,
                      mask: (parts: PartMask, directory: URL)? = nil) async throws -> Bitmap {
        let cells = cells(for: choreography)
        var renders: [Bitmap] = []
        var masks: [Bitmap] = []
        var bounds: [PixelBounds] = []
        for cell in cells {
            stage.apply(cell.pose)
            for violation in stage.violations {
                print("  warning: \(cell.label) turns \(violation)")
            }
            // RealityKit carries some state from one frame to the next, so a large
            // change of pose can differ slightly on its first frame. Render each
            // pose twice and keep the second, so that every run gives the same pixels.
            _ = try await renderer.render()
            let bitmap = Bitmap(try await renderer.render())
            guard let box = bitmap.opaqueBounds() else { throw AtlasError.emptyFrame(cell.label) }
            guard box.minX > 0, box.minY > 0, box.maxX < bitmap.width - 1, box.maxY < bitmap.height - 1 else {
                throw AtlasError.clipped(cell.label)
            }
            renders.append(bitmap)
            bounds.append(box)
            if let mask {
                // The same pose, with each part in its flat mask color and no tone mapping.
                mask.parts.show(true)
                renderer.toneMapping = false
                _ = try await renderer.render()
                masks.append(Bitmap(try await renderer.render()))
                mask.parts.show(false)
                renderer.toneMapping = true
            }
        }

        // Center the neutral pose and put its feet on the floor line. Then shrink
        // and shift every frame together until the union of all poses fits the cell.
        guard let neutral = cells.firstIndex(where: { $0.label == "neutral" }) else { throw AtlasError.missingNeutral }
        let rest = bounds[neutral]
        let centerX = Double(rest.minX + rest.maxX + 1) / 2
        let floor = Double(rest.maxY + 1)
        let union = (minX: Double(bounds.map(\.minX).min()!), minY: Double(bounds.map(\.minY).min()!),
                     maxX: Double(bounds.map(\.maxX).max()! + 1), maxY: Double(bounds.map(\.maxY).max()! + 1))
        let margin = Double(AtlasLayout.edgeMargin)
        let cellWidth = Double(AtlasLayout.cellWidth), cellHeight = Double(AtlasLayout.cellHeight)
        let fits = (height: (cellHeight - 2 * margin) / (union.maxY - union.minY),
                    width: (cellWidth / 2 - margin) / max(centerX - union.minX, union.maxX - centerX))
        let scale = min(targetHeight / Double(rest.maxY + 1 - rest.minY), fits.height, fits.width)
        // The floor line in cell pixels, moved up or down only as far as the union needs.
        var floorY = cellHeight - Double(AtlasLayout.floorMargin)
        floorY = min(floorY, cellHeight - margin - (union.maxY - floor) * scale)
        floorY = max(floorY, margin + (floor - union.minY) * scale)
        // Report the fit, so that a choreography change that shrinks the robot is easy to trace.
        print(String(format: "%@: neutral pose %.0f px tall (target %.0f px), floor %.0f px from the top",
                     stage.pet.rawValue as NSString, Double(rest.maxY + 1 - rest.minY) * scale, targetHeight, floorY))
        let edges: [(name: String, touches: (PixelBounds) -> Bool)] = [
            ("top", { Double($0.minY) == union.minY }), ("bottom", { Double($0.maxY + 1) == union.maxY }),
            ("left", { Double($0.minX) == union.minX }), ("right", { Double($0.maxX + 1) == union.maxX }),
        ]
        for (edge, touches) in edges {
            let labels = zip(cells, bounds).filter { touches($0.1) }.map(\.0.label)
            let more = labels.count > 3 ? " and \(labels.count - 3) more" : ""
            print("  \(edge) edge: \(labels.prefix(3).joined(separator: ", "))\(more)")
        }
        let cropWidth = Int((cellWidth / scale).rounded())
        let cropHeight = Int((cellHeight / scale).rounded())
        let cropX = Int((centerX - Double(cropWidth) / 2).rounded())
        let cropY = Int((floor - floorY / scale).rounded())

        if let mask {
            // Cropped and resampled exactly as the raw renders are, so that they line up.
            for (cell, bitmap) in zip(cells, masks) {
                try bitmap.resampled(x: cropX, y: cropY, cropWidth: cropWidth, cropHeight: cropHeight,
                                     width: AtlasLayout.cellWidth * 2, height: AtlasLayout.cellHeight * 2)
                    .writePNG(to: mask.directory.appendingPathComponent("\(cell.label).png"))
            }
            try mask.parts.manifest().write(to: mask.directory.appendingPathComponent("parts.json"))
        }

        var atlas = Bitmap(width: AtlasLayout.width, height: AtlasLayout.height)
        for (cell, render) in zip(cells, renders) {
            if let rawDirectory {
                // Twice the cell size with no outline, for the pixel-art pipeline.
                try render.resampled(x: cropX, y: cropY, cropWidth: cropWidth, cropHeight: cropHeight,
                                     width: AtlasLayout.cellWidth * 2, height: AtlasLayout.cellHeight * 2)
                    .writePNG(to: rawDirectory.appendingPathComponent("\(cell.label).png"))
            }
            let image = render.resampled(x: cropX, y: cropY, cropWidth: cropWidth, cropHeight: cropHeight,
                                         width: AtlasLayout.cellWidth, height: AtlasLayout.cellHeight)
                .outlined(radius: 2, color: AtlasLayout.ink)
                .outlined(radius: 1.5, color: AtlasLayout.paper)
            atlas.paste(image, atX: cell.column * AtlasLayout.cellWidth, y: cell.row * AtlasLayout.cellHeight)
            if let framesDirectory {
                try image.writePNG(to: framesDirectory.appendingPathComponent("\(cell.label).png"))
            }
        }
        return atlas
    }

    enum AtlasError: Error {
        case emptyFrame(String), clipped(String), missingNeutral
    }
}
