// ✅ REQUIRED: Use DesignResourcesKit colors
label.textColor = UIColor(designSystemColor: .textPrimary)
view.backgroundColor = UIColor(designSystemColor: .background)

// ✅ REQUIRED: Use DesignResourcesKit typography
titleLabel.font = UIFont.daxTitle1()
bodyLabel.font = UIFont.daxBody()

// ✅ REQUIRED: Use DesignResourcesKit icons
let image = DesignSystemImages.Color.Size24.bookmark

// ❌ FORBIDDEN: Hardcoded colors/fonts/icons
label.textColor = UIColor.black
titleLabel.font = UIFont.systemFont(ofSize: 24)
let image = UIImage(systemName: "bookmark")

