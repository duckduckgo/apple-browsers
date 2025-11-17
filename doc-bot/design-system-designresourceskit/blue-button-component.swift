// Current usage (likely not yet in DRK)
class DuckBlueButton: UIButton {
    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = UIColor(designSystemColor: .buttonPrimaryBackground)
        setTitleColor(UIColor(designSystemColor: .buttonPrimaryText), for: .normal)
        titleLabel?.font = UIFont.daxBody()
        layer.cornerRadius = 8
    }
}

// Future: Should be moved to DRK as reusable component

