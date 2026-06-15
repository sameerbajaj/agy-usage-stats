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
        let fillOpacity = isHovered ? (isDark ? 0.07 : 0.05) : (isDark ? 0.035 : 0.02)
        let strokeOpacity = isHovered ? (isDark ? 0.12 : 0.08) : (isDark ? 0.06 : 0.04)
        
        return content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered && accentColor != nil
                            ? accentColor!.opacity(isDark ? 0.25 : 0.4)
                            : Color.primary.opacity(strokeOpacity),
                        lineWidth: 0.75
                    )
            )
    }
}

extension View {
    public func premiumCardStyle(isHovered: Bool = false, accentColor: Color? = nil) -> some View {
        modifier(PremiumCardModifier(isHovered: isHovered, accentColor: accentColor))
    }
}
