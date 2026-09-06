import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 用 CoreImage 依 `data-format` 即時生成券碼圖。
///
/// **條碼是純粹依號碼值算出的圖形**，不是需要下載的圖片資產——所以拿到號碼與格式之後，
/// 用系統內建的 CoreImage 濾鏡在本機畫出來就行，不必（也不該）為了一張條碼多開一條
/// 對外連線。
///
/// 支援的 `format`（分流依據見 VoucherFigure.format 的原始字串）：
/// - `CODE_128` → `CICode128BarcodeGenerator`
/// - `QR_CODE`  → `CIQRCodeGenerator`
/// - `AZTEC`    → `CIAztecCodeGenerator`
/// - `PDF_417`  → `CIPDF417BarcodeGenerator`
///
/// 官網目前只用前兩種。後兩種是**預先接上**的：CoreImage 本來就內建這兩顆濾鏡，
/// 接起來幾乎沒有成本，而它們是台灣零售券碼除了 Code 128／QR 之外最可能出現的兩種。
/// 這樣官網換券種時使用者當下就有條碼可掃，不必等一次改版送審。
///
/// **刻意不接 EAN-13／CODE_39**：CoreImage 沒有內建，要自繪或引第三方。等遙測真的看到
/// `barcode_render_failed(format=other)` 再說——那個事件就是為了讓這個決定有依據而存在。
///
/// 其他未知 format、或濾鏡輸出失敗，一律回傳 `nil`——呼叫端（VoucherView）在拿到 `nil` 時
/// 必須顯示 `.voucher-figure__fallback` 等級的號碼文字，讓店員能改用手動輸入，而不是空白畫面。
enum BarcodeGenerator {
    private static let context = CIContext()

    /// - Parameters:
    ///   - value: 券碼字面值（`data-value`）。
    ///   - format: 券碼符號集（`data-format` 原始字串，例如 "CODE_128" / "QR_CODE"）。
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
        case "AZTEC":
            let aztec = CIFilter.aztecCodeGenerator()
            aztec.message = data
            filter = aztec
        // 官網若用了 PDF417，格式字串照 ZXing 慣例會是 `PDF_417`；`PDF417` 一併容錯。
        case "PDF_417", "PDF417":
            let pdf417 = CIFilter.pdf417BarcodeGenerator()
            pdf417.message = data
            filter = pdf417
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
