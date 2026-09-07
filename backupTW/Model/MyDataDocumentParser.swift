//
//  MyDataDocumentParser.swift
//  backupTW
//
//  Reading the fields a vault document carries, so a claim can be derived from
//  the original the holder kept — without the original ever leaving the phone.
//

import Foundation
import PDFKit

enum MyDataDocumentParserError: Error, Equatable {
    /// The text does not look like the document this parser reads. Named so a
    /// wrong file in the right vault slot is reported as that, not as a crash.
    case notThisDocument
    /// The document was recognised but a field the claims need is absent. The
    /// label is the human one from the page, so the holder can check the PDF.
    case missingField(String)
    /// The PDF is password-protected and no password opened it. MyData seals
    /// its PDFs with the holder's national ID number; without a stored national
    /// ID card there is nothing on the phone to try.
    case locked
}

/// One document type's extraction rules, versioned.
///
/// # Why the version travels inside the credential
///
/// A verifier that accepts `income-pdf/v1` is accepting *these* rules — which
/// line the year came from, how the total was summed. When the layout shifts
/// and the rules change, the version changes, and a verifier can decide whether
/// the new rules are ones it has reviewed. The rules are not in the verifier's
/// UI; they are here, and the credential names them.
protocol MyDataDocumentParser {
    /// `MyDataDocumentRegistry` id this parser reads (`mydata-income`, …).
    static var documentTypeID: String { get }
    /// `<name>/v<n>`, carried in the credential's `source.parser`.
    static var version: String { get }
    /// Reads the page text of the original. Throws rather than guessing.
    static func parse(text: String) throws -> MyDataParsedDocument
}

/// What a parser found: flat string fields, in the same shape the claims are
/// committed to (`Disclosure` carries strings; so does this).
struct MyDataParsedDocument: Equatable {
    let documentTypeID: String
    let parserVersion: String
    /// Fields the rules below read. Keys are the base claim names of the type.
    let fields: [String: String]
    /// Dated rows, for documents that are a table (insurance periods).
    let periods: [MyDataCoveragePeriod]

    init(documentTypeID: String, parserVersion: String,
         fields: [String: String], periods: [MyDataCoveragePeriod] = []) {
        self.documentTypeID = documentTypeID
        self.parserVersion = parserVersion
        self.fields = fields
        self.periods = periods
    }
}

/// One insured period: ISO dates, `end == nil` means still in force on the day
/// the document was produced.
struct MyDataCoveragePeriod: Equatable {
    let start: String
    let end: String?
}

/// The parsers this build ships, looked up by document type.
enum MyDataDocumentParsers {

    static func parser(for documentTypeID: String) -> MyDataDocumentParser.Type? {
        switch documentTypeID {
        case MyDataIncomeParser.documentTypeID: return MyDataIncomeParser.self
        case MyDataLaborInsuranceParser.documentTypeID: return MyDataLaborInsuranceParser.self
        case MyDataHouseholdParser.documentTypeID: return MyDataHouseholdParser.self
        default: return nil
        }
    }

    /// Every page's text, joined. `PDFDocument.string` already inserts a newline
    /// between pages; joining explicitly keeps page order stable when a page has
    /// no text layer at all (scanned), which then parses as `notThisDocument`.
    static func text(ofPDF data: Data) -> String? {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { return nil }
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }
}

// MARK: - Shared text helpers

enum MyDataTextField {

