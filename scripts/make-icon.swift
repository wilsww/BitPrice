import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconGenerationError: Error {
    case couldNotCreateBitmap
    case couldNotCreateGradient
    case couldNotCreateImage
    case couldNotCreateDestination
    case couldNotWritePNG
    case couldNotReadPixels
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
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: size * 0.22,
        cornerHeight: size * 0.22,
        transform: nil
    )
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let backgroundColors = [
        CGColor(red: 0.035, green: 0.075, blue: 0.16, alpha: 1),
        CGColor(red: 0.08, green: 0.18, blue: 0.34, alpha: 1)
    ] as CFArray
    guard let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: backgroundColors,
        locations: [0, 1]
    ) else {
        throw IconGenerationError.couldNotCreateGradient
    }
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    context.restoreGState()

    let coinRect = CGRect(x: size * 0.14, y: size * 0.14, width: size * 0.72, height: size * 0.72)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.025), blur: size * 0.055,
                      color: CGColor(gray: 0, alpha: 0.42))
    context.addEllipse(in: coinRect)
    context.clip()
    let coinColors = [
        CGColor(red: 1.0, green: 0.69, blue: 0.08, alpha: 1),
        CGColor(red: 0.93, green: 0.31, blue: 0.04, alpha: 1)
    ] as CFArray
    guard let coinGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: coinColors,
        locations: [0, 1]
    ) else {
        throw IconGenerationError.couldNotCreateGradient
    }
    context.drawLinearGradient(
        coinGradient,
        start: CGPoint(x: size * 0.28, y: size * 0.8),
        end: CGPoint(x: size * 0.75, y: size * 0.18),
        options: []
    )
    context.restoreGState()

    context.setStrokeColor(CGColor(red: 1, green: 0.91, blue: 0.65, alpha: 0.92))
    context.setLineWidth(size * 0.032)
    context.strokeEllipse(in: coinRect.insetBy(dx: size * 0.018, dy: size * 0.018))

    context.setStrokeColor(CGColor(red: 1, green: 0.985, blue: 0.9, alpha: 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)

    for stemX in [size * 0.445, size * 0.505] {
        context.beginPath()
        context.move(to: CGPoint(x: stemX, y: size * 0.25))
        context.addLine(to: CGPoint(x: stemX, y: size * 0.75))
        context.setLineWidth(size * 0.027)
        context.strokePath()
    }

    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: size * 0.42, y: size * 0.68))
    mark.addLine(to: CGPoint(x: size * 0.56, y: size * 0.68))
    mark.addCurve(
        to: CGPoint(x: size * 0.56, y: size * 0.51),
        control1: CGPoint(x: size * 0.72, y: size * 0.68),
        control2: CGPoint(x: size * 0.72, y: size * 0.51)
    )
    mark.addLine(to: CGPoint(x: size * 0.42, y: size * 0.51))
    mark.move(to: CGPoint(x: size * 0.42, y: size * 0.51))
    mark.addLine(to: CGPoint(x: size * 0.57, y: size * 0.51))
    mark.addCurve(
        to: CGPoint(x: size * 0.55, y: size * 0.31),
        control1: CGPoint(x: size * 0.75, y: size * 0.51),
        control2: CGPoint(x: size * 0.74, y: size * 0.31)
    )
    mark.addLine(to: CGPoint(x: size * 0.42, y: size * 0.31))
    context.addPath(mark)
    context.setLineWidth(size * 0.066)
    context.strokePath()

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
