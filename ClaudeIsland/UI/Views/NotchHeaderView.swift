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
    let color: Color
    var animate: Bool = false

    @State private var framePhase: Int = 0

    private let animationTimer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    init(size: CGFloat = 16, color: Color = Color.white.opacity(0.85), animate: Bool = false) {
        self.size = size
        self.color = color
        self.animate = animate
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 16.0
            let width: CGFloat = 18
            let xOffset = (canvasSize.width - width * scale) / 2
            let legShift: CGFloat = animate && framePhase.isMultiple(of: 2) ? 1 : 0
            let tailShift: CGFloat = animate && framePhase.isMultiple(of: 2) ? -1 : 0

            drawPixels(dinoShadowPixels(legShift: legShift, tailShift: tailShift),
                       color: Color.black.opacity(0.35),
                       context: &context,
                       scale: scale,
                       xOffset: xOffset,
                        yOffset: 1)
            drawPixels(dinoPixels(legShift: legShift, tailShift: tailShift),
                       color: color,
                       context: &context,
                       scale: scale,
                       xOffset: xOffset)
            drawPixels(dinoEyePixels, color: Color.white.opacity(0.95), context: &context, scale: scale, xOffset: xOffset)
        }
        .frame(width: size * 1.12, height: size)
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

    private func dinoPixels(legShift: CGFloat, tailShift: CGFloat) -> [(CGFloat, CGFloat)] {
        [
            (10, 1), (11, 1), (12, 1), (13, 1),
            (9, 2), (10, 2), (11, 2), (12, 2), (13, 2), (14, 2),
            (9, 3), (10, 3), (11, 3), (12, 3), (13, 3), (14, 3),
            (9, 4), (10, 4), (11, 4), (12, 4), (13, 4), (14, 4),
            (8, 5), (9, 5), (10, 5), (11, 5), (12, 5), (13, 5), (14, 5),
            (8, 6), (9, 6), (10, 6), (11, 6), (12, 6), (13, 6),
            (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7), (12, 7),
            (5, 8), (6, 8), (7, 8), (8, 8), (9, 8), (10, 8), (11, 8),
            (3, 9 + tailShift), (5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (10, 9), (11, 9),
            (2, 10 + tailShift), (3, 10 + tailShift), (4, 10), (5, 10), (6, 10), (7, 10), (8, 10), (9, 10), (10, 10),
            (1, 11 + tailShift), (2, 11 + tailShift), (3, 11 + tailShift), (4, 11), (5, 11), (6, 11), (7, 11), (8, 11), (9, 11),
            (1, 12 + tailShift), (2, 12 + tailShift), (3, 12 + tailShift), (4, 12), (5, 12), (6, 12), (7, 12), (8, 12),
            (2, 13 + tailShift), (3, 13 + tailShift), (4, 13), (5, 13), (6, 13), (7, 13),
            (3, 14 + tailShift), (4, 14), (5, 14), (6, 14),
            (6, 15), (7, 15), (8, 15), (9, 15),
            (7, 16), (8, 16), (9, 16),
            (7, 17 + legShift), (8, 17), (10, 17), (11, 17 + legShift),
            (7, 18 + legShift), (8, 18), (10, 18), (11, 18 + legShift),
            (7, 19 + legShift), (8, 19), (10, 19), (11, 19 + legShift),
            (12, 8), (12, 9), (13, 9)
        ]
    }

    private func dinoShadowPixels(legShift: CGFloat, tailShift: CGFloat) -> [(CGFloat, CGFloat)] {
        dinoPixels(legShift: legShift, tailShift: tailShift).map { ($0.0 + 0.65, $0.1 + 0.65) }
    }

    private var dinoEyePixels: [(CGFloat, CGFloat)] {
        [(11, 3)]
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
