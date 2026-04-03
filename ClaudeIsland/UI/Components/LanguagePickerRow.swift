//
//  LanguagePickerRow.swift
//  ClaudeIsland
//
//  Language selection picker for settings menu
//

import SwiftUI

struct LanguagePickerRow: View {
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var selectedLanguage: AppLanguage = AppSettings.appLanguage

    var body: some View {
        VStack(spacing: 0) {
            // Main row - shows current selection
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Language")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(selectedLanguage.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded language list
            if isExpanded {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            LanguageOptionRow(
                                language: language,
                                isSelected: selectedLanguage == language
                            ) {
                                selectedLanguage = language
                                AppSettings.appLanguage = language
                            }
                        }
                    }
                }
                .frame(maxHeight: CGFloat(min(AppLanguage.allCases.count, 4)) * 32)
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
        .onAppear {
            selectedLanguage = AppSettings.appLanguage
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - Language Option Row

private struct LanguageOptionRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? TerminalColors.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

                Text(language.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TerminalColors.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
