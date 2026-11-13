//
//  MenuBarIconFactory.swift
//  Pupil
//
//  Generates pixel-perfect, resolution-independent vector template icons for NSStatusBar.
//  Guaranteed to render sharp in light/dark mode and never fails on missing SF Symbols.
//

import AppKit

public enum MenuBarIconFactory {
    public static func makeStatusIcon(state: SecurityState, isGazeActive: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()

            let center = CGPoint(x: rect.midX, y: rect.midY)

            switch state {
            case .disarmed, .arming, .armed:
                drawAlternatingApertureIcon(in: context, center: center, showCenterPupil: state == .armed && isGazeActive)

            case .tamperPending, .alarm:
                // Sleek warning shield with alert mark
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x, y: center.y + 7.5))
                path.addLine(to: CGPoint(x: center.x + 6.5, y: center.y + 4.0))
                path.addLine(to: CGPoint(x: center.x + 4.5, y: center.y - 6.5))
                path.addLine(to: CGPoint(x: center.x, y: center.y - 8.0))
                path.addLine(to: CGPoint(x: center.x - 4.5, y: center.y - 6.5))
                path.addLine(to: CGPoint(x: center.x - 6.5, y: center.y + 4.0))
                path.closeSubpath()

                context.addPath(path)
                context.setLineWidth(1.3)
                context.setStrokeColor(NSColor.black.cgColor)
                context.strokePath()

                // Exclamation bar and dot
                let barRect = CGRect(x: center.x - 0.7, y: center.y - 1.5, width: 1.4, height: 4.5)
                context.addRect(barRect)
                context.addEllipse(in: CGRect(x: center.x - 0.9, y: center.y - 4.5, width: 1.8, height: 1.8))
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
            }

            context.restoreGState()
            return true
        }

        image.isTemplate = true
        return image
    }

    /// Draws the AppIcon-inspired eccentric 3-circle aperture alternating:
    /// outer (opaque/white) -> middle (clear cutout) -> inner (opaque/white).
    private static func drawAlternatingApertureIcon(
        in context: CGContext,
        center: CGPoint,
        showCenterPupil: Bool
    ) {
        // 1. Outer circle (white in template dark mode) with lower-right wedge cutout
        let outerCenter = CGPoint(x: center.x - 0.4, y: center.y - 0.2)
        let outerRadius: CGFloat = 7.3
        let outerPath = CGMutablePath()
        outerPath.move(to: outerCenter)
        outerPath.addArc(
            center: outerCenter,
            radius: outerRadius,
            startAngle: 0.0,
            endAngle: -.pi * 0.28,
            clockwise: false
        )
        outerPath.closeSubpath()
        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(outerPath)
        context.fillPath()

        // 2. Middle circle (clear cutout) shifted slightly upper-right
        let midCenter = CGPoint(x: center.x + 0.9, y: center.y + 0.8)
        let midRadius: CGFloat = 4.9
        let midRect = CGRect(
            x: midCenter.x - midRadius,
            y: midCenter.y - midRadius,
            width: midRadius * 2,
            height: midRadius * 2
        )
        context.setBlendMode(.clear)
        context.fillEllipse(in: midRect)

        // 3. Inner circle (white in template dark mode) shifted further upper-right with upper-right wedge cutout
        let innerCenter = CGPoint(x: center.x + 1.7, y: center.y + 1.4)
        let innerRadius: CGFloat = 3.0
        let innerPath = CGMutablePath()
        innerPath.move(to: innerCenter)
        innerPath.addArc(
            center: innerCenter,
            radius: innerRadius,
            startAngle: .pi * 0.28,
            endAngle: .pi * 0.02,
            clockwise: false
        )
        innerPath.closeSubpath()
        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(innerPath)
        context.fillPath()

        if showCenterPupil {
            let dotRadius: CGFloat = 0.85
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(
                x: innerCenter.x - dotRadius,
                y: innerCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }
    }
}
