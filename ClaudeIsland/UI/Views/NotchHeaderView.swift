//
//  NotchHeaderView.swift
//  ClaudeIsland
//
//  Header bar for the dynamic island
//

import Combine
import SwiftUI

struct NotchDragonIcon: View {
    let size: CGFloat
    var animate: Bool = false

    @State private var framePhase: Int = 0

    private let animationTimer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    init(size: CGFloat = 16, animate: Bool = false) {
        self.size = size
        self.animate = animate
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 16.0
            let width: CGFloat = 24
            let xOffset = (canvasSize.width - width * scale) / 2
            let tailLift: CGFloat = animate && framePhase.isMultiple(of: 2) ? -1 : 0
            let wingLift: CGFloat = animate && framePhase.isMultiple(of: 2) ? -1 : 1

            drawPixels(dragonShadowPixels(tailLift: tailLift, wingLift: wingLift),
                       color: Color.black.opacity(0.35),
                       context: &context,
                       scale: scale,
                       xOffset: xOffset,
                       yOffset: 1)
            drawPixels(dragonPixels(tailLift: tailLift, wingLift: wingLift),
                       color: Color(red: 0.16, green: 0.2, blue: 0.22),
                       context: &context,
                       scale: scale,
                       xOffset: xOffset)
            drawPixels(dragonBellyPixels, color: Color(red: 0.9, green: 0.49, blue: 0.2), context: &context, scale: scale, xOffset: xOffset)
            drawPixels(dragonWingPixels(wingLift: wingLift), color: Color(red: 0.78, green: 0.25, blue: 0.16), context: &context, scale: scale, xOffset: xOffset)
            drawPixels(dragonWingHighlightPixels(wingLift: wingLift), color: Color(red: 0.95, green: 0.55, blue: 0.18), context: &context, scale: scale, xOffset: xOffset)
            drawPixels(dragonScalePixels(tailLift: tailLift), color: Color(red: 0.33, green: 0.53, blue: 0.36), context: &context, scale: scale, xOffset: xOffset)
            drawPixels(dragonHornPixels, color: Color(red: 0.67, green: 0.62, blue: 0.52), context: &context, scale: scale, xOffset: xOffset)
            drawPixels(dragonEyePixels, color: Color(red: 0.96, green: 0.38, blue: 0.2), context: &context, scale: scale, xOffset: xOffset)
        }
        .frame(width: size * 1.5, height: size)
        .onReceive(animationTimer) { _ in
            if animate {
                framePhase = (framePhase + 1) % 4
            }
        }
    }

    private func drawPixels(
        _ pixels: [(CGFloat, CGFloat)],
        color: Color,
        context: inout GraphicsContext,
        scale: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat = 0
    ) {
        for (x, y) in pixels {
            let rect = CGRect(
                x: xOffset + x * scale,
                y: (y + yOffset) * scale,
                width: scale,
                height: scale
            )
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func dragonPixels(tailLift: CGFloat, wingLift: CGFloat) -> [(CGFloat, CGFloat)] {
        [
            (7, 3), (8, 3), (9, 3), (13, 3),
            (6, 4), (7, 4), (8, 4), (9, 4), (10, 4), (12, 4), (13, 4), (14, 4),
            (5, 5), (6, 5), (7, 5), (8, 5), (9, 5), (10, 5), (11, 5), (12, 5), (13, 5), (14, 5), (15, 5), (16, 5),
            (4, 6), (5, 6), (6, 6), (7, 6), (8, 6), (9, 6), (10, 6), (11, 6), (12, 6), (13, 6), (14, 6), (15, 6), (16, 6), (17, 6),
            (3, 7), (4, 7), (5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7), (12, 7), (13, 7), (14, 7), (15, 7), (16, 7), (17, 7),
            (3, 8), (4, 8), (5, 8), (6, 8), (7, 8), (8, 8), (9, 8), (10, 8), (11, 8), (12, 8), (13, 8), (14, 8), (15, 8), (16, 8),
            (2, 9), (3, 9), (4, 9), (5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (10, 9), (11, 9), (12, 9), (13, 9), (14, 9), (15, 9),
            (2, 10), (3, 10), (4, 10), (5, 10), (6, 10), (7, 10), (8, 10), (9, 10), (10, 10), (11, 10), (12, 10), (13, 10), (14, 10),
            (2, 11), (3, 11), (4, 11), (5, 11), (6, 11), (7, 11), (8, 11), (9, 11), (10, 11), (11, 11), (12, 11), (13, 11), (14, 11),
            (3, 12), (4, 12), (5, 12), (6, 12), (7, 12), (8, 12), (9, 12), (10, 12), (11, 12), (12, 12),
            (2, 13), (3, 13), (4, 13), (5, 13), (6, 13), (7, 13), (8, 13), (9, 13), (10, 13),
            (1, 14), (2, 14), (3, 14), (4, 14), (5, 14), (6, 14), (7, 14), (8, 14),
            (0, 15 + tailLift), (1, 15 + tailLift), (2, 15), (3, 15), (4, 15), (5, 15), (6, 15),
            (1, 16 + tailLift), (2, 16 + tailLift), (3, 16), (4, 16), (5, 16), (6, 16), (7, 16),
            (4, 17), (5, 17), (6, 17), (7, 17), (8, 17), (11, 17), (12, 17),
            (6, 18), (7, 18), (8, 18), (11, 18), (12, 18)
        ]
    }

    private func dragonShadowPixels(tailLift: CGFloat, wingLift: CGFloat) -> [(CGFloat, CGFloat)] {
        dragonPixels(tailLift: tailLift, wingLift: wingLift).map { ($0.0 + 0.65, $0.1 + 0.65) }
    }

    private var dragonBellyPixels: [(CGFloat, CGFloat)] {
        [
            (10, 8), (11, 8), (12, 8),
            (9, 9), (10, 9), (11, 9), (12, 9), (13, 9),
            (8, 10), (9, 10), (10, 10), (11, 10), (12, 10),
            (7, 11), (8, 11), (9, 11), (10, 11), (11, 11),
            (7, 12), (8, 12), (9, 12),
            (6, 13), (7, 13), (8, 13),
            (5, 14), (6, 14),
            (5, 15), (6, 15)
        ]
    }

    private func dragonWingPixels(wingLift: CGFloat) -> [(CGFloat, CGFloat)] {
        [
            (6, 2 + wingLift), (7, 2 + wingLift), (8, 2 + wingLift), (9, 2 + wingLift),
            (5, 3 + wingLift), (6, 3 + wingLift), (7, 3 + wingLift), (8, 3 + wingLift),
            (4, 4 + wingLift), (5, 4 + wingLift), (6, 4 + wingLift),
            (3, 5 + wingLift), (4, 5 + wingLift), (5, 5 + wingLift),
            (2, 6 + wingLift), (3, 6 + wingLift), (4, 6 + wingLift),
            (2, 7 + wingLift), (3, 7 + wingLift)
        ]
    }

    private func dragonWingHighlightPixels(wingLift: CGFloat) -> [(CGFloat, CGFloat)] {
        [
            (7, 3 + wingLift), (8, 3 + wingLift),
            (6, 4 + wingLift), (7, 4 + wingLift),
            (5, 5 + wingLift), (6, 5 + wingLift),
            (4, 6 + wingLift)
        ]
    }

    private func dragonScalePixels(tailLift: CGFloat) -> [(CGFloat, CGFloat)] {
        [
            (7, 5), (10, 6), (12, 6), (6, 7), (9, 8), (13, 8),
            (5, 9), (8, 10), (12, 10), (4, 11), (7, 12), (3, 14), (2, 16 + tailLift)
        ]
    }

    private var dragonHornPixels: [(CGFloat, CGFloat)] {
        [(7, 1), (13, 1), (8, 2), (12, 2)]
    }

    private var dragonEyePixels: [(CGFloat, CGFloat)] {
        [(14, 7), (15, 7), (14, 8)]
    }
}

struct ClaudeCrabIcon: View {
    let size: CGFloat
    var animateLegs: Bool = false

    var body: some View {
        NotchDragonIcon(size: size, animate: animateLegs)
    }
}

struct NotchFireStatusIcon: View {
    let size: CGFloat
    let color: Color
    var animate: Bool = true

    @State private var framePhase: Int = 0

    private let animationTimer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, _ in
            let scale = size / 16.0
            let outerColor = color
            let midColor = fireMidColor
            let innerColor = fireInnerColor
            let flamePixels = flameOuterPixels(flicker: animate ? framePhase : 0)
            let midPixels = flameMidPixels(flicker: animate ? framePhase : 0)
            let corePixels = flameCorePixels(flicker: animate ? framePhase : 0)

            drawPixels(flamePixels, color: outerColor, context: &context, scale: scale)
            drawPixels(midPixels, color: midColor, context: &context, scale: scale)
            drawPixels(corePixels, color: innerColor, context: &context, scale: scale)
        }
        .frame(width: size, height: size)
        .onReceive(animationTimer) { _ in
            if animate {
                framePhase = (framePhase + 1) % 4
            }
        }
    }

    private var fireMidColor: Color {
        color.opacity(0.85)
    }

    private var fireInnerColor: Color {
        Color.white.opacity(0.95)
    }

    private func drawPixels(
        _ pixels: [(CGFloat, CGFloat)],
        color: Color,
        context: inout GraphicsContext,
        scale: CGFloat
    ) {
        for (x, y) in pixels {
            let rect = CGRect(x: x * scale, y: y * scale, width: scale, height: scale)
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func flameOuterPixels(flicker: Int) -> [(CGFloat, CGFloat)] {
        let topOffset: CGFloat = flicker.isMultiple(of: 2) ? 0 : 1
        return [
            (7, 1 + topOffset),
            (6, 2 + topOffset), (7, 2 + topOffset), (8, 2 + topOffset),
            (5, 3 + topOffset), (6, 3 + topOffset), (7, 3 + topOffset), (8, 3 + topOffset), (9, 3 + topOffset),
            (4, 4 + topOffset), (5, 4 + topOffset), (6, 4 + topOffset), (7, 4 + topOffset), (8, 4 + topOffset), (9, 4 + topOffset), (10, 4 + topOffset),
            (4, 5 + topOffset), (5, 5 + topOffset), (6, 5 + topOffset), (7, 5 + topOffset), (8, 5 + topOffset), (9, 5 + topOffset), (10, 5 + topOffset),
            (3, 6 + topOffset), (4, 6 + topOffset), (5, 6 + topOffset), (6, 6 + topOffset), (7, 6 + topOffset), (8, 6 + topOffset), (9, 6 + topOffset), (10, 6 + topOffset),
            (4, 7 + topOffset), (5, 7 + topOffset), (6, 7 + topOffset), (7, 7 + topOffset), (8, 7 + topOffset), (9, 7 + topOffset),
            (5, 8 + topOffset), (6, 8 + topOffset), (7, 8 + topOffset), (8, 8 + topOffset),
            (6, 9 + topOffset), (7, 9 + topOffset)
        ]
    }

    private func flameMidPixels(flicker: Int) -> [(CGFloat, CGFloat)] {
        let topOffset: CGFloat = flicker == 1 || flicker == 3 ? 1 : 0
        return [
            (7, 3 + topOffset),
            (6, 4 + topOffset), (7, 4 + topOffset), (8, 4 + topOffset),
            (5, 5 + topOffset), (6, 5 + topOffset), (7, 5 + topOffset), (8, 5 + topOffset), (9, 5 + topOffset),
            (5, 6 + topOffset), (6, 6 + topOffset), (7, 6 + topOffset), (8, 6 + topOffset), (9, 6 + topOffset),
            (6, 7 + topOffset), (7, 7 + topOffset), (8, 7 + topOffset),
            (7, 8 + topOffset)
        ]
    }

    private func flameCorePixels(flicker: Int) -> [(CGFloat, CGFloat)] {
        let topOffset: CGFloat = flicker.isMultiple(of: 2) ? 0 : 1
        return [
            (7, 4 + topOffset),
            (6, 5 + topOffset), (7, 5 + topOffset), (8, 5 + topOffset),
            (6, 6 + topOffset), (7, 6 + topOffset), (8, 6 + topOffset),
            (7, 7 + topOffset)
        ]
    }
}

// Pixel art permission indicator icon
struct PermissionIndicatorIcon: View {
    let size: CGFloat
    let color: Color

    init(size: CGFloat = 14, color: Color = Color(red: 0.11, green: 0.12, blue: 0.13)) {
        self.size = size
        self.color = color
    }

    // Visible pixel positions from the SVG (at 30x30 scale)
    private let pixels: [(CGFloat, CGFloat)] = [
        (7, 7), (7, 11),           // Left column
        (11, 3),                    // Top left
        (15, 3), (15, 19), (15, 27), // Center column
        (19, 3), (19, 15),          // Right of center
        (23, 7), (23, 11)           // Right column
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

// Pixel art "ready for input" indicator icon (checkmark/done shape)
struct ReadyForInputIndicatorIcon: View {
    let size: CGFloat
    let color: Color

    init(size: CGFloat = 14, color: Color = TerminalColors.green) {
        self.size = size
        self.color = color
    }

    // Checkmark shape pixel positions (at 30x30 scale)
    private let pixels: [(CGFloat, CGFloat)] = [
        (5, 15),                    // Start of checkmark
        (9, 19),                    // Down stroke
        (13, 23),                   // Bottom of checkmark
        (17, 19),                   // Up stroke begins
        (21, 15),                   // Up stroke
        (25, 11),                   // Up stroke
        (29, 7)                     // End of checkmark
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 30.0
            let pixelSize: CGFloat = 4 * scale

            for (x, y) in pixels {
                let rect = CGRect(
                    x: x * scale - pixelSize / 2,
                    y: y * scale - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}
