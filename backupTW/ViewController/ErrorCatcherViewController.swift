//
//  ErrorCatcherViewController.swift
//  backupTW
//
//  固定 UI 彈窗設計之錯誤展示視圖。
//  整合 Short Error（簡明摘要）、Catch Error（技術資訊與複製）與 Send Error（分享傳送）三層機制。
//

import UIKit

public final class ErrorCatcherViewController: UIViewController {

    private let alertTitle: String
    private let report: ErrorDiagnosticReport
    private let onDismiss: (() -> Void)?

    private let backdropView = UIView()
    private let cardContainer = UIView()
    private let copyButton = UIButton(type: .system)

    public init(title: String, report: ErrorDiagnosticReport, onDismiss: (() -> Void)? = nil) {
        self.alertTitle = title
        self.report = report
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        setupBackdrop()
        setupCardContainer()
    }

    private func setupBackdrop() {
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdropView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissModal))
        backdropView.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupCardContainer() {
        cardContainer.backgroundColor = .secondarySystemGroupedBackground
        Bonds.round(cardContainer.layer, Bonds.Radius.container)
        Bonds.Shadow.card(cardContainer.layer)
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardContainer)

        let cardWidthFill = cardContainer.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -48)
        cardWidthFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardContainer.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            cardContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            cardWidthFill,
            cardContainer.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            cardContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        // Header Row: 警示圖示＋標題
        let badge = makeVerdictBadge()
        let titleLabel = UILabel()
        titleLabel.text = alertTitle
        titleLabel.font = Bonds.Font.sectionTitle
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        let headerRow = UIStackView(arrangedSubviews: [badge, titleLabel])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = Bonds.Space.m

        // Short Error Label
        let shortLabel = UILabel()
        shortLabel.text = report.shortError
        shortLabel.font = Bonds.Font.pageTitle
        shortLabel.textColor = .label
        shortLabel.numberOfLines = 0
        shortLabel.adjustsFontForContentSizeCategory = true

        // Catch Error 區塊
        let catchErrorCard = makeCatchErrorCard()

        // Send Error 按鈕
        var sendConfig = UIButton.Configuration.filled()
        sendConfig.cornerStyle = .capsule
        sendConfig.baseBackgroundColor = Bonds.Color.accent
        sendConfig.baseForegroundColor = .white
        sendConfig.buttonSize = .large
        sendConfig.image = UIImage(systemName: "paperplane.fill")
        sendConfig.imagePadding = Bonds.Space.s
        sendConfig.title = NSLocalizedString("Send error report", comment: "send error action")
        let sendButton = UIButton(configuration: sendConfig)
        sendButton.addTarget(self, action: #selector(sendErrorReport(_:)), for: .touchUpInside)

        // 關閉「好」按鈕
        var dismissConfig = UIButton.Configuration.gray()
        dismissConfig.cornerStyle = .capsule
        dismissConfig.buttonSize = .large
        dismissConfig.title = NSLocalizedString("OK", comment: "")
        let dismissButton = UIButton(configuration: dismissConfig)
        dismissButton.addTarget(self, action: #selector(dismissModal), for: .touchUpInside)

        let buttonsStack = UIStackView(arrangedSubviews: [sendButton, dismissButton])
        buttonsStack.axis = .vertical
        buttonsStack.spacing = Bonds.Space.s

        // 總排版 Stack
        let mainStack = UIStackView(arrangedSubviews: [
            headerRow,
            shortLabel,
            catchErrorCard,
            buttonsStack,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = Bonds.Space.l
        mainStack.isLayoutMarginsRelativeArrangement = true
        mainStack.layoutMargins = UIEdgeInsets(
            top: Bonds.Space.page, left: Bonds.Space.page,
            bottom: Bonds.Space.page, right: Bonds.Space.page)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        cardContainer.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
        ])
    }

    private func makeVerdictBadge() -> UIView {
        let container = UIView()
        let tint = Bonds.Color.Verdict.caution
        container.backgroundColor = Bonds.Color.Verdict.fill(tint)
        Bonds.round(container.layer, 10)
        container.translatesAutoresizingMaskIntoConstraints = false

        let symbol = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        symbol.tintColor = tint
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(symbol)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalToConstant: 34),
            symbol.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 20),
            symbol.heightAnchor.constraint(equalToConstant: 20),
        ])
        return container
    }

    private func makeCatchErrorCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .tertiarySystemGroupedBackground
        Bonds.round(card.layer, Bonds.Radius.card)

        let headerLabel = UILabel()
        headerLabel.text = NSLocalizedString("Caught error", comment: "catch error header")
        headerLabel.font = Bonds.Font.caption
        headerLabel.textColor = .secondaryLabel
        headerLabel.adjustsFontForContentSizeCategory = true

        var copyConfig = UIButton.Configuration.plain()
        copyConfig.image = UIImage(systemName: "doc.on.doc")
        copyConfig.imagePadding = 4
        copyConfig.title = NSLocalizedString("Copy details", comment: "copy error details button")
        copyConfig.buttonSize = .mini
        copyButton.configuration = copyConfig
        copyButton.addTarget(self, action: #selector(copyErrorDetails), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [headerLabel, copyButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.distribution = .equalSpacing

        let detailLabel = UILabel()
        detailLabel.text = "\(report.errorType) (\(report.errorCode))\n\(report.technicalDetails)"
        detailLabel.font = Bonds.Font.mono(.footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "errorCatcher.technicalDetailsScroll"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(detailLabel)
        detailLabel.accessibilityIdentifier = "errorCatcher.technicalDetails"

        let scrollHeight = scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 100)
        scrollHeight.priority = .defaultHigh
        let minimumScrollHeight = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minimumScrollHeight.priority = .required

        NSLayoutConstraint.activate([
            detailLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            detailLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollHeight,
            minimumScrollHeight,
        ])

        let innerStack = UIStackView(arrangedSubviews: [topRow, scrollView])
        innerStack.axis = .vertical
        innerStack.spacing = Bonds.Space.s
        innerStack.isLayoutMarginsRelativeArrangement = true
        innerStack.layoutMargins = UIEdgeInsets(
            top: Bonds.Space.m, left: Bonds.Space.m,
            bottom: Bonds.Space.m, right: Bonds.Space.m)
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(innerStack)
        NSLayoutConstraint.activate([
            innerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            innerStack.topAnchor.constraint(equalTo: card.topAnchor),
            innerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return card
    }

    @objc private func copyErrorDetails() {
        UIPasteboard.general.string = report.formattedText
        Bonds.Haptic.scanLocked()

        copyButton.configuration?.image = UIImage(systemName: "checkmark")
        copyButton.configuration?.title = NSLocalizedString("Copied", comment: "")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.copyButton.configuration?.image = UIImage(systemName: "doc.on.doc")
            self?.copyButton.configuration?.title = NSLocalizedString("Copy details", comment: "copy error details button")
        }
    }

    @objc private func sendErrorReport(_ sender: UIButton) {
        let activity = UIActivityViewController(
            activityItems: [report.formattedText],
            applicationActivities: nil)

        if let popover = activity.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(activity, animated: true)
    }

    @objc private func dismissModal() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}
