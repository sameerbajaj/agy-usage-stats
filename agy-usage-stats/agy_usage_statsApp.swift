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
        if viewModel.stats.queriesToday > 0 {
            return Color(red: 0.65, green: 0.45, blue: 1.0) // Vibrant purple
        } else {
            return .primary.opacity(0.65) // Dim grey
        }
    }

    private var showIcon: Bool {
        viewModel.menuBarDisplayMode != .queriesToday
    }

    private var showText: Bool {
        viewModel.menuBarDisplayMode != .iconOnly
    }

    var body: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(nsImage: makeAntigravityImage(litColor: statusColor))
            }

            if showText {
                Text("\(viewModel.stats.queriesToday)q")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .onAppear {
            // Trigger stats loading on label launch
            viewModel.setup()
        }
    }
}

/// Draw a custom upward floating arrow (defying gravity) above a ground line using CoreGraphics.
private func makeAntigravityImage(litColor: Color) -> NSImage {
    let w: CGFloat = 14
    let h: CGFloat = 12
    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let litNS = NSColor(litColor)
        
        // Ground line at the bottom
        let groundRect = NSRect(x: 2, y: 1.2, width: 10, height: 1.3)
        let groundPath = NSBezierPath(roundedRect: groundRect, xRadius: 0.6, yRadius: 0.6)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        groundPath.fill()
        
        // Upward arrow defying gravity:
        let path = NSBezierPath()
        
        // Arrow shaft
        path.move(to: NSPoint(x: 7, y: 3.5))
        path.line(to: NSPoint(x: 7, y: 9.5))
        
        // Arrow head
        path.move(to: NSPoint(x: 4.5, y: 7.0))
        path.line(to: NSPoint(x: 7, y: 9.5))
        path.line(to: NSPoint(x: 9.5, y: 7.0))
        
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        litNS.setStroke()
        path.stroke()
        return true
    }
    img.isTemplate = false
    return img
}
