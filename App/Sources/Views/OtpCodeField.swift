import SwiftUI

/// 共用 6 格 OTP 輸入元件（樣式對齊 design/Redeem.dc.html）。
/// `VoucherView`（加碼券出示）使用本元件。底層蓋一個透明的 `TextField` 承接鍵盤輸入與 focus，
/// 上層畫出對齊設計稿的方格樣式；只允許數字、最多 6 碼。
struct OtpCodeField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding
    private let length = 6

    var body: some View {
        ZStack {
            HStack(spacing: 9) {
                ForEach(0..<length, id: \.self) { index in
                    OtpDigitBox(character: character(at: index))
                }
            }

            TextField("", text: $code)
                // 截圖用 UI 測試以此 id 定位 OTP 輸入框（見 App/UITests/ScreenshotTests.swift）。
                .accessibilityIdentifier("otpCodeField")
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .onChange(of: code) { newValue in
                    let digitsOnly = newValue.filter(\.isNumber)
                    code = String(digitsOnly.prefix(length))
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        let charIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[charIndex])
    }
}

struct OtpDigitBox: View {
    let character: String

    var body: some View {
        Text(character)
            .font(Theme.displayFont(20, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(character.isEmpty ? Theme.Colors.background : Theme.Colors.card2)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(character.isEmpty ? Theme.Colors.line2 : Theme.Colors.primary, lineWidth: character.isEmpty ? 1 : 1.5)
            )
    }
}
