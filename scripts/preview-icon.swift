import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Standalone icon-artwork previewer.
//
// This does NOT touch scripts/make-icon.swift or the shipped AppIcon.icns. It
// writes candidate PNGs so the artwork can be judged before any of it is
// adopted. Once a candidate is chosen, its drawing code moves into
// make-icon.swift and this file's job is done.

enum PreviewError: Error {
    case couldNotCreateBitmap
    case couldNotCreateImage
    case couldNotCreateDestination
    case couldNotWritePNG
    case unknownGradient
}

// MARK: - Shape

/// Sampled superellipse approximation of the continuous-curvature squircle used
/// by modern system icons, matching the one already in make-icon.swift so a
/// chosen candidate transfers without a shape change.
private func squirclePath(in rect: CGRect) -> CGPath {
    let exponent: CGFloat = 5
    let sampleCount = 256
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
        let point = CGPoint(
            x: center.x + xSign * pow(abs(cosine), 2 / exponent) * radiusX,
            y: center.y + ySign * pow(abs(sine), 2 / exponent) * radiusY
        )
        if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

// MARK: - Palette

/// Bright-blue gradients, drawn bottom-left to top-right so the lighter end
/// sits where the chart line rises.
///
/// Each entry lists its stops in order. More than two stops is how a gradient
/// gets range without either end going muddy: the midpoint can be pushed
/// brighter than a straight interpolation between the ends would give.
struct Gradient {
    let stops: [(CGFloat, CGFloat, CGFloat)]
    let locations: [CGFloat]
}

let gradients: [String: Gradient] = [
    // Deep navy through azure into near-white cyan. The widest travel of the
    // set: the dark end is genuinely dark, so the light end reads as luminous
    // rather than merely pale.
    "deep": Gradient(
        stops: [
            (0.043, 0.192, 0.639),      // #0B31A3 navy
            (0.114, 0.478, 0.961),      // #1D7AF5 azure
            (0.478, 0.898, 1.000)       // #7AE5FF pale cyan
        ],
        locations: [0, 0.55, 1]
    ),
    // Violet-blue into cyan. Travels across hue as well as brightness, which
    // reads as more colourful at the same contrast.
    "violet": Gradient(
        stops: [
            (0.310, 0.176, 0.902),      // #4F2DE6 violet
            (0.145, 0.514, 0.976),      // #2583F9 blue
            (0.310, 0.906, 0.973)       // #4FE7F8 cyan
        ],
        locations: [0, 0.5, 1]
    ),
    // Indigo into electric cyan with a bright mid. The most saturated option.
    "electric": Gradient(
        stops: [
            (0.106, 0.145, 0.749),      // #1B25BF indigo
            (0.098, 0.549, 0.988),      // #198CFC electric blue
            (0.365, 0.953, 0.988)       // #5DF3FC cyan
        ],
        locations: [0, 0.5, 1]
    ),
    // Ocean: blue into teal, closest to the reference's cool green-blue end.
    "ocean": Gradient(
        stops: [
            (0.020, 0.318, 0.678),      // #0551AD deep ocean
            (0.078, 0.612, 0.902),      // #149CE6 mid blue
            (0.380, 0.937, 0.898)       // #61EFE5 teal-cyan
        ],
        locations: [0, 0.5, 1]
    ),
    // The two-stop azure from the previous round, kept as the baseline so the
    // added range is judged against something rather than in isolation.
    "azure": Gradient(
        stops: [
            (0.114, 0.435, 0.949),
            (0.259, 0.780, 0.984)
        ],
        locations: [0, 1]
    )
]

enum GradientAngle {
    /// Bottom-left to top-right, following the line's overall rise.
    case diagonal
    /// Bottom to top. Puts the brightest band behind the mark's upper half
    /// regardless of horizontal position.
    case vertical
}

private func drawGradient(
    context: CGContext,
    path: CGPath,
    rect: CGRect,
    gradient: Gradient,
    angle: GradientAngle
) throws {
    context.saveGState()
    defer { context.restoreGState() }
    context.addPath(path)
    context.clip()

    let colors = gradient.stops.map {
        CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1)
    } as CFArray
    guard let cgGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: gradient.locations
    ) else {
        throw PreviewError.couldNotCreateImage
    }

    let start: CGPoint
    let end: CGPoint
    switch angle {
    case .diagonal:
        start = CGPoint(x: rect.minX, y: rect.minY)
        end = CGPoint(x: rect.maxX, y: rect.maxY)
    case .vertical:
        start = CGPoint(x: rect.midX, y: rect.minY)
        end = CGPoint(x: rect.midX, y: rect.maxY)
    }
    context.drawLinearGradient(cgGradient, start: start, end: end, options: [])
}

