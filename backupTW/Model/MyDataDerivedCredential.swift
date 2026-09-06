//
//  MyDataDerivedCredential.swift
//  backupTW
//
//  What a vault document can say to a verifier, and the rules that say it.
//

import Foundation

/// A verifier's question, in the form the wallet computes an answer to.
///
/// # Why the rule is data the verifier sends, not code the verifier keeps
///
/// The scenarios document forbids disclosing the exact income; the verifier
/// gets 「within the ceiling: yes」. That answer depends on a year and a ceiling,
/// so the verifier states both in its signed request, the wallet computes the
/// predicate from the original, and **the same rule goes into the signed
/// credential**. A verifier can then check it evaluated the question it asked,
/// and a later reader of the credential knows what 「true」 was true *of*.
struct MyDataDisclosureRule: Equatable {
    /// `income-ceiling/v1`, `insurance-active/v1`, `household-city/v1`.
    let id: String
    /// Every value a string, in the same shape it is signed.
    let params: [String: String]

    /// The parameter names each rule needs. Anything else in `params` is
    /// refused: an unexpected key could be a verifier smuggling a field it
    /// wants echoed back under the holder's signature.
    static let requiredParams: [String: [String]] = [
        "income-ceiling/v1": ["tax_year", "ceiling_twd"],
        "insurance-active/v1": ["on_date"],
        "household-city/v1": ["city"],
    ]
    static let optionalParams: [String: [String]] = [
        "household-city/v1": ["min_months"],
    ]

    init?(json: Any?) {
        guard let object = json as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let raw = object["params"] as? [String: Any] else { return nil }
        var params: [String: String] = [:]
        for (key, value) in raw {
            guard let string = value as? String else { return nil }
            params[key] = string
        }
        self.init(id: id, params: params)
    }

    init(id: String, params: [String: String]) {
        self.id = id
        self.params = params
    }

    /// `nil` when the rule is one this build computes and its parameters are
    /// exactly the expected ones.
    func validationProblem() -> MyDataDerivationError? {
        guard let required = Self.requiredParams[id] else { return .ruleNotSupported(id) }
        for key in required where params[key]?.isEmpty != false {
            return .ruleParameterMissing(key)
        }
        let allowed = Set(required + (Self.optionalParams[id] ?? []))
        if let stray = params.keys.first(where: { !allowed.contains($0) }) {
            return .ruleParameterUnexpected(stray)
        }
        return nil
    }

    /// JSON in the shape it is signed into the credential's `rule`.
    var json: [String: Any] { ["id": id, "params": params] }

    /// The question, as the holder reads it on the consent screen.
    var question: String {
        switch id {
        case "income-ceiling/v1":
            return String(format: NSLocalizedString(
                "Was your %@ income at or below NT$%@?", comment: "derived rule question: income ceiling"),
                params["tax_year"] ?? "", Self.grouped(params["ceiling_twd"] ?? ""))
        case "insurance-active/v1":
            return String(format: NSLocalizedString(
                "Were you covered by labour insurance on %@?", comment: "derived rule question: insurance"),
                params["on_date"] ?? "")
        case "household-city/v1":
            if let months = params["min_months"], !months.isEmpty {
                return String(format: NSLocalizedString(
                    "Has your household been registered in %@ for at least %@ months?",
                    comment: "derived rule question: household city with duration"),
                    params["city"] ?? "", months)
            }
            return String(format: NSLocalizedString(
                "Is your household registered in %@?", comment: "derived rule question: household city"),
                params["city"] ?? "")
        default:
            return id
        }
    }

    /// The kind of question, without its parameters — for a list that says
    /// what a document can answer before any verifier has asked.
    var kindDescription: String {
        switch id {
        case "income-ceiling/v1":
            return NSLocalizedString("income within a ceiling for a tax year", comment: "derived rule kind")
        case "insurance-active/v1":
            return NSLocalizedString("labour insurance in force on a date", comment: "derived rule kind")
        case "household-city/v1":
            return NSLocalizedString("household registered in a city", comment: "derived rule kind")
        default:
            return id
        }
    }

    private static func grouped(_ digits: String) -> String {
        guard let value = Int(digits) else { return digits }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? digits
    }
}

enum MyDataDerivationError: Error, Equatable {
    /// The request named a rule this build does not compute.
    case ruleNotSupported(String)
    case ruleParameterMissing(String)
    case ruleParameterUnexpected(String)
    /// The rule and the document do not meet: an income rule for 2024 against
    /// a 2023 statement. Refused, not answered 「false」 — a false answer here
    /// would be a lie about the wrong year.
    case documentDoesNotCoverRule(String)
}

/// One claim a derived credential can carry.
struct MyDataDerivedClaim: Equatable {
    enum Kind: Equatable {
        /// Copied from the document (a year, a count).
        case fact
        /// Computed from the document and the rule (`true` / `false`).
        case predicate
    }
    let name: String
    let kind: Kind
}

