import UIKit

protocol SoftKeyboardDelegate: AnyObject {
    func softKeyboard(_ keyboard: SoftKeyboardView, didPress character: Character)
    func softKeyboardDidPressBackspace(_ keyboard: SoftKeyboardView)
    func softKeyboardDidPressReturn(_ keyboard: SoftKeyboardView)
    func softKeyboardDidPressTab(_ keyboard: SoftKeyboardView)
    func softKeyboardDidPressDelete(_ keyboard: SoftKeyboardView)
    func softKeyboardDidToggleShift(_ keyboard: SoftKeyboardView, shifted: Bool)
}

class SoftKeyboardView: UIView {

    static let estimatedHeight: CGFloat = 244

    weak var delegate: SoftKeyboardDelegate?

    var theme: PaperTheme {
        didSet { setNeedsDisplay(); updateKeyColors() }
    }

    private var isShifted = false
    private var isCapsLocked = false
    private var isSymbolMode = false

    private let keyRows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["⇧","z","x","c","v","b","n","m","⌫"],
        ["123","space","↵"]
    ]

    private let symbolRows: [[String]] = [
        ["!","@","#","$","%","^","&","*","(",")"],
        ["-","_","=","+","{","}","[","]","|","\\"],
        [";",":","'","\"",",",".","/","?"],
        ["⇧","(",")","~","`","<",">","⌫"],
        ["ABC","space","↵"]
    ]

    private var activeRows: [[String]] { isSymbolMode ? symbolRows : keyRows }

    private var keyButtons: [String: UIButton] = [:]
    private var containerStack: UIStackView?

    private let keyHeight: CGFloat = 42
    private let keySpacing: CGFloat = 4
    private let rowSpacing: CGFloat = 6

    init(initialTheme: PaperTheme) {
        self.theme = initialTheme
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
        buildKeyboard()
    }

    required init?(coder: NSCoder) {
        self.theme = .dark
        super.init(coder: coder)
        backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
        buildKeyboard()
    }

    private func buildKeyboard() {
        containerStack?.removeFromSuperview()
        keyButtons.removeAll()

        let container = UIStackView()
        container.axis = .vertical
        container.spacing = rowSpacing
        container.alignment = .fill
        container.distribution = .fillEqually
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        containerStack = container

        var rowIdx = 0
        for row in activeRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = keySpacing
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            container.addArrangedSubview(rowStack)

            var colIdx = 0
            for key in row {
                let btn = UIButton(type: .system)
                btn.setTitle(key, for: .normal)
                btn.titleLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
                btn.titleLabel?.adjustsFontSizeToFitWidth = true
                btn.layer.cornerRadius = 5
                btn.layer.masksToBounds = true
                btn.tag = rowIdx * 100 + colIdx
                colIdx += 1

                let isSpecial = isSpecialKey(key)

                if key == "space" {
                    btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
                }

                btn.backgroundColor = keyBackgroundColor(isSpecial: isSpecial)
                btn.setTitleColor(keyTextColor(isSpecial: isSpecial), for: .normal)
                btn.setTitleColor(keyTextColor(isSpecial: isSpecial).withAlphaComponent(0.5), for: .highlighted)

                btn.addTarget(self, action: #selector(keyTapped(_:)), for: .touchDown)
                btn.addTarget(self, action: #selector(keyReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

                let units = widthUnit(forKey: key)
                if units != 1.0 {
                    btn.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    btn.widthAnchor.constraint(greaterThanOrEqualToConstant: keyHeight * 0.8).isActive = true
                } else {
                    btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                    btn.setContentCompressionResistancePriority(.required, for: .horizontal)
                }

                rowStack.addArrangedSubview(btn)
                keyButtons[key + "_\(rowIdx)"] = btn
            }
            rowIdx += 1
        }

        updateShiftState()
    }

    private func widthUnit(forKey key: String) -> CGFloat {
        switch key {
        case "space": return 5
        case "⇧", "⌫", "↵", "123", "ABC": return 1.5
        default: return 1
        }
    }

    private func isSpecialKey(_ key: String) -> Bool {
        switch key {
        case "⇧", "⌫", "↵", "space", "123", "ABC": return true
        default: return false
        }
    }

    private func keyBackgroundColor(isSpecial: Bool) -> UIColor {
        UIColor(white: isSpecial ? 0.22 : 0.14, alpha: 1)
    }

    private func keyTextColor(isSpecial: Bool) -> UIColor {
        UIColor(white: 0.85, alpha: 1)
    }

    private func updateKeyColors() {
        for (_, btn) in keyButtons {
            guard let title = btn.titleLabel?.text else { continue }
            btn.backgroundColor = keyBackgroundColor(isSpecial: isSpecialKey(title))
            btn.setTitleColor(keyTextColor(isSpecial: isSpecialKey(title)), for: .normal)
        }
        updateShiftState()
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let title = sender.titleLabel?.text else { return }
        UIView.animate(withDuration: 0.05) {
            sender.backgroundColor = self.theme.rule.withAlphaComponent(0.6)
        }

        switch title {
        case "⇧":
            if isCapsLocked { isCapsLocked = false; isShifted = false }
            else { isShifted.toggle() }
            updateShiftState()
        case "⌫":
            delegate?.softKeyboardDidPressBackspace(self)
        case "↵":
            delegate?.softKeyboardDidPressReturn(self)
        case "space":
            delegate?.softKeyboard(self, didPress: " ")
        case "123":
            isSymbolMode = true; buildKeyboard()
        case "ABC":
            isSymbolMode = false; buildKeyboard()
        default:
            let ch: Character = (isShifted && title.count == 1) ? Character(title.uppercased()) : Character(title)
            delegate?.softKeyboard(self, didPress: ch)
            if isShifted && !isCapsLocked { isShifted = false; updateShiftState() }
        }
    }

    @objc private func keyReleased(_ sender: UIButton) {
        guard let title = sender.titleLabel?.text else { return }
        UIView.animate(withDuration: 0.1) {
            sender.backgroundColor = self.keyBackgroundColor(isSpecial: self.isSpecialKey(title))
        }
    }

    private func updateShiftState() {
        for (key, btn) in keyButtons {
            let baseKey = key.components(separatedBy: "_").first ?? ""
            if baseKey == "⇧" {
                btn.backgroundColor = isShifted ? theme.rule.withAlphaComponent(0.4) : keyBackgroundColor(isSpecial: true)
            } else if baseKey.count == 1 && !isSpecialKey(baseKey) {
                btn.setTitle(isShifted ? baseKey.uppercased() : baseKey.lowercased(), for: .normal)
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.estimatedHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 10
        layer.masksToBounds = true
    }
}