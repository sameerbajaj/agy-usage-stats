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
        var parts: [String] = []
        
        switch viewModel.menuBarDisplayMode {
        case .iconOnly:
            break
        case .quotas, .iconAndQuotas:
            parts.append(quotaText)
        case .queriesToday, .both:
            parts.append("\(viewModel.stats.queriesToday)q")
        }
        
        if viewModel.showWeeklyLimitAndReset, let weeklyInfo = viewModel.weeklyLimitInfo {
            var weekStr = ""
            if let fraction = weeklyInfo.remainingFraction {
                weekStr += String(format: "W:%.0f%%", fraction * 100)
            } else {
                weekStr += "W:100%"
            }
            if let resetTime = viewModel.formattedWeeklyResetTime {
                weekStr += " (\(resetTime))"
            }
            parts.append(weekStr)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
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
                Image(nsImage: makeAntigravityImage(
                    queriesToday: viewModel.stats.queriesToday,
                    litColor: statusColor,
                    showUsage: viewModel.showModelUsageInIcon,
                    selectedModelForIcon: viewModel.selectedModelForIcon,
                    activeFraction: viewModel.selectedModelRemainingFraction,
                    geminiFraction: viewModel.geminiRemainingFraction,
                    claudeFraction: viewModel.claudeRemainingFraction
                ))
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
/// If showUsage is true, it draws a circular quota track/arc and percentage text for the selected model option.
private func makeAntigravityImage(
    queriesToday: Int,
    litColor: Color,
    showUsage: Bool = false,
    selectedModelForIcon: IconModelSelection = .active,
    activeFraction: Double? = nil,
    geminiFraction: Double? = nil,
    claudeFraction: Double? = nil
) -> NSImage {
    let h: CGFloat = 14
    let litNS = NSColor(litColor)
    
    let geminiColor = NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1.0)
    let claudeColor = NSColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
    
    // We compute text attributes and width beforehand so the NSImage has the correct size
    var pctText = ""
    var textAttributes: [NSAttributedString.Key: Any] = [:]
    var textSize = NSSize.zero
    
    if showUsage {
        switch selectedModelForIcon {
        case .active:
            if let fraction = activeFraction {
                pctText = String(format: "%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: litNS]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .gemini:
            if let fraction = geminiFraction {
                pctText = String(format: "G:%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: geminiColor]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .claude:
            if let fraction = claudeFraction {
                pctText = String(format: "C:%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: claudeColor]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .both:
            let gf = geminiFraction ?? 1.0
            let cf = claudeFraction ?? 1.0
            pctText = String(format: "G:%.0f%% C:%.0f%%", gf * 100, cf * 100)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
            textAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
            textSize = pctText.size(withAttributes: textAttributes)
        }
    }
    
    let w: CGFloat
    if !pctText.isEmpty {
        if selectedModelForIcon == .both {
            w = 26.0 + textSize.width + 2.0
        } else {
            w = 18.0 + textSize.width + 2.0
        }
    } else {
        w = 16.0
    }
    
    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let isLit = queriesToday > 0
        
        if !pctText.isEmpty {
            switch selectedModelForIcon {
            case .active:
                if let fraction = activeFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: litNS)
                }
            case .gemini:
                if let fraction = geminiFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: geminiColor)
                }
            case .claude:
                if let fraction = claudeFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: claudeColor)
                }
            case .both:
                let gf = geminiFraction ?? 1.0
                let cf = claudeFraction ?? 1.0
                drawGauge(center: NSPoint(x: 6.0, y: 7.0), radius: 4.2, fraction: gf, strokeColor: geminiColor, chevronSize: 2.0)
                drawGauge(center: NSPoint(x: 16.0, y: 7.0), radius: 4.2, fraction: cf, strokeColor: claudeColor, chevronSize: 2.0)
            }
            
            // Draw text
            let textX: CGFloat = (selectedModelForIcon == .both) ? 24.0 : 18.0
            let textY = (14.0 - textSize.height) / 2.0 + 0.5
            pctText.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttributes)
        } else {
            // Original Antigravity chevron drawing code
            // 1. Calculate dynamic float offset based on usage stats
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
                if queriesToday >= 15 {
                    energyPath.move(to: NSPoint(x: 5.5, y: 4.2))
                    energyPath.line(to: NSPoint(x: 10.5, y: 4.2))
                    energyPath.move(to: NSPoint(x: 6.5, y: 2.8))
                    energyPath.line(to: NSPoint(x: 9.5, y: 2.8))
                } else if queriesToday >= 5 {
                    energyPath.move(to: NSPoint(x: 6.0, y: 3.5))
                    energyPath.line(to: NSPoint(x: 10.0, y: 3.5))
                } else {
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
        }
        
        return true
    }
    img.isTemplate = false
    return img
}

private func drawGauge(center: NSPoint, radius: CGFloat, fraction: Double, strokeColor: NSColor, chevronSize: CGFloat = 2.5) {
    // Draw Background Track
    let trackPath = NSBezierPath()
    trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    trackPath.lineWidth = 1.0
    NSColor.labelColor.withAlphaComponent(0.12).setStroke()
    trackPath.stroke()
    
    // Draw Progress Arc
    let progressPath = NSBezierPath()
    let startAngle: CGFloat = 90.0
    let endAngle: CGFloat = 90.0 - CGFloat(fraction * 360.0)
    progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    progressPath.lineWidth = 1.2
    progressPath.lineCapStyle = .round
    strokeColor.setStroke()
    progressPath.stroke()
    
    // Draw Tiny Chevron inside center
    let chevronPath = NSBezierPath()
    let halfSize = chevronSize
    let apexY = center.y + (halfSize * 0.7)
    let wingY = center.y - (halfSize * 0.6)
    chevronPath.move(to: NSPoint(x: center.x - halfSize, y: wingY))
    chevronPath.line(to: NSPoint(x: center.x, y: apexY))
    chevronPath.line(to: NSPoint(x: center.x + halfSize, y: wingY))
    chevronPath.lineWidth = 1.0
    chevronPath.lineCapStyle = .round
    chevronPath.lineJoinStyle = .round
    strokeColor.setStroke()
    chevronPath.stroke()
}

