//
//  Styles.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

public struct PremiumCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var isHovered: Bool
    public var accentColor: Color?
    
    public init(isHovered: Bool = false, accentColor: Color? = nil) {
        self.isHovered = isHovered
        self.accentColor = accentColor
    }
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        
        return content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark 
                          ? Color.primary.opacity(isHovered ? 0.07 : 0.035) 
                          : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered && accentColor != nil
                            ? accentColor!.opacity(isDark ? 0.25 : 0.35)
                            : (isDark ? Color.primary.opacity(isHovered ? 0.12 : 0.06) : Color.black.opacity(isHovered ? 0.10 : 0.05)),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: isDark ? Color.clear : Color.black.opacity(isHovered ? 0.04 : 0.02), radius: isHovered ? 3 : 1.5, x: 0, y: 1)
    }
}

extension View {
    public func premiumCardStyle(isHovered: Bool = false, accentColor: Color? = nil) -> some View {
        modifier(PremiumCardModifier(isHovered: isHovered, accentColor: accentColor))
    }
}

public extension Color {
    static func gemini(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.75, green: 0.6, blue: 1.0)      // Pastel Lavender
            : Color(red: 0.40, green: 0.20, blue: 0.80)    // Legible Deep Indigo
    }
    
    static func claude(isDark: Bool) -> Color {
        isDark
            ? Color(red: 1.0, green: 0.65, blue: 0.35)     // Light Pastel Orange
            : Color(red: 0.85, green: 0.30, blue: 0.02)    // Legible Deep Warm Orange
    }
    
    static func costGreen(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.25, green: 0.85, blue: 0.45)     // Pastel Green
            : Color(red: 0.08, green: 0.52, blue: 0.22)     // Deeper, high-contrast Forest Green
    }
}
