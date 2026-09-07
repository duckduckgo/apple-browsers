# Per-site permission manager — expected behavior and test scenarios

This document lists what the iOS per-site permission manager does and how to check it. It is written for anyone who tests the feature, including people who don't read code. Each scenario has three parts: the situation, what you do, and what you should see.

The feature covers three permissions — **camera**, **microphone**, and **location** — and ships behind the `sitePermissions` feature flag. Unless a scenario says otherwise, the flag is on.

Example sites used throughout: `example.com`, `maps.example.com`, and `shop.example.com` are three different subdomains of one site.

---

## 1. The feature flag

| Scenario | Steps | Expected result |
|---|---|---|
| Flag off — camera or microphone | Turn the flag off. Visit a site that asks for the camera. | The browser behaves exactly as before the feature: WebKit's own two-button prompt appears. No new menu item, no Settings entry. |
| Flag off — location | Turn the flag off. Visit a site that asks for your location. | WebKit's own location prompt appears, as before. |
| Flag off — Voice Search | Turn the flag off. Deny microphone access to the app, then tap the microphone button in the address bar. | The old plain alert appears (title, message, **Settings**, **Cancel**). |
| Flag turned off after use | Use the feature, then turn the flag off. | New page loads behave as before the feature. Pages already open keep their current state until you reload them. |

## 2. The permission prompt

| Scenario | Steps | Expected result |
|---|---|---|
| First request | Visit `example.com` and trigger a camera request. | DuckDuckGo's own dialog appears with three buttons, in this order: **Allow Once**, **Allow While Using Site**, **Never Allow**. The page stays visible behind it. |
| Our prompt comes first | Fresh install. Allow the camera in our dialog. | Only after you tap **Allow Once** or **Allow While Using Site** does the iOS system prompt ("DuckDuckGo would like to access the camera") appear. |
| Declining never reaches iOS | Fresh install. Tap **Never Allow**. | The iOS system prompt never appears. The one-time system prompt is saved for later. |
| System permission already granted | The app already has camera access. Allow a site. | No iOS system prompt. The site gets the camera immediately. |
| The system prompt never appears alone | Any situation. | The iOS system prompt only ever appears right after you allow a site in our dialog. It never appears on its own. |
| Camera and microphone together | Visit a video-call site that asks for both at once. | One combined dialog appears: *"example.com" website wants to access your camera and microphone.* Not two dialogs. |
| Camera only or microphone only | Visit a site that asks for only one of them. | The dialog names only that permission. |
| Location on DuckDuckGo search | On duckduckgo.com, trigger a location request. | A special dialog appears with the DuckDuckGo logo and the text about anonymizing your location. |
| Dialogs never stack | Trigger two requests in quick succession. | Dialogs appear one at a time, never on top of each other. |

## 3. Decisions are stored per subdomain

| Scenario | Steps | Expected result |
|---|---|---|
| Subdomains are separate | Allow the camera on `maps.example.com`. Visit `shop.example.com`. | `shop.example.com` asks again. It has its own record. |
| Deny one, keep another | Choose **Never Allow** on `shop.example.com`. Return to `maps.example.com`. | `maps.example.com` still has the camera. Only `shop.example.com` is blocked. |
| Settings shows both | After the two steps above, open Settings > Site Permissions. | Two separate entries: `maps.example.com` and `shop.example.com`. |
| `www` is the same site | Allow the camera on `www.example.com`. Visit `example.com`. | No new prompt. `www.example.com` and `example.com` share one record. |
| Address doesn't matter | Allow the camera on `https://example.com`. Later open the same site through another link or port. | Same record. Only the site name matters, not the address details. |
| Embedded frames belong to the page | A page on `example.com` embeds a widget from `widgets.example.com` that asks for the camera. | The decision is recorded for the page you see in the address bar. |
| Location from another site's frame | A page on `example.com` embeds a map from `othersite.com` that asks for your location. | The request is denied. No dialog appears. |

