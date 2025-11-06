// 🚨 RED FLAG: Using .font() likely indicates design system violation
Text("Title")
    .font(.title) // Should be .daxTitle2() or similar

Text("Body")  
    .font(.system(size: 16)) // Should be .daxBody()

// ✅ CORRECT: Using DRK modifiers
Text("Title")
    .daxTitle2()

Text("Body")
    .daxBody()

