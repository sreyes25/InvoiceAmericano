//
//  PDFGenerator.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/7/25.
//

import Foundation
import UIKit

enum PDFGenerator {
    static func makeInvoicePDF(detail: InvoiceDetail) throws -> URL {
        // Page + margins
        let pageWidth: CGFloat = 612   // 8.5" * 72
        let pageHeight: CGFloat = 792  // 11"  * 72
        let inset: CGFloat = 40

        // Doc metadata
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "Invoice \(detail.number)",
            kCGPDFContextCreator: "InvoiceAmericano"
        ] as [String : Any]

        // Renderer
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Invoice-\(detail.number).pdf")

        // Avoid stale files during iteration
        try? FileManager.default.removeItem(at: url)

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()

            // ===== Layout guides (mirrors sample structure) =====
            let leftX = inset
            let rightX = pageWidth - inset
            var y: CGFloat = inset

            // ===== Top Row =====
            // Left: Big title
            draw("INVOICE", at: CGPoint(x: leftX, y: y), font: .boldSystemFont(ofSize: 28))

            // Right: invoice meta (right-aligned block)
            let metaWidth: CGFloat = 240
            let metaX = rightX - metaWidth
            draw("Invoice # \(detail.number)",
                 at: CGPoint(x: metaX, y: y + 2),
                 font: .systemFont(ofSize: 12),
                 align: .right,
                 width: metaWidth)
            var metaY = y + 18

            // Use issued_at if present; otherwise fall back to created_at, then format.
            if let dateString = detail.issued_at ?? detail.created_at {
                draw("Date: \(prettyDate(dateString))",
                     at: CGPoint(x: metaX, y: metaY),
                     font: .systemFont(ofSize: 12),
                     align: .right,
                     width: metaWidth)
                metaY += 16
            }
            if let due = detail.dueDate {
                draw("Due: \(prettyDate(due))",
                     at: CGPoint(x: metaX, y: metaY),
                     font: .systemFont(ofSize: 12),
                     align: .right,
                     width: metaWidth)
            }

            y += 34

            // Business tagline bar (simple)
            line(y: y, inset: inset, width: pageWidth); y += 10
            draw("Invoice Americano — Simple invoicing for small businesses",
                 at: CGPoint(x: leftX, y: y),
                 font: .systemFont(ofSize: 11))
            y += 16
            line(y: y, inset: inset, width: pageWidth); y += 14

            // ===== Bill To (left column under header) =====
            var infoY = y
            draw("Bill To:", at: CGPoint(x: leftX, y: infoY), font: .boldSystemFont(ofSize: 13)); infoY += 16
            draw(detail.client?.name ?? "—", at: CGPoint(x: leftX, y: infoY), font: .systemFont(ofSize: 13)); infoY += 16
            // (Optional future lines for phone/email/address)

            // Keep y aligned to next block start
            y = max(infoY + 10, y)

            // ===== Items Table Header (Qty / Description / Amount) =====
            line(y: y, inset: inset, width: pageWidth); y += 10

            let colQtyW: CGFloat = 60
            let colAmtW: CGFloat = 100
            let colQtyX = leftX
            let colAmtX = rightX - colAmtW
            let colDescX = colQtyX + colQtyW + 10
            let descW = colAmtX - colDescX - 10

            draw("QUANTITY", at: CGPoint(x: colQtyX, y: y), font: .boldSystemFont(ofSize: 12))
            draw("DESCRIPTION", at: CGPoint(x: colDescX, y: y), font: .boldSystemFont(ofSize: 12))
            draw("AMOUNT", at: CGPoint(x: colAmtX, y: y), font: .boldSystemFont(ofSize: 12), align: .right, width: colAmtW)
            y += 18
            line(y: y, inset: inset, width: pageWidth); y += 10

            // ===== Items Rows =====
            for it in detail.line_items {
                draw("\(it.qty)", at: CGPoint(x: colQtyX, y: y), font: .systemFont(ofSize: 12))
                draw(it.description, at: CGPoint(x: colDescX, y: y), font: .systemFont(ofSize: 12), align: .left, width: descW)
                draw(currency(it.amount, code: detail.currency), at: CGPoint(x: colAmtX, y: y), font: .systemFont(ofSize: 12), align: .right, width: colAmtW)
                y += 18
            }

            // Divider below items
            y += 6
            line(y: y, inset: inset, width: pageWidth); y += 12

            // ===== Totals Block (right-aligned) =====
            let totalsLabelW: CGFloat = 120
            let totalsValueW: CGFloat = 110
            let totalsValueX = rightX
            let totalsLabelX = totalsValueX - totalsValueW - 12 - totalsLabelW

            draw("SUBTOTAL", at: CGPoint(x: totalsLabelX, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsLabelW)
            draw(currency(detail.subtotal ?? 0, code: detail.currency), at: CGPoint(x: totalsValueX - totalsValueW, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsValueW)
            y += 16

            if let tax = detail.tax, tax != 0 {
                draw("TAX", at: CGPoint(x: totalsLabelX, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsLabelW)
                draw(currency(tax, code: detail.currency), at: CGPoint(x: totalsValueX - totalsValueW, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsValueW)
                y += 16
            }

            draw("TOTAL", at: CGPoint(x: totalsLabelX, y: y), font: .boldSystemFont(ofSize: 13), align: .right, width: totalsLabelW)
            draw(currency(detail.total ?? 0, code: detail.currency), at: CGPoint(x: totalsValueX - totalsValueW, y: y), font: .boldSystemFont(ofSize: 13), align: .right, width: totalsValueW)
            y += 22

            // ===== Footer =====
            line(y: y, inset: inset, width: pageWidth); y += 10
            draw("Thank you for your business!", at: CGPoint(x: leftX, y: y), font: .systemFont(ofSize: 11)); y += 16
            draw("-.", at: CGPoint(x: leftX, y: y), font: .systemFont(ofSize: 10)); y += 14
        }

        return url
    }

    // MARK: - Helpers

    private static func draw(
        _ text: String,
        at p: CGPoint,
        font: UIFont = .systemFont(ofSize: 14),
        align: NSTextAlignment = .left,
        width: CGFloat = .greatestFiniteMagnitude,
        color: UIColor = .black
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: para,
                .foregroundColor: color
            ]
        )
        let rect = CGRect(x: p.x, y: p.y, width: width, height: .greatestFiniteMagnitude)
        attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func line(y: CGFloat, inset: CGFloat, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: inset, y: y))
        path.addLine(to: CGPoint(x: width - inset, y: y))
        UIColor.separator.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func currency(_ value: Double, code: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code ?? "USD").uppercased()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func prettyDate(_ s: String) -> String {
        // Handle yyyy-MM-dd or full ISO 8601 with fractional seconds
        // Accept several common shapes:
        // 1) "yyyy-MM-dd"
        // 2) ISO 8601 without fractional seconds: "2025-10-08T00:00:00+00:00"
        // 3) ISO 8601 with fractional seconds:  "2025-10-08T00:00:00.000Z"
        let isoNoFS = ISO8601DateFormatter()
        isoNoFS.formatOptions = [.withInternetDateTime]
        
        let isoFS = ISO8601DateFormatter()
        isoFS.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = .utc
        ymd.locale = Locale(identifier: "en_US_POSIX")

        let out = DateFormatter()
        out.dateFormat = "MM/dd/yy"
        out.timeZone = .current
        out.locale = Locale(identifier: "en_US_POSIX")

        let d = isoNoFS.date(from: s) ?? isoFS.date(from: s) ?? ymd.date(from: s)
        return d.map { out.string(from: $0) } ?? s
    }
}

private extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}
