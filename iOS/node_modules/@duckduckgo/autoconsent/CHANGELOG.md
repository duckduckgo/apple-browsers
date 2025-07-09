# v13.0.0 (Tue May 20 2025)

#### 💥 Breaking Change

- Compact rule format [#743](https://github.com/duckduckgo/autoconsent/pull/743) ([@sammacbeth](https://github.com/sammacbeth))

#### 🐛 Bug Fix

- CI: Release hook to update privacy-config repo. [#748](https://github.com/duckduckgo/autoconsent/pull/748) ([@sammacbeth](https://github.com/sammacbeth))
- Disable auto release to native apps [#747](https://github.com/duckduckgo/autoconsent/pull/747) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.20.1 (Fri May 16 2025)

#### 🐛 Bug Fix

- Fix onetrust rule [#746](https://github.com/duckduckgo/autoconsent/pull/746) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v12.20.0 (Fri May 16 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 2f58b73d955695278fb506b785926f67ee2785f9 [#745](https://github.com/duckduckgo/autoconsent/pull/745) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Bump the dev-dependencies group across 1 directory with 6 updates [#739](https://github.com/duckduckgo/autoconsent/pull/739) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add support for FastCMP and iframe piercing [#744](https://github.com/duckduckgo/autoconsent/pull/744) ([@muodov](https://github.com/muodov))
- Update EasyList Cookie to eed61600bcc040dd99171437652da1884d43dfcb [#737](https://github.com/duckduckgo/autoconsent/pull/737) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Bump @ghostery/adblocker from 2.5.1 to 2.5.2 [#732](https://github.com/duckduckgo/autoconsent/pull/732) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker-content from 2.5.1 to 2.5.2 [#733](https://github.com/duckduckgo/autoconsent/pull/733) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump tldts-experimental from 7.0.4 to 7.0.7 [#740](https://github.com/duckduckgo/autoconsent/pull/740) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Prevent OneTrust from being detected as site-specific [#738](https://github.com/duckduckgo/autoconsent/pull/738) ([@muodov](https://github.com/muodov))
- Fix: Mutation observer race condition during rule detection [#741](https://github.com/duckduckgo/autoconsent/pull/741) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.19.0 (Wed May 07 2025)

#### 🚀 Enhancement

- Bump tldts-experimental from 6.1.85 to 7.0.4 [#728](https://github.com/duckduckgo/autoconsent/pull/728) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump the dev-dependencies group across 1 directory with 7 updates [#729](https://github.com/duckduckgo/autoconsent/pull/729) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Fix: Exclude rules from detection if they have a urlPattern and it does not match. [#736](https://github.com/duckduckgo/autoconsent/pull/736) ([@sammacbeth](https://github.com/sammacbeth))
- Make detection logs toggleable [#730](https://github.com/duckduckgo/autoconsent/pull/730) ([@muodov](https://github.com/muodov))
- Bump action-asana-sync to v11 [#731](https://github.com/duckduckgo/autoconsent/pull/731) ([@sammacbeth](https://github.com/sammacbeth))
- Bump @ghostery/adblocker-content from 2.5.0 to 2.5.1 [#725](https://github.com/duckduckgo/autoconsent/pull/725) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker from 2.5.0 to 2.5.1 [#724](https://github.com/duckduckgo/autoconsent/pull/724) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.18.0 (Tue Apr 29 2025)

#### 🚀 Enhancement

- Delay reruns of the detectCmp phase until there is a dom mutation. [#721](https://github.com/duckduckgo/autoconsent/pull/721) ([@sammacbeth](https://github.com/sammacbeth))
- Prioritize checking of site-specific rules in detection phase. [#720](https://github.com/duckduckgo/autoconsent/pull/720) ([@sammacbeth](https://github.com/sammacbeth))
- Run detection phase sequentially per CMP. [#719](https://github.com/duckduckgo/autoconsent/pull/719) ([@sammacbeth](https://github.com/sammacbeth))
- Fix rule for openai [#723](https://github.com/duckduckgo/autoconsent/pull/723) ([@muodov](https://github.com/muodov))
- Update EasyList Cookie to 39338825841d682f464b10b174ea835000e30c0f [#722](https://github.com/duckduckgo/autoconsent/pull/722) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Only process Asana tasks when PR contains task URL [#718](https://github.com/duckduckgo/autoconsent/pull/718) ([@noisysocks](https://github.com/noisysocks))

#### Authors: 4

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.17.0 (Mon Apr 14 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to e1d6329233498d8cb5a5fe473e516475ee3da6e8 [#713](https://github.com/duckduckgo/autoconsent/pull/713) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Bump the dev-dependencies group across 1 directory with 5 updates [#715](https://github.com/duckduckgo/autoconsent/pull/715) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add rule for nos.nl [#712](https://github.com/duckduckgo/autoconsent/pull/712) ([@noisysocks](https://github.com/noisysocks))
- Update EasyList Cookie to 54998140e5d5e212ead7be504a42fe3afb8cfdc6 [#708](https://github.com/duckduckgo/autoconsent/pull/708) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Jenkins CI: Use GIT_COMMIT when notifying GitHub [#714](https://github.com/duckduckgo/autoconsent/pull/714) ([@noisysocks](https://github.com/noisysocks))
- Update Asana integration to support multiple tasks and ignore tasks not in CPM project [#707](https://github.com/duckduckgo/autoconsent/pull/707) ([@noisysocks](https://github.com/noisysocks))
- Update CI pipeline to run only relevant tests for a PR [#710](https://github.com/duckduckgo/autoconsent/pull/710) ([@noisysocks](https://github.com/noisysocks))
- Fix HTML formatting for task list in release notes [#705](https://github.com/duckduckgo/autoconsent/pull/705) ([@noisysocks](https://github.com/noisysocks))

#### ⚠️ Pushed to `main`

- Try main branch of native-github-asana-sync ([@noisysocks](https://github.com/noisysocks))
- Try a different build of native-github-asana-sync ([@noisysocks](https://github.com/noisysocks))
- Try different build of native-github-asana-sync ([@noisysocks](https://github.com/noisysocks))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.16.0 (Tue Mar 25 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 43935b4bf6a715553ae4d2ccc628462fad8188f2 [#704](https://github.com/duckduckgo/autoconsent/pull/704) ([@muodov](https://github.com/muodov) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Fix rule for bbb.org [#678](https://github.com/duckduckgo/autoconsent/pull/678) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Add Asana automations [#701](https://github.com/duckduckgo/autoconsent/pull/701) ([@noisysocks](https://github.com/noisysocks))
- Bump the dev-dependencies group with 5 updates [#702](https://github.com/duckduckgo/autoconsent/pull/702) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump tldts-experimental from 6.1.84 to 6.1.85 [#703](https://github.com/duckduckgo/autoconsent/pull/703) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Improve burpee.com rule [#698](https://github.com/duckduckgo/autoconsent/pull/698) ([@noisysocks](https://github.com/noisysocks))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))

---

# v12.15.0 (Fri Mar 21 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 9232b2df4b9314504bc835d2aaf3fb72c3aa872a [#700](https://github.com/duckduckgo/autoconsent/pull/700) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Update deepl rule to match new markup [#695](https://github.com/duckduckgo/autoconsent/pull/695) ([@noisysocks](https://github.com/noisysocks) [@muodov](https://github.com/muodov))
- Add rule for caranddriver.com [#696](https://github.com/duckduckgo/autoconsent/pull/696) ([@noisysocks](https://github.com/noisysocks))
- Add AdOpt CMP [#697](https://github.com/duckduckgo/autoconsent/pull/697) ([@noisysocks](https://github.com/noisysocks))

#### 🐛 Bug Fix

- Bump the dev-dependencies group with 2 updates [#699](https://github.com/duckduckgo/autoconsent/pull/699) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 5

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.14.0 (Fri Mar 14 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to b6ba5e180e756441787c7415b894e2ade23a758f [#692](https://github.com/duckduckgo/autoconsent/pull/692) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Fix sourcepoint rule for US version of ft.com [#693](https://github.com/duckduckgo/autoconsent/pull/693) ([@muodov](https://github.com/muodov))
- More site-specific rules [#676](https://github.com/duckduckgo/autoconsent/pull/676) ([@muodov](https://github.com/muodov))
- Fix a race condition with self-test in test extension [#690](https://github.com/duckduckgo/autoconsent/pull/690) ([@muodov](https://github.com/muodov))
- add rule for web.de [#691](https://github.com/duckduckgo/autoconsent/pull/691) ([@muodov](https://github.com/muodov))
- Bump the dev-dependencies group across 1 directory with 12 updates [#689](https://github.com/duckduckgo/autoconsent/pull/689) ([@dependabot[bot]](https://github.com/dependabot[bot]) [@muodov](https://github.com/muodov))
- Bump @ghostery/adblocker-content from 2.3.1 to 2.5.0 [#607](https://github.com/duckduckgo/autoconsent/pull/607) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker from 2.3.1 to 2.5.0 [#608](https://github.com/duckduckgo/autoconsent/pull/608) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- support no-reject Osano popups [#683](https://github.com/duckduckgo/autoconsent/pull/683) ([@muodov](https://github.com/muodov))
- Add rule for ok.ru [#665](https://github.com/duckduckgo/autoconsent/pull/665) ([@muodov](https://github.com/muodov))
- Automatically restore element focus after the opt-in/opt-out [#687](https://github.com/duckduckgo/autoconsent/pull/687) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Update Asana sync action [#694](https://github.com/duckduckgo/autoconsent/pull/694) ([@sammacbeth](https://github.com/sammacbeth))
- Bump tldts-experimental from 6.1.82 to 6.1.84 [#688](https://github.com/duckduckgo/autoconsent/pull/688) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.13.0 (Fri Mar 07 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 0f2116100a57d0ec74666508d405fc4da80f1f9d [#685](https://github.com/duckduckgo/autoconsent/pull/685) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Several site-specific rules [#673](https://github.com/duckduckgo/autoconsent/pull/673) ([@muodov](https://github.com/muodov))
- add rule for fedex.com [#669](https://github.com/duckduckgo/autoconsent/pull/669) ([@muodov](https://github.com/muodov))
- Rule batch [#684](https://github.com/duckduckgo/autoconsent/pull/684) ([@muodov](https://github.com/muodov))
- Add rule for pornhat and a few other sites [#677](https://github.com/duckduckgo/autoconsent/pull/677) ([@muodov](https://github.com/muodov))
- Add rule for live.paloaltonetworks.com [#672](https://github.com/duckduckgo/autoconsent/pull/672) ([@muodov](https://github.com/muodov))
- Update rules for finsweet CMPs [#658](https://github.com/duckduckgo/autoconsent/pull/658) ([@muodov](https://github.com/muodov))
- add rules for povr.com and tinyurl.com [#659](https://github.com/duckduckgo/autoconsent/pull/659) ([@muodov](https://github.com/muodov))
- fix instagram rule [#668](https://github.com/duckduckgo/autoconsent/pull/668) ([@muodov](https://github.com/muodov))
- add rule for acs.org [#671](https://github.com/duckduckgo/autoconsent/pull/671) ([@muodov](https://github.com/muodov))
- Add rule for ryanair [#670](https://github.com/duckduckgo/autoconsent/pull/670) ([@muodov](https://github.com/muodov))
- [NSFW] add rule for several sites [#682](https://github.com/duckduckgo/autoconsent/pull/682) ([@muodov](https://github.com/muodov))
- Batch of site-specific rules [#680](https://github.com/duckduckgo/autoconsent/pull/680) ([@muodov](https://github.com/muodov))
- Rules for Toyota sites [#679](https://github.com/duckduckgo/autoconsent/pull/679) ([@muodov](https://github.com/muodov))
- Another batch of rules [#681](https://github.com/duckduckgo/autoconsent/pull/681) ([@muodov](https://github.com/muodov))
- Declarative rule steps for negation and for matching cookies [#663](https://github.com/duckduckgo/autoconsent/pull/663) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Bump tldts-experimental from 6.1.77 to 6.1.82 [#674](https://github.com/duckduckgo/autoconsent/pull/674) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Monthly Coverage data update [#667](https://github.com/duckduckgo/autoconsent/pull/667) ([@daxtheduck](https://github.com/daxtheduck) [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 5

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Dax ([@daxtheduck](https://github.com/daxtheduck))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.12.0 (Fri Feb 28 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 1f078adcab61d59e006a1b16847c07bcede57ea3 [#664](https://github.com/duckduckgo/autoconsent/pull/664) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- add rule for tplink sites [#662](https://github.com/duckduckgo/autoconsent/pull/662) ([@muodov](https://github.com/muodov))
- Add rule for synology sites [#661](https://github.com/duckduckgo/autoconsent/pull/661) ([@muodov](https://github.com/muodov))
- add rule for wix.com [#666](https://github.com/duckduckgo/autoconsent/pull/666) ([@muodov](https://github.com/muodov))
- Site-specific rules for several top domains [#657](https://github.com/duckduckgo/autoconsent/pull/657) ([@muodov](https://github.com/muodov))
- Fix rules for xhamster [#649](https://github.com/duckduckgo/autoconsent/pull/649) ([@muodov](https://github.com/muodov))
- Support another flavor of borlabs [#650](https://github.com/duckduckgo/autoconsent/pull/650) ([@muodov](https://github.com/muodov))
- Add rule for macaron CMP [#651](https://github.com/duckduckgo/autoconsent/pull/651) ([@muodov](https://github.com/muodov))
- add rule for a common cmp [#652](https://github.com/duckduckgo/autoconsent/pull/652) ([@muodov](https://github.com/muodov))
- Add rule for ring.com [#654](https://github.com/duckduckgo/autoconsent/pull/654) ([@muodov](https://github.com/muodov))
- add rule for nhnieuws.nl [#655](https://github.com/duckduckgo/autoconsent/pull/655) ([@muodov](https://github.com/muodov))
- add rule for plos.org [#656](https://github.com/duckduckgo/autoconsent/pull/656) ([@muodov](https://github.com/muodov))
- Add rule for help.twitter.com [#648](https://github.com/duckduckgo/autoconsent/pull/648) ([@muodov](https://github.com/muodov))
- Add rule for anthropic [#647](https://github.com/duckduckgo/autoconsent/pull/647) ([@muodov](https://github.com/muodov))
- add rule for adultfriendfinder.com [#646](https://github.com/duckduckgo/autoconsent/pull/646) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- increase the timeout in cookiebot to prevent race conditions [#653](https://github.com/duckduckgo/autoconsent/pull/653) ([@muodov](https://github.com/muodov))

#### 🏠 Internal

- Do not print the rule in creation script [#660](https://github.com/duckduckgo/autoconsent/pull/660) ([@muodov](https://github.com/muodov))

#### Authors: 3

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.11.0 (Fri Feb 21 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 021d8018ab06e861b47cb0c6f2eae756f27c05de [#643](https://github.com/duckduckgo/autoconsent/pull/643) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Add artificial delay to the sourcepoint rule to mitigate race conditions [#640](https://github.com/duckduckgo/autoconsent/pull/640) ([@muodov](https://github.com/muodov))
- Add rule for gdpr-legal-cookie CMP [#636](https://github.com/duckduckgo/autoconsent/pull/636) ([@noisysocks](https://github.com/noisysocks))

#### 🏠 Internal

- Update release workflow to support Apple monorepo [#627](https://github.com/duckduckgo/autoconsent/pull/627) ([@samsymons](https://github.com/samsymons))

#### 🧪 Tests

- Monthly Coverage data update [#642](https://github.com/duckduckgo/autoconsent/pull/642) ([@daxtheduck](https://github.com/daxtheduck) [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 6

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Dax ([@daxtheduck](https://github.com/daxtheduck))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))
- Sam Symons ([@samsymons](https://github.com/samsymons))

---

# v12.10.0 (Fri Feb 14 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 7c1f69a77b0ee7c97112fba6f7394d11edcf3877 [#638](https://github.com/duckduckgo/autoconsent/pull/638) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Add site specific rule for bbc.com [#637](https://github.com/duckduckgo/autoconsent/pull/637) ([@noisysocks](https://github.com/noisysocks))
- Bump the dev-dependencies group across 1 directory with 6 updates [#634](https://github.com/duckduckgo/autoconsent/pull/634) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Add rule for inmobi.com and related websites [#639](https://github.com/duckduckgo/autoconsent/pull/639) ([@noisysocks](https://github.com/noisysocks))
- Add rule for ct-ultimate-gdpr CMP [#635](https://github.com/duckduckgo/autoconsent/pull/635) ([@noisysocks](https://github.com/noisysocks) [@muodov](https://github.com/muodov))
- Add Pandectes CMP [#632](https://github.com/duckduckgo/autoconsent/pull/632) ([@noisysocks](https://github.com/noisysocks))
- Bump tldts-experimental from 6.1.75 to 6.1.77 [#633](https://github.com/duckduckgo/autoconsent/pull/633) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add jetpack-eu-cookie-law CMP [#631](https://github.com/duckduckgo/autoconsent/pull/631) ([@noisysocks](https://github.com/noisysocks))

#### Authors: 5

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.9.0 (Fri Feb 07 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 7eba802a2208dd322d820a2aad7a256377c3afec [#630](https://github.com/duckduckgo/autoconsent/pull/630) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Fix Tealium rule on barmer.de [#628](https://github.com/duckduckgo/autoconsent/pull/628) ([@noisysocks](https://github.com/noisysocks))
- Adjust cookie-law-info to hide site-specific #cookie-law-bg element [#625](https://github.com/duckduckgo/autoconsent/pull/625) ([@noisysocks](https://github.com/noisysocks))
- Remove wetransfer rule, update fide to remove popup on wetransfer.com [#626](https://github.com/duckduckgo/autoconsent/pull/626) ([@noisysocks](https://github.com/noisysocks))
- Monthly Coverage data update [#622](https://github.com/duckduckgo/autoconsent/pull/622) ([@daxtheduck](https://github.com/daxtheduck) [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 4

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Dax ([@daxtheduck](https://github.com/daxtheduck))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.8.0 (Fri Jan 31 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to 71afe4eb4e86bb49fac1a7d5e53a10373081336e [#618](https://github.com/duckduckgo/autoconsent/pull/618) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Improve Termly rule [#619](https://github.com/duckduckgo/autoconsent/pull/619) ([@muodov](https://github.com/muodov))
- Bump the dev-dependencies group across 1 directory with 5 updates [#621](https://github.com/duckduckgo/autoconsent/pull/621) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add rule for Shopify Customer Privacy CMP [#616](https://github.com/duckduckgo/autoconsent/pull/616) ([@noisysocks](https://github.com/noisysocks))
- Add rule for Gravito [#610](https://github.com/duckduckgo/autoconsent/pull/610) ([@muodov](https://github.com/muodov))
- Improve the Civic rule [#614](https://github.com/duckduckgo/autoconsent/pull/614) ([@muodov](https://github.com/muodov))
- Add rule for postnl.nl [#612](https://github.com/duckduckgo/autoconsent/pull/612) ([@muodov](https://github.com/muodov))
- Quantcast fixes [#611](https://github.com/duckduckgo/autoconsent/pull/611) ([@muodov](https://github.com/muodov))
- Add rule for Privado CMP [#602](https://github.com/duckduckgo/autoconsent/pull/602) ([@muodov](https://github.com/muodov))
- Support CCPA sourcepoint popup on timeout.com [#603](https://github.com/duckduckgo/autoconsent/pull/603) ([@muodov](https://github.com/muodov))
- Fix opera rule [#604](https://github.com/duckduckgo/autoconsent/pull/604) ([@muodov](https://github.com/muodov))
- Adapt gov.uk rule for https://www.tax.service.gov.uk/business-account [#605](https://github.com/duckduckgo/autoconsent/pull/605) ([@muodov](https://github.com/muodov))
- cosmetic rule for womenshealthmag [#601](https://github.com/duckduckgo/autoconsent/pull/601) ([@muodov](https://github.com/muodov))
- Add rule for Squiz CDP [#599](https://github.com/duckduckgo/autoconsent/pull/599) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Bump tldts-experimental from 6.1.70 to 6.1.75 [#606](https://github.com/duckduckgo/autoconsent/pull/606) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Monthly Coverage data update [#620](https://github.com/duckduckgo/autoconsent/pull/620) ([@daxtheduck](https://github.com/daxtheduck) [@sammacbeth](https://github.com/sammacbeth))

#### 🧪 Tests

- Validate JSON rules [#613](https://github.com/duckduckgo/autoconsent/pull/613) ([@muodov](https://github.com/muodov))

#### Authors: 6

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Dax ([@daxtheduck](https://github.com/daxtheduck))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Robert Anderson ([@noisysocks](https://github.com/noisysocks))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.7.0 (Fri Jan 24 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to c9d3f97eb2e68f73a6648dcc76e607be41ed952c [#600](https://github.com/duckduckgo/autoconsent/pull/600) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Fix sourcepoint on the US version of theguardian.com [#598](https://github.com/duckduckgo/autoconsent/pull/598) ([@muodov](https://github.com/muodov))
- Cleaning up tests: 1-as [#597](https://github.com/duckduckgo/autoconsent/pull/597) ([@sammacbeth](https://github.com/sammacbeth))
- Add consent-manager rule [#542](https://github.com/duckduckgo/autoconsent/pull/542) ([@sammacbeth](https://github.com/sammacbeth))
- Add ef-ccpa rule [#545](https://github.com/duckduckgo/autoconsent/pull/545) ([@sammacbeth](https://github.com/sammacbeth))
- Fix dpgmedia rule https://gathering.tweakers.net/ [#596](https://github.com/duckduckgo/autoconsent/pull/596) ([@muodov](https://github.com/muodov))

#### Authors: 3

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.6.0 (Fri Jan 17 2025)

#### 🚀 Enhancement

- Reduce filter list size by using domain popularity, updating encoding, and removing unapplicable rules [#592](https://github.com/duckduckgo/autoconsent/pull/592) ([@dharb](https://github.com/dharb) [@muodov](https://github.com/muodov))

#### 🧪 Tests

- Add tests for DomActions.prehide() [#552](https://github.com/duckduckgo/autoconsent/pull/552) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))

#### Authors: 4

- David Harbage ([@dharb](https://github.com/dharb))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Ondřej Frei ([@freiondrej](https://github.com/freiondrej))
- ondrej.frei (frei.ondrej@pm.me)

---

# v12.5.0 (Fri Jan 10 2025)

#### 🚀 Enhancement

- Update EasyList Cookie to dd9fb5774b073ef64b28d515e3814e70e7211d0e [#588](https://github.com/duckduckgo/autoconsent/pull/588) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Update EasyList Cookie to f686424e0b6048c5c8934a389933a0fed837aaf6 [#580](https://github.com/duckduckgo/autoconsent/pull/580) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Bump the dev-dependencies group across 1 directory with 6 updates [#582](https://github.com/duckduckgo/autoconsent/pull/582) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- feat: readly.com [#583](https://github.com/duckduckgo/autoconsent/pull/583) ([@seia-soto](https://github.com/seia-soto))

#### 🐛 Bug Fix

- Fix an exception in the test extension when filterlist is disabled [#584](https://github.com/duckduckgo/autoconsent/pull/584) ([@muodov](https://github.com/muodov))
- Bump tldts-experimental from 6.1.66 to 6.1.70 [#581](https://github.com/duckduckgo/autoconsent/pull/581) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker from 2.3.0 to 2.3.1 [#576](https://github.com/duckduckgo/autoconsent/pull/576) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker-content from 2.3.0 to 2.3.1 [#575](https://github.com/duckduckgo/autoconsent/pull/575) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🧪 Tests

- Add tests for DomActions.undoPrehide() [#553](https://github.com/duckduckgo/autoconsent/pull/553) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))

#### Authors: 7

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Ondřej Frei ([@freiondrej](https://github.com/freiondrej))
- ondrej.frei (frei.ondrej@pm.me)
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.4.0 (Fri Dec 20 2024)

#### 🚀 Enhancement

- Update EasyList Cookie to b0774541b1f941a5c0ed2d62b1ab75a8235e2e5b [#577](https://github.com/duckduckgo/autoconsent/pull/577) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Export eval snippets [#572](https://github.com/duckduckgo/autoconsent/pull/572) ([@muodov](https://github.com/muodov))
- Bump the dev-dependencies group across 1 directory with 6 updates [#566](https://github.com/duckduckgo/autoconsent/pull/566) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.3.0 (Fri Dec 13 2024)

#### 🚀 Enhancement

- Update EasyList Cookie to 2063c2ed880d0bd63019fb98192ca753e6e68044 [#569](https://github.com/duckduckgo/autoconsent/pull/569) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Bump @ghostery/adblocker from 2.0.4 to 2.3.0 [#565](https://github.com/duckduckgo/autoconsent/pull/565) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @ghostery/adblocker-content from 2.0.4 to 2.3.0 [#563](https://github.com/duckduckgo/autoconsent/pull/563) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Allow adblocker module to be tree-shaked for builds without a bundled filterlist [#567](https://github.com/duckduckgo/autoconsent/pull/567) ([@sammacbeth](https://github.com/sammacbeth))
- Add optional heuristic pattern detection [#555](https://github.com/duckduckgo/autoconsent/pull/555) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Bump tldts-experimental from 6.1.61 to 6.1.66 [#564](https://github.com/duckduckgo/autoconsent/pull/564) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Set the due date on the release task [#560](https://github.com/duckduckgo/autoconsent/pull/560) ([@muodov](https://github.com/muodov))
- Monthly Coverage data update [#561](https://github.com/duckduckgo/autoconsent/pull/561) ([@daxtheduck](https://github.com/daxtheduck) [@sammacbeth](https://github.com/sammacbeth))

#### 🧪 Tests

- Add a fake filterlist rule for testing [#562](https://github.com/duckduckgo/autoconsent/pull/562) ([@muodov](https://github.com/muodov))

#### Authors: 5

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Dax ([@daxtheduck](https://github.com/daxtheduck))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.2.0 (Fri Dec 06 2024)

#### 🚀 Enhancement

- Update EasyList Cookie to 3684b7f8a35e3dc59fcfbfeb1ca270eec1ddde31 [#558](https://github.com/duckduckgo/autoconsent/pull/558) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### Authors: 2

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.1.0 (Fri Nov 29 2024)

#### 🚀 Enhancement

- Update EasyList Cookie to 683577e4ba3f1454aed77ea23cde7308356a0be3 [#551](https://github.com/duckduckgo/autoconsent/pull/551) ([@sammacbeth](https://github.com/sammacbeth) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### 🐛 Bug Fix

- Restrict ensighten detection to only when popup is visible. [#539](https://github.com/duckduckgo/autoconsent/pull/539) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 2

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v12.0.0 (Fri Nov 22 2024)

#### 💥 Breaking Change

- Report filterlist early [#538](https://github.com/duckduckgo/autoconsent/pull/538) ([@muodov](https://github.com/muodov))

#### 🚀 Enhancement

- Update EasyList Cookie to 71bf77b47b6c0ab286d2e210ba2b2640e63434ae [#546](https://github.com/duckduckgo/autoconsent/pull/546) ([@muodov](https://github.com/muodov) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Improve Civic rule [#524](https://github.com/duckduckgo/autoconsent/pull/524) ([@muodov](https://github.com/muodov))
- Add a rule for skyscanner [#537](https://github.com/duckduckgo/autoconsent/pull/537) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Add cookie-consent-spice rule [#540](https://github.com/duckduckgo/autoconsent/pull/540) ([@sammacbeth](https://github.com/sammacbeth))
- Add kconsent rule [#541](https://github.com/duckduckgo/autoconsent/pull/541) ([@sammacbeth](https://github.com/sammacbeth))
- Add Cassie rule [#543](https://github.com/duckduckgo/autoconsent/pull/543) ([@sammacbeth](https://github.com/sammacbeth))
- Fix tealium on eurostar.com [#544](https://github.com/duckduckgo/autoconsent/pull/544) ([@sammacbeth](https://github.com/sammacbeth))
- Bump tldts-experimental from 6.1.60 to 6.1.61 [#534](https://github.com/duckduckgo/autoconsent/pull/534) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump the dev-dependencies group with 3 updates [#533](https://github.com/duckduckgo/autoconsent/pull/533) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Tweak easylist update schedule to fit app release schedule [#535](https://github.com/duckduckgo/autoconsent/pull/535) ([@muodov](https://github.com/muodov))

#### 🧪 Tests

- Make sure that the test page uses an eval rule [#536](https://github.com/duckduckgo/autoconsent/pull/536) ([@muodov](https://github.com/muodov))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v11.5.0 (Sun Nov 17 2024)

#### 🚀 Enhancement

- Update EasyList Cookie to 4061c37b19f3992043ed817d82b3e171c4e8cc6c [#532](https://github.com/duckduckgo/autoconsent/pull/532) ([@muodov](https://github.com/muodov) [@github-actions[bot]](https://github.com/github-actions[bot]))

#### Authors: 2

- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v11.4.0 (Fri Nov 15 2024)

#### 🚀 Enhancement

- Fix rule for bing [#529](https://github.com/duckduckgo/autoconsent/pull/529) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v11.3.0 (Fri Nov 15 2024)

#### 🚀 Enhancement

- Fix release workflow parameters [#531](https://github.com/duckduckgo/autoconsent/pull/531) ([@muodov](https://github.com/muodov))
- Fix release workflow [#530](https://github.com/duckduckgo/autoconsent/pull/530) ([@muodov](https://github.com/muodov))
- Automate DDG releases [#528](https://github.com/duckduckgo/autoconsent/pull/528) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v11.2.0 (Thu Nov 14 2024)

#### 🚀 Enhancement

- Do not bundle network allowlist rules from easylist [#527](https://github.com/duckduckgo/autoconsent/pull/527) ([@muodov](https://github.com/muodov))
- Bump typescript-eslint from 8.13.0 to 8.14.0 in the dev-dependencies group [#525](https://github.com/duckduckgo/autoconsent/pull/525) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Bump tldts-experimental from 6.1.58 to 6.1.60 [#526](https://github.com/duckduckgo/autoconsent/pull/526) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### ⚠️ Pushed to `main`

- Do not run prettier on autogenerated manifest files ([@muodov](https://github.com/muodov))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v11.1.0 (Mon Nov 11 2024)

#### 🚀 Enhancement

- Fix arbeitsagentur [#523](https://github.com/duckduckgo/autoconsent/pull/523) ([@muodov](https://github.com/muodov))
- Update dpgmedia [#521](https://github.com/duckduckgo/autoconsent/pull/521) ([@muodov](https://github.com/muodov))
- Fix a rule for pornhub [#520](https://github.com/duckduckgo/autoconsent/pull/520) ([@muodov](https://github.com/muodov))
- fix trustarc popup detection [#519](https://github.com/duckduckgo/autoconsent/pull/519) ([@muodov](https://github.com/muodov))
- Add rule for tesco.com [#508](https://github.com/duckduckgo/autoconsent/pull/508) ([@muodov](https://github.com/muodov))
- Update EasyList Cookie to 3e2a625d9b08717134a6a0b6b39b73de3e7c792b [#522](https://github.com/duckduckgo/autoconsent/pull/522) ([@muodov](https://github.com/muodov) [@github-actions[bot]](https://github.com/github-actions[bot]))
- Bump the dev-dependencies group across 1 directory with 7 updates [#515](https://github.com/duckduckgo/autoconsent/pull/515) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Ignore lint PR commit [#516](https://github.com/duckduckgo/autoconsent/pull/516) ([@muodov](https://github.com/muodov))
- Bump tldts-experimental from 6.1.51 to 6.1.58 [#511](https://github.com/duckduckgo/autoconsent/pull/511) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🧪 Tests

- Use shared ESLint config + adopt Prettier [#513](https://github.com/duckduckgo/autoconsent/pull/513) ([@muodov](https://github.com/muodov))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@github-actions[bot]](https://github.com/github-actions[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v11.0.0 (Thu Nov 07 2024)

#### 💥 Breaking Change

- Support cosmetic filterlists [#466](https://github.com/duckduckgo/autoconsent/pull/466) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Bump the dev-dependencies group across 1 directory with 6 updates [#507](https://github.com/duckduckgo/autoconsent/pull/507) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### ⚠️ Pushed to `main`

- Try to fix ci retry [ckip ci] ([@muodov](https://github.com/muodov))

#### 🧪 Tests

- (DomActions) WTR tests for elementVisible() [#497](https://github.com/duckduckgo/autoconsent/pull/497) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))
- (DomActions) WTR tests for waitForElement() [#496](https://github.com/duckduckgo/autoconsent/pull/496) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Ondřej Frei ([@freiondrej](https://github.com/freiondrej))
- ondrej.frei (frei.ondrej@pm.me)

---

# v10.17.0 (Thu Oct 24 2024)

#### 🚀 Enhancement

- Add rule for americanexpress [#503](https://github.com/duckduckgo/autoconsent/pull/503) ([@muodov](https://github.com/muodov))
- Fix race condition in Sourcepoint rule [#502](https://github.com/duckduckgo/autoconsent/pull/502) ([@muodov](https://github.com/muodov))
- Add a rule for android.com [#501](https://github.com/duckduckgo/autoconsent/pull/501) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Fix standalone google for international regions [#500](https://github.com/duckduckgo/autoconsent/pull/500) ([@muodov](https://github.com/muodov))
- Fix paypal-us [#499](https://github.com/duckduckgo/autoconsent/pull/499) ([@muodov](https://github.com/muodov))
- (DomActions) WTR tests for elementSelector() [#495](https://github.com/duckduckgo/autoconsent/pull/495) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))

#### Authors: 3

- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Ondřej Frei ([@freiondrej](https://github.com/freiondrej))
- ondrej.frei (frei.ondrej@pm.me)

---

# v10.16.0 (Tue Oct 15 2024)

#### 🚀 Enhancement

- Update dependencies [#494](https://github.com/duckduckgo/autoconsent/pull/494) ([@muodov](https://github.com/muodov))
- Add rule for openai [#489](https://github.com/duckduckgo/autoconsent/pull/489) ([@muodov](https://github.com/muodov))

#### 🧪 Tests

- #333 Convert DomActions playwright-based unit test to WebTestRunner HTML test [#491](https://github.com/duckduckgo/autoconsent/pull/491) (frei.ondrej@pm.me [@freiondrej](https://github.com/freiondrej))

#### Authors: 3

- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Ondřej Frei ([@freiondrej](https://github.com/freiondrej))
- ondrej.frei (frei.ondrej@pm.me)

---

# v10.15.0 (Mon Aug 19 2024)

#### 🚀 Enhancement

- Tweak ensighten rule for britishairways.com [#488](https://github.com/duckduckgo/autoconsent/pull/488) ([@muodov](https://github.com/muodov))
- Add a rule for admiral GDPR popups [#487](https://github.com/duckduckgo/autoconsent/pull/487) ([@muodov](https://github.com/muodov))
- Add rule for tesla [#486](https://github.com/duckduckgo/autoconsent/pull/486) ([@muodov](https://github.com/muodov))
- Add rule for american airlines [#485](https://github.com/duckduckgo/autoconsent/pull/485) ([@muodov](https://github.com/muodov))
- Aliexpress & temu [#484](https://github.com/duckduckgo/autoconsent/pull/484) ([@muodov](https://github.com/muodov))
- Add a rule for abc.net.au [#482](https://github.com/duckduckgo/autoconsent/pull/482) ([@muodov](https://github.com/muodov))
- add rule for medium.com [#481](https://github.com/duckduckgo/autoconsent/pull/481) ([@muodov](https://github.com/muodov))
- Rule for Dan.com [#480](https://github.com/duckduckgo/autoconsent/pull/480) ([@muodov](https://github.com/muodov))
- Add a rule for nike [#479](https://github.com/duckduckgo/autoconsent/pull/479) ([@muodov](https://github.com/muodov))
- Add a rule for wise.com [#478](https://github.com/duckduckgo/autoconsent/pull/478) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Monthly Coverage data update [#477](https://github.com/duckduckgo/autoconsent/pull/477) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.14.0 (Wed Aug 07 2024)

#### 🚀 Enhancement

- Batch of regression fixes [#476](https://github.com/duckduckgo/autoconsent/pull/476) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.13.0 (Thu Aug 01 2024)

#### 🚀 Enhancement

- Allow disabling test extension per site [#475](https://github.com/duckduckgo/autoconsent/pull/475) ([@muodov](https://github.com/muodov))
- Update UserCentrics API [#470](https://github.com/duckduckgo/autoconsent/pull/470) ([@seia-soto](https://github.com/seia-soto))
- Add chaletplus-com [#472](https://github.com/duckduckgo/autoconsent/pull/472) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))
- Add dpgmedia.nl [#474](https://github.com/duckduckgo/autoconsent/pull/474) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.12.1 (Mon Jul 29 2024)

#### 🐛 Bug Fix

- Add netbeat.de [#471](https://github.com/duckduckgo/autoconsent/pull/471) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))
- Update configuration object in `api.md` [#469](https://github.com/duckduckgo/autoconsent/pull/469) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.12.0 (Tue Jul 23 2024)

#### 🚀 Enhancement

- Support check24-partnerprogramm.de [#465](https://github.com/duckduckgo/autoconsent/pull/465) ([@seia-soto](https://github.com/seia-soto))
- Support Acris CMP [#464](https://github.com/duckduckgo/autoconsent/pull/464) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Monthly Coverage data update [#463](https://github.com/duckduckgo/autoconsent/pull/463) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 4

- Dax the Deployer (dax@duckduckgo.com)
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.11.0 (Mon Jul 01 2024)

#### 🚀 Enhancement

- Add zentralruf-de [#461](https://github.com/duckduckgo/autoconsent/pull/461) ([@seia-soto](https://github.com/seia-soto))

#### 🐛 Bug Fix

- Monthly Coverage data update [#454](https://github.com/duckduckgo/autoconsent/pull/454) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- Dax the Deployer (dax@duckduckgo.com)
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.10.0 (Mon Jun 03 2024)

#### 🚀 Enhancement

- Fix some reload loops on www.fidelity.co.uk and other Ensighten sites [#452](https://github.com/duckduckgo/autoconsent/pull/452) ([@muodov](https://github.com/muodov))
- Add a rule for ebay [#449](https://github.com/duckduckgo/autoconsent/pull/449) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.9.0 (Tue May 28 2024)

#### 🚀 Enhancement

- Roblox [#448](https://github.com/duckduckgo/autoconsent/pull/448) ([@muodov](https://github.com/muodov))
- Fix the Ketch rule [#447](https://github.com/duckduckgo/autoconsent/pull/447) ([@muodov](https://github.com/muodov))
- Make Fides rule more robust [#442](https://github.com/duckduckgo/autoconsent/pull/442) ([@muodov](https://github.com/muodov))
- Add support for cookieCuttr CMP [#440](https://github.com/duckduckgo/autoconsent/pull/440) ([@muodov](https://github.com/muodov))
- Add travelonbags.com [#438](https://github.com/duckduckgo/autoconsent/pull/438) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Fix overlay in complianz-optout [#450](https://github.com/duckduckgo/autoconsent/pull/450) ([@muodov](https://github.com/muodov))
- Fix overlay on https://sports.tipico.de/de [#451](https://github.com/duckduckgo/autoconsent/pull/451) ([@muodov](https://github.com/muodov))
- upgrade dependencies [#439](https://github.com/duckduckgo/autoconsent/pull/439) ([@muodov](https://github.com/muodov))

#### ⚠️ Pushed to `main`

- Update DDG PR template ([@muodov](https://github.com/muodov))
- Refer to the changelog instead of copying github release notes ([@muodov](https://github.com/muodov))
- Fix ddg release ([@muodov](https://github.com/muodov))
- Fix Asana API usage ([@muodov](https://github.com/muodov))
- Update readme.md ([@muodov](https://github.com/muodov))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.8.0 (Tue May 14 2024)

#### 🚀 Enhancement

- Adjusted TrustArc optout [#436](https://github.com/duckduckgo/autoconsent/pull/436) ([@hyebahi](https://github.com/hyebahi))

#### 🐛 Bug Fix

- fix: instagram.com [#435](https://github.com/duckduckgo/autoconsent/pull/435) ([@seia-soto](https://github.com/seia-soto))
- Monthly Coverage data update [#434](https://github.com/duckduckgo/autoconsent/pull/434) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 4

- [@hyebahi](https://github.com/hyebahi)
- Dax the Deployer (dax@duckduckgo.com)
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.7.0 (Thu May 02 2024)

#### 🚀 Enhancement

- Fix the rule for termsfeed3 [#430](https://github.com/duckduckgo/autoconsent/pull/430) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Add espace-personnel.agirc-arrco.fr [#429](https://github.com/duckduckgo/autoconsent/pull/429) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.6.3 (Fri Apr 26 2024)

#### 🐛 Bug Fix

- Fix race condition in iubenda, as seen on https://leaddev.com/leaddev-london [#428](https://github.com/duckduckgo/autoconsent/pull/428) ([@muodov](https://github.com/muodov))
- Tweak DDG release CI scripts [#426](https://github.com/duckduckgo/autoconsent/pull/426) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.6.2 (Tue Apr 23 2024)

#### 🐛 Bug Fix

- Click 'Save & Exit' instead of 'Cancel' in dmgmedia popup [#425](https://github.com/duckduckgo/autoconsent/pull/425) ([@sammacbeth](https://github.com/sammacbeth))
- Fix sibbo rule [#423](https://github.com/duckduckgo/autoconsent/pull/423) ([@sammacbeth](https://github.com/sammacbeth))
- Update readme.md [#420](https://github.com/duckduckgo/autoconsent/pull/420) ([@hyebahi](https://github.com/hyebahi))

#### Authors: 2

- [@hyebahi](https://github.com/hyebahi)
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.6.1 (Fri Apr 12 2024)

#### 🐛 Bug Fix

- Fix Klaro rule (wogibtswas.de, www.suedtirol.com) [#404](https://github.com/duckduckgo/autoconsent/pull/404) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.6.0 (Fri Apr 12 2024)

#### 🚀 Enhancement

- Fix detection in tarteaucitron [#415](https://github.com/duckduckgo/autoconsent/pull/415) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Monthly Coverage data update [#413](https://github.com/duckduckgo/autoconsent/pull/413) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### ⚠️ Pushed to `main`

- Remove git commit from asana tasks ([@muodov](https://github.com/muodov))
- Remove the default value for the release workflow ([@muodov](https://github.com/muodov))
- Make the ddg release workflow manual ([@muodov](https://github.com/muodov))

#### Authors: 3

- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.5.0 (Tue Apr 02 2024)

#### 🚀 Enhancement

- Fix Moove on mitglieder.franzspitzer.de [#409](https://github.com/duckduckgo/autoconsent/pull/409) ([@muodov](https://github.com/muodov))
- Add .cc-type-out-out variant of Complianz popup [#402](https://github.com/duckduckgo/autoconsent/pull/402) ([@sammacbeth](https://github.com/sammacbeth))
- Rules for two Ensighten banner variants [#403](https://github.com/duckduckgo/autoconsent/pull/403) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 2

- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.4.0 (Tue Mar 26 2024)

#### 🚀 Enhancement

- Check runcontext for prehide selectors. [#400](https://github.com/duckduckgo/autoconsent/pull/400) ([@sammacbeth](https://github.com/sammacbeth))
- Fix rules for tumblr.com, onlyfans, canva.com, cookie-script [#395](https://github.com/duckduckgo/autoconsent/pull/395) ([@muodov](https://github.com/muodov))

#### Authors: 2

- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.3.2 (Wed Mar 20 2024)

#### 🐛 Bug Fix

- fix: outdated strato.de [#399](https://github.com/duckduckgo/autoconsent/pull/399) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 1

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))

---

# v10.3.1 (Fri Mar 15 2024)

#### 🐛 Bug Fix

- Fix the trigger event for the CI automation [#394](https://github.com/duckduckgo/autoconsent/pull/394) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v10.3.0 (Fri Mar 15 2024)

#### 🚀 Enhancement

- DDG release automation [#389](https://github.com/duckduckgo/autoconsent/pull/389) ([@muodov](https://github.com/muodov))
- Bump the dev-dependencies group with 4 updates [#390](https://github.com/duckduckgo/autoconsent/pull/390) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Fix infinite reload for OneTrust sites [#393](https://github.com/duckduckgo/autoconsent/pull/393) ([@muodov](https://github.com/muodov))
- Script to crawl page text content in multiple languages. [#386](https://github.com/duckduckgo/autoconsent/pull/386) ([@sammacbeth](https://github.com/sammacbeth))
- Update Asana sync action [#388](https://github.com/duckduckgo/autoconsent/pull/388) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.2.0 (Tue Mar 05 2024)

#### 🚀 Enhancement

- feat: support coca-cola.com using OneTrust [#376](https://github.com/duckduckgo/autoconsent/pull/376) ([@seia-soto](https://github.com/seia-soto))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 4 updates [#385](https://github.com/duckduckgo/autoconsent/pull/385) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))

---

# v10.1.0 (Tue Mar 05 2024)

#### 🚀 Enhancement

- Sirdata fix [#379](https://github.com/duckduckgo/autoconsent/pull/379) ([@sammacbeth](https://github.com/sammacbeth) [@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Fix a US popup on nature.com [#384](https://github.com/duckduckgo/autoconsent/pull/384) ([@muodov](https://github.com/muodov))
- Monthly Coverage data update [#383](https://github.com/duckduckgo/autoconsent/pull/383) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v10.0.0 (Fri Mar 01 2024)

#### 💥 Breaking Change

- Bump the dev-dependencies group with 4 updates [#377](https://github.com/duckduckgo/autoconsent/pull/377) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🚀 Enhancement

- Support reject button in clinch [#375](https://github.com/duckduckgo/autoconsent/pull/375) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Update action-asana-sync [#378](https://github.com/duckduckgo/autoconsent/pull/378) ([@sammacbeth](https://github.com/sammacbeth))
- Setup github status reporting for Jenkins multibranch job [#373](https://github.com/duckduckgo/autoconsent/pull/373) ([@sammacbeth](https://github.com/sammacbeth))
- Monthly Coverage data update [#372](https://github.com/duckduckgo/autoconsent/pull/372) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### ⚠️ Pushed to `main`

- Update asana.yml ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 7 updates [#382](https://github.com/duckduckgo/autoconsent/pull/382) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump the dev-dependencies group with 5 updates [#374](https://github.com/duckduckgo/autoconsent/pull/374) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v9.7.2 (Fri Feb 02 2024)

#### 🐛 Bug Fix

- Tweak some site-specific rules to support mobile versions [#371](https://github.com/duckduckgo/autoconsent/pull/371) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.7.1 (Fri Feb 02 2024)

#### 🐛 Bug Fix

- Avoid :has selectors in detect rules [#370](https://github.com/duckduckgo/autoconsent/pull/370) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.7.0 (Fri Feb 02 2024)

#### 🚀 Enhancement

- More rules for common CMPs [#367](https://github.com/duckduckgo/autoconsent/pull/367) ([@muodov](https://github.com/muodov))
- More site-specific pop-ups [#366](https://github.com/duckduckgo/autoconsent/pull/366) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.6.0 (Wed Jan 31 2024)

#### 🚀 Enhancement

- Add rule for webflow [#364](https://github.com/duckduckgo/autoconsent/pull/364) ([@muodov](https://github.com/muodov))
- Handle Tealium implicit modal [#363](https://github.com/duckduckgo/autoconsent/pull/363) ([@muodov](https://github.com/muodov))
- Fix reddit rule [#362](https://github.com/duckduckgo/autoconsent/pull/362) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- regression fix: Do not run opt-out unless a pop-up is actually shown [#365](https://github.com/duckduckgo/autoconsent/pull/365) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.5.0 (Wed Jan 31 2024)

#### 🚀 Enhancement

- Fix Ketch and eu-cookie-compliance [#351](https://github.com/duckduckgo/autoconsent/pull/351) ([@muodov](https://github.com/muodov))
- Bump the dev-dependencies group with 7 updates [#360](https://github.com/duckduckgo/autoconsent/pull/360) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add rule for fides CMP [#359](https://github.com/duckduckgo/autoconsent/pull/359) ([@muodov](https://github.com/muodov))
- More site-specific rules [#358](https://github.com/duckduckgo/autoconsent/pull/358) ([@muodov](https://github.com/muodov))
- Support another version of uniconsent [#355](https://github.com/duckduckgo/autoconsent/pull/355) ([@muodov](https://github.com/muodov))
- Improve Consentmanager.net [#353](https://github.com/duckduckgo/autoconsent/pull/353) ([@muodov](https://github.com/muodov))
- Improve cookie-law-info rule [#352](https://github.com/duckduckgo/autoconsent/pull/352) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- fix: paypal-us [#361](https://github.com/duckduckgo/autoconsent/pull/361) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.4.0 (Fri Jan 26 2024)

#### 🚀 Enhancement

- Improve Osano rule [#350](https://github.com/duckduckgo/autoconsent/pull/350) ([@muodov](https://github.com/muodov))
- Increase timeout in the sourcepoint rule [#349](https://github.com/duckduckgo/autoconsent/pull/349) ([@muodov](https://github.com/muodov))
- Complianz regression fixes [#347](https://github.com/duckduckgo/autoconsent/pull/347) ([@muodov](https://github.com/muodov))
- Add rule for bahn.de [#348](https://github.com/duckduckgo/autoconsent/pull/348) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.3.0 (Fri Jan 26 2024)

#### 🚀 Enhancement

- Add rules from Jan 10 Ghostery fixes [#341](https://github.com/duckduckgo/autoconsent/pull/341) ([@seia-soto](https://github.com/seia-soto))
- Fix the Canonical rule [#345](https://github.com/duckduckgo/autoconsent/pull/345) ([@muodov](https://github.com/muodov))
- Update the EZoic rule [#344](https://github.com/duckduckgo/autoconsent/pull/344) ([@muodov](https://github.com/muodov))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.2.1 (Fri Jan 26 2024)

#### 🐛 Bug Fix

- Handle absence of structuredClone() [#356](https://github.com/duckduckgo/autoconsent/pull/356) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v9.2.0 (Thu Jan 25 2024)

#### 🚀 Enhancement

- Handle popup right after first popup detected (#326) [#327](https://github.com/duckduckgo/autoconsent/pull/327) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 1

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))

---

# v9.1.0 (Thu Jan 11 2024)

#### 🚀 Enhancement

- Add a rule for lightbox CMP [#329](https://github.com/duckduckgo/autoconsent/pull/329) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 1

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))

---

# v9.0.0 (Thu Jan 11 2024)

#### 💥 Breaking Change

- Configurable logs [#332](https://github.com/duckduckgo/autoconsent/pull/332) ([@muodov](https://github.com/muodov))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 3 updates [#335](https://github.com/duckduckgo/autoconsent/pull/335) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v8.2.0 (Thu Jan 11 2024)

#### 🚀 Enhancement

- Klaro: fix toggle selectors [#339](https://github.com/duckduckgo/autoconsent/pull/339) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v8.1.0 (Wed Jan 10 2024)

#### 🚀 Enhancement

- Add a rule for ing.de [#337](https://github.com/duckduckgo/autoconsent/pull/337) ([@seia-soto](https://github.com/seia-soto))
- Add a rule for hema.com [#319](https://github.com/duckduckgo/autoconsent/pull/319) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Only use sites where the popup is open by default as examples [#336](https://github.com/duckduckgo/autoconsent/pull/336) ([@sammacbeth](https://github.com/sammacbeth))
- Test a subset of sites found in the coverage crawl in CI [#323](https://github.com/duckduckgo/autoconsent/pull/323) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v8.0.0 (Sat Jan 06 2024)

#### 💥 Breaking Change

- single selector in hide rules [#334](https://github.com/duckduckgo/autoconsent/pull/334) ([@muodov](https://github.com/muodov))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 4 updates [#328](https://github.com/duckduckgo/autoconsent/pull/328) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v7.1.0 (Wed Jan 03 2024)

#### 🚀 Enhancement

- iWink rule [#123](https://github.com/duckduckgo/autoconsent/pull/123) ([@Tomassie91](https://github.com/Tomassie91) [@muodov](https://github.com/muodov))
- Improve Tealium support [#315](https://github.com/duckduckgo/autoconsent/pull/315) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Monthly Coverage data update [#330](https://github.com/duckduckgo/autoconsent/pull/330) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 4

- [@Tomassie91](https://github.com/Tomassie91)
- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v7.0.0 (Thu Dec 28 2023)

#### 💥 Breaking Change

- Fix CSP errors when running eval rules in MV3 extension [#318](https://github.com/duckduckgo/autoconsent/pull/318) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.7.0 (Thu Dec 28 2023)

#### 🚀 Enhancement

- Add a rule for ciaopeople.it [#320](https://github.com/duckduckgo/autoconsent/pull/320) ([@seia-soto](https://github.com/seia-soto) [@muodov](https://github.com/muodov))
- Add a rule for roofingmegastore.co.uk [#325](https://github.com/duckduckgo/autoconsent/pull/325) ([@seia-soto](https://github.com/seia-soto))
- Add a rule for csu-landtag.de [#324](https://github.com/duckduckgo/autoconsent/pull/324) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 2

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.6.1 (Wed Dec 27 2023)

#### 🐛 Bug Fix

- Add a deferred check for usercentrics [#322](https://github.com/duckduckgo/autoconsent/pull/322) ([@seia-soto](https://github.com/seia-soto))

#### Authors: 1

- HoJeong Go ([@seia-soto](https://github.com/seia-soto))

---

# v6.6.0 (Wed Dec 20 2023)

#### 🚀 Enhancement

- Add rule for opera.com [#314](https://github.com/duckduckgo/autoconsent/pull/314) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.5.0 (Tue Dec 19 2023)

#### 🚀 Enhancement

- Blocksy CMP [#313](https://github.com/duckduckgo/autoconsent/pull/313) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Do not click on the youtube consent page [#311](https://github.com/duckduckgo/autoconsent/pull/311) ([@muodov](https://github.com/muodov))
- Monthly Coverage data update [#307](https://github.com/duckduckgo/autoconsent/pull/307) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 3 updates [#312](https://github.com/duckduckgo/autoconsent/pull/312) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump the dev-dependencies group with 5 updates [#309](https://github.com/duckduckgo/autoconsent/pull/309) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump the dev-dependencies group with 5 updates [#308](https://github.com/duckduckgo/autoconsent/pull/308) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v6.4.3 (Mon Dec 04 2023)

#### 🐛 Bug Fix

- Cookiebot fixes [#304](https://github.com/duckduckgo/autoconsent/pull/304) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.4.2 (Mon Dec 04 2023)

#### 🐛 Bug Fix

- Add a rule for CookieYes [#306](https://github.com/duckduckgo/autoconsent/pull/306) ([@muodov](https://github.com/muodov))
- Add a rule for yahoo pop-up [#305](https://github.com/duckduckgo/autoconsent/pull/305) ([@muodov](https://github.com/muodov))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 3 updates [#303](https://github.com/duckduckgo/autoconsent/pull/303) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.4.1 (Mon Nov 27 2023)

#### 🐛 Bug Fix

- CCPA fix for Sourcepoint [#302](https://github.com/duckduckgo/autoconsent/pull/302) ([@muodov](https://github.com/muodov))
- Group dependabot PRs [#299](https://github.com/duckduckgo/autoconsent/pull/299) ([@sammacbeth](https://github.com/sammacbeth))
- Monthly Coverage data update [#293](https://github.com/duckduckgo/autoconsent/pull/293) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump the dev-dependencies group with 6 updates [#300](https://github.com/duckduckgo/autoconsent/pull/300) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump typescript from 5.2.2 to 5.3.2 [#298](https://github.com/duckduckgo/autoconsent/pull/298) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.53.0 to 8.54.0 [#297](https://github.com/duckduckgo/autoconsent/pull/297) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump esbuild from 0.19.5 to 0.19.6 [#295](https://github.com/duckduckgo/autoconsent/pull/295) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.39.0 to 1.40.0 [#294](https://github.com/duckduckgo/autoconsent/pull/294) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v6.4.0 (Mon Nov 20 2023)

#### 🚀 Enhancement

- Add a rule for nature.com [#290](https://github.com/duckduckgo/autoconsent/pull/290) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Takealot fix [#292](https://github.com/duckduckgo/autoconsent/pull/292) ([@muodov](https://github.com/muodov))
- Monthly Coverage data update [#289](https://github.com/duckduckgo/autoconsent/pull/289) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### Authors: 3

- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v6.3.0 (Tue Nov 14 2023)

#### 🚀 Enhancement

- Some optimizations [#283](https://github.com/duckduckgo/autoconsent/pull/283) ([@muodov](https://github.com/muodov))
- Bump web-ext from 7.7.0 to 7.8.0 [#284](https://github.com/duckduckgo/autoconsent/pull/284) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Bump chai and @types/chai [#285](https://github.com/duckduckgo/autoconsent/pull/285) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/mocha from 10.0.1 to 10.0.4 [#286](https://github.com/duckduckgo/autoconsent/pull/286) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🔩 Dependency Updates

- Bump @types/chrome from 0.0.245 to 0.0.251 [#287](https://github.com/duckduckgo/autoconsent/pull/287) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.2.0 (Fri Nov 10 2023)

#### 🚀 Enhancement

- Bump eslint from 8.48.0 to 8.53.0 [#279](https://github.com/duckduckgo/autoconsent/pull/279) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.38.0 to 1.39.0 [#272](https://github.com/duckduckgo/autoconsent/pull/272) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.37.1 to 1.38.0 [#256](https://github.com/duckduckgo/autoconsent/pull/256) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Add rule for almacmp [#281](https://github.com/duckduckgo/autoconsent/pull/281) ([@muodov](https://github.com/muodov))
- add rule for tropicfeel.com (shopify site) [#280](https://github.com/duckduckgo/autoconsent/pull/280) ([@muodov](https://github.com/muodov))
- Bump esbuild from 0.19.2 to 0.19.5 [#273](https://github.com/duckduckgo/autoconsent/pull/273) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Monthly Coverage data update [#277](https://github.com/duckduckgo/autoconsent/pull/277) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))
- Monthly Coverage data update [#266](https://github.com/duckduckgo/autoconsent/pull/266) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))
- Bump version of asana sync action [#260](https://github.com/duckduckgo/autoconsent/pull/260) ([@sammacbeth](https://github.com/sammacbeth))
- Add asana sync for PRs [#258](https://github.com/duckduckgo/autoconsent/pull/258) ([@sammacbeth](https://github.com/sammacbeth))
- Monthly Coverage data update [#253](https://github.com/duckduckgo/autoconsent/pull/253) (dax@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth))

#### ⚠️ Pushed to `main`

- Final fix of asana project ID ([@sammacbeth](https://github.com/sammacbeth))
- Fix Asana project ID ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump @puppeteer/replay from 2.13.3 to 2.13.4 [#264](https://github.com/duckduckgo/autoconsent/pull/264) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump typescript from 5.1.6 to 5.2.2 [#251](https://github.com/duckduckgo/autoconsent/pull/251) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chai from 4.3.5 to 4.3.6 [#250](https://github.com/duckduckgo/autoconsent/pull/250) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump auto from 11.0.1 to 11.0.4 [#247](https://github.com/duckduckgo/autoconsent/pull/247) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 4

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Dax the Deployer (dax@duckduckgo.com)
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v6.1.1 (Thu Sep 14 2023)

#### 🐛 Bug Fix

- Update test site domain [#252](https://github.com/duckduckgo/autoconsent/pull/252) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v6.1.0 (Tue Sep 12 2023)

#### 🚀 Enhancement

- Bump web-ext from 7.6.2 to 7.7.0 [#249](https://github.com/duckduckgo/autoconsent/pull/249) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Add rule for activobank.pt [#244](https://github.com/duckduckgo/autoconsent/pull/244) ([@muodov](https://github.com/muodov))
- Update trustarc-frame.ts [#235](https://github.com/duckduckgo/autoconsent/pull/235) ([@hyebahi](https://github.com/hyebahi))

#### 🔩 Dependency Updates

- Bump @types/chrome from 0.0.243 to 0.0.245 [#245](https://github.com/duckduckgo/autoconsent/pull/245) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump tslib from 2.6.1 to 2.6.2 [#242](https://github.com/duckduckgo/autoconsent/pull/242) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump chai from 4.3.7 to 4.3.8 [#241](https://github.com/duckduckgo/autoconsent/pull/241) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.36.2 to 1.37.1 [#239](https://github.com/duckduckgo/autoconsent/pull/239) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump esbuild from 0.18.11 to 0.19.2 [#234](https://github.com/duckduckgo/autoconsent/pull/234) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @puppeteer/replay from 2.13.2 to 2.13.3 [#222](https://github.com/duckduckgo/autoconsent/pull/222) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.242 to 0.0.243 [#221](https://github.com/duckduckgo/autoconsent/pull/221) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump auto from 10.46.0 to 11.0.1 [#233](https://github.com/duckduckgo/autoconsent/pull/233) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@hyebahi](https://github.com/hyebahi)
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v6.0.0 (Tue Aug 22 2023)

#### 💥 Breaking Change

- Inline evals [#236](https://github.com/duckduckgo/autoconsent/pull/236) ([@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- August crawl data [#238](https://github.com/duckduckgo/autoconsent/pull/238) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 2

- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v5.3.0 (Wed Aug 09 2023)

#### 🚀 Enhancement

- Fix the target ES version to avoid surprises downstream [#227](https://github.com/duckduckgo/autoconsent/pull/227) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v5.2.0 (Thu Aug 03 2023)

#### 🚀 Enhancement

- Bump tslib from 2.5.3 to 2.6.1 [#217](https://github.com/duckduckgo/autoconsent/pull/217) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @puppeteer/replay from 2.11.0 to 2.13.2 [#216](https://github.com/duckduckgo/autoconsent/pull/216) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.45.0 to 8.46.0 [#215](https://github.com/duckduckgo/autoconsent/pull/215) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Bump @types/chrome from 0.0.241 to 0.0.242 [#218](https://github.com/duckduckgo/autoconsent/pull/218) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add rules for twitch.tv and kleinanzeigen.de [#220](https://github.com/duckduckgo/autoconsent/pull/220) ([@muodov](https://github.com/muodov))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v5.1.0 (Mon Jul 31 2023)

#### 🚀 Enhancement

- Bump @playwright/test from 1.35.1 to 1.36.2 [#213](https://github.com/duckduckgo/autoconsent/pull/213) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Fix usercentrics-api [#214](https://github.com/duckduckgo/autoconsent/pull/214) ([@muodov](https://github.com/muodov))

#### 🔩 Dependency Updates

- Bump eslint from 8.43.0 to 8.45.0 [#208](https://github.com/duckduckgo/autoconsent/pull/208) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.237 to 0.0.241 [#206](https://github.com/duckduckgo/autoconsent/pull/206) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @typescript-eslint/parser from 5.60.0 to 5.62.0 [#203](https://github.com/duckduckgo/autoconsent/pull/203) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v5.0.1 (Tue Jul 18 2023)

#### 🐛 Bug Fix

- Fix burpee rule matching and add new rule [#211](https://github.com/duckduckgo/autoconsent/pull/211) ([@sammacbeth](https://github.com/sammacbeth))
- Add July crawl data [#199](https://github.com/duckduckgo/autoconsent/pull/199) ([@sammacbeth](https://github.com/sammacbeth))
- Build with ESBuild [#204](https://github.com/duckduckgo/autoconsent/pull/204) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v5.0.0 (Thu Jul 13 2023)

#### 💥 Breaking Change

- Bump typescript from 4.9.5 to 5.1.6 [#196](https://github.com/duckduckgo/autoconsent/pull/196) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🚀 Enhancement

- Cancel prehide rules if the pop-up takes too long to appear [#205](https://github.com/duckduckgo/autoconsent/pull/205) ([@muodov](https://github.com/muodov))
- Bump @playwright/test from 1.33.0 to 1.35.1 [#191](https://github.com/duckduckgo/autoconsent/pull/191) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v4.4.0 (Tue Jul 11 2023)

#### 🚀 Enhancement

- Support Chrome recorder generated selectors [#148](https://github.com/duckduckgo/autoconsent/pull/148) ([@sammacbeth](https://github.com/sammacbeth))

#### 🐛 Bug Fix

- Add initial coverage data [#188](https://github.com/duckduckgo/autoconsent/pull/188) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.3.3 (Thu Jun 22 2023)

#### 🐛 Bug Fix

- Remove wait from detectCmp step [#189](https://github.com/duckduckgo/autoconsent/pull/189) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.3.2 (Wed Jun 21 2023)

#### 🐛 Bug Fix

- Limit triggering of nba.com rule [#187](https://github.com/duckduckgo/autoconsent/pull/187) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.3.1 (Tue Jun 20 2023)

#### 🐛 Bug Fix

- Bump @typescript-eslint/eslint-plugin from 5.59.11 to 5.60.0 [#186](https://github.com/duckduckgo/autoconsent/pull/186) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chai from 4.3.4 to 4.3.5 [#183](https://github.com/duckduckgo/autoconsent/pull/183) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- added nba.com notice rule and test and modified oneTrust rule class [#172](https://github.com/duckduckgo/autoconsent/pull/172) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))

#### 🔩 Dependency Updates

- Bump @typescript-eslint/parser from 5.59.2 to 5.60.0 [#185](https://github.com/duckduckgo/autoconsent/pull/185) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.40.0 to 8.43.0 [#184](https://github.com/duckduckgo/autoconsent/pull/184) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Amanda RASOLOFOTSARA ([@icodebyamanda](https://github.com/icodebyamanda))
- euw-arasolofotsara1 (arasolofotsara@duckduckgo.com)

---

# v4.3.0 (Tue Jun 20 2023)

#### 🚀 Enhancement

- add batch of rules and tests for banners reported by users [#181](https://github.com/duckduckgo/autoconsent/pull/181) (arasolofotsara@duckduckgo.com [@sammacbeth](https://github.com/sammacbeth) [@icodebyamanda](https://github.com/icodebyamanda))

#### Authors: 3

- Amanda RASOLOFOTSARA ([@icodebyamanda](https://github.com/icodebyamanda))
- euw-arasolofotsara1 (arasolofotsara@duckduckgo.com)
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.2.0 (Mon Jun 19 2023)

#### 🚀 Enhancement

- Bump @typescript-eslint/eslint-plugin from 5.45.1 to 5.59.2 [#143](https://github.com/duckduckgo/autoconsent/pull/143) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump web-ext from 7.4.0 to 7.6.2 [#145](https://github.com/duckduckgo/autoconsent/pull/145) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @typescript-eslint/parser from 5.51.0 to 5.59.2 [#146](https://github.com/duckduckgo/autoconsent/pull/146) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.30.0 to 1.33.0 [#147](https://github.com/duckduckgo/autoconsent/pull/147) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🐛 Bug Fix

- Round 2: Add to US top sites optOut banners rules and tests [#175](https://github.com/duckduckgo/autoconsent/pull/175) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- added verification to check if user's optout on TrustArc CMP has been set [#159](https://github.com/duckduckgo/autoconsent/pull/159) ([@hyebahi](https://github.com/hyebahi) [@sammacbeth](https://github.com/sammacbeth))
- Added rule for cookiefirst [#177](https://github.com/duckduckgo/autoconsent/pull/177) ([@kunalvirk](https://github.com/kunalvirk))
- Bump @typescript-eslint/eslint-plugin from 5.59.5 to 5.59.11 [#182](https://github.com/duckduckgo/autoconsent/pull/182) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump tslib from 2.5.0 to 2.5.3 [#179](https://github.com/duckduckgo/autoconsent/pull/179) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.235 to 0.0.237 [#173](https://github.com/duckduckgo/autoconsent/pull/173) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @rollup/plugin-typescript from 11.1.0 to 11.1.1 [#161](https://github.com/duckduckgo/autoconsent/pull/161) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- rewrote CMP Ketch to include US in the rules [#171](https://github.com/duckduckgo/autoconsent/pull/171) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- added 2 US CMP optOut rules and tests [#168](https://github.com/duckduckgo/autoconsent/pull/168) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Round 2: added 5 notice banner rules and tests top US sites [#167](https://github.com/duckduckgo/autoconsent/pull/167) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- added 4 notice banner rules and tests top sites [#164](https://github.com/duckduckgo/autoconsent/pull/164) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add xhamster.com custom US notice banner rule and test [#154](https://github.com/duckduckgo/autoconsent/pull/154) (arasolofotsara@duckduckgo.com [@muodov](https://github.com/muodov) [@icodebyamanda](https://github.com/icodebyamanda))
- Add youporn custom notice banner's rule and test [#158](https://github.com/duckduckgo/autoconsent/pull/158) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add pornpics custom US notice banner rule and test [#156](https://github.com/duckduckgo/autoconsent/pull/156) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add whitepages custom US notice banner rule and test [#155](https://github.com/duckduckgo/autoconsent/pull/155) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add the cmp wpcc rule and test to notice banners [#157](https://github.com/duckduckgo/autoconsent/pull/157) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Bump @types/chrome from 0.0.234 to 0.0.235 [#149](https://github.com/duckduckgo/autoconsent/pull/149) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.206 to 0.0.234 [#144](https://github.com/duckduckgo/autoconsent/pull/144) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Tweak the Civic rule [#131](https://github.com/duckduckgo/autoconsent/pull/131) ([@muodov](https://github.com/muodov))

#### 🔩 Dependency Updates

- Bump auto from 10.42.0 to 10.46.0 [#162](https://github.com/duckduckgo/autoconsent/pull/162) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.36.0 to 8.40.0 [#153](https://github.com/duckduckgo/autoconsent/pull/153) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @typescript-eslint/eslint-plugin from 5.59.2 to 5.59.5 [#152](https://github.com/duckduckgo/autoconsent/pull/152) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @rollup/plugin-typescript from 11.0.0 to 11.1.0 [#151](https://github.com/duckduckgo/autoconsent/pull/151) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 7

- [@dependabot[bot]](https://github.com/dependabot[bot])
- [@hyebahi](https://github.com/hyebahi)
- Amanda RASOLOFOTSARA ([@icodebyamanda](https://github.com/icodebyamanda))
- euw-arasolofotsara1 (arasolofotsara@duckduckgo.com)
- Kunal Virk ([@kunalvirk](https://github.com/kunalvirk))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.1.3 (Tue Feb 14 2023)

#### 🐛 Bug Fix

- Reduce triggering of coinbase and theverge rules [#101](https://github.com/duckduckgo/autoconsent/pull/101) ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump tslib from 2.4.1 to 2.5.0 [#97](https://github.com/duckduckgo/autoconsent/pull/97) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump auto from 10.37.6 to 10.42.0 [#98](https://github.com/duckduckgo/autoconsent/pull/98) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.31.0 to 8.34.0 [#100](https://github.com/duckduckgo/autoconsent/pull/100) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.1.2 (Thu Feb 09 2023)

#### 🐛 Bug Fix

- New rules [#95](https://github.com/duckduckgo/autoconsent/pull/95) ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump mocha from 10.1.0 to 10.2.0 [#64](https://github.com/duckduckgo/autoconsent/pull/64) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @playwright/test from 1.24.2 to 1.30.0 [#92](https://github.com/duckduckgo/autoconsent/pull/92) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump typescript from 4.8.4 to 4.9.5 [#93](https://github.com/duckduckgo/autoconsent/pull/93) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @rollup/plugin-typescript from 10.0.1 to 11.0.0 [#89](https://github.com/duckduckgo/autoconsent/pull/89) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @typescript-eslint/parser from 5.46.1 to 5.51.0 [#94](https://github.com/duckduckgo/autoconsent/pull/94) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 2

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.1.1 (Tue Jan 24 2023)

#### 🐛 Bug Fix

- Add a test cosmetic rule [#91](https://github.com/duckduckgo/autoconsent/pull/91) ([@muodov](https://github.com/muodov))

#### Authors: 1

- Maxim Tsoy ([@muodov](https://github.com/muodov))

---

# v4.1.0 (Tue Jan 17 2023)

#### 🚀 Enhancement

- Cosmetic rules [#67](https://github.com/duckduckgo/autoconsent/pull/67) ([@muodov](https://github.com/muodov))
- Extension Devtools [#42](https://github.com/duckduckgo/autoconsent/pull/42) ([@sammacbeth](https://github.com/sammacbeth) [@muodov](https://github.com/muodov))

#### 🐛 Bug Fix

- Cleaning up invalid tests [#49](https://github.com/duckduckgo/autoconsent/pull/49) ([@sammacbeth](https://github.com/sammacbeth))
- Fix type warning on bundle. [#83](https://github.com/duckduckgo/autoconsent/pull/83) ([@sammacbeth](https://github.com/sammacbeth))
- Add broken site issue template [#69](https://github.com/duckduckgo/autoconsent/pull/69) ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump @rollup/plugin-json from 5.0.2 to 6.0.0 [#72](https://github.com/duckduckgo/autoconsent/pull/72) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.204 to 0.0.206 [#85](https://github.com/duckduckgo/autoconsent/pull/85) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump eslint from 8.29.0 to 8.31.0 [#84](https://github.com/duckduckgo/autoconsent/pull/84) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v4.0.0 (Wed Dec 14 2022)

#### 💥 Breaking Change

- Bump @rollup/plugin-json from 4.1.0 to 5.0.2 [#61](https://github.com/duckduckgo/autoconsent/pull/61) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @rollup/plugin-typescript from 8.3.2 to 10.0.1 [#58](https://github.com/duckduckgo/autoconsent/pull/58) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### 🚀 Enhancement

- Bump @typescript-eslint/parser from 5.42.1 to 5.45.1 [#60](https://github.com/duckduckgo/autoconsent/pull/60) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @typescript-eslint/eslint-plugin from 5.42.1 to 5.45.1 [#59](https://github.com/duckduckgo/autoconsent/pull/59) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Add cookiealert CMP (cookiebot variant) [#47](https://github.com/duckduckgo/autoconsent/pull/47) ([@sammacbeth](https://github.com/sammacbeth))

#### 🐛 Bug Fix

- Bump @typescript-eslint/parser from 5.45.1 to 5.46.1 [#65](https://github.com/duckduckgo/autoconsent/pull/65) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump @types/chrome from 0.0.188 to 0.0.204 [#63](https://github.com/duckduckgo/autoconsent/pull/63) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Fix Sourcepoint CCPA popup handling [#57](https://github.com/duckduckgo/autoconsent/pull/57) ([@muodov](https://github.com/muodov))
- Fix typescript warnings [#56](https://github.com/duckduckgo/autoconsent/pull/56) ([@sammacbeth](https://github.com/sammacbeth))
- Bump tslib from 2.4.0 to 2.4.1 [#52](https://github.com/duckduckgo/autoconsent/pull/52) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump chai from 4.3.6 to 4.3.7 [#51](https://github.com/duckduckgo/autoconsent/pull/51) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Lint all code and rules in CI [#44](https://github.com/duckduckgo/autoconsent/pull/44) ([@sammacbeth](https://github.com/sammacbeth))
- Reduce triggering of affinity.serif.com rule [#45](https://github.com/duckduckgo/autoconsent/pull/45) ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump eslint from 8.28.0 to 8.29.0 [#62](https://github.com/duckduckgo/autoconsent/pull/62) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump mocha and @types/mocha [#53](https://github.com/duckduckgo/autoconsent/pull/53) ([@dependabot[bot]](https://github.com/dependabot[bot]))
- Bump web-ext from 7.3.0 to 7.4.0 [#54](https://github.com/duckduckgo/autoconsent/pull/54) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 3

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v3.0.4 (Mon Nov 21 2022)

#### 🐛 Bug Fix

- Fix sourcepoint prehiding; Remove sourcepoint-top. [#50](https://github.com/duckduckgo/autoconsent/pull/50) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v3.0.3 (Fri Nov 18 2022)

#### 🐛 Bug Fix

- Fix borlabs tests. [#43](https://github.com/duckduckgo/autoconsent/pull/43) ([@sammacbeth](https://github.com/sammacbeth))
- Fix reddit [#46](https://github.com/duckduckgo/autoconsent/pull/46) ([@sammacbeth](https://github.com/sammacbeth))
- Add extra options for Jenkins to improve test reliability. [#48](https://github.com/duckduckgo/autoconsent/pull/48) ([@sammacbeth](https://github.com/sammacbeth))
- Fix popup showing after opt-out complete on stackoverflow.com [#41](https://github.com/duckduckgo/autoconsent/pull/41) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v3.0.2 (Fri Nov 04 2022)

#### 🐛 Bug Fix

- Ignore Sourcepoint cookie paywall [#40](https://github.com/duckduckgo/autoconsent/pull/40) ([@sammacbeth](https://github.com/sammacbeth))

#### Authors: 1

- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))

---

# v3.0.1 (Thu Nov 03 2022)

#### 🐛 Bug Fix

- Use auto to automate releases on PR merge. [#37](https://github.com/duckduckgo/autoconsent/pull/37) ([@sammacbeth](https://github.com/sammacbeth))
- Remove asus rule [#38](https://github.com/duckduckgo/autoconsent/pull/38) ([@sammacbeth](https://github.com/sammacbeth))
- Slow down consentmanager popup check to prevent false positive. [#36](https://github.com/duckduckgo/autoconsent/pull/36) ([@sammacbeth](https://github.com/sammacbeth))
- Fix unwrapping of eval result array. [#33](https://github.com/duckduckgo/autoconsent/pull/33) ([@sammacbeth](https://github.com/sammacbeth))
- A bunch of site-specific rules + extension improvements [#30](https://github.com/duckduckgo/autoconsent/pull/30) ([@muodov](https://github.com/muodov) [@adewes](https://github.com/adewes))
- Optin hotfix [#31](https://github.com/duckduckgo/autoconsent/pull/31) ([@muodov](https://github.com/muodov))
- privacymanager.io + onetrust fix [#28](https://github.com/duckduckgo/autoconsent/pull/28) ([@muodov](https://github.com/muodov))
- Add rules for Sibbo (CMP) [#24](https://github.com/duckduckgo/autoconsent/pull/24) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add rules for Pubtech (CMP) [#25](https://github.com/duckduckgo/autoconsent/pull/25) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add more rules for IAB-supporting CMPs [#27](https://github.com/duckduckgo/autoconsent/pull/27) ([@muodov](https://github.com/muodov))
- Add rules for Axeptio (CMP) [#23](https://github.com/duckduckgo/autoconsent/pull/23) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- New rules [#26](https://github.com/duckduckgo/autoconsent/pull/26) ([@muodov](https://github.com/muodov))
- Added rules to monzo.com (US coverage) [#22](https://github.com/duckduckgo/autoconsent/pull/22) (arasolofotsara@duckduckgo.com [@icodebyamanda](https://github.com/icodebyamanda))
- Add rule for affinity.serif.com [#21](https://github.com/duckduckgo/autoconsent/pull/21) ([@muodov](https://github.com/muodov))
- Use new jenkins node [#20](https://github.com/duckduckgo/autoconsent/pull/20) ([@sammacbeth](https://github.com/sammacbeth))
- Fix manifest copy paths [#19](https://github.com/duckduckgo/autoconsent/pull/19) ([@muodov](https://github.com/muodov))
- 2.1.0 [#18](https://github.com/duckduckgo/autoconsent/pull/18) ([@muodov](https://github.com/muodov))
- Support for MV2 on Firefox. [#16](https://github.com/duckduckgo/autoconsent/pull/16) ([@sammacbeth](https://github.com/sammacbeth))
- Opt in improvements [#17](https://github.com/duckduckgo/autoconsent/pull/17) ([@muodov](https://github.com/muodov))
- 2.0.0 [#15](https://github.com/duckduckgo/autoconsent/pull/15) ([@muodov](https://github.com/muodov))
- Fat content script architecture [#14](https://github.com/duckduckgo/autoconsent/pull/14) ([@muodov](https://github.com/muodov))
- Setup Jenkins multibranch testing [#13](https://github.com/duckduckgo/autoconsent/pull/13) ([@sammacbeth](https://github.com/sammacbeth))
- More UK coverage [#12](https://github.com/duckduckgo/autoconsent/pull/12) ([@jdorweiler](https://github.com/jdorweiler))
- v1.0.7 [#11](https://github.com/duckduckgo/autoconsent/pull/11) ([@muodov](https://github.com/muodov))
- Some cosmetic fixes [#10](https://github.com/duckduckgo/autoconsent/pull/10) ([@muodov](https://github.com/muodov))
- Convert OneTrust rule to JS [#9](https://github.com/duckduckgo/autoconsent/pull/9) ([@muodov](https://github.com/muodov))
- Fix popup detection [#4](https://github.com/duckduckgo/autoconsent/pull/4) ([@muodov](https://github.com/muodov))
- revert visible change [#8](https://github.com/duckduckgo/autoconsent/pull/8) ([@jdorweiler](https://github.com/jdorweiler))
- Add more tests [#6](https://github.com/duckduckgo/autoconsent/pull/6) ([@jdorweiler](https://github.com/jdorweiler) [@sammacbeth](https://github.com/sammacbeth))
- v1.0.4 [#5](https://github.com/duckduckgo/autoconsent/pull/5) ([@jdorweiler](https://github.com/jdorweiler))
- More rules for DE sites [#3](https://github.com/duckduckgo/autoconsent/pull/3) ([@jdorweiler](https://github.com/jdorweiler))
- more CMP rules [#1](https://github.com/duckduckgo/autoconsent/pull/1) ([@jdorweiler](https://github.com/jdorweiler))

#### ⚠️ Pushed to `main`

- 3.0.0 ([@adewes](https://github.com/adewes))
- 2.2.1 ([@muodov](https://github.com/muodov))
- Minor flicker fix for uniconsent ([@muodov](https://github.com/muodov))
- 2.2.0 ([@muodov](https://github.com/muodov))
- 2.1.2 ([@sammacbeth](https://github.com/sammacbeth))
- 2.1.1 ([@muodov](https://github.com/muodov))
- 1.0.8 ([@jdorweiler](https://github.com/jdorweiler))
- 1.0.6 ([@muodov](https://github.com/muodov))
- 1.0.5 ([@jdorweiler](https://github.com/jdorweiler))
- v1.0.3 ([@jdorweiler](https://github.com/jdorweiler))
- Publish to duckduckgo's npm. ([@sammacbeth](https://github.com/sammacbeth))
- 1.0.2 ([@sammacbeth](https://github.com/sammacbeth))
- Onetrust fixes. ([@sammacbeth](https://github.com/sammacbeth))
- 1.0.1 ([@sammacbeth](https://github.com/sammacbeth))
- Wait longer before unhiding on Consent-o-matic CMPs ([@sammacbeth](https://github.com/sammacbeth))
- 1.0.0 ([@sammacbeth](https://github.com/sammacbeth))
- cancer.org -> Onetrust ([@sammacbeth](https://github.com/sammacbeth))
- forums.cpanel.net -> cookiebot ([@sammacbeth](https://github.com/sammacbeth))
- Add prehide selectors to rules ([@sammacbeth](https://github.com/sammacbeth))
- Support for prehide rules ([@sammacbeth](https://github.com/sammacbeth))
- Support auto-optout in test addon. ([@sammacbeth](https://github.com/sammacbeth))
- Add klaro ([@sammacbeth](https://github.com/sammacbeth))
- Prepare to support prehiding. ([@sammacbeth](https://github.com/sammacbeth))
- 0.10.0 ([@sammacbeth](https://github.com/sammacbeth))
- Revert "expatica.com changed CMP." ([@sammacbeth](https://github.com/sammacbeth))
- Sourcepoint: unhide elements after rule completes ([@sammacbeth](https://github.com/sammacbeth))
- Add undohide rule for removing CSS hiding rules ([@sammacbeth](https://github.com/sammacbeth))
- expatica.com changed CMP. ([@sammacbeth](https://github.com/sammacbeth))
- 0.9.4 ([@sammacbeth](https://github.com/sammacbeth))
- Cookiebot fixes ([@sammacbeth](https://github.com/sammacbeth))
- Remove uniconsent ([@sammacbeth](https://github.com/sammacbeth))
- Cookie law info fix ([@sammacbeth](https://github.com/sammacbeth))
- 0.9.3 ([@sammacbeth](https://github.com/sammacbeth))
- More region skipping ([@sammacbeth](https://github.com/sammacbeth))
- Fix rule builder ([@sammacbeth](https://github.com/sammacbeth))
- Break out of detection when an exception occurs. ([@sammacbeth](https://github.com/sammacbeth))
- Wait for popups too ([@sammacbeth](https://github.com/sammacbeth))
- 0.9.2 ([@sammacbeth](https://github.com/sammacbeth))
- Test stability improvements ([@sammacbeth](https://github.com/sammacbeth))
- Use built-in screenshotting ([@sammacbeth](https://github.com/sammacbeth))
- Remove unused CMPs ([@sammacbeth](https://github.com/sammacbeth))
- 0.9.1 ([@sammacbeth](https://github.com/sammacbeth))
- More test coverage ([@sammacbeth](https://github.com/sammacbeth))
- Sourcepoint DNS fix. ([@sammacbeth](https://github.com/sammacbeth))
- Account for regional differences in tests ([@sammacbeth](https://github.com/sammacbeth))
- Test spec tweaks ([@sammacbeth](https://github.com/sammacbeth))
- Skip some tests based on region. ([@sammacbeth](https://github.com/sammacbeth))
- Update test runner to use describe ([@sammacbeth](https://github.com/sammacbeth))
- Add region to test names ([@sammacbeth](https://github.com/sammacbeth))
- Puppeteer frame detection fixes ([@sammacbeth](https://github.com/sammacbeth))
- 0.9.0 ([@sammacbeth](https://github.com/sammacbeth))
- Playwright tests ([@sammacbeth](https://github.com/sammacbeth))
- 0.8.1 ([@sammacbeth](https://github.com/sammacbeth))
- Fix for Onetrust on stack exchange sites. ([@sammacbeth](https://github.com/sammacbeth))
- Sourcepoint fix ([@sammacbeth](https://github.com/sammacbeth))
- 0.8.0 ([@sammacbeth](https://github.com/sammacbeth))
- Batch of CMP additions and fixes for US sites. ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.5 ([@sammacbeth](https://github.com/sammacbeth))
- Stricter TS config. ([@sammacbeth](https://github.com/sammacbeth))
- Drop onetrust-stackoverflow CMP ([@sammacbeth](https://github.com/sammacbeth))
- Add npm clean script ([@sammacbeth](https://github.com/sammacbeth))
- Test CMP update ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.4 ([@sammacbeth](https://github.com/sammacbeth))
- Make parallel rules an AND ([@sammacbeth](https://github.com/sammacbeth))
- Onetrust fixes ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.3 ([@sammacbeth](https://github.com/sammacbeth))
- Remove broken CMPs ([@sammacbeth](https://github.com/sammacbeth))
- Implement Evidon. ([@sammacbeth](https://github.com/sammacbeth))
- Consentmanager.net implementation. ([@sammacbeth](https://github.com/sammacbeth))
- Cybotcookiebot fixes and improvements. ([@sammacbeth](https://github.com/sammacbeth))
- Implement tealium CMP ([@sammacbeth](https://github.com/sammacbeth))
- TrustArc fixes and hiding. ([@sammacbeth](https://github.com/sammacbeth))
- Disable ez-cookie (broken) ([@sammacbeth](https://github.com/sammacbeth))
- Remove Sirdata (broken) ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.2 ([@sammacbeth](https://github.com/sammacbeth))
- Make hideElements a noop on puppeteer. ([@sammacbeth](https://github.com/sammacbeth))
- Fix puppeteer visibility detection ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.1 ([@sammacbeth](https://github.com/sammacbeth))
- Ensure everything gets built before publish ([@sammacbeth](https://github.com/sammacbeth))
- Create autoconsent rule for onetrust ([@sammacbeth](https://github.com/sammacbeth))
- 0.7.0 ([@sammacbeth](https://github.com/sammacbeth))
- More specific detection for cookiebot ([@sammacbeth](https://github.com/sammacbeth))
- Add API for disabling CMPs ([@sammacbeth](https://github.com/sammacbeth))
- 0.6.3 ([@sammacbeth](https://github.com/sammacbeth))
- Make consent-o-matic action method a string ([@sammacbeth](https://github.com/sammacbeth))
- More test cases ([@sammacbeth](https://github.com/sammacbeth))
- Fixes for the puppeteer tab implementation. ([@sammacbeth](https://github.com/sammacbeth))
- Minor CMP fixes ([@sammacbeth](https://github.com/sammacbeth))
- 0.6.2 ([@sammacbeth](https://github.com/sammacbeth))
- Addon version as a date ([@sammacbeth](https://github.com/sammacbeth))
- Clear frames on main frame change. ([@sammacbeth](https://github.com/sammacbeth))
- Hide popup while clicking it. ([@sammacbeth](https://github.com/sammacbeth))
- 0.6.1 ([@sammacbeth](https://github.com/sammacbeth))
- Fix rule builder when there are no consent-o-matic overrides ([@sammacbeth](https://github.com/sammacbeth))
- Fix publishing of .js files ([@sammacbeth](https://github.com/sammacbeth))
- 0.6.0 ([@sammacbeth](https://github.com/sammacbeth))
- Preparing for cross-platform support ([@sammacbeth](https://github.com/sammacbeth))
- Bump version ([@sammacbeth](https://github.com/sammacbeth))
- Add Google funding choices CMP ([@sammacbeth](https://github.com/sammacbeth))
- Cleanup broken CMPs ([@sammacbeth](https://github.com/sammacbeth))
- Add watch build script ([@sammacbeth](https://github.com/sammacbeth))
- Add update url ([@sammacbeth](https://github.com/sammacbeth))
- Fix sourcepoint implementation. ([@sammacbeth](https://github.com/sammacbeth))
- Bump consent-o-matic rules ([@sammacbeth](https://github.com/sammacbeth))
- Change extension ID and bump version ([@sammacbeth](https://github.com/sammacbeth))
- Add page action icons ([@sammacbeth](https://github.com/sammacbeth))
- Return early on detection if one returns true ([@sammacbeth](https://github.com/sammacbeth))
- Control running of opt out from a page action ([@sammacbeth](https://github.com/sammacbeth))
- 0.5.4 ([@sammacbeth](https://github.com/sammacbeth))
- Disable debugging messages in content-script. Fixes #18 ([@sammacbeth](https://github.com/sammacbeth))
- 0.5.3 ([@sammacbeth](https://github.com/sammacbeth))
- Use TCFv2 as the default test. ([@sammacbeth](https://github.com/sammacbeth))
- Updated version of quantcast ([@sammacbeth](https://github.com/sammacbeth))
- Update consent-o-matic rules ([@sammacbeth](https://github.com/sammacbeth))
- Google opt-out rule ([@sammacbeth](https://github.com/sammacbeth))
- Add privacy-mgmt CMP - new on theguardian.com ([@sammacbeth](https://github.com/sammacbeth))
- 0.5.2 ([@sammacbeth](https://github.com/sammacbeth))
- 0.5.1 ([@sammacbeth](https://github.com/sammacbeth))
- Update web-ext ([@sammacbeth](https://github.com/sammacbeth))
- Remove cosmetic rule breaking condor.de ([@sammacbeth](https://github.com/sammacbeth))
- Remove #cookiebanner - breaking on bamf.de ([@sammacbeth](https://github.com/sammacbeth))
- 0.5.0 ([@sammacbeth](https://github.com/sammacbeth))
- Extra bracket ([@sammacbeth](https://github.com/sammacbeth))
- Remove rule that breaks www.nomanssky.com ([@sammacbeth](https://github.com/sammacbeth))
- Remove rule that breaks www.huk.de ([@sammacbeth](https://github.com/sammacbeth))
- Remove rule breaking congstar.de ([@sammacbeth](https://github.com/sammacbeth))
- Remove problematic cosmetic rule ([@sammacbeth](https://github.com/sammacbeth))
- 0.4.0 ([@sammacbeth](https://github.com/sammacbeth))
- Export web module as cjs ([@sammacbeth](https://github.com/sammacbeth))
- Add rule exception for tommy.de ([@sammacbeth](https://github.com/sammacbeth))
- 0.3.3 ([@sammacbeth](https://github.com/sammacbeth))
- Fix rule is undefined error. ([@sammacbeth](https://github.com/sammacbeth))
- 0.3.2 ([@sammacbeth](https://github.com/sammacbeth))
- More new cosmetics ([@sammacbeth](https://github.com/sammacbeth))
- Add another future site. ([@sammacbeth](https://github.com/sammacbeth))
- New cosmetics rules for sites in issue #6 ([@sammacbeth](https://github.com/sammacbeth))
- Add Drupal CMP ([@sammacbeth](https://github.com/sammacbeth))
- Add InternetBrands CMP ([@sammacbeth](https://github.com/sammacbeth))
- Add Cevent ([@sammacbeth](https://github.com/sammacbeth))
- Improve Sourcepoint reliability. ([@sammacbeth](https://github.com/sammacbeth))
- Add Clarip CMP ([@sammacbeth](https://github.com/sammacbeth))
- Fix case where non-Cookiebot providers use the CookieConsent global ([@sammacbeth](https://github.com/sammacbeth))
- Add Sourcepoint CMP ([@sammacbeth](https://github.com/sammacbeth))
- Add .gdprPopup cosmetic rule. Fixes #3. ([@sammacbeth](https://github.com/sammacbeth))
- Add cookies-overlay rule. Fixes #4 ([@sammacbeth](https://github.com/sammacbeth))
- Hotfix medium scroll-lock ([@sammacbeth](https://github.com/sammacbeth))
- Remove chip and focus specific cosmetics ([@sammacbeth](https://github.com/sammacbeth))
- Disable cmsCookieNotification ([@sammacbeth](https://github.com/sammacbeth))
- 0.3.1 ([@sammacbeth](https://github.com/sammacbeth))
- Fix tagcommander CMP not detecting frame. ([@sammacbeth](https://github.com/sammacbeth))
- Update readme.md ([@sammacbeth](https://github.com/sammacbeth))
- Fix the test extension. ([@sammacbeth](https://github.com/sammacbeth))
- Updated cosmetics. ([@sammacbeth](https://github.com/sammacbeth))
- Add Civic CMP. ([@sammacbeth](https://github.com/sammacbeth))
- Implement termly consent banner. ([@sammacbeth](https://github.com/sammacbeth))
- More cosmetic improvements. ([@sammacbeth](https://github.com/sammacbeth))
- Cosmetic fix for bussgeldkatalog.de ([@sammacbeth](https://github.com/sammacbeth))
- 0.3.0 ([@sammacbeth](https://github.com/sammacbeth))
- Defer rule resolution on checkTab function. Use `checked` method to wait ([@sammacbeth](https://github.com/sammacbeth))
- Additional cookie banner cosmetics. ([@sammacbeth](https://github.com/sammacbeth))
- Don't auto-reload test extension ([@sammacbeth](https://github.com/sammacbeth))
- Fix admiral consent. ([@sammacbeth](https://github.com/sammacbeth))
- Testing sidebar improvements. ([@sammacbeth](https://github.com/sammacbeth))
- Fix catch eval errors. ([@sammacbeth](https://github.com/sammacbeth))
- Fix screenshot paths ([@sammacbeth](https://github.com/sammacbeth))
- Catch eval errors. ([@sammacbeth](https://github.com/sammacbeth))
- Remove protocol from screenshot path. ([@sammacbeth](https://github.com/sammacbeth))
- Add job summary output. ([@sammacbeth](https://github.com/sammacbeth))
- Add admiral CMP. ([@sammacbeth](https://github.com/sammacbeth))
- More cosmetics. ([@sammacbeth](https://github.com/sammacbeth))
- Add CMP for entrepreneur.com ([@sammacbeth](https://github.com/sammacbeth))
- Add w18lara cmp ([@sammacbeth](https://github.com/sammacbeth))
- Future cmp. ([@sammacbeth](https://github.com/sammacbeth))
- Add Sirdata CMP. ([@sammacbeth](https://github.com/sammacbeth))
- Tagcommander fixes ([@sammacbeth](https://github.com/sammacbeth))
- Add faktor.io CMP ([@sammacbeth](https://github.com/sammacbeth))
- Improve testing extension with cosmetics. ([@sammacbeth](https://github.com/sammacbeth))
- Add new cosmetic rules ([@sammacbeth](https://github.com/sammacbeth))
- 0.2.0 ([@sammacbeth](https://github.com/sammacbeth))
- npm audit fix ([@sammacbeth](https://github.com/sammacbeth))
- Make content script messaging pluggable ([@sammacbeth](https://github.com/sammacbeth))
- Remove 'frame' message and use webNavigation API instead. ([@sammacbeth](https://github.com/sammacbeth))
- 0.1.0 ([@sammacbeth](https://github.com/sammacbeth))
- Fix the crawler. ([@sammacbeth](https://github.com/sammacbeth))
- Add cosmetic rules in JSON form. ([@sammacbeth](https://github.com/sammacbeth))
- Fix asus opt-out. ([@sammacbeth](https://github.com/sammacbeth))
- 0.0.7 ([@sammacbeth](https://github.com/sammacbeth))
- Remove cosmetics from project ([@sammacbeth](https://github.com/sammacbeth))
- Add Wikia CMP ([@sammacbeth](https://github.com/sammacbeth))
- Fix some issues on tagcommander ([@sammacbeth](https://github.com/sammacbeth))
- Add sidebar to test extension ([@sammacbeth](https://github.com/sammacbeth))
- 0.0.6 ([@sammacbeth](https://github.com/sammacbeth))
- Make webextension listener sync ([@sammacbeth](https://github.com/sammacbeth))
- 0.0.5 ([@sammacbeth](https://github.com/sammacbeth))
- Cleaning. ([@sammacbeth](https://github.com/sammacbeth))
- Revert to cosmetic opt-out for trustarc. ([@sammacbeth](https://github.com/sammacbeth))
- 0.0.4 ([@sammacbeth](https://github.com/sammacbeth))
- Avoid preinstall hook ([@sammacbeth](https://github.com/sammacbeth))
- Bump version. ([@sammacbeth](https://github.com/sammacbeth))
- Test extension for testing and debugging autoconsent rules. ([@sammacbeth](https://github.com/sammacbeth))
- 0.0.2 ([@sammacbeth](https://github.com/sammacbeth))
- Add license and readme. ([@sammacbeth](https://github.com/sammacbeth))
- Mark sites where popup was not detected. ([@sammacbeth](https://github.com/sammacbeth))
- Make app gdpr popup detection less aggressive. ([@sammacbeth](https://github.com/sammacbeth))
- Also check if popup is detected during crawl. ([@sammacbeth](https://github.com/sammacbeth))
- Further coverage improvements. ([@sammacbeth](https://github.com/sammacbeth))
- Fix techradar opt-out. ([@sammacbeth](https://github.com/sammacbeth))
- Split dynamic and static cosmetics. ([@sammacbeth](https://github.com/sammacbeth))
- Move tabs implementations into module. ([@sammacbeth](https://github.com/sammacbeth))
- Add recommended rules to report. ([@sammacbeth](https://github.com/sammacbeth))
- Make sandboxing toggleable. ([@sammacbeth](https://github.com/sammacbeth))
- WIP dockerized puppeteer. ([@sammacbeth](https://github.com/sammacbeth))
- Add auto crawl deployment ([@sammacbeth](https://github.com/sammacbeth))
- Fix errors with missing elements. ([@sammacbeth](https://github.com/sammacbeth))
- Support frame creation after first load. ([@sammacbeth](https://github.com/sammacbeth))
- Crawler html report. ([@sammacbeth](https://github.com/sammacbeth))
- Implement tab.goto ([@sammacbeth](https://github.com/sammacbeth))
- More fixes. ([@sammacbeth](https://github.com/sammacbeth))
- Didomi fix. ([@sammacbeth](https://github.com/sammacbeth))
- app_gdpr fixes and new entries. ([@sammacbeth](https://github.com/sammacbeth))
- Crawling with opt-out test. ([@sammacbeth](https://github.com/sammacbeth))
- Initial commit: autoconsent rules from re:consent plus crawler implementation. ([@sammacbeth](https://github.com/sammacbeth))

#### 🔩 Dependency Updates

- Bump terser from 5.13.1 to 5.15.1 [#34](https://github.com/duckduckgo/autoconsent/pull/34) ([@dependabot[bot]](https://github.com/dependabot[bot]))

#### Authors: 7

- [@dependabot[bot]](https://github.com/dependabot[bot])
- Amanda RASOLOFOTSARA ([@icodebyamanda](https://github.com/icodebyamanda))
- Andreas Dewes ([@adewes](https://github.com/adewes))
- euw-arasolofotsara1 (arasolofotsara@duckduckgo.com)
- Jason ([@jdorweiler](https://github.com/jdorweiler))
- Maxim Tsoy ([@muodov](https://github.com/muodov))
- Sam Macbeth ([@sammacbeth](https://github.com/sammacbeth))
