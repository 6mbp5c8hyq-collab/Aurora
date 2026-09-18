import XCTest
import UIKit
import PDFKit
@testable import AURORA

final class Phase1OreDocumentAdmissionTests: XCTestCase {
    private func imageOnlyPDF() throws -> Data {
        let imageSize = CGSize(width: 1600, height: 2000)
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 82, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let row: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            "GLAUCONITE XRF ANALYSIS".draw(at: CGPoint(x: 100, y: 180), withAttributes: title)
            "K2O 10.5 %".draw(at: CGPoint(x: 120, y: 520), withAttributes: row)
            "Fe2O3 8.0 %".draw(at: CGPoint(x: 120, y: 720), withAttributes: row)
            "SiO2 55.0 %".draw(at: CGPoint(x: 120, y: 920), withAttributes: row)
        }

        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: page.insetBy(dx: 28, dy: 28))
        }
    }

    private func textLayerPDF() -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            let text = """
            GLAUCONITE XRF ANALYSIS
            Sample: PHASE1-GL-001
            K2O 10.5 %
            Fe2O3 8.0 %
            SiO2 55.0 %
            Al2O3 9.4 %
            MgO 3.1 %
            CaO 1.8 %
            LOI 7.2 %
            Dry route acceptance document
            """
            text.draw(in: CGRect(x: 52, y: 80, width: 510, height: 500), withAttributes: attrs)
        }
    }

    func testImageOnlyPDFUsesVisionOCRFallback() async throws {
        let pdf = try imageOnlyPDF()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertTrue((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let receipt = try await OreDocumentAdmissionV3.extractFallbackText(fromPDF: pdf)
        XCTAssertEqual(receipt.mode, .visionOCR)
        XCTAssertEqual(receipt.pageCount, 1)
        XCTAssertEqual(receipt.processedPages, 1)
        XCTAssertFalse(receipt.truncated)
        XCTAssertTrue(receipt.isUsable)
        XCTAssertTrue(receipt.text.contains("--- PAGE 1 ---"))
        XCTAssertTrue(receipt.text.localizedCaseInsensitiveContains("K2O"))
        XCTAssertTrue(receipt.text.contains("10.5"))
        XCTAssertTrue(receipt.text.localizedCaseInsensitiveContains("Fe2O3"))
        XCTAssertTrue(receipt.text.contains("8.0"))
    }

    func testUsefulNativeTextLayerPrecedesOCR() async throws {
        let pdf = textLayerPDF()
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThan((document.string ?? "").count, 80)

        let receipt = try await OreDocumentAdmissionV3.extractFallbackText(fromPDF: pdf)
        XCTAssertEqual(receipt.mode, .textLayer)
        XCTAssertEqual(receipt.pageCount, 1)
        XCTAssertEqual(receipt.processedPages, 1)
        XCTAssertFalse(receipt.truncated)
        XCTAssertTrue(receipt.text.localizedCaseInsensitiveContains("K2O"))
        XCTAssertTrue(receipt.text.localizedCaseInsensitiveContains("Fe2O3"))
    }

    func testReceiptAuthorityIsExtractionOnly() {
        XCTAssertEqual(OreDocumentAdmissionReceiptV3.ExtractionMode.textLayer.rawValue, "client_pdf_text_layer_unverified")
        XCTAssertEqual(OreDocumentAdmissionReceiptV3.ExtractionMode.visionOCR.rawValue, "client_vision_ocr_unverified")
        XCTAssertEqual(OreDocumentAdmissionV3.maximumOCRPages, 24)
        XCTAssertEqual(OreDocumentAdmissionV3.revision, "AURORA-ORE-DOCUMENT-ADMISSION-V3-2026.09.17")
    }
}
