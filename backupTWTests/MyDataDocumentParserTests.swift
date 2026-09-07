//
//  MyDataDocumentParserTests.swift
//  backupTWTests
//
//  What the vault parsers read, and what they refuse to guess.
//
//  ⚠️ The fixtures here are synthetic page text in the layouts the parsers
//  expect. The real-document gate (docs/mydata-vc-verifier-scenarios.md, gate
//  1) is checked on a phone with the DEBUG 「Parse the original」 row, not here.
//

import Foundation
import PDFKit
import Testing
import UIKit
@testable import backupTW

@Suite("MyData 文字欄位：日期、數字、標籤")
struct MyDataTextFieldTests {

    @Test(arguments: [
        ("113/02/01", "2024-02-01"),
        ("113.02.01", "2024-02-01"),
        ("113年2月1日", "2024-02-01"),
        ("民國113年02月01日", "2024-02-01"),
        ("1130201", "2024-02-01"),
        ("2024-02-01", "2024-02-01"),
        ("2024/02/01", "2024-02-01"),
        ("20240201", "2024-02-01"),
    ])
    func everyDateSpellingBecomesISO(_ raw: String, _ iso: String) {
        #expect(MyDataTextField.isoDate(raw) == iso)
    }

    @Test func aDateThatIsNotOneIsNil() {
        #expect(MyDataTextField.isoDate("113/13/01") == nil)
        #expect(MyDataTextField.isoDate("abc") == nil)
        #expect(MyDataTextField.isoDate("") == nil)
    }

    @Test func labelsAcceptBothColonWidths() {
        #expect(MyDataTextField.value(after: "所得年度", in: "所得年度：113") == "113")
        #expect(MyDataTextField.value(after: "所得年度", in: "所得年度: 113") == "113")
        #expect(MyDataTextField.value(after: "所得年度", in: "所得年度：113  所得人：王小明") == "113")
    }

    @Test func amountsLoseTheirFormatting() {
        #expect(MyDataTextField.digits("NT$1,234,567 元") == "1234567")
        #expect(MyDataTextField.digits("無") == nil)
        #expect(MyDataTextField.gregorianYear("113年度") == "2024")
        #expect(MyDataTextField.gregorianYear("2024") == "2024")
    }
}

@Suite("個人所得資料 parser")
struct MyDataIncomeParserTests {

    static let statement = """
    財政部財政資訊中心 個人所得資料表
    所得年度：113  所得人姓名：王小明
    序號 所得類別 扣繳單位 給付總額
    1 薪資所得 扣繳單位：有備而來股份有限公司 給付總額：1,200,000
    2 利息所得 扣繳單位：測試銀行 給付總額：3,450
    合計 1,203,450
    """

    @Test func readsTheYearAndTheTotalFromTheTotalLine() throws {
        let parsed = try MyDataIncomeParser.parse(text: Self.statement)
        #expect(parsed.parserVersion == "income-pdf/v1")
        #expect(parsed.fields[MyDataIncomeParser.taxYearField] == "2024")
        #expect(parsed.fields[MyDataIncomeParser.totalField] == "1203450")
        #expect(parsed.fields[MyDataIncomeParser.payerCountField] == "2")
    }

    @Test func sumsTheRowsWhenThereIsNoTotalLine() throws {
        let text = Self.statement.components(separatedBy: "\n").filter { !$0.contains("合計") }.joined(separator: "\n")
        let parsed = try MyDataIncomeParser.parse(text: text)
        #expect(parsed.fields[MyDataIncomeParser.totalField] == "1203450")
    }

    @Test func refusesADocumentOfAnotherKind() {
        #expect(throws: MyDataDocumentParserError.notThisDocument) {
            _ = try MyDataIncomeParser.parse(text: "現戶全戶戶籍資料 戶籍地址：臺北市")
        }
    }

    @Test func refusesAStatementWithoutAmountsRatherThanReportingZero() {
        #expect(throws: MyDataDocumentParserError.missingField("給付總額")) {
            _ = try MyDataIncomeParser.parse(text: "個人所得資料表\n所得年度：113\n查無資料")
        }
    }
}

@Suite("被保險人投保資料 parser")
struct MyDataLaborInsuranceParserTests {

