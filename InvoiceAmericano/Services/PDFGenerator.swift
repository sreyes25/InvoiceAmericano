//  PDFGenerator.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/7/25.
//

import Foundation
import UIKit
import Supabase

enum PDFGenerator {

    // MARK: - Async Branding-Aware API
    /// Try to resolve a logo image either from branding.logoURL... or by falling back to the deterministic
    /// Supabase public URL at branding/user/{uid}/logo.png. Cache-bust to avoid stale images.
    private static func fetchLogoImage(from branding: Any?) async -> UIImage? {
        // 1) Try URL in branding payload
        if let urlString = readString(branding, keys: ["logoURL","logoUrl","logo_url","logo"])?.trimmedNonEmpty,
           let url = URL(string: urlString) {
            if let data = try? await downloadNoCache(url: url),
               let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 {
                return img
            }
        }
        // 2) Fallback to deterministic Supabase public URL path for current user
        do {
            let client = SupabaseManager.shared.client
            let session = try? await client.auth.session
            if let uid = session?.user.id.uuidString.lowercased() {
                let path = "user/\(uid)/logo.png"
                let publicURL = try client.storage.from("branding").getPublicURL(path: path)
                if let data = try? await downloadNoCache(url: publicURL),
                   let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 {
                    return img
                }
            }
        } catch {
            // ignore – logo is optional
        }
        return nil
    }

    /// Renders an invoice PDF. If `includeBranding` is true, we fetch name/tagline/accent/logo from BrandingService.
    static func makeInvoicePDF(detail: InvoiceDetail, includeBranding: Bool = true) async throws -> URL {
        // Resolve business name from profiles.display_name so first PDF reflects onboarding immediately
        let businessName: String = await fetchBusinessName()
        var branding: Any? = nil
        if includeBranding {
            // We may still read optional theming from BrandingService (tagline/accent/logo),
            // but the name itself comes from profiles.display_name.
            let loaded = try? await BrandingService.loadBranding()
            branding = loaded
        }

        // Extract theming from branding (tagline/accent come from branding table/json)
        let tagline = readString(branding, keys: ["tagline","businessTagline","tag_line"])?.trimmedNonEmpty
        let accentHexStr = readString(branding, keys: ["accentHex","accent_hex","accentColor","accent"])?.trimmedNonEmpty
        let accent = accentHexStr.flatMap(hexToUIColor) ?? UIColor.systemBlue

        // Optional logo
        let logo: UIImage? = await fetchLogoImage(from: branding)

        // Optional default footer text
        let defaults = try? await InvoiceDefaultsService.loadDefaults()
        let footerText = defaults?.footerNotes?.trimmedNonEmpty

        return try render(
            detail: detail,
            businessName: businessName,
            tagline: tagline,
            accent: accent,
            logo: logo,
            footerText: footerText
        )
    }

