import SwiftUI

// Cursor-style buttons. Ghost is the default; primary is reserved for the main
// action on a surface. See design.md section 2.3.

/// Secondary / ghost button: subtle wash fill, hairline border, primary text.
public struct CursorGhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body13)
                .foregroundStyle(CursorTheme.textPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusMD)
                        .fill(configuration.isPressed ? CursorTheme.selectActive : CursorTheme.surfaceWash)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusMD)
                        .stroke(CursorTheme.borderSubtle, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: CursorTheme.radiusMD))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Primary button: filled accent blue with near-black text.
public struct CursorPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body13.weight(.medium))
                .foregroundStyle(CursorTheme.onAccent)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusMD)
                        .fill(configuration.isPressed ? CursorTheme.blueHover : CursorTheme.blue)
                )
                .contentShape(RoundedRectangle(cornerRadius: CursorTheme.radiusMD))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
