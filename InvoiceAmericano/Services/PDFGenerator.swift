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

            // ===== Table header + line items (with pagination) =====
            // Common column metrics
            let colIndexW: CGFloat = 28
            let colAmtW: CGFloat   = 90

            let colIndexX          = leftX
            let colAmtX            = rightX - colAmtW
            let colDescX           = colIndexX + colIndexW + 10
            let descW              = colAmtX - colDescX - 10

            let itemTitleFont = UIFont.boldSystemFont(ofSize: 12)
            let itemBodyFont  = UIFont.systemFont(ofSize: 12)
            let unitsFont     = UIFont.systemFont(ofSize: 10)

            // Draw the table header and return the new y-position
            func drawItemsHeader(at startY: CGFloat) -> CGFloat {
                var yy = startY
                drawLine(y: yy, inset: inset, pageWidth: pageW)
                yy += 10

                draw("ITEM",
                     at: CGPoint(x: colIndexX,  y: yy),
                     font: .boldSystemFont(ofSize: 12))
                draw("DESCRIPTION",
                     at: CGPoint(x: colDescX,   y: yy),
                     font: .boldSystemFont(ofSize: 12))
                draw("AMOUNT",
                     at: CGPoint(x: colAmtX,    y: yy),
                     font: .boldSystemFont(ofSize: 12),
                     align: .right,
                     width: colAmtW)

                yy += 18
                drawLine(y: yy, inset: inset, pageWidth: pageW)
                yy += 8
                return yy
            }

            // Reserve some space at the bottom of the page for totals + footer.
            // Slightly tighter so long descriptions can use more of the page
            // before we push the next item to a new page.
            let bottomReserved: CGFloat = 10
            let pageContentBottom = pageH - inset - bottomReserved


            // Helper to start a continuation page for items
            func startNewItemsPage() {
                ctx.beginPage()
                // Solid background
                UIColor.white.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

                var yy: CGFloat = inset
                draw("Items (continued)", at: CGPoint(x: leftX, y: yy), font: UIFont.boldSystemFont(ofSize: 13))
                yy += 22
                y = drawItemsHeader(at: yy)
            }

            // Initial header on the first page
            y = drawItemsHeader(at: y)

            // ===== Line items with pagination (allow splitting across pages without wasting space) =====
            for (index, item) in detail.line_items.enumerated() {
                // Title/description logic – mirrors the app UI behavior
                let rawTitle = item.title?.trimmedNonEmpty
                let rawDesc  = item.description.trimmedNonEmpty
                let (title, fullBody) = normalizeTitleAndBody(title: rawTitle, description: rawDesc)

                var remainingBody = fullBody
                var firstSegment = true

                // We may need to draw a single item across multiple pages
                while firstSegment || remainingBody != nil {

                    // Ensure there is at least room for a line of text on this page;
                    // if not, start a new continuation page.
                    if y + itemBodyFont.lineHeight > pageContentBottom {
                        startNewItemsPage()
                    }

                    let startY = y
                    var rowHeight: CGFloat = 0

                    // Item index (1-based) and amount appear on the first segment only.
                    if firstSegment {
                        let itemNumber = index + 1
                        draw("\(itemNumber)",
                             at: CGPoint(x: colIndexX, y: startY),
                             font: itemBodyFont)

                        draw(currency(item.amount, code: detail.currency),
                             at: CGPoint(x: colAmtX, y: startY),
                             font: itemBodyFont,
                             align: .right,
                             width: colAmtW)
                    }

                    // 1) Title (bold, may wrap to multiple lines) – only on the first segment
                    if firstSegment, let title {
                        let titleHeight = textHeight(title, font: itemTitleFont, width: descW)
                        draw(title,
                             at: CGPoint(x: colDescX, y: startY),
                             font: itemTitleFont,
                             align: .left,
                             width: descW)
                        rowHeight = max(rowHeight, titleHeight)
                    }

                    // 2) Body/description (regular) – may span pages and be split across them
                    if let bodySource = remainingBody ?? fullBody {
                        let spacing: CGFloat = (firstSegment && title != nil ? 2 : 0)
                        let bodyY = startY + rowHeight + spacing

                        // How much vertical space is left for body text on this page?
                        var availableBodyHeight = pageContentBottom - bodyY

                        // If there is no room even for one line, push to a new page and try again.
                        if availableBodyHeight <= itemBodyFont.lineHeight {
                            startNewItemsPage()
                            continue
                        }

                        // Split body text into a chunk that fits on this page and an optional remainder.
                        let split = splitTextToFit(
                            bodySource,
                            font: itemBodyFont,
                            width: descW,
                            maxHeight: availableBodyHeight
                        )

                        if !split.fitting.isEmpty {
                            let usedHeight = textHeight(split.fitting, font: itemBodyFont, width: descW)
                            draw(split.fitting,
                                 at: CGPoint(x: colDescX, y: bodyY),
                                 font: itemBodyFont,
                                 align: .left,
                                 width: descW)

                            rowHeight = max(rowHeight, (bodyY - startY) + usedHeight)
                        }

                        remainingBody = split.remainder
                    }

                    // 3) Units breakdown only on the final segment
                    if remainingBody == nil, item.qty > 1, item.amount > 0 {
                        let unit = item.amount / Double(item.qty)
                        let unitsText = "\(item.qty) x \(currency(unit, code: detail.currency)) each"
                        let spacingBelow: CGFloat = 2
                        var unitsY = startY + rowHeight + spacingBelow
                        let unitsHeight = textHeight(unitsText, font: unitsFont, width: descW)

                        // If the units line doesn't fit on this page, start a new page and draw it there.
                        if unitsY + unitsHeight > pageContentBottom {
                            startNewItemsPage()
                            unitsY = y
                        }

                        draw(unitsText,
                             at: CGPoint(x: colDescX, y: unitsY),
                             font: unitsFont,
                             align: .left,
                             width: descW,
                             color: UIColor(white: 0.4, alpha: 1.0))

                        rowHeight = max(rowHeight, (unitsY - startY) + unitsHeight)
                    }

                    if rowHeight == 0 {
                        rowHeight = itemBodyFont.lineHeight
                    }

                    // padding between segments/rows
                    y = startY + rowHeight + 6

                    // After the first segment, we only draw continuations if there is still body text left.
                    if firstSegment {
                        firstSegment = false
                        if remainingBody == nil { break }
                    } else if remainingBody == nil {
                        break
                    }
                }
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

    /// Measure the height needed to draw a block of text with a given font and width.
    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }

    /// Split `text` into a prefix that fits within `maxHeight` and an optional remainder.
    /// Ensures that page breaks never occur inside a word by snapping the split point
    /// back to the last whitespace or newline before the boundary, while always consuming
    /// at least one character to make progress.
    private static func splitTextToFit(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> (fitting: String, remainder: String?) {
        guard !text.isEmpty else { return ("", nil) }

        // If the whole text fits, we are done.
        if textHeight(text, font: font, width: width) <= maxHeight {
            return (text, nil)
        }

        let ns = text as NSString
        var low = 0
        var high = ns.length
        var best = 0

        // Binary search for the longest prefix that fits vertically.
        while low <= high {
            let mid = (low + high) / 2
            if mid == 0 { break }
            let candidate = ns.substring(to: mid)
            let h = textHeight(candidate, font: font, width: width)
            if h <= maxHeight {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        // Snap the break back to the last whitespace/newline so we don't
        // cut a word in half across pages.
        let whitespace = CharacterSet.whitespacesAndNewlines
        var safeBest = best
        if safeBest > 0 && safeBest < ns.length {
            var i = safeBest
            while i > 0 {
                let ch = ns.character(at: i - 1)
                if let scalar = UnicodeScalar(ch), whitespace.contains(scalar) {
                    // Break *before* this whitespace.
                    safeBest = i - 1
                    break
                }
                i -= 1
            }
        }

        // Ensure we always consume at least one character to make progress.
        if safeBest == 0 {
            safeBest = min(1, ns.length)
        }

        let fitting = ns.substring(to: safeBest)
        let remainder: String? = (safeBest < ns.length) ? ns.substring(from: safeBest) : nil
        return (fitting, remainder)
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

    // MARK: - Item title/description normalization (shared logic with UI intent)
    /// Returns a preferred title and body for a line item, following these rules:
    /// - If a distinct `title` exists, it is used as the bold line. The description (if non‑empty
    ///   and not identical) is shown as a second regular line.
    /// - If no title but a short description exists (<= 32 chars), treat it as a title only.
    /// - Otherwise, use the description as the body only.
    private static func normalizeTitleAndBody(title: String?, description: String?) -> (String?, String?) {
        let t = title?.trimmedNonEmpty
        let d = description?.trimmedNonEmpty

        // 1) Explicit title wins; description becomes body if distinct
        if let t {
            if let d, d.caseInsensitiveCompare(t) != .orderedSame {
                return (t, d)
            } else {
                // Description is empty or same as title – show title only
                return (t, nil)
            }
        }

        // 2) No title – decide based on description length
        guard let d else { return (nil, nil) }
        let threshold = 32
        if d.count <= threshold {
            // Short description promoted to title
            return (d, nil)
        } else {
            // Long description stays as body text
            return (nil, d)
        }
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
