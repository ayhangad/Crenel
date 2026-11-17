import AppKit
import CoreText

/// A meeting as a paginated PDF: the plain-text export's blocks set in type on A4 or
/// Letter pages, with the page number at the foot. Core Text fills one page frame at a
/// time, so a long transcript simply continues on the next page.
///
///     let data = MeetingPDFRenderer.pdfData(meeting: meeting, transcription: stored)
enum MeetingPDFRenderer {
    enum PaperSize {
        case a4
        case letter

        /// Letter where the locale measures in US units, A4 everywhere else.
        static var current: PaperSize {
            Locale.current.measurementSystem == .us ? .letter : .a4
        }

        var points: CGSize {
            switch self {
            case .a4: CGSize(width: 595.28, height: 841.89)
            case .letter: CGSize(width: 612, height: 792)
            }
        }
    }

    private static let margin: CGFloat = 56
    private static let footerHeight: CGFloat = 20

    static func pdfData(
        meeting: StoredMeeting,
        transcription: StoredTranscription,
        paper: PaperSize = .current
    ) -> Data {
        let text = attributedText(MeetingPlainTextFormatter.blocks(meeting: meeting, transcription: transcription))
        return render(text, paper: paper, title: meeting.title)
    }

    // MARK: Pages

    private static func render(_ text: NSAttributedString, paper: PaperSize, title: String) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paper.points)
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Crenel"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            return Data()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let textRect = CGRect(
            x: margin,
            y: margin + footerHeight,
            width: mediaBox.width - margin * 2,
            height: mediaBox.height - margin * 2 - footerHeight
        )
        let path = CGPath(rect: textRect, transform: nil)
        var location = 0
        var page = 0
        repeat {
            page += 1
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            drawPageNumber(page, in: context, mediaBox: mediaBox)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            // A frame that fits nothing would repeat forever; stop instead.
            guard visible.length > 0 else { break }
            location = visible.location + visible.length
        } while location < text.length
        context.closePDF()
        return data as Data
    }

    private static func drawPageNumber(_ page: Int, in context: CGContext, mediaBox: CGRect) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(page)", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            foregroundColor: NSColor.gray.cgColor
        ]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: (mediaBox.width - CGFloat(width)) / 2, y: margin - 12)
        CTLineDraw(line, context)
    }

    // MARK: Type

    /// Core Text reads a CGColor under its own key.
    private static let foregroundColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    private static func attributedText(_ blocks: [MeetingPlainTextFormatter.Block]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            switch block {
            case .title(let title):
                result.append(paragraph(title, size: 20, weight: .semibold, after: 4))
            case .meta(let text):
                result.append(paragraph(text, size: 10, color: .gray, after: 10))
            case .heading(let heading):
                result.append(paragraph(heading, size: 13, weight: .semibold, before: 14, after: 6))
            case .paragraph(let text):
                result.append(paragraph(text, size: 10.5, after: 6, lineHeight: 1.25))
            case .item(let text):
                result.append(paragraph("•\t\(text)", size: 10.5, after: 3, lineHeight: 1.25, hanging: 14))
            case .speaker(let name, let time):
                result.append(paragraph(name, size: 10.5, weight: .semibold, before: 6, after: 1, endsParagraph: false))
                result.append(paragraph("  \(time)", size: 9, color: .gray, before: 6, after: 1))
            }
        }
        return result
    }

    private static func paragraph(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .black,
        before: CGFloat = 0,
        after: CGFloat = 0,
        lineHeight: CGFloat = 1.1,
        hanging: CGFloat = 0,
        endsParagraph: Bool = true
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineHeightMultiple = lineHeight
        style.lineBreakMode = .byWordWrapping
        if hanging > 0 {
            style.headIndent = hanging
            style.tabStops = [NSTextTab(textAlignment: .left, location: hanging)]
        }
        return NSAttributedString(string: endsParagraph ? text + "\n" : text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            foregroundColor: color.cgColor,
            .paragraphStyle: style
        ])
    }
}