## 4. Allow Once

| Scenario | Steps | Expected result |
|---|---|---|
| Works for the page | Tap **Allow Once**. Use the camera. | The camera works for this page. |
| Ends on reload | Tap **Allow Once**, then reload the page. | The site asks again. |
| Ends when you leave | Tap **Allow Once**, then navigate to another page. | The next page asks again. |
| Survives going to the background | Tap **Allow Once**. Switch to another app, then come back. | The permission is still active. |
| Ends when the app is closed | Tap **Allow Once**. Force-quit the app and reopen it. | The site asks again. |
| Never saved | Tap **Allow Once**, then open Settings > Site Permissions. | The site is not listed. |
| A single-page site navigating within itself | Tap **Allow Once** on a site that changes its address without reloading (for example, a web app switching tabs). | The permission stays active. |

## 5. Saved decisions

| Scenario | Steps | Expected result |
|---|---|---|
| Allow While Using Site | Tap **Allow While Using Site**. Close the tab. Return to the site later. | The site gets the camera without asking. |
| Never Allow | Tap **Never Allow**. Return to the site later and trigger a request. | The request is denied silently. No dialog. |
| Deny once | In the dialog, deny for this page only (the site's request fails without a saved decision), then trigger the request again on the same page. | No second dialog on this page. |
| Allow once, then the site asks again after finishing | Tap **Allow Once**. The site stops using the camera and later asks again. | The dialog may appear again. |

## 6. Global settings (Settings > Site Permissions)

Each permission type has a global default: **Ask Each Time** or **Never Allow**.

| Scenario | Steps | Expected result |
|---|---|---|
| Default | Fresh install. Open Settings > Site Permissions. | All three types show **Ask Each Time**. |
| Never Allow stops new prompts | Set Camera to **Never Allow**. Visit a new site that asks for the camera. | No dialog. The request is denied silently. |
| A saved Allow still works | Allow the camera on `example.com` first. Then set the global default to **Never Allow**. Return to `example.com`. | The camera still works. The global setting stops new asking; it does not override sites you already allowed. |
| A saved Never still blocks | Set a site to **Never Allow**. Set the global default back to **Ask Each Time**. | The site is still blocked. |
| System Settings link | On the Site Permissions page, tap the **System Settings** link in the footer. | iOS Settings opens on the DuckDuckGo app page. |

## 7. Manage Sites (the list in Settings)

| Scenario | Steps | Expected result |
|---|---|---|
| Empty state | Fresh install. Open Settings > Site Permissions. | The global settings and footer only. No **Manage Sites** section. |
| Prompting creates no entry | Visit a site, see the dialog, and dismiss it without a permanent choice. | The site is not listed. |
| Allow Once creates no entry | Tap **Allow Once**. | The site is not listed. |
| A permanent choice creates an entry | Tap **Allow While Using Site** or **Never Allow**. | The site appears under **Manage Sites**. |
| Per-site page | Tap a site in the list. | A page titled with the site name shows Location, Camera, and Microphone, each with **Ask Each Time / Always Allow / Never Allow**. The header shows the real site name. |
| Reset to Ask keeps the entry | On a site's page, set every permission back to **Ask Each Time**. | The site stays in the list until you remove it. |
| Remove one site | Tap **Remove Permissions** on a site's page. | The site disappears from the list. A toast says *Permissions removed for example.com* with **Undo**. |
| Undo | Tap **Undo** on the toast. | The site and its exact previous choices return. |
| Undo after a newer change | Remove a site, then make a new choice for that site before the toast disappears, then tap **Undo**. | Your newer choice is kept. Undo does not overwrite it. |
| Remove all | Tap **Remove All Site Permissions**. | The list empties. A toast offers **Undo**. The global defaults are unchanged. |
| Position in Settings | Open the main Settings screen in different languages. | The **Site Permissions** row appears in alphabetical position for that language. Its position can differ by language. |

## 8. The on-site sheet (browser menu > Site Permissions)

| Scenario | Steps | Expected result |
|---|---|---|
| Hidden by default | Visit a site that has never asked for a permission. Open the browser menu. | No **Site Permissions** item. |
| Appears after a decision | Make any permanent choice, or hold an active Allow Once. Open the menu. | The **Site Permissions** item appears. |
| Appears for a reset site | A site whose only record is a reset to **Ask Each Time**. | The item appears. |
| Sheet contents | Tap **Site Permissions**. | A sheet titled *Permissions for "example.com"* lists the relevant permissions: saved ones, active ones, and ones requested during this visit. Permissions the site never touched are not listed. |
| Long site names | Open the sheet on a site with a very long name. | The title is shortened with an ellipsis. |
| Icon states | Compare rows. | Ask Each Time: outline icon. Never Allow: blocked icon. Always Allow: solid icon. Currently in use: solid red icon. |
| Muted camera or microphone | The site mutes its own camera or microphone stream. | The icon is not red. The permission is not shown as in use. |
| Accessibility | Use VoiceOver on the rows. | VoiceOver reads the permission, its saved state, and whether it is in use. The visible design is unchanged. |
| Grant needs a reload | Change a permission from Never Allow to Always Allow while the page is open. | The sheet says *Reload the page for changes to take effect.* The site gets the permission after reload. |
| Deny stops use immediately | While the site is using the camera, change it to **Never Allow**. | The camera stops right away. |
| Remove stops use immediately | While the site is using the camera, tap **Remove Permissions**. | The camera stops right away. The toast offers **Undo**. |
| Same list as Settings | Change a permission in the sheet. Open Settings > Site Permissions. | The change is reflected there. Both surfaces show one shared record. |

## 9. Recovering from a denied system permission

The iOS system prompt appears only once per permission for the whole app. After you tap **Don't Allow** on it, only iOS Settings can turn the permission back on.

| Scenario | Steps | Expected result |
|---|---|---|
| Case A: deny the system prompt | Allow a site, then tap **Don't Allow** on the iOS prompt. | The site does not get the permission. A toast says *DuckDuckGo couldn't give camera access to this site.* The site's **Always Allow** choice is kept. |
| Case A: the sheet shows a reminder | After the step above, open the menu > Site Permissions. | The sheet shows a **Go to System Settings** row and explains that DuckDuckGo needs access to the camera. |
| Case B: system permission already denied | The app already has camera access denied. Allow a site. | No iOS prompt (it can't be shown). A reminder dialog appears: *DuckDuckGo needs to access your camera*, with **Change Permissions** and **Cancel**. |
| Change Permissions | Tap **Change Permissions**. | iOS Settings opens on the DuckDuckGo app page. |
| Coming back from Settings | Enable the permission in iOS Settings and return to the browser. Trigger the request again. | The site gets the permission. The reminder disappears from the sheet. |
| Revoked later in iOS Settings | Allow a site and the system prompt. Later, turn the permission off in iOS Settings. Return and trigger a request. | Same as Case B. The site's saved choice is not changed. |
| Camera and microphone, one blocked | The app has microphone access but camera access is denied. A site asks for both. | The request is denied without an iOS prompt. The reminder names only the camera. |
| Camera and microphone, both blocked | Both are denied at the system level. A site asks for both. | The reminder names camera and microphone together. |
| Restricted device | Camera access is blocked by Screen Time or a device-management profile. | Treated like a denied system permission. The standard reminder appears. (Dedicated handling for this case is planned later.) |

## 10. Fire Button

| Scenario | Steps | Expected result |
|---|---|---|
| Fire clears permissions | Save permissions on several sites. Press the Fire Button. | The sites disappear from Settings > Site Permissions. They ask again on the next visit. |
| Fireproofed sites keep permissions | Fireproof `example.com`. Save permissions on it. Press the Fire Button. | `example.com` keeps its permissions and stays listed. |
| Fireproofing covers the whole site | Fireproof `maps.example.com`. Save permissions on `maps.example.com` and on `shop.example.com`. Press the Fire Button. | Both keep their permissions, because fireproofing protects the whole `example.com` site, the same way it protects cookies. |
| Manual removal ignores fireproofing | Fireproof `example.com`. Tap **Remove All Site Permissions** in Settings. | `example.com` is removed too. |
| Global defaults survive Fire | Set Camera to **Never Allow**. Press the Fire Button. | Camera is still **Never Allow**. Fire clears site records only. |
| Fire works with the flag off | Save permissions, turn the flag off, press the Fire Button, turn the flag on. | The saved permissions are gone. |
| Auto-clear | Enable auto-clear on app start. Save permissions. Restart the app. | Permissions are cleared the same way the Fire Button clears them. |

## 11. Fire-mode tabs

| Scenario | Steps | Expected result |
|---|---|---|
| Saved decisions apply | Save **Always Allow** on `example.com` in a normal tab. Open `example.com` in a fire-mode tab. | No prompt. The saved decision applies. |
| Global settings apply | Set Camera to **Never Allow**. Ask for the camera in a fire-mode tab. | Denied silently. |
| Nothing is saved | In a fire-mode tab, tap **Allow While Using Site** on a new site. Then open Settings > Site Permissions. | The site is not listed. The choice lasted only for that fire-mode session. |

## 12. Duck.ai

| Scenario | Steps | Expected result |
|---|---|---|
| Duck.ai is unchanged | Use voice features in Duck.ai. | Behavior is exactly as before the feature, with the flag on or off. No three-button dialog, no Settings entry. |
| Global Never Allow doesn't apply | Set Microphone to **Never Allow**. Use Duck.ai voice. | Duck.ai still follows its own microphone behavior. |

## 13. Voice Search

| Scenario | Steps | Expected result |
|---|---|---|
| Microphone denied | Deny microphone access to the app. Tap the microphone button in the address bar. | A dialog says *DuckDuckGo needs to access your microphone* and explains it's needed for Private Voice Search, with **Change Permissions**, **Hide Voice Search**, and **Cancel**. |
| Change Permissions | Tap **Change Permissions**. | iOS Settings opens on the DuckDuckGo app page. |
| Hide Voice Search | Tap **Hide Voice Search**. | The microphone button disappears from the address bar (the Voice Search setting is turned off). |

## 14. Location specifics

| Scenario | Steps | Expected result |
|---|---|---|
| Our dialog replaces WebKit's | Visit a site that asks for your location. | Only DuckDuckGo's three-button dialog appears. WebKit's "would like to use your location" prompt does not. |
| Continuous location | Allow location on a map site that tracks you as you move. | Position updates keep flowing until you leave the page or close the tab. |
| Insecure pages | Visit an `http://` page that asks for your location. | Denied. No dialog. |
| The site checks its own permission state | On the test page `privacy-test-pages.site/features/permissions-api.html`, compare the reported state with what actually happens on request. | They agree: granted, denied, or prompt. |
| Site opts out of location | Visit a page whose server disables geolocation for itself. | Denied. No dialog. |

## 15. Privacy and analytics

| Scenario | Steps | Expected result |
|---|---|---|
| No site names in analytics | Review the pixels the feature sends. | They record the permission type and the choice, never the website address. |
| Nothing leaves the device | Use the feature on two devices with the same account. | Permission choices do not sync between devices. They are stored only on the device. |

---

## Test sites

- Camera, microphone, and location requests: `privacy-test-pages.site/features/permissions-api.html`
- Location only: `privacy-test-pages.site/features/geolocation.html`
- Embedded frames: `privacy-test-pages.site/features/iframe-permissions.html`
- Subdomain scenarios: use the test subdomains listed in the privacy-test-pages repository.
