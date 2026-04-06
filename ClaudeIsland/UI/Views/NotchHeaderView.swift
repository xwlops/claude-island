//
//  NotchHeaderView.swift
//  ClaudeIsland
//
//  Header bar for the dynamic island
//

import Combine
import SwiftUI

enum NotchDinoPose {
    case waiting
    case running
    case jumping
    case ducking
    case crashed
}

private enum ClaudeState {
    case idle
    case thinking
    case alert
    case bashful
    case crashed
}

private struct SpringState {
    var position: CGFloat = 0
    var velocity: CGFloat = 0

    mutating func update(target: CGFloat, stiffness: CGFloat, damping: CGFloat) {
        let force = (target - position) * stiffness
        velocity = (velocity + force) * damping
        position += velocity
    }
}

private struct NotchJellyPetV2: View {
    let size: CGFloat
    let state: ClaudeState
    let gradient: Gradient
    var animate: Bool = true

    @State private var breathPhase: CGFloat = 0
    @State private var wobble = SpringState()
    @State private var wobbleTarget: CGFloat = 0
    @State private var antennaeWobble = SpringState()
    @State private var blinkProgress: CGFloat = 0
    @State private var elapsed: TimeInterval = 0
    @State private var nextBlink: TimeInterval = Double.random(in: 2.5...5.0)

    private let ticker = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let poseShift: CGFloat = state == .alert ? -size * 0.028 : 0
            let squash: CGFloat = state == .bashful ? 0.92 : (state == .crashed ? 0.88 : 1.0)
            let antennaDrop: CGFloat = state == .crashed ? size * 0.05 : 0
            let cx = w / 2
            let cy = h / 2 + size * 0.06 + poseShift

            let breath = sin(breathPhase) * (state == .alert ? 0.018 : 0.014)
            let wob = wobble.position
            let antWob = antennaeWobble.position

            let bodyW = w * 0.68
            let bodyH = h * 0.60 * (1.0 + breath) * squash

            let topW = bodyW * (state == .bashful ? 0.79 : 0.82)
            let bottomW = bodyW * (state == .bashful ? 1.05 : 1.00)
            let top = cy - bodyH * 0.50
            let bottom = cy + bodyH * 0.50
            let topL = cx - topW / 2 + wob
            let topR = cx + topW / 2 + wob
            let botL = cx - bottomW / 2 + wob * 0.6
            let botR = cx + bottomW / 2 + wob * 0.6
            let r: CGFloat = bodyH * 0.38

            var blob = Path()
            blob.move(to: CGPoint(x: topL + r, y: top))
            blob.addLine(to: CGPoint(x: topR - r, y: top))
            blob.addQuadCurve(
                to: CGPoint(x: topR, y: top + r),
                control: CGPoint(x: topR, y: top)
            )
            blob.addLine(to: CGPoint(x: botR, y: bottom - r * 0.6))
            blob.addQuadCurve(
                to: CGPoint(x: botR - r * 0.7, y: bottom),
                control: CGPoint(x: botR, y: bottom)
            )
            blob.addLine(to: CGPoint(x: botL + r * 0.7, y: bottom))
            blob.addQuadCurve(
                to: CGPoint(x: botL, y: bottom - r * 0.6),
                control: CGPoint(x: botL, y: bottom)
            )
            blob.addLine(to: CGPoint(x: topL, y: top + r))
            blob.addQuadCurve(
                to: CGPoint(x: topL + r, y: top),
                control: CGPoint(x: topL, y: top)
            )
            blob.closeSubpath()