    /// Both colon widths appear in the same MyData document (measured on the
    /// national ID), so a label is followed by either.
    static func value(after label: String, in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            guard let range = line.range(of: label) else { continue }
            let rest = line[range.upperBound...]
            guard let colon = rest.firstIndex(where: { $0 == "：" || $0 == ":" }) else { continue }
            var value = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // A line can carry two fields: 「所得年度：113 所得人：王小明」.
            if let split = value.range(of: "  ") ?? value.range(of: "\t") {
                value = String(value[..<split.lowerBound])
            }
            if let nextLabel = value.range(of: " ") , value[nextLabel.upperBound...].contains(where: { $0 == "：" || $0 == ":" }) {
                value = String(value[..<nextLabel.lowerBound])
            }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// `"1,234,567"` / `"NT$1,234"` / `"1234567 元"` → `"1234567"`. `nil` when
    /// there is no digit at all.
    static func digits(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : String(Int(digits) ?? 0)
    }

    /// A Republic-of-China or Gregorian date in any of the spellings MyData
    /// documents use, to ISO `yyyy-MM-dd`. Unrecognised → `nil`, never a guess.
    ///
    /// Spellings seen or expected: `113/02/01`, `113.02.01`, `113年2月1日`,
    /// `民國113年02月01日`, `1130201`, `2024-02-01`, `2024/02/01`.
    static func isoDate(_ raw: String) -> String? {
        let text = raw.replacingOccurrences(of: "民國", with: "")
            .trimmingCharacters(in: .whitespaces)
        let patterns = [
            "^(\\d{2,4})[/.\\-年](\\d{1,2})[/.\\-月](\\d{1,2})日?$",
            "^(\\d{3})(\\d{2})(\\d{2})$",
            "^(\\d{4})(\\d{2})(\\d{2})$",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges == 4,
                  let yearRange = Range(match.range(at: 1), in: text),
                  let monthRange = Range(match.range(at: 2), in: text),
                  let dayRange = Range(match.range(at: 3), in: text),
                  let year = Int(text[yearRange]), let month = Int(text[monthRange]),
                  let day = Int(text[dayRange]) else { continue }
            let gregorianYear = year < 1000 ? year + 1911 : year
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            return String(format: "%04d-%02d-%02d", gregorianYear, month, day)
        }
        return nil
    }

    /// Every date-looking token in a line, in order, as ISO strings.
    static func isoDates(in line: String) -> [String] {
        let pattern = "(民國)?\\d{2,4}[/.\\-年]\\d{1,2}[/.\\-月]\\d{1,2}日?|\\b\\d{7}\\b|\\b\\d{8}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap {
            guard let range = Range($0.range, in: line) else { return nil }
            return isoDate(String(line[range]))
        }
    }

    /// `113` or `113年度` or `2024` → the Gregorian year as a string.
    static func gregorianYear(_ raw: String) -> String? {
        guard let digits = digits(raw), let year = Int(digits) else { return nil }
        return String(year < 1000 ? year + 1911 : year)
    }

    /// 台 → 臺 and full-width digits to ASCII, so a city name compares equal no
    /// matter which keyboard produced the document or the verifier's rule.
    static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "台", with: "臺")
            .applyingTransform(.fullwidthToHalfwidth, reverse: false)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}

// MARK: - 個人所得資料（財政部）

/// The income statement: the tax year, and the sum of every 給付總額 row.
///
/// The document is a table of income items, one per payer, each with a
/// 給付總額. Two layouts are handled: a 合計 line carrying the total, or the
/// per-row amounts to sum. A document with neither is refused rather than
/// reported as zero income — zero is a claim, not a parse failure.
enum MyDataIncomeParser: MyDataDocumentParser {
    static let documentTypeID = "mydata-income"
    static let version = "income-pdf/v1"

    static let taxYearField = "tax_year"
    static let totalField = "income_total_twd"
    static let payerCountField = "payer_count"

    static func parse(text: String) throws -> MyDataParsedDocument {
        let recognised = ["所得資料", "給付總額", "所得年度"].contains { text.contains($0) }
        guard recognised else { throw MyDataDocumentParserError.notThisDocument }

        guard let year = MyDataTextField.value(after: "所得年度", in: text).flatMap(MyDataTextField.gregorianYear)
                ?? firstYear(in: text) else {
            throw MyDataDocumentParserError.missingField("所得年度")
        }

        let lines = text.components(separatedBy: .newlines)
        var total: Int?
        if let totalLine = lines.first(where: { $0.contains("合計") }),
           let amount = trailingAmount(in: totalLine) {
            total = amount
        } else {
            let amounts = lines.compactMap { line -> Int? in
                guard line.contains("給付總額") else { return nil }
                return MyDataTextField.value(after: "給付總額", in: line)
                    .flatMap(MyDataTextField.digits).flatMap(Int.init)
            }
            if !amounts.isEmpty { total = amounts.reduce(0, +) }
        }
        guard let total else { throw MyDataDocumentParserError.missingField("給付總額") }

        let payers = lines.filter { $0.contains("扣繳單位") || $0.contains("給付單位") }
            .compactMap { MyDataTextField.value(after: $0.contains("扣繳單位") ? "扣繳單位" : "給付單位", in: $0) }
        return MyDataParsedDocument(
            documentTypeID: documentTypeID, parserVersion: version,
            fields: [taxYearField: year,
                     totalField: String(total),
                     payerCountField: String(payers.count)])
    }

