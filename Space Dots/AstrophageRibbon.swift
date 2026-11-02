import SwiftUI

/// Standalone visual study for the Home backdrop.
///
/// This view is intentionally not referenced by `ContentView`. Use the preview
/// below to iterate on the ribbon shape, movement and glow in isolation.
struct AstrophageRibbonView: View {

    private static let ribbonCount = 8
    private static let wideRibbonWidthMultiplier: CGFloat = 4.0
    private static let slimRibbonWidthMultiplier: CGFloat = 1.5
    private let rendersAsynchronously: Bool
    private let showsFilmGrain: Bool
    private let elapsedOverride: Double?

    init(
        rendersAsynchronously: Bool = true,
        showsFilmGrain: Bool = true,
        elapsedOverride: Double? = nil
    ) {
        self.rendersAsynchronously = rendersAsynchronously
        self.showsFilmGrain = showsFilmGrain
        self.elapsedOverride = elapsedOverride
    }

    private struct Ribbon {
        let verticalPosition: Double
        let primaryAmplitude: Double
        let secondaryAmplitude: Double
        let primaryFrequency: Double
        let secondaryFrequency: Double
        let phase: Double
        let speed: Double
        let thickness: Double
        let twistFrequency: Double
        let opacity: Double
        let highlightStrength: Double
        let widthMultiplier: CGFloat
    }

    private static let ribbons: [Ribbon] = (0..<ribbonCount).map { index in
        let seed = Double(index)
        let distributionPosition = Double(index) / Double(ribbonCount - 1)
        let edgeWaveScale = 0.58 + (0.42 * sin(distributionPosition * .pi))
        return Ribbon(
            verticalPosition: 0.18
                + (distributionPosition * 0.64),
            primaryAmplitude: (
                0.025 + stableRandom(seed * 1.73) * 0.055
            ) * edgeWaveScale,
            secondaryAmplitude: (
                0.008 + stableRandom(seed * 2.41) * 0.022
            ) * edgeWaveScale,
            primaryFrequency: 0.72 + stableRandom(seed * 3.19) * 1.15,
            secondaryFrequency: 1.8 + stableRandom(seed * 4.07) * 2.1,
            phase: stableRandom(seed * 5.11) * .pi * 2.0,
            speed: 0.05 + stableRandom(seed * 6.13) * 0.10,
            thickness: 0.009 + stableRandom(seed * 7.31) * 0.023,
            twistFrequency: 1.15 + stableRandom(seed * 8.23) * 2.4,
            opacity: 0.20 + stableRandom(seed * 9.47) * 0.34,
            highlightStrength: stableRandom(seed * 10.67),
            widthMultiplier: stableRandom(seed * 11.71) > 0.72
                ? Self.slimRibbonWidthMultiplier
                : Self.wideRibbonWidthMultiplier
        )
    }

    private static func stableRandom(_ seed: Double) -> Double {
        let value = sin((seed + 0.37) * 12.9898) * 43_758.5453
        return value - floor(value)
    }

