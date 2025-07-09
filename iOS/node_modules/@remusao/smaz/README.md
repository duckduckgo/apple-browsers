# `@remusao/smaz`

> Compress strings using custom codebooks

A port of the [smaz](https://github.com/antirez/smaz) small string compression library to JavaScript.

From the original library:

> Smaz is a simple compression library suitable for compressing very short
> strings. General purpose compression libraries will build the state needed
> for compressing data dynamically, in order to be able to compress every kind
> of data. This is a very good idea, but not for a specific problem: compressing
> small strings will not work.
>
> Smaz instead is not good for compressing general purpose data, but can compress
> text by 40-50% in the average case (works better with English), and is able to
> perform a bit of compression for HTML and urls as well. The important point is
> that Smaz is able to compress even strings of two or three bytes!
>
> For example the string "the" is compressed into a single byte.
>
> To compare this with other libraries, think that like zlib will
> usually not be able to compress text shorter than 100 bytes.

## Usage

```javascript
const { compress, decompress } = require('@remusao/smaz');

const compressed = compress('foobar');
console.log(decompress(compressed));
```
