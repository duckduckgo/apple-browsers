// BEFORE: Legacy hardcoded styling
class OldViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = UIColor.black
    }
}

// AFTER: Updated to use design system
class OldViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = UIFont.daxTitle2()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
    }
}

