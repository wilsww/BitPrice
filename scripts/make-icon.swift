import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconGenerationError: Error {
    case couldNotCreateBitmap
    case couldNotCreateImage
    case couldNotCreateDestination
    case couldNotWritePNG
    case couldNotReadPixels
    case couldNotCreateGradient
}

private let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

/// Returns a sampled superellipse approximation of the continuous-curvature
/// squircle used by modern system icons. Apple does not publish the exact
/// system curve, so this is deliberately an approximation rather than a claim
/// to reproduce Apple's official shape.
private func approximateSquirclePath(in rect: CGRect) -> CGPath {
    let exponent: CGFloat = 5
    let sampleCount = 128
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radiusX = rect.width / 2
    let radiusY = rect.height / 2
    let path = CGMutablePath()

    for sample in 0..<sampleCount {
        let angle = 2 * CGFloat.pi * CGFloat(sample) / CGFloat(sampleCount)
        let cosine = cos(angle)
        let sine = sin(angle)
        let xSign: CGFloat = cosine < 0 ? -1 : 1
        let ySign: CGFloat = sine < 0 ? -1 : 1
        let x = center.x + xSign * pow(abs(cosine), 2 / exponent) * radiusX
        let y = center.y + ySign * pow(abs(sine), 2 / exponent) * radiusY
        let point = CGPoint(x: x, y: y)
        if sample == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

private func makeIcon(pixels: Int, destinationURL: URL) throws {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconGenerationError.couldNotCreateBitmap
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let inset = size * 0.035
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = approximateSquirclePath(in: tile)
    try fillWithGradient(context: context, path: tilePath, rect: tile)
    drawChartMark(context: context, tile: tile)

    guard let image = context.makeImage() else {
        throw IconGenerationError.couldNotCreateImage
    }
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw IconGenerationError.couldNotCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconGenerationError.couldNotWritePNG
    }
}

/// The icon's background: indigo through electric blue into cyan, drawn from
/// the bottom-left corner to the top-right so the brightest end sits where the
/// chart mark breaks out.
///
/// Three stops rather than two. A two-stop gradient's midpoint is forced to the
/// average of its ends, which flattens the middle of the tile — most of its
/// visible area. The third stop lets the middle be brighter than that average,
/// which is what gives the gradient its range.
private func fillWithGradient(context: CGContext, path: CGPath, rect: CGRect) throws {
    context.saveGState()
    defer { context.restoreGState() }
    context.addPath(path)
    context.clip()

    let colors = [
        CGColor(red: 0.106, green: 0.145, blue: 0.749, alpha: 1),   // #1B25BF indigo
        CGColor(red: 0.098, green: 0.549, blue: 0.988, alpha: 1),   // #198CFC electric blue
        CGColor(red: 0.365, green: 0.953, blue: 0.988, alpha: 1)    // #5DF3FC cyan
    ] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.5, 1]
    ) else {
        throw IconGenerationError.couldNotCreateGradient
    }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
    )
}

/// The chart mark, in unit coordinates within the tile, y up.
///
/// Read left to right: a rising lead-in, then two troughs around a middle peak
/// that stays below both outer highs — which is what makes the shape a W rather
/// than a zigzag — then a breakout carrying above everything before it. The W
/// is the core of the mark; the two extensions are what keep it reading as a
/// price series instead of a bare letter.
private let chartMarkPoints: [CGPoint] = [
    CGPoint(x: 0.08, y: 0.42),
    CGPoint(x: 0.22, y: 0.62),
    CGPoint(x: 0.34, y: 0.26),
    CGPoint(x: 0.50, y: 0.55),
    CGPoint(x: 0.65, y: 0.29),
    CGPoint(x: 0.92, y: 0.86)
]

private func drawChartMark(context: CGContext, tile: CGRect) {
    // Six vertices is at the edge of what a 16-pixel tile can hold. Below 64
    // pixels the stroke is thickened so the line survives rasterisation; the
    // floor keeps it from vanishing entirely at the smallest size.
    let isSmall = tile.width < 64
    let weight: CGFloat = isSmall ? 0.095 : 0.075
    let lineWidth = max(tile.width * weight, 1.6)

    let points = chartMarkPoints.map { unit in
        CGPoint(x: tile.minX + unit.x * tile.width, y: tile.minY + unit.y * tile.height)
    }
    let mark = CGMutablePath()
    mark.move(to: points[0])
    for point in points.dropFirst() { mark.addLine(to: point) }

    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(mark)
    context.strokePath()
}

