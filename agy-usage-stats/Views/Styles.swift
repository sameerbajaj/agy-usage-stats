//
//  Styles.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

// MARK: - Premium Card Styling
public struct PremiumCardModifier: ViewModifier {
    public var isHovered: Bool
    public var accentColor: Color?
    
    public init(isHovered: Bool = false, accentColor: Color? = nil) {
        self.isHovered = isHovered
        self.accentColor = accentColor
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered && accentColor != nil
                            ? accentColor!.opacity(0.2)
                            : Color.white.opacity(0.04),
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
