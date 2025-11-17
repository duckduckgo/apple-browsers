// RED FLAGS - should be caught in review
.font(.title)                           // Should use .daxTitle2()
UIColor.black                          // Should use design system color
Color(red: 0.1, green: 0.2, blue: 0.3) // Should use semantic color
UIColor.systemBlue                     // Should use .accent or appropriate semantic color

// GOOD PATTERNS - approve these
Text("Title").daxTitle2()
UIFont.daxBody()
UIColor(designSystemColor: .textPrimary)
Color(designSystemColor: .background)