private func appendBigEndian(_ value: UInt32, to data: inout Data) {
    data.append(contentsOf: [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ])
}

private func generateIconset(at outputDirectory: URL) throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for iconFile in iconFiles {
        try makeIcon(
            pixels: iconFile.pixels,
            destinationURL: outputDirectory.appendingPathComponent(iconFile.name)
        )
    }
}

private func packICNS(iconsetURL: URL, outputURL: URL) throws {
    let smallRepresentations = try [
        (pixels: 16, filename: "icon_16x16.png", colorType: "is32", maskType: "s8mk"),
        (pixels: 32, filename: "icon_32x32.png", colorType: "il32", maskType: "l8mk")
    ].flatMap { representation -> [(String, Data)] in
        let rgba = try decodedRGBA(
            from: iconsetURL.appendingPathComponent(representation.filename),
            pixels: representation.pixels
        )
        return [
            (representation.colorType, compressedRGB(from: rgba)),
            (representation.maskType, alphaMask(from: rgba))
        ]
    }
    let pngRepresentations: [(type: String, filename: String)] = [
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]
    let pngChunks = try pngRepresentations.map { representation -> (String, Data) in
        let url = iconsetURL.appendingPathComponent(representation.filename)
        return (representation.type, try Data(contentsOf: url))
    }
    let chunks = smallRepresentations + pngChunks
    let totalLength = chunks.reduce(8) { $0 + 8 + $1.1.count }
    guard let encodedLength = UInt32(exactly: totalLength) else {
        throw IconGenerationError.couldNotWritePNG
    }

    var container = Data("icns".utf8)
    appendBigEndian(encodedLength, to: &container)
    for chunk in chunks {
        container.append(Data(chunk.0.utf8))
        guard let chunkLength = UInt32(exactly: chunk.1.count + 8) else {
            throw IconGenerationError.couldNotWritePNG
        }
        appendBigEndian(chunkLength, to: &container)
        container.append(chunk.1)
    }
    try container.write(to: outputURL, options: .atomic)
}

private func decodedRGBA(from url: URL, pixels: Int) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(
              data: nil,
              width: pixels,
              height: pixels,
              bitsPerComponent: 8,
              bytesPerRow: pixels * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                  CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw IconGenerationError.couldNotReadPixels
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let rawBytes = context.data else {
        throw IconGenerationError.couldNotReadPixels
    }
    let buffer = rawBytes.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: buffer, count: pixels * pixels * 4))
}

private func compressedRGB(from rgba: [UInt8]) -> Data {
    var output = Data()
    for channel in 0..<3 {
        let values = stride(from: channel, to: rgba.count, by: 4).map { rgba[$0] }
        output.append(packBits(values))
    }
    return output
}

private func alphaMask(from rgba: [UInt8]) -> Data {
    Data(stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
}

private func packBits(_ values: [UInt8]) -> Data {
    var encoded = Data()
    var index = 0
    while index < values.count {
        var repeatCount = 1
        while index + repeatCount < values.count,
              values[index + repeatCount] == values[index],
              repeatCount < 130 {
            repeatCount += 1
        }
        if repeatCount >= 3 {
            encoded.append(0x80 | UInt8(repeatCount - 3))
            encoded.append(values[index])
            index += repeatCount
            continue
        }

        let literalStart = index
        index += repeatCount
        while index < values.count, index - literalStart < 128 {
            var nextRepeatCount = 1
            while index + nextRepeatCount < values.count,
                  values[index + nextRepeatCount] == values[index],
                  nextRepeatCount < 130 {
                nextRepeatCount += 1
            }
            if nextRepeatCount >= 3 { break }
            index += min(nextRepeatCount, 128 - (index - literalStart))
        }
        let literalCount = index - literalStart
        encoded.append(UInt8(literalCount - 1))
        encoded.append(contentsOf: values[literalStart..<index])
    }
    return encoded
}

do {
    switch CommandLine.arguments.count {
    case 2:
        try generateIconset(at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    case 4 where CommandLine.arguments[1] == "--pack":
        try packICNS(
            iconsetURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
            outputURL: URL(fileURLWithPath: CommandLine.arguments[3])
        )
    default:
        fputs("usage: make-icon <output.iconset> | --pack <input.iconset> <output.icns>\n", stderr)
        exit(EXIT_FAILURE)
    }
} catch {
    fputs("icon generation failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
