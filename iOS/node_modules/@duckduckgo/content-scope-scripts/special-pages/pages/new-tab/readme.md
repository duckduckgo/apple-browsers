# URL Search Parameter Reference Guide
 This comprehensive guide documents all available URL search parameters for testing, reviews, and development purposes. Use these parameters to trigger specific states, features, or experiments without modifying code.

 ## Page-Level Parameters

 ### Component Display View
 - **Purpose**: Displays configurable stickersheet view outside normal page flow
 - **Parameter**: `display`
 - **Example**: `?display=components`
 - **Options**:
   - `components` - Shows component stickersheet

 ### Language/Locale Selector
 - **Purpose**: Tests UI with different languages to verify layout and translations
 - **Parameter**: `locale`
 - **Example**: `?locale=fr`
 - **Options**: Any language code available in the [locale directory](../public/locales)

 ### Text Length Modifier
 - **Purpose**: Tests UI with different text lengths to verify layout flexibility
 - **Parameter**: `textLength`
 - **Example**: `?textLength=1.5`
 - **Options**:
   - Number higher than 1

 ### Platform Simulator
 - **Purpose**: Simulates different platforms for testing
 - **Parameter**: `platform`
 - **Example**: `?platform=windows`
 - **Options**:
   - `windows`
   - `macos`
   - `android`
   - `ios`
   - `integration`

 ### Animation Toggle
 - **Purpose**: Enables/disables animations for testing
 - **Parameter**: `animation`
 - **Example**: `?animation=none`
 - **Options**:
   - `view-transitions` - Enables animations
   - `none` - Disables animations

 ### Error Testing
 - **Purpose**: Forces error state for testing error handling
 - **Parameter**: `willThrow`
 - **Example**: `?willThrow=true`
 - **Options**:
   - `true` - Forces an error

### Skip Reading form LocalStorage
 - **Purpose**: If present, prevents the mock transport from reading persisted state (like widget configs) from localStorage on initialization
 - **Parameter**: `skip-read`
 - **Example**: `?skip-read=true`
 - **Options**:
   - `true`

### Skip Writing to LocalStorage
 - **Purpose**: If present, prevents the mock transport from writing state changes (like widget configs) to localStorage
 - **Parameter**: `skip-read`
 - **Example**: `?skip-read=true`
 - **Options**:
   - `true`

### Control Visual styles
`defaultStyles`
 - **Purpose**: If set to `visual-refresh`, applies specific background color variables (`--default-light-background-color`, `--default-dark-background-color`) to the body.
 - **Parameter**: `defaultStyles`
 - **Example**: `?defaultStyles=visual-refresh`
 - **Options**:
   - `visual-refresh`

 ## Feature Parameters

 ### Favorites
 - **Purpose**: Controls favorites feature
 - **Parameter**: `favorites`
 - **Example**: `?favorites=show`
 - **Options**:
   - `many`
   - `single`
   - `none`
   - `small-icon`
   - `fallbacks`
   - `titles`

 ### Update Notification
 - **Purpose**: Controls update notification display
 - **Parameter**: `update-notification`
 - **Example**: `?update-notification=show`
 - **Options**:
   - `show` - Shows update notification
   - `hide` - Hides update notification

 ### Update Notification Delay
 - **Purpose**: Sets delay before showing update notification
 - **Parameter**: `update-notification-delay`
 - **Example**: `?update-notification-delay=5000`
 - **Options**: Time in milliseconds

 ### Customizer Auto-Open
 - **Purpose**: Controls whether customizer opens automatically
 - **Parameter**: `customizer_autoOpen`
 - **Example**: `?customizer_autoOpen=true`
 - **Options**:
   - `true` - Opens customizer automatically
   - `false` - Does not open customizer automatically

 ### RMF (Remote Messaging Framework)
 - **Purpose**: Controls Remote Messaging Framework dialog
 - **Parameter**: `rmf`
 - **Example**: `?rmf=show`
 - **Options**:
   - `show` - Shows RMF dialog
   - `hide` - Hides RMF dialog

 ### RMF Delay
 - **Purpose**: Sets delay before showing RMF dialog
 - **Parameter**: `rmf-delay`
 - **Example**: `?rmf-delay=10000`
 - **Options**: Time in milliseconds

## Privacy Protections widget

 ### Activity
  - **Purpose**: Modifies activity display count
 - **Parameter**: `activity`
 - **Example**: `?activity=empty`
 - **Options**:
   - `empty`

 ### Feed Controls
 - **Purpose**: Modifies feed display and behavior
 - **Parameter**: `feed`
 - **Example**: `?feed=activity`
 - **Options**:
   - `stats` - Displays the Privacy Stats widget
   - `activity` - Displays the Activity widget
   - `both` - Display both privacy widgets

### Proctections
 - **Purpose**: Controls number of stats shown in Protections feature
 - **Parameter**: `protections`
 - **Example**: `?protections=many`
 - **Options**:
   - `many`
   - `few`
   - `empty`

### Protections Continuous
 - **Purpose**: Displays a continuous flow of protections stats to hydrate Protections widget
 - **Parameter**: `protections.continuous`
 - **Example**: `?protections.continuous=`
 - **Options**:


 ### Stats Display
 - **Purpose**: Controls statistics display
 - **Parameter**: `stats`
 - **Example**: `?stats=show`
 - **Options**:
   - `show` - Shows statistics
   - `hide` - Hides statistics

 ### Stats Update Count
 - **Purpose**: Sets the number of updates for statistics
 - **Parameter**: `stats-update-count`
 - **Example**: `?stats-update-count=5`
 - **Options**: Any positive integer


 ## Experiment Parameters

 ### Freemium PIR Banner
 - **Purpose**: Tests different PIR banner states
 - **Parameter**: `pir`
 - **Example**: `?pir=onboarding`
 - **Options**:
   - `onboarding` - Shows onboarding PIR banner
   - `scan_results` - Shows scan results PIR banner



 ## Combining Parameters

 Parameters can be combined using the `&` character to test multiple features simultaneously:

 `
 ?display=components&locale=fr&textLength=long
 `

 This example shows the component stickersheet in French with long text strings.

 ## Usage Examples

 ### For Developers
 - Testing language support: `?locale=de`
 - Testing responsive layouts: `?textLength=long&platform=mobile`
 - Testing error states: `?willThrow=true`

 ### For Product Reviews
 - Testing experiment variations: `?pir=onboarding`
 - Testing feature states: `?stats=show&feed=empty`

 ### For Design Reviews
 - Component review: `?display=components`
 - Testing text overflow: `?textLength=long`
 - Testing animations: `?animation=on`
