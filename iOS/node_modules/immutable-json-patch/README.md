# immutable-json-patch

Immutable JSON patch with support for reverting operations.

Features:

- Apply JSON patch operations on a JSON document in an immutable way.
- Create inverse of the JSON patch operations to fully revert applied operations.
- Hook into the operations right before and after they are executed.

Try it out on a playground: https://josdejong.github.io/immutable-json-patch/

See http://jsonpatch.com/ for a clear description of the JSONPatch standard itself.


## Install

```
$ npm install immutable-json-patch
```

Note that in the `lib` folder, there are builds for ESM, UMD, and CommonJs.

## Load

ESM:

```js
import { immutableJSONPatch, revertJSONPatch } from 'immutable-json-patch'
```

CommonJs:

```js
const { immutableJSONPatch, revertJSONPatch } = require('immutable-json-patch')
```


## Use

Example from http://jsonpatch.com/#simple-example, using `immutable-json-patch`:

```js
import { immutableJSONPatch, revertJSONPatch } from 'immutable-json-patch'

const document = {
  baz: 'qux',
  foo: 'bar'
}
console.log('document', document)

const operations = [
  { op: 'replace', path: '/baz', value: 'boo' },
  { op: 'add', path: '/hello', value: ['world'] },
  { op: 'remove', path: '/foo' }
]
console.log('operations', operations)

const updatedDocument = immutableJSONPatch(document, operations)
console.log('updatedDocument', updatedDocument)
// updatedDocument = {
//   "baz": "boo",
//   "hello": ["world"]
// }

const reverseOperations = revertJSONPatch(document, operations)
console.log('reverseOperations', reverseOperations)
// reverseOperations = [
//   { op: 'add', path: '/foo', value: 'bar' },
//   { op: 'remove', path: '/hello' },
//   { op: 'replace', path: '/baz', value: 'qux' }
// ]

const revertedDocument = immutableJSONPatch(updatedJsonupdatedDocument, reverseOperations)
console.log('revertedDocument', revertedJsonrevertedDocument)
// revertedDocument = {
//   "baz": "qux",
//   "foo": "bar"
// }
```


### API

#### immutableJSONPatch(document, operations [, options]) => updatedDocument

Apply a list with JSON Patch operations to a JSON document.

```ts
declare function immutableJSONPatch<T, U = unknown> (document: T, operations: JSONPatchDocument, options?: JSONPatchOptions) : U
```

Where:

-   `document: T` is a JSON document
-   `operations: JSONPatchDocument` is an array with JSONPatch operations
-   `options: JSONPatchOptions` is an optional object allowing passing hooks `before` and `after`. With those hooks it is possible to alter the JSON document and/or applied operation before and after this is applied. This allows for example to instantiate classes or additional data structures when applying a JSON patch operation. Or you can keep certain data stats up to date. For example, it is possible to have an array with `Customer` class instances, and instantiate a `new Customer` when an `add` operation is performed. And in this library itself, the `before` callback is used to create inverse operations whilst applying the actual operations on the document.
 
    The callbacks look like:

    ```ts
    const options = {
      before: (document: unknown, operation: JSONPatchOperation) => {
        console.log('before operation', { document, operation })
        // return { document?: unknown, operation?: JSONPatchOperation } | undefined
      },
    
      after: (document: unknown, operation: JSONPatchOperation, previousDocument: unknown) => {
        console.log('after operation', { document, operation, previousDocument })
        // return document | undefined
      }
    }
    ```
    
    When the `before` or `after` callback returns an object with altered `document`, this will be used to apply the operation. When and altered `operation` is returned from `before` in an object, this operation will be applied instead of the original operation. 
    
The function returns an updated JSON document where the JSON patch operations are applied. The original JSON document is not changed.

#### revertJSONPatch(document, operations, options) => reverseOperations

Generate the JSON patch operations that will revert the provided list with JSON Patch operations when applied to the provided JSON document.

```ts
declare function revertJSONPatch<T, U> (document: T, operations: JSONPatchDocument, options?: RevertJSONPatchOptions) : JSONPatchDocument
```

Where:

-   `document: T` is a JSON document
-   `operations: JSONPatchDocument` is an array with JSONPatch operations
-   `options: JSONPatchOptions` is an optional object allowing passing a hook `before`. With this hook it is possible to alter the JSON document and/or generated `reverseOperations` before this is applied.

The function returns a list with the reverse JSON Patch operations. These operations can be applied to the updated JSON document (the output of `immutableJSONPatch`) to restore the original JSON document.

#### util functions

The library exposes a set of utility functions and typeguards to work with JSON pointers and to do immutable operations on JSON data:

```ts
declare function parsePath<T>(document: T, path: JSONPointer): JSONPath
declare function parseFrom(path: JSONPointer): JSONPath

declare function parseJSONPointer (pointer: JSONPointer) : JSONPath
declare function compileJSONPointer (path: JSONPath) : JSONPointer
declare function compileJSONPointerProp (pathProp: string | number) : JSONPointer
declare function appendToJSONPointer (pointer: JSONPointer, pathProp: string | number) : JSONPointer
declare function startsWithJSONPointer (pointer: JSONPointer, searchPointer: JSONPointer) : boolean

declare function isJSONPatchOperation(operation: unknown): operation is JSONPatchOperation
declare function isJSONPatchAdd(operation: unknown): operation is JSONPatchAdd
declare function isJSONPatchRemove(operation: unknown): operation is JSONPatchRemove
declare function isJSONPatchReplace(operation: unknown): operation is JSONPatchReplace
declare function isJSONPatchCopy(operation: unknown): operation is JSONPatchCopy
declare function isJSONPatchMove(operation: unknown): operation is JSONPatchMove
declare function isJSONPatchTest(operation: unknown): operation is JSONPatchTest

declare function getIn<T, U = unknown>(object: U, path: JSONPath) : T | undefined
declare function setIn<T, U = unknown, V = unknown> (object: U, path: JSONPath, value: V, createPath = false) : T
declare function updateIn<T, U = unknown, V = unknown> (object: T, path: JSONPath, transform: (value: U) => V) : T
declare function deleteIn<T, U = unknown> (object: U, path: JSONPath) : T
declare function existsIn<T> (document: T, path: JSONPath) : boolean
declare function insertAt<T, U = unknown> (document: T, path: JSONPath, value: U) : T
declare function transform <T, U = unknown, V = unknown, W = unknown> (
  document: U, 
  callback: (document: V, path: JSONPath) => W, path: JSONPath = []
) : T 
```

### Develop

To build the library (ESM, CommonJs, and UMD output in the folder `lib`):

```
$ npm install 
$ npm run build
```

To run the unit tests:

```
$ npm test
```

To run the linter (eslint):

```
$ npm run lint
```

To run the linter, build all, and run unit tests and integration tests:

```
$ npm run build-and-test
```


## License

Released under the [ISC license](LICENSE.md).