    private static func firstYear(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d{2,4})\\s*年度"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return MyDataTextField.gregorianYear(String(text[range]))
    }

    /// The last number on a line: 「合計　　1,234,567」.
    private static func trailingAmount(in line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9][0-9,]*)\\s*(元)?\\s*$"),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return MyDataTextField.digits(String(line[range])).flatMap(Int.init)
    }
}

// MARK: - 被保險人投保資料（勞保局）

/// Insured periods, one per row: the unit, a 加保 date, an optional 退保 date.
///
/// Rows are found by their dates rather than by column position: a row's first
/// date is the enrolment, a second date (when present) the withdrawal. A row
/// with a label but no date is not a period. The salary column is deliberately
/// not extracted — no scenario asks for it, and a field that is never parsed is
/// a field that can never leak.
enum MyDataLaborInsuranceParser: MyDataDocumentParser {
    static let documentTypeID = "mydata-labor-insurance"
    static let version = "labor-insurance-pdf/v1"

    static let periodCountField = "period_count"
    static let latestStartField = "latest_start"

    static func parse(text: String) throws -> MyDataParsedDocument {
        let recognised = ["投保資料", "加保", "投保單位"].contains { text.contains($0) }
        guard recognised else { throw MyDataDocumentParserError.notThisDocument }

        var periods: [MyDataCoveragePeriod] = []
        for line in text.components(separatedBy: .newlines) {
            // Header and title lines name the columns without dates; the rows
            // that matter carry at least an enrolment date.
            let dates = MyDataTextField.isoDates(in: line)
            guard let start = dates.first else { continue }
            let labelledEnd = MyDataTextField.value(after: "退保日期", in: line).flatMap(MyDataTextField.isoDate)
            let end = labelledEnd ?? (dates.count > 1 ? dates[1] : nil)
            periods.append(MyDataCoveragePeriod(start: start, end: end))
        }
        guard !periods.isEmpty else { throw MyDataDocumentParserError.missingField("加保日期") }
        let latest = periods.map(\.start).max() ?? ""
        return MyDataParsedDocument(
            documentTypeID: documentTypeID, parserVersion: version,
            fields: [periodCountField: String(periods.count), latestStartField: latest],
            periods: periods)
    }
}

// MARK: - 現戶全戶戶籍資料（戶政司）

/// The registered address, reduced to its city and district, and the date the
/// household was registered there when the page carries one.
///
/// Only the two coarsest address parts are ever extracted. The street, number,
/// household members and 記事 stay in the original: no scenario asks for them,
/// and the 6 gates in docs/mydata-vc-verifier-scenarios.md forbid deriving a
/// field that no verifier question needs.
enum MyDataHouseholdParser: MyDataDocumentParser {
    static let documentTypeID = "mydata-household"
    static let version = "household-pdf/v1"

    static let cityField = "household_city"
    static let districtField = "household_district"
    static let registeredSinceField = "registered_since"

    private static let cities = ["臺北市", "新北市", "桃園市", "臺中市", "臺南市", "高雄市",
                                 "基隆市", "新竹市", "嘉義市", "新竹縣", "苗栗縣", "彰化縣",
                                 "南投縣", "雲林縣", "嘉義縣", "屏東縣", "宜蘭縣", "花蓮縣",
                                 "臺東縣", "澎湖縣", "金門縣", "連江縣"]

    static func parse(text: String) throws -> MyDataParsedDocument {
        guard ["戶籍", "戶長", "戶號"].contains(where: { text.contains($0) }) else {
            throw MyDataDocumentParserError.notThisDocument
        }
        guard let rawAddress = MyDataTextField.value(after: "戶籍地址", in: text)
                ?? MyDataTextField.value(after: "住址", in: text) else {
            throw MyDataDocumentParserError.missingField("戶籍地址")
        }
        let address = MyDataTextField.normalised(rawAddress)
        guard let city = cities.first(where: { address.hasPrefix($0) }) else {
            throw MyDataDocumentParserError.missingField("縣市")
        }
        let afterCity = address.dropFirst(city.count)
        var district = ""
        if let end = afterCity.firstIndex(where: { "區鄉鎮市".contains($0) }) {
            district = String(afterCity[...end])
        }

        var fields = [cityField: city, districtField: district]
        for label in ["遷入日期", "初設戶籍日期", "設籍日期", "遷入登記日期"] {
            if let since = MyDataTextField.value(after: label, in: text).flatMap(MyDataTextField.isoDate) {
                fields[registeredSinceField] = since
                break
            }
        }
        return MyDataParsedDocument(documentTypeID: documentTypeID, parserVersion: version, fields: fields)
    }
}