// MARK: - The mark

/// The chart path, in unit coordinates within the mark box, y up.
///
/// Read left to right: a rising lead-in, then the W's two troughs and middle
/// peak, then a breakout that carries above everything before it. The W is the
/// core; the two extensions are what stop it reading as a bare letter.
private func chartPoints(style: MarkStyle) -> [CGPoint] {
    switch style {
    case .leadIn:
        // Lead-in rises at roughly the same slope as the breakout, so the two
        // extensions look like one continuous series interrupted by the W.
        return [
            CGPoint(x: 0.08, y: 0.42),      // start low left
            CGPoint(x: 0.22, y: 0.62),      // rise into the pattern
            CGPoint(x: 0.34, y: 0.26),      // first trough
            CGPoint(x: 0.50, y: 0.55),      // middle peak, below the outer highs
            CGPoint(x: 0.65, y: 0.29),      // second trough
            CGPoint(x: 0.92, y: 0.86)       // breakout, highest point
        ]
    case .steepLeadIn:
        // A shorter, steeper lead-in. The W occupies more of the width, so it
        // survives small sizes better, at the cost of a less prominent run-up.
        return [
            CGPoint(x: 0.09, y: 0.46),
            CGPoint(x: 0.20, y: 0.66),
            CGPoint(x: 0.32, y: 0.25),
            CGPoint(x: 0.49, y: 0.56),
            CGPoint(x: 0.66, y: 0.28),
            CGPoint(x: 0.91, y: 0.88)
        ]
    case .lowLeadIn:
        // The lead-in starts near the troughs rather than mid-height, so the
        // whole shape trends upward from the very first point. The W's left
        // shoulder is lower than its right, which emphasises recovery.
        return [
            CGPoint(x: 0.08, y: 0.30),
            CGPoint(x: 0.21, y: 0.58),
            CGPoint(x: 0.33, y: 0.24),
            CGPoint(x: 0.50, y: 0.54),
            CGPoint(x: 0.65, y: 0.27),
            CGPoint(x: 0.92, y: 0.84)
        ]
    }
}

enum MarkStyle: String {
    case leadIn
    case steepLeadIn
    case lowLeadIn
}

private func drawMark(
    context: CGContext,
    tile: CGRect,
    style: MarkStyle,
    weight: CGFloat
) {
    let points = chartPoints(style: style).map { unit in
        CGPoint(x: tile.minX + unit.x * tile.width, y: tile.minY + unit.y * tile.height)
    }
    let path = CGMutablePath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }

    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(tile.width * weight)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
}

// MARK: - Rendering

struct Candidate {
    let label: String
    let gradient: String
    let angle: GradientAngle
    let style: MarkStyle
    let weight: CGFloat
}

private func renderTile(candidate: Candidate, in context: CGContext, rect: CGRect) throws {
    guard let gradient = gradients[candidate.gradient] else {
        throw PreviewError.unknownGradient
    }
    let inset = rect.width * 0.035
    let tile = rect.insetBy(dx: inset, dy: inset)
    try drawGradient(
        context: context,
        path: squirclePath(in: tile),
        rect: tile,
        gradient: gradient,
        angle: candidate.angle
    )
    drawMark(context: context, tile: tile, style: candidate.style, weight: candidate.weight)
}

