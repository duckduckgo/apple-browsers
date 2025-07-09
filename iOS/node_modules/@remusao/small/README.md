# `@remusao/small`

> Return smallest valid content of different types

Based on the work from: https://github.com/mathiasbynens/small/

## Usage

```javascript
const { getResourceForMime, getDataUrlForMime } = require('@remusao/small');

console.log(getResourceForMime('mp3'));
// {
//   contentType: 'audio/mpeg;base64',
//   aliases: [ 'audio/mpeg', '.mp3', 'mp3' ],
//   body: '/+MYxAAAAANIAAAAAExBTUUzLjk4LjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
// }

console.log(getDataUrlForMime('mp3'));
// audio/mpeg;base64,/+MYxAAAAANIAAAAAExBTUUzLjk4LjIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```
