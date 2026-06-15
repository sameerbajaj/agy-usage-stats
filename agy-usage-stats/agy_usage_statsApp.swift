//
//  agy_usage_statsApp.swift
//  agy-usage-stats
//
//  Created by Sameer Bajaj on 6/14/26.
//

import SwiftUI
import AppKit
import Combine

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
    @State private var refreshTrigger = false

    private var statusColor: Color {
        var fractions: [Double] = []
        if let gf = viewModel.geminiUsageFraction {
            fractions.append(gf)
        }
        if let cf = viewModel.claudeUsageFraction {
            fractions.append(cf)
        }
        
        if let minFraction = fractions.min() {
            if minFraction > 0.5 {
                return Color(red: 0.15, green: 0.85, blue: 0.55) // Premium emerald green
            } else if minFraction > 0.2 {
                return Color(red: 1.0, green: 0.60, blue: 0.15) // Premium warm orange
            } else {
                return Color(red: 1.0, green: 0.35, blue: 0.35) // Premium ruby red
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
        guard viewModel.stats.quotaInfo != nil else {
            return "no session"
        }
        
        var parts: [String] = []
        if let gf = viewModel.geminiUsageFraction {
            parts.append(String(format: "G:%.0f%%", gf * 100))
        }
        if let cf = viewModel.claudeUsageFraction {
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
                    activeUsageFraction: viewModel.selectedModelUsageFraction,
                    geminiUsageFraction: viewModel.geminiUsageFraction,
                    claudeUsageFraction: viewModel.claudeUsageFraction,
                    activeFillFraction: viewModel.selectedModelCircleFillFraction,
                    geminiFillFraction: viewModel.geminiCircleFillFraction,
                    claudeFillFraction: viewModel.claudeCircleFillFraction
                ))
            }

            if let text = textToDisplay {
                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .id(refreshTrigger)
        .onAppear {
            // Trigger stats loading on label launch
            viewModel.setup()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            refreshTrigger.toggle()
        }
    }
}

// MARK: - Menu Bar Drawing

/// Draw a custom upward floating arrow/chevron (defying gravity) above a ground line using CoreGraphics.
/// The chevron levitates higher and displays energy lines under it as usage/queries increase.
/// If showUsage is true, it draws a circular quota track/arc and percentage text for the selected model option.
private func makeAntigravityImage(
    queriesToday: Int,
    litColor: Color,
    showUsage: Bool = false,
    selectedModelForIcon: IconModelSelection = .active,
    activeUsageFraction: Double? = nil,
    geminiUsageFraction: Double? = nil,
    claudeUsageFraction: Double? = nil,
    activeFillFraction: Double? = nil,
    geminiFillFraction: Double? = nil,
    claudeFillFraction: Double? = nil
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
            if let fraction = activeUsageFraction {
                pctText = String(format: "%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: litNS]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .gemini:
            if let fraction = geminiUsageFraction {
                pctText = String(format: "G:%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: geminiColor]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .claude:
            if let fraction = claudeUsageFraction {
                pctText = String(format: "C:%.0f%%", fraction * 100)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
                textAttributes = [.font: font, .foregroundColor: claudeColor]
                textSize = pctText.size(withAttributes: textAttributes)
            }
        case .both:
            let gf = geminiUsageFraction ?? 1.0
            let cf = claudeUsageFraction ?? 1.0
            pctText = String(format: "G:%.0f%% C:%.0f%%", gf * 100, cf * 100)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
            textAttributes = [.font: font, .foregroundColor: NSColor.textColor]
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
                if let fraction = activeFillFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: litNS)
                }
            case .gemini:
                if let fraction = geminiFillFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: geminiColor)
                }
            case .claude:
                if let fraction = claudeFillFraction {
                    drawGauge(center: NSPoint(x: 8.0, y: 7.0), radius: 5.2, fraction: fraction, strokeColor: claudeColor)
                }
            case .both:
                let gf = geminiFillFraction ?? 1.0
                let cf = claudeFillFraction ?? 1.0
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
    trackPath.lineWidth = 1.2
    NSColor.labelColor.withAlphaComponent(0.15).setStroke()
    trackPath.stroke()
    
    // Draw Progress Arc
    let progressPath = NSBezierPath()
    let startAngle: CGFloat = 90.0
    let endAngle: CGFloat = 90.0 - CGFloat(fraction * 360.0)
    progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    progressPath.lineWidth = 1.6
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
    chevronPath.lineWidth = chevronSize > 2.0 ? 1.2 : 1.0
    chevronPath.lineCapStyle = .round
    chevronPath.lineJoinStyle = .round
    strokeColor.setStroke()
    chevronPath.stroke()
}