    static let record = """
    勞動部勞工保險局 被保險人投保資料
    投保單位名稱 加保日期 退保日期 投保薪資
    甲公司 110/03/01 112/06/30 45,800
    乙公司 112/07/01  50,600
    """

    @Test func readsOnePeriodPerDatedRow() throws {
        let parsed = try MyDataLaborInsuranceParser.parse(text: Self.record)
        #expect(parsed.periods == [
            MyDataCoveragePeriod(start: "2021-03-01", end: "2023-06-30"),
            MyDataCoveragePeriod(start: "2023-07-01", end: nil),
        ])
        #expect(parsed.fields[MyDataLaborInsuranceParser.latestStartField] == "2023-07-01")
        // The salary column is never read.
        #expect(parsed.fields.values.contains("50600") == false)
    }

    @Test func labelledRowsAreReadTheSameWay() throws {
        let text = "被保險人投保資料\n投保單位：丙公司 加保日期：1130115 退保日期：1130430"
        let parsed = try MyDataLaborInsuranceParser.parse(text: text)
        #expect(parsed.periods == [MyDataCoveragePeriod(start: "2024-01-15", end: "2024-04-30")])
    }

    @Test func aRecordWithoutDatesIsMissingItsEnrolment() {
        #expect(throws: MyDataDocumentParserError.missingField("加保日期")) {
            _ = try MyDataLaborInsuranceParser.parse(text: "被保險人投保資料\n查無投保紀錄")
        }
    }
}

@Suite("現戶全戶戶籍資料 parser")
struct MyDataHouseholdParserTests {

    static let record = """
    現戶全戶戶籍資料
    戶號：A1234567 戶長：王小明
    戶籍地址：台北市大安區和平東路二段 1 號 3 樓
    遷入日期：民國108年05月20日
    記事：略
    """

    @Test func keepsOnlyTheCityAndDistrict() throws {
        let parsed = try MyDataHouseholdParser.parse(text: Self.record)
        #expect(parsed.fields[MyDataHouseholdParser.cityField] == "臺北市")
        #expect(parsed.fields[MyDataHouseholdParser.districtField] == "大安區")
        #expect(parsed.fields[MyDataHouseholdParser.registeredSinceField] == "2019-05-20")
        // The street and number never make it into a field.
        #expect(parsed.fields.values.contains { $0.contains("和平東路") } == false)
    }

    @Test func aCountyAddressParsesTheSameWay() throws {
        let parsed = try MyDataHouseholdParser.parse(text: "戶籍資料\n戶籍地址：新竹縣竹北市光明六路 1 號")
        #expect(parsed.fields[MyDataHouseholdParser.cityField] == "新竹縣")
        #expect(parsed.fields[MyDataHouseholdParser.districtField] == "竹北市")
        #expect(parsed.fields[MyDataHouseholdParser.registeredSinceField] == nil)
    }

    @Test func anAddressOutsideTheKnownCitiesIsRefused() {
        #expect(throws: MyDataDocumentParserError.missingField("縣市")) {
            _ = try MyDataHouseholdParser.parse(text: "戶籍資料\n戶籍地址：火星市")
        }
    }
}

@Suite("規則 → 衍生欄位")
struct MyDataDerivedCredentialTypeTests {

    @Test func incomeWithinCeilingIsComputedForTheAskedYear() throws {
        let parsed = try MyDataIncomeParser.parse(text: MyDataIncomeParserTests.statement)
        let within = try MyDataDerivedCredentialType.income.derive(
            from: parsed, rule: .init(id: "income-ceiling/v1", params: ["tax_year": "2024", "ceiling_twd": "1500000"]))
        #expect(within == ["tax_year": "2024", "payer_count": "2", "income_within_ceiling": "true"])
        let above = try MyDataDerivedCredentialType.income.derive(
            from: parsed, rule: .init(id: "income-ceiling/v1", params: ["tax_year": "2024", "ceiling_twd": "1000000"]))
        #expect(above["income_within_ceiling"] == "false")
    }