/// The credential type a vault document derives into: its `vct`, its claims,
/// and the rules it answers.
///
/// # Why `vct` is a URL under bonds-tw.github.io
///
/// SD-JWT VC names a credential's type with `vct`; a verifier that recognises
/// the URL knows the claim names, their labels, and which are predicates —
/// the Type Metadata document lives at that URL. The wallet is the party that
/// defines what it derives, so the type lives under the wallet's own host, not
/// any one verifier's.
struct MyDataDerivedCredentialType: Equatable {
    let vct: String
    /// `vct#integrity`: SRI-style SHA-256 of the Type Metadata document at
    /// `vct`, so a verifier can pin the exact claim definitions this build
    /// minted against. Recomputed whenever the metadata file changes
    /// (bonds-tw.github.io `vct/index.json` lists the current values).
    let vctIntegrity: String
    /// `MyDataDocumentRegistry` id of the source document.
    let documentTypeID: String
    let claims: [MyDataDerivedClaim]
    let rules: [String]

    static let vctBase = "https://bonds-tw.github.io/vct/"

    static let income = MyDataDerivedCredentialType(
        vct: vctBase + "mydata-income/v1.json",
        vctIntegrity: "sha256-UWf/U6jOpKCHfZxeIMTh0snMIglSOjDdxy76cI/BENA=",
        documentTypeID: MyDataIncomeParser.documentTypeID,
        claims: [.init(name: "tax_year", kind: .fact),
                 .init(name: "payer_count", kind: .fact),
                 .init(name: "income_within_ceiling", kind: .predicate)],
        rules: ["income-ceiling/v1"])

    static let laborInsurance = MyDataDerivedCredentialType(
        vct: vctBase + "mydata-labor-insurance/v1.json",
        vctIntegrity: "sha256-qtCc76IWmYLsuHXKYGXmHL00MI4vjKWvSwuzjWKEXPs=",
        documentTypeID: MyDataLaborInsuranceParser.documentTypeID,
        claims: [.init(name: "on_date", kind: .fact),
                 .init(name: "insured_on_date", kind: .predicate)],
        rules: ["insurance-active/v1"])

    static let household = MyDataDerivedCredentialType(
        vct: vctBase + "mydata-household/v1.json",
        vctIntegrity: "sha256-d8lnX7PMXJyryDSHYcHYPEa9TlKEZX9DUgRWJ9jSEk0=",
        documentTypeID: MyDataHouseholdParser.documentTypeID,
        claims: [.init(name: "registered_in_city", kind: .predicate),
                 .init(name: "registered_at_least_months", kind: .predicate)],
        rules: ["household-city/v1"])

    static let all: [MyDataDerivedCredentialType] = [income, laborInsurance, household]

    static func lookup(vct: String) -> MyDataDerivedCredentialType? {
        all.first { $0.vct == vct }
    }

    static func lookup(documentTypeID: String) -> MyDataDerivedCredentialType? {
        all.first { $0.documentTypeID == documentTypeID }
    }

    var claimNames: [String] { claims.map(\.name) }

    /// Computes every claim of this type from a parsed document and a rule.
    ///
    /// Returns strings only, `"true"` / `"false"` for predicates — the same
    /// spelling the national ID's `over18AtIssuance` already uses and the
    /// verifier already reads. A predicate that cannot be evaluated (a
    /// household page without a registration date, asked for a duration) is
    /// simply absent, so it can neither be disclosed nor requested.
    func derive(from document: MyDataParsedDocument,
                rule: MyDataDisclosureRule) throws -> [String: String] {
        guard document.documentTypeID == documentTypeID else {
            throw MyDataDerivationError.documentDoesNotCoverRule(document.documentTypeID)
        }
        if let problem = rule.validationProblem() { throw problem }
        guard rules.contains(rule.id) else { throw MyDataDerivationError.ruleNotSupported(rule.id) }

        switch rule.id {
        case "income-ceiling/v1":
            guard let year = document.fields[MyDataIncomeParser.taxYearField],
                  let total = document.fields[MyDataIncomeParser.totalField].flatMap(Int.init),
                  let ceiling = Int(rule.params["ceiling_twd"] ?? "") else {
                throw MyDataDerivationError.documentDoesNotCoverRule("income")
            }
            guard year == rule.params["tax_year"] else {
                throw MyDataDerivationError.documentDoesNotCoverRule("tax_year")
            }
            return ["tax_year": year,
                    "payer_count": document.fields[MyDataIncomeParser.payerCountField] ?? "0",
                    "income_within_ceiling": total <= ceiling ? "true" : "false"]

        case "insurance-active/v1":
            guard let onDate = rule.params["on_date"].flatMap(MyDataTextField.isoDate) else {
                throw MyDataDerivationError.ruleParameterMissing("on_date")
            }
            let active = document.periods.contains { period in
                period.start <= onDate && (period.end == nil || period.end! >= onDate)
            }
            return ["on_date": onDate, "insured_on_date": active ? "true" : "false"]

        case "household-city/v1":
            guard let city = document.fields[MyDataHouseholdParser.cityField] else {
                throw MyDataDerivationError.documentDoesNotCoverRule("household_city")
            }
            let asked = MyDataTextField.normalised(rule.params["city"] ?? "")
            var claims = ["registered_in_city": city == asked ? "true" : "false"]
            if let months = rule.params["min_months"].flatMap(Int.init),
               let since = document.fields[MyDataHouseholdParser.registeredSinceField] {
                claims["registered_at_least_months"] =
                    Self.months(from: since, to: Date()) >= months && city == asked ? "true" : "false"
            }
            return claims

        default:
            throw MyDataDerivationError.ruleNotSupported(rule.id)
        }
    }

    static func months(from iso: String, to now: Date) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let since = formatter.date(from: iso) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        return max(0, calendar.dateComponents([.month], from: since, to: now).month ?? 0)
    }
}