/// One contact sheet holding every candidate: a large tile per row for judging
/// the artwork, and 32px and 16px tiles beside it for judging whether it
/// survives the sizes where detail dies.
private func renderContactSheet(candidates: [Candidate], to url: URL) throws {
    let large = 240
    let gutter = 28
    let rowHeight = large + gutter
    let width = gutter + large + gutter + 32 + gutter + 16 + gutter + 150
    let height = gutter + rowHeight * candidates.count

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw PreviewError.couldNotCreateBitmap
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    // Mid grey: neither light nor dark mode flatters a white stroke, so judge
    // against something between them.
    context.setFillColor(CGColor(gray: 0.55, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Rows top-down, so the first candidate is the top row in the written file.
    for (index, candidate) in candidates.enumerated() {
        let rowTop = height - gutter - rowHeight * index
        let rowBottom = CGFloat(rowTop - large)

        try renderTile(
            candidate: candidate,
            in: context,
            rect: CGRect(x: CGFloat(gutter), y: rowBottom, width: CGFloat(large), height: CGFloat(large))
        )

        // Small sizes are rendered into their own bitmaps and drawn scaled, so
        // they show real small-size rasterisation rather than a downscale of
        // the large tile.
        var smallX = CGFloat(gutter + large + gutter)
        for smallSize in [32, 16] {
            guard let smallContext = CGContext(
                data: nil,
                width: smallSize,
                height: smallSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw PreviewError.couldNotCreateBitmap
            }
            smallContext.setAllowsAntialiasing(true)
            smallContext.setShouldAntialias(true)
            try renderTile(
                candidate: candidate,
                in: smallContext,
                rect: CGRect(x: 0, y: 0, width: CGFloat(smallSize), height: CGFloat(smallSize))
            )
            if let smallImage = smallContext.makeImage() {
                context.interpolationQuality = .none
                context.draw(
                    smallImage,
                    in: CGRect(
                        x: smallX,
                        y: rowBottom + CGFloat(large - smallSize) / 2,
                        width: CGFloat(smallSize),
                        height: CGFloat(smallSize)
                    )
                )
                context.interpolationQuality = .default
            }
            smallX += CGFloat(smallSize + gutter)
        }
    }

    guard let image = context.makeImage() else { throw PreviewError.couldNotCreateImage }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw PreviewError.couldNotCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PreviewError.couldNotWritePNG }
}

// MARK: - Main

// Row order matches the order below, top to bottom in the written sheet.
let candidates: [Candidate] = [
    Candidate(label: "1", gradient: "deep", angle: .diagonal, style: .leadIn, weight: 0.075),
    Candidate(label: "2", gradient: "violet", angle: .diagonal, style: .leadIn, weight: 0.075),
    Candidate(label: "3", gradient: "electric", angle: .diagonal, style: .leadIn, weight: 0.075),
    Candidate(label: "4", gradient: "ocean", angle: .diagonal, style: .leadIn, weight: 0.075),
    Candidate(label: "5", gradient: "deep", angle: .vertical, style: .leadIn, weight: 0.075),
    Candidate(label: "6", gradient: "deep", angle: .diagonal, style: .steepLeadIn, weight: 0.075),
    Candidate(label: "7", gradient: "deep", angle: .diagonal, style: .lowLeadIn, weight: 0.075),
    Candidate(label: "8", gradient: "azure", angle: .diagonal, style: .leadIn, weight: 0.075)
]

let outputURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "design/icon/candidates.png")

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try renderContactSheet(candidates: candidates, to: outputURL)
    print("wrote \(candidates.count) candidates to \(outputURL.path)")
} catch {
    fputs("preview generation failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