    var body: some View {
        Group {
            if let elapsedOverride {
                ribbonVisual(elapsed: elapsedOverride)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    ribbonVisual(
                        elapsed: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ribbonVisual(elapsed: Double) -> some View {
        ZStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.006, green: 0.000, blue: 0.001),
                        Color(red: 0.085, green: 0.002, blue: 0.010),
                        Color(red: 0.014, green: 0.000, blue: 0.002)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas(
                    opaque: false,
                    colorMode: .linear,
                    rendersAsynchronously: rendersAsynchronously
                ) { context, size in
                    drawAmbientRibbonField(
                        in: &context,
                        size: size,
                        elapsed: elapsed
                    )
                    drawRibbons(in: &context, size: size, elapsed: elapsed)
                }
                .blur(radius: 8.0)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white, location: 0.15),
                            .init(color: .white, location: 0.85),
                            .init(color: .clear, location: 1.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }

            if showsFilmGrain {
                FilmGrainOverlay()
            }
        }
    }

    private func drawRibbons(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: Double
    ) {
        for (index, ribbon) in Self.ribbons.enumerated() {
            let geometry = makeGeometry(
                for: ribbon,
                index: index,
                size: size,
                elapsed: elapsed
            )

            var glowContext = context
            glowContext.blendMode = .plusLighter
            glowContext.addFilter(.blur(radius: geometry.baseThickness * 1.55))
            glowContext.fill(
                geometry.ribbonPath,
                with: .color(Color(
                    red: 0.694,
                    green: 0.149,
                    blue: 0.239,
                    opacity: ribbon.opacity * 0.44
                ))
            )

            // A narrow core keeps the red body intact; when core lines cross,
            // additive blending turns only those local spots into white flares.
            var overlapGlowContext = context
            overlapGlowContext.blendMode = .plusLighter
            overlapGlowContext.addFilter(
                .blur(radius: geometry.baseThickness * 0.28)
            )
            overlapGlowContext.stroke(
                geometry.highlightPath,
                with: .color(Color.white.opacity(ribbon.opacity * 0.14)),
                style: StrokeStyle(
                    lineWidth: max(1.0, geometry.baseThickness * 0.14),
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            var bodyContext = context
            bodyContext.blendMode = .plusLighter
            bodyContext.fill(
                geometry.ribbonPath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(
                            color: Color(
                                red: 0.52,
                                green: 0.070,
                                blue: 0.125,
                                opacity: ribbon.opacity * 0.54
                            ),
                            location: 0.0
                        ),
                        .init(
                            color: Color(
                                red: 0.694,
                                green: 0.149,
                                blue: 0.239,
                                opacity: ribbon.opacity
                            ),
                            location: 0.48
                        ),
                        .init(
                            color: Color(
                                red: 0.46,
                                green: 0.050,
                                blue: 0.098,
                                opacity: ribbon.opacity * 0.44
                            ),
                            location: 1.0
                        )
                    ]),
                    startPoint: CGPoint(
                        x: 0.0,
                        y: size.height * CGFloat(ribbon.verticalPosition)
                    ),
                    endPoint: CGPoint(
                        x: size.width,
                        y: size.height * CGFloat(ribbon.verticalPosition)
                    )
                )
            )

            var highlightContext = context
            highlightContext.blendMode = .plusLighter
            highlightContext.stroke(
                geometry.highlightPath,
                with: .color(Color(
                    red: 0.94,
                    green: 0.44,
                    blue: 0.53,
                    opacity: (0.10 + ribbon.highlightStrength * 0.30)
                        * ribbon.opacity
                )),
                style: StrokeStyle(
                    lineWidth: max(1.0, geometry.baseThickness * 0.075),
                    lineCap: .round,
                    lineJoin: .round
                )
            )

        }
    }

