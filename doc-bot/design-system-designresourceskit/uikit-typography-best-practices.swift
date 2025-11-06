// ✅ CORRECT: Use typography directly without modification
class FeatureViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Typography is automatically configured for dynamic type
        titleLabel.font = UIFont.daxTitle2()
        bodyLabel.font = UIFont.daxBody()
        
        // Colors should also come from design system
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        bodyLabel.textColor = UIColor(designSystemColor: .textSecondary)
    }
}

// ❌ INCORRECT: Don't modify or override DRK fonts
titleLabel.font = UIFont.daxBody().withSize(18) // Don't override size
bodyLabel.font = UIFont.systemFont(ofSize: 16)  // Don't use system fonts