            context.fill(
                blob,
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: cx - bodyW * 0.08 + wob * 0.2, y: cy - bodyH * 0.25),
                    startRadius: 1,
                    endRadius: bodyW * 0.85
                )
            )

            if state != .bashful {
                let antBase = CGPoint(x: cx + wob, y: top + 1)
                let antTip = CGPoint(x: cx + antWob * 2.5 + wob * 0.3, y: top - size * 0.22 + antennaDrop)
                let antBall = CGPoint(x: antTip.x, y: antTip.y - size * 0.055)

                var antStalk = Path()
                antStalk.move(to: antBase)
                antStalk.addQuadCurve(
                    to: antTip,
                    control: CGPoint(x: cx + antWob * 1.2 + wob * 0.2, y: top - size * 0.10 + antennaDrop * 0.7)
                )
                context.stroke(
                    antStalk,
                    with: .color(gradient.stops.last?.color.opacity(state == .crashed ? 0.45 : 0.85) ?? .teal),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: antBall.x - size * 0.045,
                        y: antBall.y - size * 0.045,
                        width: size * 0.09,
                        height: size * 0.09
                    )),
                    with: .color(gradient.stops.last?.color.opacity(state == .crashed ? 0.72 : 1.0) ?? .teal)
                )
            }

            context.fill(
                Path(ellipseIn: CGRect(
                    x: cx - bodyW * 0.26 - wob * 0.35,
                    y: cy - bodyH * 0.30,
                    width: bodyW * 0.17,
                    height: bodyW * 0.17
                )),
                with: .color(.white.opacity(state == .crashed ? 0.22 : 0.40))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: cx - bodyW * 0.36 - wob * 0.25,
                    y: cy - bodyH * 0.16,
                    width: bodyW * 0.07,
                    height: bodyW * 0.07
                )),
                with: .color(.white.opacity(state == .crashed ? 0.12 : 0.24))
            )

            let eyeY = cy - bodyH * 0.06 + (state == .bashful ? size * 0.01 : 0)
            let eyeEL = cx - bodyW * 0.16 + wob * 0.55
            let eyeER = cx + bodyW * 0.14 + wob * 0.55
            let eyeOpenL: CGFloat = state == .alert ? 4.7 : 4.2
            let eyeOpenR: CGFloat = state == .alert ? 4.0 : 3.6
            let eyeH = max(0.15, 1.0 - blinkProgress)

            context.fill(
                Path(ellipseIn: CGRect(
                    x: eyeEL - eyeOpenL / 2,
                    y: eyeY - eyeOpenL * eyeH / 2,
                    width: eyeOpenL,
                    height: eyeOpenL * eyeH
                )),
                with: .color(.black.opacity(state == .crashed ? 0.55 : 0.84))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: eyeER - eyeOpenR / 2,
                    y: eyeY - eyeOpenR * eyeH / 2,
                    width: eyeOpenR,
                    height: eyeOpenR * eyeH
                )),
                with: .color(.black.opacity(state == .crashed ? 0.55 : 0.84))
            )

            let mouthCX = cx - 1.2 + wob * 0.45
            let mouthY = eyeY + 7.5
            let mouthCurve: CGFloat = switch state {
            case .thinking: 1.0
            case .alert: 4.8
            case .bashful: 2.8
            case .crashed: -2.6
            case .idle: 3.8
            }

            var mouth = Path()
            mouth.move(to: CGPoint(x: mouthCX - 5.5, y: mouthY))
            mouth.addQuadCurve(
                to: CGPoint(x: mouthCX + 5.5, y: mouthY),
                control: CGPoint(x: mouthCX, y: mouthY + mouthCurve)
            )
            context.stroke(
                mouth,
                with: .color(.black.opacity(state == .crashed ? 0.5 : 0.72)),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
            )
        }
        .frame(width: size * 1.4, height: size * 1.32)
        .onReceive(ticker) { _ in
            guard animate else { return }

            breathPhase += state == .alert ? 0.016 : 0.010

            wobble.update(target: wobbleTarget, stiffness: 0.09, damping: 0.74)
            antennaeWobble.update(target: wobble.position * 0.6, stiffness: 0.05, damping: 0.80)

            elapsed += 0.016
            if elapsed >= nextBlink {
                elapsed = 0
                nextBlink = Double.random(in: 2.2...5.8)

                withAnimation(.easeInOut(duration: 0.07)) { blinkProgress = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                    withAnimation(.easeInOut(duration: 0.09)) { blinkProgress = 0 }
                }

                let range: ClosedRange<CGFloat> = state == .alert ? -3.0...3.0 : -2.2...2.2
                wobbleTarget = CGFloat.random(in: range)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    wobbleTarget = 0
                }
            }
        }
    }
}

struct NotchDragonIcon: View {
    let size: CGFloat
    let color: Color
    let pose: NotchDinoPose
    var animate: Bool = false

    init(
        size: CGFloat = 16,
        color: Color = Color.white.opacity(0.85),
        pose: NotchDinoPose = .running,
        animate: Bool = false
    ) {
        self.size = size
        self.color = color
        self.pose = pose
        self.animate = animate
    }

    var body: some View {
        NotchJellyPetV2(
            size: size,
            state: claudeState,
            gradient: jellyGradient,
            animate: animate
        )
        .frame(width: frameWidth, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private var frameWidth: CGFloat {
        switch pose {
        case .jumping:
            return size * 1.22
        case .ducking:
            return size * 1.16
        default:
            return size * 1.18
        }
    }

    private var claudeState: ClaudeState {
        switch pose {
        case .waiting:
            return .idle
        case .running:
            return .thinking
        case .jumping:
            return .alert
        case .ducking:
            return .bashful
        case .crashed:
            return .crashed
        }
    }

    private var jellyGradient: Gradient {
        Gradient(stops: [
            .init(color: color.opacity(0.98), location: 0.0),
            .init(color: color.opacity(0.82), location: 0.58),
            .init(color: color.opacity(0.52), location: 1.0)
        ])
    }

    private var accessibilityLabel: Text {
        switch pose {
        case .waiting:
            return Text("Idle mascot")
        case .running:
            return Text("Working mascot")
        case .jumping:
            return Text("Attention mascot")
        case .ducking:
            return Text("Approval mascot")
        case .crashed:
            return Text("Ended mascot")
        }
    }
}

struct ClaudeCrabIcon: View {
    let size: CGFloat
    var animateLegs: Bool = false

    var body: some View {
        NotchDragonIcon(size: size, pose: .running, animate: animateLegs)
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