    private func drawAmbientRibbonField(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: Double
    ) {
        let segmentCount = 64
        var upperEdge: [CGPoint] = []
        var lowerEdge: [CGPoint] = []
        upperEdge.reserveCapacity(segmentCount + 1)
        lowerEdge.reserveCapacity(segmentCount + 1)

        for segment in 0...segmentCount {
            let progress = Double(segment) / Double(segmentCount)
            let phase = progress * .pi * 2.0
            let convergence = progress * progress * (3.0 - 2.0 * progress)
            let centerY = size.height * CGFloat(
                0.50
                    + (sin(phase * 1.05 + elapsed * 0.030) * 0.095)
                    + (sin(phase * 2.35 - elapsed * 0.018) * 0.037)
            )
            let halfHeight = size.height * CGFloat(
                0.21 - (0.11 * convergence)
            )
            let x = size.width * CGFloat(progress)
            upperEdge.append(CGPoint(x: x, y: centerY - halfHeight))
            lowerEdge.append(CGPoint(x: x, y: centerY + halfHeight))
        }

        var fieldPath = Path()
        if let first = upperEdge.first {
            fieldPath.move(to: first)
            for point in upperEdge.dropFirst() {
                fieldPath.addLine(to: point)
            }
            for point in lowerEdge.reversed() {
                fieldPath.addLine(to: point)
            }
            fieldPath.closeSubpath()
        }

        var fieldContext = context
        fieldContext.blendMode = .plusLighter
        fieldContext.addFilter(.blur(radius: size.height * 0.055))
        fieldContext.fill(
            fieldPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(
                        color: Color(
                            red: 0.37,
                            green: 0.025,
                            blue: 0.075,
                            opacity: 0.30
                        ),
                        location: 0.0
                    ),
                    .init(
                        color: Color(
                            red: 0.694,
                            green: 0.149,
                            blue: 0.239,
                            opacity: 0.56
                        ),
                        location: 0.52
                    ),
                    .init(
                        color: Color(
                            red: 0.42,
                            green: 0.040,
                            blue: 0.090,
                            opacity: 0.26
                        ),
                        location: 1.0
                    )
                ]),
                startPoint: CGPoint(x: 0.0, y: size.height * 0.5),
                endPoint: CGPoint(x: size.width, y: size.height * 0.5)
            )
        )
    }

    private func makeGeometry(
        for ribbon: Ribbon,
        index: Int,
        size: CGSize,
        elapsed: Double
    ) -> (
        ribbonPath: Path,
        highlightPath: Path,
        baseThickness: CGFloat
    ) {
        let segmentCount = 72
        let baseThickness = size.height
            * CGFloat(ribbon.thickness)
            * ribbon.widthMultiplier
        var upperEdge: [CGPoint] = []
        var lowerEdge: [CGPoint] = []
        var highlights: [CGPoint] = []

        upperEdge.reserveCapacity(segmentCount + 1)
        lowerEdge.reserveCapacity(segmentCount + 1)
        highlights.reserveCapacity(segmentCount + 1)

        for segment in 0...segmentCount {
            let progress = Double(segment) / Double(segmentCount)
            let xPhase = progress * .pi * 2.0
            let travelPhase = elapsed * ribbon.speed
            let primaryWave = sin(
                xPhase * ribbon.primaryFrequency
                    + ribbon.phase
                    + travelPhase
            ) * ribbon.primaryAmplitude
            let secondaryWave = sin(
                xPhase * ribbon.secondaryFrequency
                    - ribbon.phase * 0.73
                    - travelPhase * 0.64
            ) * ribbon.secondaryAmplitude
            let slowLift = sin(
                elapsed * 0.06
                    + ribbon.phase
                    + Double(index) * 0.21
            ) * 0.012
            let convergence = progress * progress * (3.0 - 2.0 * progress)
            let convergedVerticalPosition = 0.5
                + ((ribbon.verticalPosition - 0.5) * (1.0 - (0.82 * convergence)))
            let waveScale = 1.0 - (0.60 * convergence)
            let centerY = size.height * CGFloat(
                convergedVerticalPosition
                    + ((primaryWave + secondaryWave) * waveScale)
                    + slowLift
            )

            let twist = sin(
                xPhase * ribbon.twistFrequency
                    - elapsed * (0.08 + ribbon.speed * 0.38)
                    + ribbon.phase * 1.31
            )
            let pinch = 0.22 + 0.78 * abs(twist)
            let halfWidth = baseThickness * CGFloat(pinch)
            let center = CGPoint(x: size.width * CGFloat(progress), y: centerY)

            upperEdge.append(CGPoint(x: center.x, y: center.y - halfWidth))
            lowerEdge.append(CGPoint(x: center.x, y: center.y + halfWidth))
            highlights.append(CGPoint(
                x: center.x,
                y: center.y - (halfWidth * CGFloat(twist) * 0.82)
            ))
        }

        var highlightPath = Path()
        append(points: highlights, to: &highlightPath)

        var ribbonPath = Path()
        if let first = upperEdge.first {
            ribbonPath.move(to: first)
            for point in upperEdge.dropFirst() {
                ribbonPath.addLine(to: point)
            }
            for point in lowerEdge.reversed() {
                ribbonPath.addLine(to: point)
            }
            ribbonPath.closeSubpath()
        }

        return (ribbonPath, highlightPath, baseThickness)
    }

    private func append(points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
    }

}

/// A separate film-grain layer updated at 12 Hz.
private struct FilmGrainOverlay: View {

    private static let grainCount = 3_600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
            let frame = Double(
                Int(timeline.date.timeIntervalSinceReferenceDate * 12.0)
            )

            Canvas(
                opaque: false,
                colorMode: .linear,
                rendersAsynchronously: true
            ) { context, size in
                context.blendMode = .plusLighter

                for index in 0..<Self.grainCount {
                    let seed = Double(index)
                    let x = size.width * CGFloat(
                        Self.stableRandom(seed * 1.41 + frame * 0.19)
                    )
                    let y = size.height * CGFloat(
                        Self.stableRandom(seed * 2.73 + frame * 0.31)
                    )
                    let brightness = Self.stableRandom(seed * 4.19 + frame)
                    let pointSize: CGFloat = brightness > 0.82 ? 1.45 : 0.92
                    let opacity = 0.025 + (brightness * 0.065)
                    let point = CGRect(
                        x: x,
                        y: y,
                        width: pointSize,
                        height: pointSize
                    )
                    context.fill(
                        Path(ellipseIn: point),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func stableRandom(_ seed: Double) -> Double {
        let value = sin((seed + 0.37) * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

#Preview("Astrophage ribbons") {
    AstrophageRibbonView()
        .frame(width: 1_280, height: 720)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .padding(40)
        .background(Color.black)
}