    @Test func theWrongYearIsRefusedNotAnsweredFalse() throws {
        let parsed = try MyDataIncomeParser.parse(text: MyDataIncomeParserTests.statement)
        #expect(throws: MyDataDerivationError.documentDoesNotCoverRule("tax_year")) {
            _ = try MyDataDerivedCredentialType.income.derive(
                from: parsed, rule: .init(id: "income-ceiling/v1", params: ["tax_year": "2023", "ceiling_twd": "1"]))
        }
    }

    @Test func insuranceOnADateLooksAcrossEveryPeriod() throws {
        let parsed = try MyDataLaborInsuranceParser.parse(text: MyDataLaborInsuranceParserTests.record)
        func insured(_ date: String) throws -> String? {
            try MyDataDerivedCredentialType.laborInsurance.derive(
                from: parsed, rule: .init(id: "insurance-active/v1", params: ["on_date": date]))["insured_on_date"]
        }
        #expect(try insured("2022-01-01") == "true")    // inside the first period
        #expect(try insured("2023-06-30") == "true")    // last day of it
        #expect(try insured("2026-09-01") == "true")    // open-ended second period
        #expect(try insured("2020-12-31") == "false")   // before any
        #expect(try insured("113/06/30") == "true")     // ROC spelling in the rule
    }

    @Test func householdCityComparesNormalisedNames() throws {
        let parsed = try MyDataHouseholdParser.parse(text: MyDataHouseholdParserTests.record)
        let claims = try MyDataDerivedCredentialType.household.derive(
            from: parsed, rule: .init(id: "household-city/v1", params: ["city": "台北市", "min_months": "6"]))
        #expect(claims["registered_in_city"] == "true")
        #expect(claims["registered_at_least_months"] == "true")
        let other = try MyDataDerivedCredentialType.household.derive(
            from: parsed, rule: .init(id: "household-city/v1", params: ["city": "新北市"]))
        #expect(other == ["registered_in_city": "false"])
    }

    @Test func aRuleWithAStrayParameterIsRefused() {
        let rule = MyDataDisclosureRule(id: "income-ceiling/v1",
                                        params: ["tax_year": "2024", "ceiling_twd": "1", "echo_me": "x"])
        #expect(rule.validationProblem() == .ruleParameterUnexpected("echo_me"))
        #expect(MyDataDisclosureRule(id: "unknown/v9", params: [:]).validationProblem() == .ruleNotSupported("unknown/v9"))
        #expect(MyDataDisclosureRule(json: ["id": "x", "params": ["a": 1]]) == nil)
    }

    @Test func everyTypeHasAParserAndAUniqueVCT() {
        for type in MyDataDerivedCredentialType.all {
            #expect(MyDataDocumentParsers.parser(for: type.documentTypeID) != nil, Comment(rawValue: type.vct))
            #expect(type.vct.hasPrefix("https://bonds-tw.github.io/vct/"))
        }
        #expect(Set(MyDataDerivedCredentialType.all.map(\.vct)).count == MyDataDerivedCredentialType.all.count)
    }
}

@Suite("保險箱原檔文字抽取：PDF 密碼、CSV 編碼")
struct MyDataVaultTextTests {

    private func pdf(text: String, password: String?) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 300), format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            text.draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        guard let password, let document = PDFDocument(data: data) else { return data }
        let sealed = NSMutableData()
        // PDFKit writes the encrypted copy through a temporary file.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        document.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
        sealed.append(try! Data(contentsOf: url))
        try? FileManager.default.removeItem(at: url)
        return sealed as Data
    }

    @Test func aPlainPDFYieldsItsText() throws {
        let text = try MyDataVaultText.text(of: pdf(text: "所得年度：113", password: nil), fileExtension: "pdf")
        #expect(text.contains("所得年度"))
    }

    @Test func aSealedPDFOpensWithThePasswordAndRefusesWithout() throws {
        let sealed = pdf(text: "所得年度：113", password: "A123456789")
        #expect(try PDFDocument(data: sealed)?.isLocked == true)
        #expect(throws: MyDataDocumentParserError.locked) {
            _ = try MyDataVaultText.text(of: sealed, fileExtension: "pdf")
        }
        let text = try MyDataVaultText.text(of: sealed, fileExtension: "pdf", password: "a123456789")
        #expect(text.contains("所得年度"))
    }

    @Test func aCSVIsDecodedAsUTF8ThenBig5() throws {
        #expect(try MyDataVaultText.text(of: Data("所得年度,113".utf8), fileExtension: "csv") == "所得年度,113")
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        let bytes = try #require("所得年度,113".data(using: String.Encoding(rawValue: big5)))
        #expect(try MyDataVaultText.text(of: bytes, fileExtension: "csv") == "所得年度,113")
    }
}
