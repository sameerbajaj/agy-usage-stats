//
//  agy_usage_statsApp.swift
//  agy-usage-stats
//
//  Created by Sameer Bajaj on 6/14/26.
//

import SwiftUI
import AppKit

@main
struct agy_usage_statsApp: App {
    @State private var viewModel = AgyStatsViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let viewModel: AgyStatsViewModel

    private var statusColor: Color {
        if let quota = viewModel.stats.quotaInfo {
            let fractions = quota.groups.flatMap { $0.buckets.compactMap { $0.remainingFraction } }
            if let minFraction = fractions.min() {
                if minFraction > 0.5 {
                    return .green
                } else if minFraction > 0.2 {
                    return .orange
                } else {
                    return .red
                }
            }
        }
        if viewModel.stats.queriesToday > 0 {
            return Color(red: 0.65, green: 0.45, blue: 1.0) // Vibrant purple
        } else {
            return .primary.opacity(0.65) // Dim grey
        }
    }

    private var showIcon: Bool {
        switch viewModel.menuBarDisplayMode {
        case .iconOnly, .iconAndQuotas, .both:
            return true
        case .quotas, .queriesToday:
            return false
        }
    }

    private var textToDisplay: String? {
        switch viewModel.menuBarDisplayMode {
        case .iconOnly:
            return nil
        case .quotas, .iconAndQuotas:
            return quotaText
        case .queriesToday, .both:
            return "\(viewModel.stats.queriesToday)q"
        }
    }

    private var quotaText: String {
        guard let quota = viewModel.stats.quotaInfo else {
            return "no session"
        }
        
        var geminiFraction: Double? = nil
        var claudeFraction: Double? = nil
        
        for group in quota.groups {
            let name = group.displayName.lowercased()
            let minBucketFraction = group.buckets.compactMap { $0.remainingFraction }.min()
            if name.contains("gemini") {
                geminiFraction = minBucketFraction
            } else if name.contains("claude") || name.contains("gpt") {
                claudeFraction = minBucketFraction
            }
        }
        
        var parts: [String] = []
        if let gf = geminiFraction {
            parts.append(String(format: "G:%.0f%%", gf * 100))
        }
        if let cf = claudeFraction {
            parts.append(String(format: "C:%.0f%%", cf * 100))
        }
        
        if parts.isEmpty {
            return "100%"
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(nsImage: makeAntigravityImage(queriesToday: viewModel.stats.queriesToday, litColor: statusColor))
            }

            if let text = textToDisplay {
                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .onAppear {
            // Trigger stats loading on label launch
            viewModel.setup()
        }
    }
}

/// Draw a custom upward floating arrow/chevron (defying gravity) above a ground line using CoreGraphics.
/// The chevron levitates higher and displays energy lines under it as usage/queries increase.
private func makeAntigravityImage(queriesToday: Int, litColor: Color) -> NSImage {
    let w: CGFloat = 16
    let h: CGFloat = 14
    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let litNS = NSColor(litColor)
        let isLit = queriesToday > 0
        
        // 1. Calculate dynamic float offset based on usage stats
        // Starts resting at 0, floats up to 4.5 points
        let maxFloat: CGFloat = 4.5
        let floatOffset: CGFloat
        if queriesToday == 0 {
            floatOffset = 0
        } else if queriesToday < 5 {
            floatOffset = 1.5
        } else if queriesToday < 15 {
            floatOffset = 3.0
        } else {
            floatOffset = maxFloat
        }
        
        // 2. Draw ground line at the bottom
        let groundRect = NSRect(x: 2.0, y: 1.5, width: 12.0, height: 1.2)
        let groundPath = NSBezierPath(roundedRect: groundRect, xRadius: 0.6, yRadius: 0.6)
        NSColor.labelColor.withAlphaComponent(isLit ? 0.15 : 0.3).setFill()
        groundPath.fill()
        
        // 3. Draw energy waves underneath the floating icon (if active)
        if isLit {
            let energyPath = NSBezierPath()
            
            // Draw 1 or 2 tiny glowing dashes/dots based on activity level
            if queriesToday >= 15 {
                // High activity: 2 waves
                energyPath.move(to: NSPoint(x: 5.5, y: 4.2))
                energyPath.line(to: NSPoint(x: 10.5, y: 4.2))
                energyPath.move(to: NSPoint(x: 6.5, y: 2.8))
                energyPath.line(to: NSPoint(x: 9.5, y: 2.8))
            } else if queriesToday >= 5 {
                // Medium activity: 1 wave
                energyPath.move(to: NSPoint(x: 6.0, y: 3.5))
                energyPath.line(to: NSPoint(x: 10.0, y: 3.5))
            } else {
                // Low activity: 1 small dot
                energyPath.move(to: NSPoint(x: 7.5, y: 3.0))
                energyPath.line(to: NSPoint(x: 8.5, y: 3.0))
            }
            
            energyPath.lineWidth = 0.8
            energyPath.lineCapStyle = .round
            litNS.withAlphaComponent(0.5).setStroke()
            energyPath.stroke()
        }
        
        // 4. Draw the Antigravity "A" chevron (Outer Chevron)
        let outerChevron = NSBezierPath()
        let apexY = 7.2 + floatOffset
        let wingY = 3.8 + floatOffset
        
        outerChevron.move(to: NSPoint(x: 3.5, y: wingY))
        outerChevron.line(to: NSPoint(x: 8.0, y: apexY))
        outerChevron.line(to: NSPoint(x: 12.5, y: wingY))
        
        outerChevron.lineWidth = 1.6
        outerChevron.lineCapStyle = .round
        outerChevron.lineJoinStyle = .round
        
        litNS.setStroke()
        outerChevron.stroke()
        
        // 5. Draw the inner crossbar/chevron of the "A"
        // It glows brighter (higher opacity) as statistics increase
        if isLit {
            let innerChevron = NSBezierPath()
            let innerApexY = apexY - 2.2
            let innerWingY = wingY - 0.2
            
            innerChevron.move(to: NSPoint(x: 5.5, y: innerWingY))
            innerChevron.line(to: NSPoint(x: 8.0, y: innerApexY))
            innerChevron.line(to: NSPoint(x: 10.5, y: innerWingY))
            
            innerChevron.lineWidth = 1.0
            innerChevron.lineCapStyle = .round
            innerChevron.lineJoinStyle = .round
            
            let alpha = queriesToday >= 15 ? 1.0 : 0.65
            litNS.withAlphaComponent(alpha).setStroke()
            innerChevron.stroke()
        }
        
        return true
    }
    img.isTemplate = false
    return img
}

