import SwiftUI

/// 設計系統：白底亮橘・運動風。
/// Token 來源：9 畫面設計稿的 CSS variables。
/// 本 App 以淺色為主，深色模式先沿用淺色 token。
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// 背景 #F5F6F8
        static let background = Color(hex: 0xF5F6F8)
        /// 卡片 #FFFFFF
        static let card = Color(hex: 0xFFFFFF)
        /// 卡片次要（暖色底）#FFF7EE
        static let card2 = Color(hex: 0xFFF7EE)
        /// 主色橘 #FF5A1F
        static let primary = Color(hex: 0xFF5A1F)
        /// 深橘 #E8480F
        static let primaryDark = Color(hex: 0xE8480F)
        /// 亮黃 #FFC24D
        static let amber = Color(hex: 0xFFC24D)
        /// 文字 #1A1D24
        static let text = Color(hex: 0x1A1D24)
        /// 次要文字 #697485
        static let muted = Color(hex: 0x697485)
        /// 淡 #9AA1AC
        static let dim = Color(hex: 0x9AA1AC)
        /// 成功綠 #12A150
        static let success = Color(hex: 0x12A150)
        static let successBackground = Color(hex: 0xE6F6EE)
        /// 危險 #E5443B
        static let danger = Color(hex: 0xE5443B)
        /// 邊線 #ECEDF1
        static let line = Color(hex: 0xECEDF1)
        static let line2 = Color(hex: 0xE0E3E9)
        /// 審核中警示（黃底文字）
        static let warnText = Color(hex: 0x9A6400)
        static let warnBackground = Color(hex: 0xFFF4D6)
        /// 尚未開始（灰底灰字）
        static let disabledBackground = Color(hex: 0xEEF0F3)

        /// 主色 CTA 漸層（左上到右下，橘 → 深橘）
        static let primaryGradient = LinearGradient(
            colors: [Color(hex: 0xFF7A2B), Color(hex: 0xFF5109)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 步數環漸層（黃 → 橘）
        static let ringGradient = LinearGradient(
            colors: [amber, primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Radii

    enum Radius {
        static let small: CGFloat = 14
        static let medium: CGFloat = 18
        static let large: CGFloat = 22
        static let xlarge: CGFloat = 26
    }

    // MARK: - Shadows

    enum Shadow {
        static let card = ShadowStyle(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
        static let subtle = ShadowStyle(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Fonts

    /// 標題字體：系統 rounded design（設計稿為 Baloo 2 圓體，先以 SF Rounded 替代）。
    static func displayFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8) / 255
        let b = Double(hex & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Card modifier

/// 卡片樣式：白底、圓角、柔和淺灰陰影、細邊線。
struct CardModifier: ViewModifier {
    var radius: CGFloat = Theme.Radius.large
    var padding: CGFloat = 18
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(highlighted ? Theme.Colors.amber : Theme.Colors.line, lineWidth: highlighted ? 2 : 1)
            )
            .shadow(color: Theme.Shadow.card.color, radius: Theme.Shadow.card.radius,
                    x: Theme.Shadow.card.x, y: Theme.Shadow.card.y)
    }
}

extension View {
    /// 套用共用卡片樣式（白底、圓角、陰影）。
    func cardStyle(radius: CGFloat = Theme.Radius.large, padding: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(CardModifier(radius: radius, padding: padding, highlighted: highlighted))
    }
}

// MARK: - Primary Button Style

/// 大按鈕、橘色漸層、hit target ≥ 44pt，支援動態字級。
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
            configuration.label
                .font(Theme.displayFont(17, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(isEnabled ? Theme.Colors.primaryGradient : LinearGradient(colors: [Theme.Colors.dim, Theme.Colors.dim], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .shadow(color: Theme.Colors.primary.opacity(isEnabled ? 0.28 : 0), radius: 16, x: 0, y: 8)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        .disabled(isLoading || !isEnabled)
    }
}

/// 次要按鈕：白底、邊線。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.Colors.text)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.Colors.line2, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var huihanPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var huihanSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Status Badge

/// TaskState 對應的狀態徽章樣式。
struct StatusBadge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }
}
