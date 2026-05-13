# How do I reach page X? — Rebranded Onboarding

| Page | Required state (in order) |
|---|---|
| ① Landing | `hasSeenOnboarding = false` + FF `onboardingRebranding = ON` + launch app |
| ②a Intro `.default` | reach ① + `onboardingUserType = .newUser` (Debug menu) |
| ②b Intro `.restoreData` | reach ① + `onboardingUserType = .returningUser` + sync account exists (eligible for restore) |
| ②c Intro `.skipTutorial` | reach ① + `onboardingUserType = .returningUser` + no sync account |
| ③ Skip confirmation | reach any ② + tap **Skip** |
| ④ Browsers Comparison | reach ②a/②c + tap **Continue** (or ②b + Skip without restore) |
| ⑤ Add to Dock Promo | reach ④ on **iPhone** + tap **Next** |
| ⑤b Add to Dock Tutorial | reach ⑤ + tap **Show me how** |
| ⑥ App Icon Picker | reach ⑤/⑤b on iPhone, or ④ directly on iPad |
| ⑦ Address Bar Position | reach ⑥ on **iPhone** + tap **Next** (iPad skips this) |
| ⑧ Search Experience | reach ⑦ on iPhone + tap **Next** |
| ⑨ Duck.ai Query Experiment | reach ⑧ + choose **AI Chat** + FF `onboardingDuckAIQueryExperiment = ON` + cohort `treatmentA` or `treatmentB` |

### Practical debug recipe
1. Reset onboarding → Debug menu → "Reset Onboarding" (clears hasSeenOnboarding and the resume store).
2. Rebrand flag → Debug menu → Feature Flags → onboardingRebranding = ON.
3. User type → Debug menu → "Onboarding User Type" → .newUser or .returningUser (only works on DEBUG/ALPHA builds; see OnboardingManager.swift:80-86).
4. For the Duck.ai experiment page (⑨) → also flip onboardingDuckAIQueryExperiment ON and force cohort treatmentA/treatmentB via the experiment override.
5. Cold launch and walk through.

Skip ahead via resume store: OnboardingResumeStep (OnboardingManager.swift:158) is in UserDefaults. Setting resumeStep = .searchExperienceSelection and relaunching jumps you straight to ⑧, etc. The Debug menu may already expose this — search DebugScreens for resume.

