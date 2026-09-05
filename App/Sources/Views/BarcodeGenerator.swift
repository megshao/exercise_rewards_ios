import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 用 CoreImage 依 `data-format` 即時生成券碼圖。官網前端本身是用 JsBarcode/node-qrcode
/// 依 `data-value`/`data-format` 產生（見 docs/redeem-flow-capture.md 步驟 8），App 端沒有
/// 那兩個套件，改用系統內建的 CoreImage 濾鏡在本機重畫同一組資料——**條碼是純粹依號碼值算出
/// 的圖形**，不是官網資產，本地重畫並不違反「不得引用外部網域」的限制。
///
/// 兩種 `format`（分流依據見 VoucherFigure.format 的原始字串）：
/// - `CODE_128` → `CICode128BarcodeGenerator`
/// - `QR_CODE`  → `CIQRCodeGenerator`
/// 其他未知 format、或濾鏡輸出失敗，一律回傳 `nil`——呼叫端（VoucherView）在拿到 `nil` 時
/// 必須顯示 `.voucher-figure__fallback` 等級的號碼文字，讓店員能改用手動輸入，而不是空白畫面。
enum BarcodeGenerator {
    private static let context = CIContext()

    /// - Parameters:
    ///   - value: 券碼字面值（`data-value`）。
    ///   - format: 券碼符號集（`data-format` 原始字串，"CODE_128" 或 "QR_CODE"）。
    ///   - scale: 放大倍率，避免 CoreImage 產出的原生小圖被拉伸而糊掉（預設對應約合適的顯示解析度）。
    static func barcodeImage(value: String, format: String, scale: CGFloat = 8) -> UIImage? {
        guard !value.isEmpty, let data = value.data(using: .ascii) else {
            return nil
        }

        let filter: CIFilter?
        switch format.uppercased() {
        case "CODE_128":
            let code128 = CIFilter.code128BarcodeGenerator()
            code128.message = data
            filter = code128
        case "QR_CODE":
            let qr = CIFilter.qrCodeGenerator()
            qr.message = data
            qr.correctionLevel = "M"
            filter = qr
        default:
            filter = nil
        }

        guard let outputImage = filter?.outputImage else {
            return nil
        }

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
