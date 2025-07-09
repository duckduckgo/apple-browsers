import { describe, it } from 'node:test';
import { equal } from 'node:assert/strict';
import { convertMarkdownToHTMLForStrongTags } from '../freemiumPIRBanner.utils.js';

describe('convertMarkdownToHTMLForStrongTags', () => {
    it('with terms wrapped in "**" will return with <strong> tags wrapping that part of the string', () => {
        const str = 'Find out which sites are selling **your info**.';
        const expected = 'Find out which sites are selling <strong>your info</strong>.';
        const actual = convertMarkdownToHTMLForStrongTags(str);
        equal(actual, expected);
    });

    it("will not affect strings that don't have two sets of two astrisks", () => {
        const strWithoutStars = 'Gingerbread oat cake dessert macaroon powder tiramisu topping.';
        const strWithOneStar = 'Gingerbread oat* cake dessert macaroon powder tiramisu topping.';
        const strWithOneStarSandwich = 'Gingerbread *oat* cake dessert macaroon powder tiramisu topping.';
        const strWithUnevenStars = 'Gingerbread **oat* cake dessert macaroon powder tiramisu topping.';

        const actualWithoutStars = convertMarkdownToHTMLForStrongTags(strWithoutStars);
        const actualWithOneStar = convertMarkdownToHTMLForStrongTags(strWithOneStar);
        const actualWithOneStarSandwich = convertMarkdownToHTMLForStrongTags(strWithOneStarSandwich);
        const actualWithUnevenStars = convertMarkdownToHTMLForStrongTags(strWithUnevenStars);

        equal(actualWithoutStars, strWithoutStars);
        equal(actualWithOneStar, strWithOneStar);
        equal(actualWithOneStarSandwich, strWithOneStarSandwich);
        equal(actualWithUnevenStars, strWithUnevenStars);
    });

    it('will handle strings that have more than one set of bolded words', () => {
        const str = 'Gingerbread **oat cake** dessert **macaroon powder tiramisu** topping.';
        const expected = 'Gingerbread <strong>oat cake</strong> dessert <strong>macaroon powder tiramisu</strong> topping.';
        const actual = convertMarkdownToHTMLForStrongTags(str);
        equal(actual, expected);
    });

    it('ignores HTML', () => {
        const str = 'abc **def** <script>alert(document.cookie)</script>';
        const expected = 'abc <strong>def</strong> &lt;script&gt;alert(document.cookie)&lt;&#x2F;script&gt;';
        const actual = convertMarkdownToHTMLForStrongTags(str);
        equal(actual, expected);
    });
});
