import { expect } from '@playwright/test';

export class OmnibarPage {
    /**
     * @param {import("../../../integration-tests/new-tab.page.js").NewtabPage} ntp
     */
    constructor(ntp) {
        this.ntp = ntp;
        this.page = this.ntp.page;
    }

    context() {
        return this.page.locator('[data-entry-point="omnibar"]');
    }

    async ready() {
        await this.ntp.mocks.waitForCallCount({ method: 'omnibar_getConfig', count: 1 });
    }

    searchInput() {
        return this.context().getByRole('combobox');
    }

    chatInput() {
        return this.context().getByRole('textbox', { name: 'Chat privately with Duck.ai' });
    }

    tabList() {
        return this.context().getByRole('tablist');
    }

    searchTab() {
        return this.context().getByRole('tab', { name: 'Search' });
    }

    aiTab() {
        return this.context().getByRole('tab', { name: 'Duck.ai' });
    }

    aiChatButton() {
        return this.context().getByRole('button', { name: 'Duck.ai' });
    }

    suggestionsList() {
        return this.context().getByRole('listbox');
    }

    suggestions() {
        return this.suggestionsList().getByRole('option');
    }

    /**
     * @param {number} count
     */
    async expectSuggestionsCount(count) {
        await expect(this.suggestions()).toHaveCount(count);
    }

    selectedSuggestion() {
        return this.suggestionsList().getByRole('option', { selected: true });
    }

    /**
     * @param {string} text
     */
    async expectSelectedSuggestion(text) {
        await expect(this.selectedSuggestion()).toHaveText(text);
    }

    async expectNoSelection() {
        await expect(this.selectedSuggestion()).toHaveCount(0);
    }

    async waitForSuggestions() {
        await expect(this.suggestions().first()).toBeVisible();
    }

    /**
     * @param {string} value
     */
    async expectInputValue(value) {
        await expect(this.searchInput()).toHaveValue(value);
    }

    /**
     * @param {number} startIndex
     * @param {number} endIndex
     */
    async expectInputSelection(startIndex, endIndex) {
        const input = this.searchInput();
        const selectionStart = await input.evaluate((/** @type {HTMLInputElement} */ el) => el.selectionStart);
        const selectionEnd = await input.evaluate((/** @type {HTMLInputElement} */ el) => el.selectionEnd);
        expect(selectionStart).toBe(startIndex);
        expect(selectionEnd).toBe(endIndex);
    }

    /**
     * @param {string} selectedText
     */
    async expectInputSelectionText(selectedText) {
        const input = this.searchInput();
        const selection = await input.evaluate((/** @type {HTMLInputElement} */ el) =>
            el.value.slice(el.selectionStart ?? 0, el.selectionEnd ?? 0),
        );
        expect(selection).toBe(selectedText);
    }

    /**
     * @param {'search' | 'ai'} mode
     */
    async expectMode(mode) {
        if (mode === 'search') {
            await expect(this.searchTab()).toHaveAttribute('aria-selected', 'true');
        } else {
            await expect(this.aiTab()).toHaveAttribute('aria-selected', 'true');
        }
    }

    /**
     * @param {string} method
     * @param {number} count
     */
    async expectMethodCallCount(method, count) {
        await this.ntp.mocks.waitForCallCount({ method, count });
    }

    /**
     * @param {string} method
     * @param {object} expectedParams
     */
    async expectMethodCalledWith(method, expectedParams) {
        const calls = await this.ntp.mocks.waitForCallCount({ method, count: 1 });
        expect(calls[0].payload.params).toEqual(expectedParams);
    }
}
