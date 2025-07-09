import { convertToLegalComments } from '../scripts/utils/comment-plugin.js';

describe('convertToLegalComments', () => {
    it('should convert single line comments with copyright', () => {
        const input = `// This is a copyright notice
const foo = 'bar';`;

        const expected = `//! This is a copyright notice
const foo = 'bar';`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should convert multiple consecutive line comments following a copyright line', () => {
        const input = `// This is a copyright notice
// This is a second line
// This is a third line
const foo = 'bar';`;

        const expected = `//! This is a copyright notice
//! This is a second line
//! This is a third line
const foo = 'bar';`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should stop converting after a non-comment line is encountered', () => {
        const input = `// This is a copyright notice
// This is a second line
const foo = 'bar';
// This is a regular comment that should not be converted`;

        const expected = `//! This is a copyright notice
//! This is a second line
const foo = 'bar';
// This is a regular comment that should not be converted`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle multiple separate comment blocks', () => {
        const input = `// This is a regular comment
const a = 1;

// This has copyright info
// And continues here
const b = 2;

// Another copyright notice
// With more details
// And even more info
const c = 3;`;

        const expected = `// This is a regular comment
const a = 1;

//! This has copyright info
//! And continues here
const b = 2;

//! Another copyright notice
//! With more details
//! And even more info
const c = 3;`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle indented comments', () => {
        const input = `function test() {
    // This has copyright info
    // This is indented
    return true;
}`;

        const expected = `function test() {
    //! This has copyright info
    //! This is indented
    return true;
}`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle block comments with copyright', () => {
        const input = `/* This is a copyright block comment */
const foo = 'bar';

/* This is a regular
   multiline comment */`;

        const expected = `/*! This is a copyright block comment */
const foo = 'bar';

/* This is a regular
   multiline comment */`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle mixed comment types', () => {
        const input = `// This has copyright info
// This continues
/* This is a regular block comment */
const foo = 'bar';

/* This is a copyright block comment */
// This is a regular comment after a block`;

        const expected = `//! This has copyright info
//! This continues
/* This is a regular block comment */
const foo = 'bar';

/*! This is a copyright block comment */
// This is a regular comment after a block`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle block comments breaking line comment sequences', () => {
        const input = `// This has copyright info
// This line should be converted
/* This block comment breaks the sequence */
// This line should NOT be converted
// Even though it follows another comment`;

        const expected = `//! This has copyright info
//! This line should be converted
/* This block comment breaks the sequence */
// This line should NOT be converted
// Even though it follows another comment`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle case insensitivity for "copyright"', () => {
        const input = `// This has COPYRIGHT info
// This continues
const foo = 'bar';

// This has Copyright mixed case
// More comments
const baz = 'qux';`;

        const expected = `//! This has COPYRIGHT info
//! This continues
const foo = 'bar';

//! This has Copyright mixed case
//! More comments
const baz = 'qux';`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should not convert comments without copyright', () => {
        const input = `// This is a regular comment
// Another regular comment
const foo = 'bar';`;

        const expected = `// This is a regular comment
// Another regular comment
const foo = 'bar';`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should handle code with no comments', () => {
        const input = `const foo = 'bar';
function test() {
  return true;
}
const obj = { key: 'value' };`;

        const expected = input; // Should remain unchanged

        expect(convertToLegalComments(input)).toEqual(expected);
    });

    it('should treat empty lines as non-comment lines that break the sequence', () => {
        const input = `// This has copyright info
// This continues

// These comments should NOT be converted
// Because empty line breaks the sequence
const foo = 'bar';`;

        const expected = `//! This has copyright info
//! This continues

// These comments should NOT be converted
// Because empty line breaks the sequence
const foo = 'bar';`;

        expect(convertToLegalComments(input)).toEqual(expected);
    });
});
