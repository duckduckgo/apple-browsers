import { test, expect } from '@playwright/test';
import { NewtabPage } from '../../../integration-tests/new-tab.page.js';
import { OmnibarPage } from './omnibar.page.js';

test.describe('omnibar widget', () => {
    test('fetches config on load', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true, 'omnibar.enableAi': true } });
        await ntp.mocks.waitForCallCount({ method: 'initialSetup', count: 1 });
        await ntp.mocks.waitForCallCount({ method: 'omnibar_getConfig', count: 1 });
    });

    test('search form submission', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        await omnibar.searchInput().fill('pizza');
        await omnibar.searchInput().press('Enter');

        await omnibar.expectMethodCalledWith('omnibar_submitSearch', {
            term: 'pizza',
            target: 'same-tab',
        });
    });

    test('AI chat form submission', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        await omnibar.aiTab().click();
        await omnibar.expectMode('ai');

        await omnibar.chatInput().fill('pizza');
        await omnibar.chatInput().press('Enter');

        await omnibar.expectMethodCalledWith('omnibar_submitChat', {
            chat: 'pizza',
            target: 'same-tab',
        });
    });

    test('AI chat button in search form submits chat message', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        await omnibar.searchInput().fill('pizza');
        await omnibar.aiChatButton().click();

        await omnibar.expectMethodCalledWith('omnibar_submitChat', {
            chat: 'pizza',
            target: 'same-tab',
        });
    });

    test('mode switching preserves query state', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Start in search mode, type query
        await omnibar.searchInput().fill('pizza');
        await expect(omnibar.searchInput()).toHaveValue('pizza');

        // Switch to AI mode
        await omnibar.aiTab().click();
        await omnibar.expectMode('ai');
        await expect(omnibar.chatInput()).toHaveValue('pizza');

        // Switch back to search mode
        await omnibar.searchTab().click();
        await omnibar.expectMode('search');
        await expect(omnibar.searchInput()).toHaveValue('pizza');
    });

    test('omnibar without AI enabled does not show tab list', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true, 'omnibar.enableAi': false } });
        await omnibar.ready();

        await expect(omnibar.tabList()).toHaveCount(0);
    });

    test('suggestions list arrow down navigation', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza dough" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.expectSuggestionsCount(2);

        // Initially no selection
        await omnibar.expectNoSelection();

        // Press arrow down - select first item
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza dough recipe');

        // Press arrow down again - select second item
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('Pizza Dough Calculator');

        // Press arrow down again - clear selection
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectNoSelection();

        // Press arrow down again - rotate back to first item
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza dough recipe');
    });

    test('suggestions list arrow up navigation', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza dough" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.expectSuggestionsCount(2);

        // Initially no selection
        await omnibar.expectNoSelection();

        // Press arrow up - select last item (reverse direction)
        await omnibar.searchInput().press('ArrowUp');
        await omnibar.expectSelectedSuggestion('Pizza Dough Calculator');

        // Press arrow up again - select first item
        await omnibar.searchInput().press('ArrowUp');
        await omnibar.expectSelectedSuggestion('pizza dough recipe');

        // Press arrow up again - clear selection
        await omnibar.searchInput().press('ArrowUp');
        await omnibar.expectNoSelection();

        // Press arrow up again - rotate back to last item
        await omnibar.searchInput().press('ArrowUp');
        await omnibar.expectSelectedSuggestion('Pizza Dough Calculator');
    });

    test('arrow down and enter should open selected suggestion', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza dough" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.expectSuggestionsCount(2);

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza dough recipe');

        // Press enter to open selected suggestion
        await omnibar.searchInput().press('Enter');

        await omnibar.expectMethodCalledWith('omnibar_openSuggestion', {
            suggestion: expect.objectContaining({
                phrase: 'pizza dough recipe',
                kind: 'phrase',
            }),
            target: 'same-tab',
        });
    });

    test('clicking on a suggestion should open it', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza dough" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.expectSuggestionsCount(2);

        // Click on the second suggestion
        await omnibar.suggestions().nth(1).click();

        await omnibar.expectMethodCalledWith('omnibar_openSuggestion', {
            suggestion: expect.objectContaining({
                title: 'Pizza Dough Calculator',
                kind: 'historyEntry',
            }),
            target: 'same-tab',
        });
    });

    test('mouse over should select suggestion, mouse out should clear selection', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza dough" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.expectSuggestionsCount(2);

        // Initially no selection
        await omnibar.expectNoSelection();

        // Hover over first suggestion
        await omnibar.suggestions().nth(0).hover();
        await omnibar.expectSelectedSuggestion('pizza dough recipe');

        // Hover over second suggestion
        await omnibar.suggestions().nth(1).hover();
        await omnibar.expectSelectedSuggestion('Pizza Dough Calculator');

        // Mouse out to clear selection (hover outside suggestions)
        await omnibar.searchInput().hover();
        await omnibar.expectNoSelection();
    });

    test('pressing tab should move focus away from input', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Focus on search input
        await omnibar.searchInput().focus();
        await expect(omnibar.searchInput()).toBeFocused();

        // Press tab to move focus away
        await omnibar.searchInput().press('Tab');
        await expect(omnibar.searchInput()).not.toBeFocused();
    });

    test('input suggestion when title begins with query', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Select "pizza near me" suggestion (starts with "pizza")
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');

        // Input should show "pizza[ near me]" with " near me" selected
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');
        await omnibar.expectInputSelection(5, 13);
    });

    test('input suggestion when url begins with query', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Navigate to find "pizzahut.com" suggestion (url starts with "pizza")
        await omnibar.searchInput().press('ArrowDown'); // pizza near me
        await omnibar.searchInput().press('ArrowDown'); // pizza delivery
        await omnibar.searchInput().press('ArrowDown'); // pizza hut
        await omnibar.searchInput().press('ArrowDown'); // pizzahut.com
        await omnibar.expectSelectedSuggestion('pizzahut.com');

        // Input should show "pizza[hut.com]" with "hut.com" selected
        await omnibar.expectInputValue('pizzahut.com');
        await omnibar.expectInputSelectionText('hut.com');
        await omnibar.expectInputSelection(5, 12);
    });

    test('input suggestion when neither title nor url begins with query', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Navigate to find a history entry that doesn't start with "pizza"
        // Keep pressing down until we get to "Italian Pizza History"
        for (let i = 0; i < 15; i++) {
            await omnibar.searchInput().press('ArrowDown');
        }
        await omnibar.expectSelectedSuggestion('Italian Pizza History');

        // Input should show "[Italian Pizza History]" with entire text selected
        await omnibar.expectInputValue('Italian Pizza History');
        await omnibar.expectInputSelectionText('Italian Pizza History');
        await omnibar.expectInputSelection(0, 21);
    });

    test('arrow down after arrow left should restore suggestion selection', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');

        // Input should show "pizza[ near me]" with " near me" selected
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');
        await omnibar.expectInputSelection(5, 13);

        // Press left arrow to move cursor
        await omnibar.searchInput().press('ArrowLeft');

        // Input should now show "pizza near me" with cursor after "pizza"
        await omnibar.expectNoSelection();
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelection(5, 5);

        // Press arrow down again
        await omnibar.searchInput().press('ArrowDown');

        // Should be back to "pizza[ near me]" with " near me" selected
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');
        await omnibar.expectInputSelection(5, 13);
    });

    test('arrow left when suggestion selected should place cursor to left of selection', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press left arrow to move cursor to left of selection
        await omnibar.searchInput().press('ArrowLeft');

        // Cursor should be positioned after "pizza" (no selection)
        await omnibar.expectNoSelection();
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelection(5, 5);
    });

    test('arrow right when suggestion selected should place cursor to right of selection', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press right arrow to move cursor to right of selection
        await omnibar.searchInput().press('ArrowRight');

        // Cursor should be positioned at the end of input (no selection)
        await omnibar.expectNoSelection();
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelection(13, 13);
    });

    test('delete when suggestion selected should remove selection and place cursor at end of original query', async ({
        page,
    }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press delete to remove selection
        await omnibar.searchInput().press('Delete');

        // Input should show "pizza" with cursor at end
        await omnibar.expectNoSelection();
        await omnibar.expectInputValue('pizza');
        await omnibar.expectInputSelection(5, 5);
    });

    test('typing when suggestion selected should replace selection with new text', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Type " mar" to replace selection - simulate actual typing behavior
        await omnibar.searchInput().pressSequentially(' mar');
        await omnibar.waitForSuggestions();

        // Input should show "pizza mar" with cursor at end, no selection
        await omnibar.expectNoSelection();
        await omnibar.expectInputValue('pizza mar');
        await omnibar.expectInputSelection(9, 9);
        await omnibar.expectSuggestionsCount(2);
    });

    test('clearing input field should hide suggestions', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza dough');
        await omnibar.waitForSuggestions();

        // Verify suggestions appear
        await omnibar.expectSuggestionsCount(2);

        // Clear the input field
        await omnibar.searchInput().fill('');

        // Verify suggestions are hidden
        await omnibar.expectSuggestionsCount(0);
    });

    test('pressing ESC should hide suggestions while preserving input suggestion', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press ESC to hide suggestions
        await omnibar.searchInput().press('Escape');

        // Suggestions should be hidden but input should remain "pizza[ near me]"
        await omnibar.expectSuggestionsCount(0);
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');
        await omnibar.expectInputSelection(5, 13);
    });

    test('arrow keys after ESC should move cursor, not navigate hidden suggestions', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press ESC to hide suggestions
        await omnibar.searchInput().press('Escape');
        await omnibar.expectSuggestionsCount(0);
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Press arrow down - should move cursor to end, not navigate hidden suggestions
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelection(13, 13); // cursor at end
        await omnibar.expectSuggestionsCount(0); // still hidden

        // Clear input and test arrow up
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.searchInput().press('Escape');
        await omnibar.expectSuggestionsCount(0);
        await omnibar.expectInputSelectionText(' near me');

        // Press arrow up - should move cursor to beginning, not navigate hidden suggestions
        await omnibar.searchInput().press('ArrowUp');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelection(0, 0); // cursor at beginning
        await omnibar.expectSuggestionsCount(0); // still hidden
    });

    test('clearing input field should reset selected suggestion index', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Press arrow down to select first suggestion
        await omnibar.searchInput().press('ArrowDown');
        await omnibar.expectSelectedSuggestion('pizza near me');
        await omnibar.expectInputValue('pizza near me');
        await omnibar.expectInputSelectionText(' near me');

        // Clear the input field completely
        await omnibar.searchInput().fill('');

        // Input should be completely empty, not repopulated with suggestion
        await omnibar.expectInputValue('');
        await omnibar.expectSuggestionsCount(0);

        // Verify no selection text remains
        await omnibar.expectInputSelection(0, 0);
    });

    test('clicking outside search field should close suggestions', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Verify suggestions are visible
        await omnibar.expectSuggestionsCount(17);

        // Click outside the search field (on the page body)
        await page.click('body', { position: { x: 100, y: 100 } });

        // Suggestions should be closed
        await omnibar.expectSuggestionsCount(0);

        // Input should retain its value
        await omnibar.expectInputValue('pizza');
    });

    test('focusing outside search field should close suggestions', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        const omnibar = new OmnibarPage(ntp);
        await ntp.reducedMotion();

        await ntp.openPage({ additional: { omnibar: true } });
        await omnibar.ready();

        // Type "pizza" to get suggestions
        await omnibar.searchInput().fill('pizza');
        await omnibar.waitForSuggestions();

        // Verify suggestions are visible
        await omnibar.expectSuggestionsCount(17);

        // Focus outside the search form (press Shift+Tab to move focus to pill switcher)
        await omnibar.searchInput().press('Shift+Tab');

        // Suggestions should be closed
        await omnibar.expectSuggestionsCount(0);

        // Input should retain its value
        await omnibar.expectInputValue('pizza');
    });
});