    /// Fetch the current user's business name from profiles.display_name (single source of truth)
    private static func fetchBusinessName() async -> String {
        let client = SupabaseManager.shared.client
        if let session = try? await client.auth.session {
            let uid = session.user.id.uuidString
            struct Row: Decodable { let display_name: String? }
            if let row: Row = try? await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid)
                .single()
                .execute()
                .value,
               let name = row.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }
        return "Your Business"
    }

    // MARK: - Sync API w/ simple defaults (back-compat)
    static func makeInvoicePDF(detail: InvoiceDetail) throws -> URL {
        try render(
            detail: detail,
            businessName: "Your Business",
            tagline: nil,
            accent: .systemBlue,
            logo: nil,
            footerText: nil
        )
    }

    // MARK: - Core Render (single page)
    private static func render(
        detail: InvoiceDetail,
        businessName: String,
        tagline: String?,
        accent: UIColor,
        logo: UIImage?,
        footerText: String?
    ) throws -> URL {

        // US Letter @72dpi
        let pageW: CGFloat = 612
        let pageH: CGFloat = 792
        let inset:  CGFloat = 40

        // PDF metadata
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "Invoice \(detail.number)",
            kCGPDFContextCreator: "InvoiceAmericano"
        ] as [String : Any]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH),
            format: format
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Invoice-\(detail.number).pdf")
        try? FileManager.default.removeItem(at: url)

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()

            // Solid white background so dark mode never shows through
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

            let leftX  = inset
            let rightX = pageW - inset
            var y: CGFloat = inset

            // ===== Top thin header bar (matches Invoice#2 style) =====
            accent.setFill()
            UIRectFill(CGRect(x: 0, y: y, width: pageW, height: 4))
            y += 16

            // ===== Header: business on left, logo on right, meta under logo =====
            let headerNameFont  = UIFont.boldSystemFont(ofSize: 20)
            let headerTagFont   = UIFont.systemFont(ofSize: 12)
            let metaFont        = UIFont.systemFont(ofSize: 12)
            let metaWidth: CGFloat = 220
            let metaX = rightX - metaWidth

            // Left: Business name + tagline
            draw(businessName, at: CGPoint(x: leftX, y: y), font: headerNameFont)
            if let tag = tagline, !tag.isEmpty {
                draw(tag, at: CGPoint(x: leftX, y: y + 22), font: headerTagFont, color: UIColor(white: 0.35, alpha: 1))
            }

            // Enlarged logo box for a bigger appearance
            let logoBox = CGRect(x: rightX - 200, y: y - 10, width: 200, height: 100)

            // Debug guide (disabled in production):
            // UIColor.systemRed.withAlphaComponent(0.25).setStroke()
            // UIBezierPath(rect: logoBox).stroke()

            var rightBlockTop = y
            if let logo {
                // Fit inside the new, larger box (no extra multiplier)
                let fitted = fit(size: logo.size, maxW: logoBox.width, maxH: logoBox.height)
                let imgRect = CGRect(
                    x: logoBox.midX - fitted.width / 2,
                    y: logoBox.midY - fitted.height / 2,
                    width: fitted.width,
                    height: fitted.height
                )
                logo.draw(in: imgRect)
                rightBlockTop = max(rightBlockTop, logoBox.maxY)
            } else {
                // If there's no logo, keep the header height consistent with the box
                rightBlockTop = max(rightBlockTop, logoBox.maxY)
            }

            // Add more space below the taller logo
            var metaY = rightBlockTop + 16
            draw("Invoice # \(detail.number)", at: CGPoint(x: metaX, y: metaY), font: metaFont, align: .right, width: metaWidth)
            metaY += 16
            if let ds = detail.issued_at ?? detail.created_at {
                draw("Date: \(prettyDate(ds))", at: CGPoint(x: metaX, y: metaY), font: metaFont, align: .right, width: metaWidth)
                metaY += 16
            }
            if let due = detail.dueDate {
                draw("Due: \(prettyDate(due))", at: CGPoint(x: metaX, y: metaY), font: metaFont, align: .right, width: metaWidth)
            }

            // Push content further down to accommodate the bigger logo
            y = max(y + 60, metaY + 15)

            // Thin divider (matches the example’s light lines)
            drawLine(y: y, inset: inset, pageWidth: pageW)
            y += 12

            // ===== Bill To block =====
            draw("Bill To:", at: CGPoint(x: leftX, y: y), font: UIFont.boldSystemFont(ofSize: 13))
            y += 16
            draw(detail.client?.name ?? "—", at: CGPoint(x: leftX, y: y), font: UIFont.systemFont(ofSize: 13))
            y += 20

            // ===== Table header =====
            drawLine(y: y, inset: inset, pageWidth: pageW)
            y += 10

            let colQtyW: CGFloat  = 60
            let colAmtW: CGFloat  = 100
            let colQtyX           = leftX
            let colAmtX           = rightX - colAmtW
            let colDescX          = colQtyX + colQtyW + 10
            let descW             = colAmtX - colDescX - 10

            draw("QUANTITY",    at: CGPoint(x: colQtyX,  y: y), font: .boldSystemFont(ofSize: 12))
            draw("DESCRIPTION", at: CGPoint(x: colDescX, y: y), font: .boldSystemFont(ofSize: 12))
            draw("AMOUNT",      at: CGPoint(x: colAmtX,  y: y), font: .boldSystemFont(ofSize: 12), align: .right, width: colAmtW)

            y += 18
            drawLine(y: y, inset: inset, pageWidth: pageW)
            y += 8

            // ===== Line items =====
            for item in detail.line_items {
                draw("\(item.qty)",                      at: CGPoint(x: colQtyX,  y: y), font: .systemFont(ofSize: 12))
                draw(item.description,                   at: CGPoint(x: colDescX, y: y), font: .systemFont(ofSize: 12), align: .left,  width: descW)
                draw(currency(item.amount, code: detail.currency),
                                                      at: CGPoint(x: colAmtX,  y: y), font: .systemFont(ofSize: 12), align: .right, width: colAmtW)
                y += 18
            }

            // Bottom divider under items
            y += 6
            drawLine(y: y, inset: inset, pageWidth: pageW)
            y += 12

            // ===== Totals (right aligned) =====
            let totalsLabelW: CGFloat = 120
            let totalsValueW: CGFloat = 110
            let totalsValueX          = rightX
            let totalsLabelX          = totalsValueX - totalsValueW - 12 - totalsLabelW

            draw("SUBTOTAL", at: CGPoint(x: totalsLabelX, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsLabelW)
            draw(currency(detail.subtotal ?? 0, code: detail.currency),
                             at: CGPoint(x: totalsValueX - totalsValueW, y: y),
                             font: .systemFont(ofSize: 12), align: .right, width: totalsValueW)
            y += 16

            if let t = detail.tax, t != 0 {
                draw("TAX", at: CGPoint(x: totalsLabelX, y: y), font: .systemFont(ofSize: 12), align: .right, width: totalsLabelW)
                draw(currency(t, code: detail.currency),
                                 at: CGPoint(x: totalsValueX - totalsValueW, y: y),
                                 font: .systemFont(ofSize: 12), align: .right, width: totalsValueW)
                y += 12
            }

            // Accent stripe above TOTAL (thin, matches the sample)
            let stripeY = y + 6
            accent.setFill()
            UIRectFill(CGRect(x: totalsLabelX, y: stripeY, width: totalsLabelW + 12 + totalsValueW, height: 2))
            y += 12

            draw("TOTAL", at: CGPoint(x: totalsLabelX, y: y), font: .boldSystemFont(ofSize: 13), align: .right, width: totalsLabelW)
            draw(currency(detail.total ?? 0, code: detail.currency),
                             at: CGPoint(x: totalsValueX - totalsValueW, y: y),
                             font: .boldSystemFont(ofSize: 13), align: .right, width: totalsValueW)
            y += 24

            // ===== Footer =====
            drawLine(y: y, inset: inset, pageWidth: pageW)
            y += 10
            draw("Thank you for your business!", at: CGPoint(x: leftX, y: y), font: .systemFont(ofSize: 11))
            y += 14
            draw((footerText ?? "-"), at: CGPoint(x: leftX, y: y), font: .systemFont(ofSize: 10))
        }

        return url
    }

    // MARK: - Drawing helpers

    /// Draw attributed text block with alignment and width.
    private static func draw(
        _ text: String,
        at origin: CGPoint,
        font: UIFont,
        align: NSTextAlignment = .left,
        width: CGFloat = .greatestFiniteMagnitude,
        color: UIColor = .black
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para,
            .foregroundColor: color
        ]
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: .greatestFiniteMagnitude)
        NSAttributedString(string: text, attributes: attrs)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    /// Light divider line that looks good in light/dark themes.
    private static func drawLine(y: CGFloat, inset: CGFloat, pageWidth: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: inset, y: y))
        path.addLine(to: CGPoint(x: pageWidth - inset, y: y))
        UIColor(white: 0.85, alpha: 1).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    /// Keep an image inside a bounding box while preserving aspect.
    private static func fit(size: CGSize, maxW: CGFloat, maxH: CGFloat) -> CGSize {
        let wr = maxW / max(size.width, 1)
        let hr = maxH / max(size.height, 1)
        let r  = min(wr, hr)
        return CGSize(width: size.width * r, height: size.height * r)
    }

    // MARK: - Format helpers

    private static func currency(_ value: Double, code: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code ?? "USD").uppercased()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func prettyDate(_ s: String) -> String {
        // Accept: "yyyy-MM-dd" OR ISO8601 (with or w/out fractional seconds)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoFS = ISO8601DateFormatter()
        isoFS.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = TimeZone(secondsFromGMT: 0)
        ymd.locale = Locale(identifier: "en_US_POSIX")

        let out = DateFormatter()
        out.dateFormat = "MM/dd/yy"
        out.timeZone = .current
        out.locale = Locale(identifier: "en_US_POSIX")

        let d = iso.date(from: s) ?? isoFS.date(from: s) ?? ymd.date(from: s)
        return d.map { out.string(from: $0) } ?? s
    }

    private static func hexToUIColor(_ hex: String) -> UIColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let rgb = Int(s, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Download with cache-busting to ensure fresh logos after updates.
    private static func downloadNoCache(url: URL) async throws -> Data {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "cb", value: String(Int(Date().timeIntervalSince1970))))
        comps?.queryItems = q
        let finalURL = comps?.url ?? url

        var req = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 400, !data.isEmpty else {
            throw NSError(domain: "pdf.logo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Logo download failed"])
        }
        return data
    }

    // MARK: - Reflection helper for Branding payloads
    private static func readString(_ any: Any?, keys: [String]) -> String? {
        guard let any else { return nil }
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first { return readString(child.value, keys: keys) }
            return nil
        }
        for child in mirror.children {
            if let label = child.label, keys.contains(label) {
                return child.value as? String
            }
        }
        return nil
    }
}

// MARK: - Small helpers
private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
