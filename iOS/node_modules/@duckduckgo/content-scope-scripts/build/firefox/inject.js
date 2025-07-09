/*! © DuckDuckGo ContentScopeScripts protections https://github.com/duckduckgo/content-scope-scripts/ */
"use strict";
(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __typeError = (msg) => {
    throw TypeError(msg);
  };
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
  var __accessCheck = (obj, member, msg) => member.has(obj) || __typeError("Cannot " + msg);
  var __privateGet = (obj, member, getter) => (__accessCheck(obj, member, "read from private field"), getter ? getter.call(obj) : member.get(obj));
  var __privateAdd = (obj, member, value) => member.has(obj) ? __typeError("Cannot add the same private member more than once") : member instanceof WeakSet ? member.add(obj) : member.set(obj, value);
  var __privateSet = (obj, member, value, setter) => (__accessCheck(obj, member, "write to private field"), setter ? setter.call(obj, value) : member.set(obj, value), value);
  var __privateMethod = (obj, member, method) => (__accessCheck(obj, member, "access private method"), method);

  // ../node_modules/seedrandom/lib/alea.js
  var require_alea = __commonJS({
    "../node_modules/seedrandom/lib/alea.js"(exports, module) {
      //! Copyright (C) 2010 by Johannes Baagøe <baagoe@baagoe.org>
      //!
      //! Permission is hereby granted, free of charge, to any person obtaining a copy
      //! of this software and associated documentation files (the "Software"), to deal
      //! in the Software without restriction, including without limitation the rights
      //! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      //! copies of the Software, and to permit persons to whom the Software is
      //! furnished to do so, subject to the following conditions:
      //!
      //! The above copyright notice and this permission notice shall be included in
      //! all copies or substantial portions of the Software.
      //!
      //! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      //! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      //! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      //! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      //! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      //! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
      //! THE SOFTWARE.
      (function(global, module2, define2) {
        function Alea(seed) {
          var me2 = this, mash = Mash();
          me2.next = function() {
            var t = 2091639 * me2.s0 + me2.c * 23283064365386963e-26;
            me2.s0 = me2.s1;
            me2.s1 = me2.s2;
            return me2.s2 = t - (me2.c = t | 0);
          };
          me2.c = 1;
          me2.s0 = mash(" ");
          me2.s1 = mash(" ");
          me2.s2 = mash(" ");
          me2.s0 -= mash(seed);
          if (me2.s0 < 0) {
            me2.s0 += 1;
          }
          me2.s1 -= mash(seed);
          if (me2.s1 < 0) {
            me2.s1 += 1;
          }
          me2.s2 -= mash(seed);
          if (me2.s2 < 0) {
            me2.s2 += 1;
          }
          mash = null;
        }
        function copy2(f, t) {
          t.c = f.c;
          t.s0 = f.s0;
          t.s1 = f.s1;
          t.s2 = f.s2;
          return t;
        }
        function impl(seed, opts) {
          var xg = new Alea(seed), state = opts && opts.state, prng = xg.next;
          prng.int32 = function() {
            return xg.next() * 4294967296 | 0;
          };
          prng.double = function() {
            return prng() + (prng() * 2097152 | 0) * 11102230246251565e-32;
          };
          prng.quick = prng;
          if (state) {
            if (typeof state == "object") copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        function Mash() {
          var n = 4022871197;
          var mash = function(data) {
            data = String(data);
            for (var i = 0; i < data.length; i++) {
              n += data.charCodeAt(i);
              var h = 0.02519603282416938 * n;
              n = h >>> 0;
              h -= n;
              h *= n;
              n = h >>> 0;
              h -= n;
              n += h * 4294967296;
            }
            return (n >>> 0) * 23283064365386963e-26;
          };
          return mash;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.alea = impl;
        }
      })(
        exports,
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // ../node_modules/seedrandom/lib/xor128.js
  var require_xor128 = __commonJS({
    "../node_modules/seedrandom/lib/xor128.js"(exports, module) {
      (function(global, module2, define2) {
        function XorGen(seed) {
          var me2 = this, strseed = "";
          me2.x = 0;
          me2.y = 0;
          me2.z = 0;
          me2.w = 0;
          me2.next = function() {
            var t = me2.x ^ me2.x << 11;
            me2.x = me2.y;
            me2.y = me2.z;
            me2.z = me2.w;
            return me2.w ^= me2.w >>> 19 ^ t ^ t >>> 8;
          };
          if (seed === (seed | 0)) {
            me2.x = seed;
          } else {
            strseed += seed;
          }
          for (var k = 0; k < strseed.length + 64; k++) {
            me2.x ^= strseed.charCodeAt(k) | 0;
            me2.next();
          }
        }
        function copy2(f, t) {
          t.x = f.x;
          t.y = f.y;
          t.z = f.z;
          t.w = f.w;
          return t;
        }
        function impl(seed, opts) {
          var xg = new XorGen(seed), state = opts && opts.state, prng = function() {
            return (xg.next() >>> 0) / 4294967296;
          };
          prng.double = function() {
            do {
              var top = xg.next() >>> 11, bot = (xg.next() >>> 0) / 4294967296, result = (top + bot) / (1 << 21);
            } while (result === 0);
            return result;
          };
          prng.int32 = xg.next;
          prng.quick = prng;
          if (state) {
            if (typeof state == "object") copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.xor128 = impl;
        }
      })(
        exports,
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // ../node_modules/seedrandom/lib/xorwow.js
  var require_xorwow = __commonJS({
    "../node_modules/seedrandom/lib/xorwow.js"(exports, module) {
      (function(global, module2, define2) {
        function XorGen(seed) {
          var me2 = this, strseed = "";
          me2.next = function() {
            var t = me2.x ^ me2.x >>> 2;
            me2.x = me2.y;
            me2.y = me2.z;
            me2.z = me2.w;
            me2.w = me2.v;
            return (me2.d = me2.d + 362437 | 0) + (me2.v = me2.v ^ me2.v << 4 ^ (t ^ t << 1)) | 0;
          };
          me2.x = 0;
          me2.y = 0;
          me2.z = 0;
          me2.w = 0;
          me2.v = 0;
          if (seed === (seed | 0)) {
            me2.x = seed;
          } else {
            strseed += seed;
          }
          for (var k = 0; k < strseed.length + 64; k++) {
            me2.x ^= strseed.charCodeAt(k) | 0;
            if (k == strseed.length) {
              me2.d = me2.x << 10 ^ me2.x >>> 4;
            }
            me2.next();
          }
        }
        function copy2(f, t) {
          t.x = f.x;
          t.y = f.y;
          t.z = f.z;
          t.w = f.w;
          t.v = f.v;
          t.d = f.d;
          return t;
        }
        function impl(seed, opts) {
          var xg = new XorGen(seed), state = opts && opts.state, prng = function() {
            return (xg.next() >>> 0) / 4294967296;
          };
          prng.double = function() {
            do {
              var top = xg.next() >>> 11, bot = (xg.next() >>> 0) / 4294967296, result = (top + bot) / (1 << 21);
            } while (result === 0);
            return result;
          };
          prng.int32 = xg.next;
          prng.quick = prng;
          if (state) {
            if (typeof state == "object") copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.xorwow = impl;
        }
      })(
        exports,
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // ../node_modules/seedrandom/lib/xorshift7.js
  var require_xorshift7 = __commonJS({
    "../node_modules/seedrandom/lib/xorshift7.js"(exports, module) {
      (function(global, module2, define2) {
        function XorGen(seed) {
          var me2 = this;
          me2.next = function() {
            var X = me2.x, i = me2.i, t, v2, w2;
            t = X[i];
            t ^= t >>> 7;
            v2 = t ^ t << 24;
            t = X[i + 1 & 7];
            v2 ^= t ^ t >>> 10;
            t = X[i + 3 & 7];
            v2 ^= t ^ t >>> 3;
            t = X[i + 4 & 7];
            v2 ^= t ^ t << 7;
            t = X[i + 7 & 7];
            t = t ^ t << 13;
            v2 ^= t ^ t << 9;
            X[i] = v2;
            me2.i = i + 1 & 7;
            return v2;
          };
          function init2(me3, seed2) {
            var j2, w2, X = [];
            if (seed2 === (seed2 | 0)) {
              w2 = X[0] = seed2;
            } else {
              seed2 = "" + seed2;
              for (j2 = 0; j2 < seed2.length; ++j2) {
                X[j2 & 7] = X[j2 & 7] << 15 ^ seed2.charCodeAt(j2) + X[j2 + 1 & 7] << 13;
              }
            }
            while (X.length < 8) X.push(0);
            for (j2 = 0; j2 < 8 && X[j2] === 0; ++j2) ;
            if (j2 == 8) w2 = X[7] = -1;
            else w2 = X[j2];
            me3.x = X;
            me3.i = 0;
            for (j2 = 256; j2 > 0; --j2) {
              me3.next();
            }
          }
          init2(me2, seed);
        }
        function copy2(f, t) {
          t.x = f.x.slice();
          t.i = f.i;
          return t;
        }
        function impl(seed, opts) {
          if (seed == null) seed = +/* @__PURE__ */ new Date();
          var xg = new XorGen(seed), state = opts && opts.state, prng = function() {
            return (xg.next() >>> 0) / 4294967296;
          };
          prng.double = function() {
            do {
              var top = xg.next() >>> 11, bot = (xg.next() >>> 0) / 4294967296, result = (top + bot) / (1 << 21);
            } while (result === 0);
            return result;
          };
          prng.int32 = xg.next;
          prng.quick = prng;
          if (state) {
            if (state.x) copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.xorshift7 = impl;
        }
      })(
        exports,
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // ../node_modules/seedrandom/lib/xor4096.js
  var require_xor4096 = __commonJS({
    "../node_modules/seedrandom/lib/xor4096.js"(exports, module) {
      (function(global, module2, define2) {
        function XorGen(seed) {
          var me2 = this;
          me2.next = function() {
            var w2 = me2.w, X = me2.X, i = me2.i, t, v2;
            me2.w = w2 = w2 + 1640531527 | 0;
            v2 = X[i + 34 & 127];
            t = X[i = i + 1 & 127];
            v2 ^= v2 << 13;
            t ^= t << 17;
            v2 ^= v2 >>> 15;
            t ^= t >>> 12;
            v2 = X[i] = v2 ^ t;
            me2.i = i;
            return v2 + (w2 ^ w2 >>> 16) | 0;
          };
          function init2(me3, seed2) {
            var t, v2, i, j2, w2, X = [], limit = 128;
            if (seed2 === (seed2 | 0)) {
              v2 = seed2;
              seed2 = null;
            } else {
              seed2 = seed2 + "\0";
              v2 = 0;
              limit = Math.max(limit, seed2.length);
            }
            for (i = 0, j2 = -32; j2 < limit; ++j2) {
              if (seed2) v2 ^= seed2.charCodeAt((j2 + 32) % seed2.length);
              if (j2 === 0) w2 = v2;
              v2 ^= v2 << 10;
              v2 ^= v2 >>> 15;
              v2 ^= v2 << 4;
              v2 ^= v2 >>> 13;
              if (j2 >= 0) {
                w2 = w2 + 1640531527 | 0;
                t = X[j2 & 127] ^= v2 + w2;
                i = 0 == t ? i + 1 : 0;
              }
            }
            if (i >= 128) {
              X[(seed2 && seed2.length || 0) & 127] = -1;
            }
            i = 127;
            for (j2 = 4 * 128; j2 > 0; --j2) {
              v2 = X[i + 34 & 127];
              t = X[i = i + 1 & 127];
              v2 ^= v2 << 13;
              t ^= t << 17;
              v2 ^= v2 >>> 15;
              t ^= t >>> 12;
              X[i] = v2 ^ t;
            }
            me3.w = w2;
            me3.X = X;
            me3.i = i;
          }
          init2(me2, seed);
        }
        function copy2(f, t) {
          t.i = f.i;
          t.w = f.w;
          t.X = f.X.slice();
          return t;
        }
        ;
        function impl(seed, opts) {
          if (seed == null) seed = +/* @__PURE__ */ new Date();
          var xg = new XorGen(seed), state = opts && opts.state, prng = function() {
            return (xg.next() >>> 0) / 4294967296;
          };
          prng.double = function() {
            do {
              var top = xg.next() >>> 11, bot = (xg.next() >>> 0) / 4294967296, result = (top + bot) / (1 << 21);
            } while (result === 0);
            return result;
          };
          prng.int32 = xg.next;
          prng.quick = prng;
          if (state) {
            if (state.X) copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.xor4096 = impl;
        }
      })(
        exports,
        // window object or global
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // ../node_modules/seedrandom/lib/tychei.js
  var require_tychei = __commonJS({
    "../node_modules/seedrandom/lib/tychei.js"(exports, module) {
      (function(global, module2, define2) {
        function XorGen(seed) {
          var me2 = this, strseed = "";
          me2.next = function() {
            var b2 = me2.b, c = me2.c, d = me2.d, a2 = me2.a;
            b2 = b2 << 25 ^ b2 >>> 7 ^ c;
            c = c - d | 0;
            d = d << 24 ^ d >>> 8 ^ a2;
            a2 = a2 - b2 | 0;
            me2.b = b2 = b2 << 20 ^ b2 >>> 12 ^ c;
            me2.c = c = c - d | 0;
            me2.d = d << 16 ^ c >>> 16 ^ a2;
            return me2.a = a2 - b2 | 0;
          };
          me2.a = 0;
          me2.b = 0;
          me2.c = 2654435769 | 0;
          me2.d = 1367130551;
          if (seed === Math.floor(seed)) {
            me2.a = seed / 4294967296 | 0;
            me2.b = seed | 0;
          } else {
            strseed += seed;
          }
          for (var k = 0; k < strseed.length + 20; k++) {
            me2.b ^= strseed.charCodeAt(k) | 0;
            me2.next();
          }
        }
        function copy2(f, t) {
          t.a = f.a;
          t.b = f.b;
          t.c = f.c;
          t.d = f.d;
          return t;
        }
        ;
        function impl(seed, opts) {
          var xg = new XorGen(seed), state = opts && opts.state, prng = function() {
            return (xg.next() >>> 0) / 4294967296;
          };
          prng.double = function() {
            do {
              var top = xg.next() >>> 11, bot = (xg.next() >>> 0) / 4294967296, result = (top + bot) / (1 << 21);
            } while (result === 0);
            return result;
          };
          prng.int32 = xg.next;
          prng.quick = prng;
          if (state) {
            if (typeof state == "object") copy2(state, xg);
            prng.state = function() {
              return copy2(xg, {});
            };
          }
          return prng;
        }
        if (module2 && module2.exports) {
          module2.exports = impl;
        } else if (define2 && define2.amd) {
          define2(function() {
            return impl;
          });
        } else {
          this.tychei = impl;
        }
      })(
        exports,
        typeof module == "object" && module,
        // present in node.js
        typeof define == "function" && define
        // present with an AMD loader
      );
    }
  });

  // (disabled):crypto
  var require_crypto = __commonJS({
    "(disabled):crypto"() {
    }
  });

  // ../node_modules/seedrandom/seedrandom.js
  var require_seedrandom = __commonJS({
    "../node_modules/seedrandom/seedrandom.js"(exports, module) {
      /*!
      Copyright 2019 David Bau.
      
      Permission is hereby granted, free of charge, to any person obtaining
      a copy of this software and associated documentation files (the
      "Software"), to deal in the Software without restriction, including
      without limitation the rights to use, copy, modify, merge, publish,
      distribute, sublicense, and/or sell copies of the Software, and to
      permit persons to whom the Software is furnished to do so, subject to
      the following conditions:
      
      The above copyright notice and this permission notice shall be
      included in all copies or substantial portions of the Software.
      
      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
      EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
      IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
      CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
      TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
      SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
      
      */
      (function(global, pool, math) {
        var width = 256, chunks = 6, digits = 52, rngname = "random", startdenom = math.pow(width, chunks), significance = math.pow(2, digits), overflow = significance * 2, mask = width - 1, nodecrypto;
        function seedrandom(seed, options, callback) {
          var key = [];
          options = options == true ? { entropy: true } : options || {};
          var shortseed = mixkey(flatten(
            options.entropy ? [seed, tostring(pool)] : seed == null ? autoseed() : seed,
            3
          ), key);
          var arc4 = new ARC4(key);
          var prng = function() {
            var n = arc4.g(chunks), d = startdenom, x2 = 0;
            while (n < significance) {
              n = (n + x2) * width;
              d *= width;
              x2 = arc4.g(1);
            }
            while (n >= overflow) {
              n /= 2;
              d /= 2;
              x2 >>>= 1;
            }
            return (n + x2) / d;
          };
          prng.int32 = function() {
            return arc4.g(4) | 0;
          };
          prng.quick = function() {
            return arc4.g(4) / 4294967296;
          };
          prng.double = prng;
          mixkey(tostring(arc4.S), pool);
          return (options.pass || callback || function(prng2, seed2, is_math_call, state) {
            if (state) {
              if (state.S) {
                copy2(state, arc4);
              }
              prng2.state = function() {
                return copy2(arc4, {});
              };
            }
            if (is_math_call) {
              math[rngname] = prng2;
              return seed2;
            } else return prng2;
          })(
            prng,
            shortseed,
            "global" in options ? options.global : this == math,
            options.state
          );
        }
        function ARC4(key) {
          var t, keylen = key.length, me2 = this, i = 0, j2 = me2.i = me2.j = 0, s = me2.S = [];
          if (!keylen) {
            key = [keylen++];
          }
          while (i < width) {
            s[i] = i++;
          }
          for (i = 0; i < width; i++) {
            s[i] = s[j2 = mask & j2 + key[i % keylen] + (t = s[i])];
            s[j2] = t;
          }
          (me2.g = function(count) {
            var t2, r = 0, i2 = me2.i, j3 = me2.j, s2 = me2.S;
            while (count--) {
              t2 = s2[i2 = mask & i2 + 1];
              r = r * width + s2[mask & (s2[i2] = s2[j3 = mask & j3 + t2]) + (s2[j3] = t2)];
            }
            me2.i = i2;
            me2.j = j3;
            return r;
          })(width);
        }
        function copy2(f, t) {
          t.i = f.i;
          t.j = f.j;
          t.S = f.S.slice();
          return t;
        }
        ;
        function flatten(obj, depth) {
          var result = [], typ = typeof obj, prop;
          if (depth && typ == "object") {
            for (prop in obj) {
              try {
                result.push(flatten(obj[prop], depth - 1));
              } catch (e) {
              }
            }
          }
          return result.length ? result : typ == "string" ? obj : obj + "\0";
        }
        function mixkey(seed, key) {
          var stringseed = seed + "", smear, j2 = 0;
          while (j2 < stringseed.length) {
            key[mask & j2] = mask & (smear ^= key[mask & j2] * 19) + stringseed.charCodeAt(j2++);
          }
          return tostring(key);
        }
        function autoseed() {
          try {
            var out;
            if (nodecrypto && (out = nodecrypto.randomBytes)) {
              out = out(width);
            } else {
              out = new Uint8Array(width);
              (global.crypto || global.msCrypto).getRandomValues(out);
            }
            return tostring(out);
          } catch (e) {
            var browser = global.navigator, plugins = browser && browser.plugins;
            return [+/* @__PURE__ */ new Date(), global, plugins, global.screen, tostring(pool)];
          }
        }
        function tostring(a2) {
          return String.fromCharCode.apply(0, a2);
        }
        mixkey(math.random(), pool);
        if (typeof module == "object" && module.exports) {
          module.exports = seedrandom;
          try {
            nodecrypto = require_crypto();
          } catch (ex) {
          }
        } else if (typeof define == "function" && define.amd) {
          define(function() {
            return seedrandom;
          });
        } else {
          math["seed" + rngname] = seedrandom;
        }
      })(
        // global: `self` in browsers (including strict mode and web workers),
        // otherwise `this` in Node and other environments
        typeof self !== "undefined" ? self : exports,
        [],
        // pool: entropy pool starts empty
        Math
        // math: package containing random, pow, and seedrandom
      );
    }
  });

  // ../node_modules/seedrandom/index.js
  var require_seedrandom2 = __commonJS({
    "../node_modules/seedrandom/index.js"(exports, module) {
      var alea = require_alea();
      var xor128 = require_xor128();
      var xorwow = require_xorwow();
      var xorshift7 = require_xorshift7();
      var xor4096 = require_xor4096();
      var tychei = require_tychei();
      var sr = require_seedrandom();
      sr.alea = alea;
      sr.xor128 = xor128;
      sr.xorwow = xorwow;
      sr.xorshift7 = xorshift7;
      sr.xor4096 = xor4096;
      sr.tychei = tychei;
      module.exports = sr;
    }
  });

  // src/captured-globals.js
  var captured_globals_exports = {};
  __export(captured_globals_exports, {
    CustomEvent: () => CustomEvent2,
    Error: () => Error2,
    Map: () => Map2,
    Promise: () => Promise2,
    Proxy: () => Proxy2,
    Reflect: () => Reflect2,
    Set: () => Set2,
    String: () => String2,
    Symbol: () => Symbol2,
    TypeError: () => TypeError2,
    URL: () => URL2,
    addEventListener: () => addEventListener,
    customElementsDefine: () => customElementsDefine,
    customElementsGet: () => customElementsGet,
    dispatchEvent: () => dispatchEvent,
    functionToString: () => functionToString,
    getOwnPropertyDescriptor: () => getOwnPropertyDescriptor,
    getOwnPropertyDescriptors: () => getOwnPropertyDescriptors,
    hasOwnProperty: () => hasOwnProperty,
    objectDefineProperty: () => objectDefineProperty,
    objectEntries: () => objectEntries,
    objectKeys: () => objectKeys,
    randomUUID: () => randomUUID,
    removeEventListener: () => removeEventListener,
    toString: () => toString
  });
  var Set2 = globalThis.Set;
  var Reflect2 = globalThis.Reflect;
  var customElementsGet = globalThis.customElements?.get.bind(globalThis.customElements);
  var customElementsDefine = globalThis.customElements?.define.bind(globalThis.customElements);
  var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
  var getOwnPropertyDescriptors = Object.getOwnPropertyDescriptors;
  var toString = Object.prototype.toString;
  var objectKeys = Object.keys;
  var objectEntries = Object.entries;
  var objectDefineProperty = Object.defineProperty;
  var URL2 = globalThis.URL;
  var Proxy2 = globalThis.Proxy;
  var functionToString = Function.prototype.toString;
  var TypeError2 = globalThis.TypeError;
  var Symbol2 = globalThis.Symbol;
  var hasOwnProperty = Object.prototype.hasOwnProperty;
  var dispatchEvent = globalThis.dispatchEvent?.bind(globalThis);
  var addEventListener = globalThis.addEventListener?.bind(globalThis);
  var removeEventListener = globalThis.removeEventListener?.bind(globalThis);
  var CustomEvent2 = globalThis.CustomEvent;
  var Promise2 = globalThis.Promise;
  var String2 = globalThis.String;
  var Map2 = globalThis.Map;
  var Error2 = globalThis.Error;
  var randomUUID = globalThis.crypto?.randomUUID?.bind(globalThis.crypto);

  // src/utils.js
  var globalObj = typeof window === "undefined" ? globalThis : window;
  var Error3 = globalObj.Error;
  var messageSecret;
  var OriginalCustomEvent = typeof CustomEvent === "undefined" ? null : CustomEvent;
  var originalWindowDispatchEvent = typeof window === "undefined" ? null : window.dispatchEvent.bind(window);
  function registerMessageSecret(secret2) {
    messageSecret = secret2;
  }
  function getInjectionElement() {
    return document.head || document.documentElement;
  }
  function createStyleElement(css) {
    const style = document.createElement("style");
    style.innerText = css;
    return style;
  }
  function injectGlobalStyles(css) {
    const style = createStyleElement(css);
    getInjectionElement().appendChild(style);
  }
  function getGlobal() {
    return globalObj;
  }
  function nextRandom(v2) {
    return Math.abs(v2 >> 1 | (v2 << 62 ^ v2 << 61) & ~(~0 << 63) << 62);
  }
  var exemptionLists = {};
  function shouldExemptUrl(type, url) {
    for (const regex of exemptionLists[type]) {
      if (regex.test(url)) {
        return true;
      }
    }
    return false;
  }
  var debug = false;
  function initStringExemptionLists(args) {
    const { stringExemptionLists } = args;
    debug = args.debug;
    for (const type in stringExemptionLists) {
      exemptionLists[type] = [];
      for (const stringExemption of stringExemptionLists[type]) {
        exemptionLists[type].push(new RegExp(stringExemption));
      }
    }
  }
  function isBeingFramed() {
    if (globalThis.location && "ancestorOrigins" in globalThis.location) {
      return globalThis.location.ancestorOrigins.length > 0;
    }
    return globalThis.top !== globalThis.window;
  }
  function isThirdPartyFrame() {
    if (!isBeingFramed()) {
      return false;
    }
    const tabHostname = getTabHostname();
    if (!tabHostname) {
      return true;
    }
    return !matchHostname(globalThis.location.hostname, tabHostname);
  }
  function getTabUrl() {
    let framingURLString = null;
    try {
      framingURLString = globalThis.top.location.href;
    } catch {
      framingURLString = getTopLevelOriginFromFrameAncestors() ?? globalThis.document.referrer;
    }
    let framingURL;
    try {
      framingURL = new URL(framingURLString);
    } catch {
      framingURL = null;
    }
    return framingURL;
  }
  function getTopLevelOriginFromFrameAncestors() {
    if ("ancestorOrigins" in globalThis.location && globalThis.location.ancestorOrigins.length) {
      return globalThis.location.ancestorOrigins.item(globalThis.location.ancestorOrigins.length - 1);
    }
    return null;
  }
  function getTabHostname() {
    const topURLString = getTabUrl()?.hostname;
    return topURLString || null;
  }
  function matchHostname(hostname, exceptionDomain) {
    return hostname === exceptionDomain || hostname.endsWith(`.${exceptionDomain}`);
  }
  var lineTest = /(\()?(https?:[^)]+):[0-9]+:[0-9]+(\))?/;
  function getStackTraceUrls(stack) {
    const urls = new Set2();
    try {
      const errorLines = stack.split("\n");
      for (const line of errorLines) {
        const res = line.match(lineTest);
        if (res) {
          urls.add(new URL(res[2], location.href));
        }
      }
    } catch (e) {
    }
    return urls;
  }
  function getStackTraceOrigins(stack) {
    const urls = getStackTraceUrls(stack);
    const origins = new Set2();
    for (const url of urls) {
      origins.add(url.hostname);
    }
    return origins;
  }
  function shouldExemptMethod(type) {
    if (!(type in exemptionLists) || exemptionLists[type].length === 0) {
      return false;
    }
    const stack = getStack();
    const errorFiles = getStackTraceUrls(stack);
    for (const path of errorFiles) {
      if (shouldExemptUrl(type, path.href)) {
        return true;
      }
    }
    return false;
  }
  function iterateDataKey(key, callback) {
    let item = key.charCodeAt(0);
    for (const i in key) {
      let byte = key.charCodeAt(i);
      for (let j2 = 8; j2 >= 0; j2--) {
        const res = callback(item, byte);
        if (res === null) {
          return;
        }
        item = nextRandom(item);
        byte = byte >> 1;
      }
    }
  }
  function isFeatureBroken(args, feature) {
    return isPlatformSpecificFeature(feature) ? !args.site.enabledFeatures.includes(feature) : args.site.isBroken || args.site.allowlisted || !args.site.enabledFeatures.includes(feature);
  }
  function camelcase(dashCaseText) {
    return dashCaseText.replace(/-(.)/g, (_2, letter) => {
      return letter.toUpperCase();
    });
  }
  function isAppleSilicon() {
    const canvas = document.createElement("canvas");
    const gl = canvas.getContext("webgl");
    return gl.getSupportedExtensions().indexOf("WEBGL_compressed_texture_etc") !== -1;
  }
  function processAttrByCriteria(configSetting) {
    let bestOption;
    for (const item of configSetting) {
      if (item.criteria) {
        if (item.criteria.arch === "AppleSilicon" && isAppleSilicon()) {
          bestOption = item;
          break;
        }
      } else {
        bestOption = item;
      }
    }
    return bestOption;
  }
  var functionMap = {
    /** Useful for debugging APIs in the wild, shouldn't be used */
    debug: (...args) => {
      console.log("debugger", ...args);
      debugger;
    },
    noop: () => {
    }
  };
  function processAttr(configSetting, defaultValue) {
    if (configSetting === void 0) {
      return defaultValue;
    }
    const configSettingType = typeof configSetting;
    switch (configSettingType) {
      case "object":
        if (Array.isArray(configSetting)) {
          configSetting = processAttrByCriteria(configSetting);
          if (configSetting === void 0) {
            return defaultValue;
          }
        }
        if (!configSetting.type) {
          return defaultValue;
        }
        if (configSetting.type === "function") {
          if (configSetting.functionName && functionMap[configSetting.functionName]) {
            return functionMap[configSetting.functionName];
          }
        }
        if (configSetting.type === "undefined") {
          return void 0;
        }
        return configSetting.value;
      default:
        return defaultValue;
    }
  }
  function getStack() {
    return new Error3().stack;
  }
  function debugSerialize(argsArray) {
    const maxSerializedSize = 1e3;
    const serializedArgs = argsArray.map((arg) => {
      try {
        const serializableOut = JSON.stringify(arg);
        if (serializableOut.length > maxSerializedSize) {
          return `<truncated, length: ${serializableOut.length}, value: ${serializableOut.substring(0, maxSerializedSize)}...>`;
        }
        return serializableOut;
      } catch (e) {
        return "<unserializable>";
      }
    });
    return JSON.stringify(serializedArgs);
  }
  var DDGProxy = class {
    /**
     * @param {import('./content-feature').default} feature
     * @param {P} objectScope
     * @param {string} property
     * @param {ProxyObject<P>} proxyObject
     */
    constructor(feature, objectScope, property, proxyObject) {
      this.objectScope = objectScope;
      this.property = property;
      this.feature = feature;
      this.featureName = feature.name;
      this.camelFeatureName = camelcase(this.featureName);
      const outputHandler = (...args) => {
        this.feature.addDebugFlag();
        const isExempt = shouldExemptMethod(this.camelFeatureName);
        if (debug) {
          postDebugMessage(this.camelFeatureName, {
            isProxy: true,
            action: isExempt ? "ignore" : "restrict",
            kind: this.property,
            documentUrl: document.location.href,
            stack: getStack(),
            args: debugSerialize(args[2])
          });
        }
        if (isExempt) {
          return DDGReflect.apply(args[0], args[1], args[2]);
        }
        return proxyObject.apply(...args);
      };
      const getMethod = (target, prop, receiver) => {
        this.feature.addDebugFlag();
        if (prop === "toString") {
          const method = Reflect.get(target, prop, receiver).bind(target);
          Object.defineProperty(method, "toString", {
            value: String.toString.bind(String.toString),
            enumerable: false
          });
          return method;
        }
        return DDGReflect.get(target, prop, receiver);
      };
      this._native = objectScope[property];
      const handler = {};
      handler.apply = outputHandler;
      handler.get = getMethod;
      this.internal = new globalObj.Proxy(objectScope[property], handler);
    }
    // Actually apply the proxy to the native property
    overload() {
      this.objectScope[this.property] = this.internal;
    }
    overloadDescriptor() {
      this.feature.defineProperty(this.objectScope, this.property, {
        value: this.internal,
        writable: true,
        enumerable: true,
        configurable: true
      });
    }
  };
  var maxCounter = /* @__PURE__ */ new Map();
  function numberOfTimesDebugged(feature) {
    if (!maxCounter.has(feature)) {
      maxCounter.set(feature, 1);
    } else {
      maxCounter.set(feature, maxCounter.get(feature) + 1);
    }
    return maxCounter.get(feature);
  }
  var DEBUG_MAX_TIMES = 5e3;
  function postDebugMessage(feature, message, allowNonDebug = false) {
    if (!debug && !allowNonDebug) {
      return;
    }
    if (numberOfTimesDebugged(feature) > DEBUG_MAX_TIMES) {
      return;
    }
    if (message.stack) {
      const scriptOrigins = [...getStackTraceOrigins(message.stack)];
      message.scriptOrigins = scriptOrigins;
    }
    globalObj.postMessage({
      action: feature,
      message
    });
  }
  var DDGPromise = globalObj.Promise;
  var DDGReflect = globalObj.Reflect;
  function isUnprotectedDomain(topLevelHostname, featureList) {
    let unprotectedDomain = false;
    if (!topLevelHostname) {
      return false;
    }
    const domainParts = topLevelHostname.split(".");
    while (domainParts.length > 1 && !unprotectedDomain) {
      const partialDomain = domainParts.join(".");
      unprotectedDomain = featureList.filter((domain) => domain.domain === partialDomain).length > 0;
      domainParts.shift();
    }
    return unprotectedDomain;
  }
  function computeLimitedSiteObject() {
    const tabURL = getTabUrl();
    return {
      domain: tabURL?.hostname || null,
      url: tabURL?.href || null
    };
  }
  function parseVersionString(versionString) {
    return versionString.split(".").map(Number);
  }
  function satisfiesMinVersion(minVersionString, applicationVersionString) {
    const minVersions = parseVersionString(minVersionString);
    const currentVersions = parseVersionString(applicationVersionString);
    const maxLength = Math.max(minVersions.length, currentVersions.length);
    for (let i = 0; i < maxLength; i++) {
      const minNumberPart = minVersions[i] || 0;
      const currentVersionPart = currentVersions[i] || 0;
      if (currentVersionPart > minNumberPart) {
        return true;
      }
      if (currentVersionPart < minNumberPart) {
        return false;
      }
    }
    return true;
  }
  function isSupportedVersion(minSupportedVersion, currentVersion) {
    if (typeof currentVersion === "string" && typeof minSupportedVersion === "string") {
      if (satisfiesMinVersion(minSupportedVersion, currentVersion)) {
        return true;
      }
    } else if (typeof currentVersion === "number" && typeof minSupportedVersion === "number") {
      if (minSupportedVersion <= currentVersion) {
        return true;
      }
    }
    return false;
  }
  function computeEnabledFeatures(data, topLevelHostname, platformVersion, platformSpecificFeatures2 = []) {
    const remoteFeatureNames = Object.keys(data.features);
    const platformSpecificFeaturesNotInRemoteConfig = platformSpecificFeatures2.filter(
      (featureName) => !remoteFeatureNames.includes(featureName)
    );
    const enabledFeatures = remoteFeatureNames.filter((featureName) => {
      const feature = data.features[featureName];
      if (feature.minSupportedVersion && platformVersion) {
        if (!isSupportedVersion(feature.minSupportedVersion, platformVersion)) {
          return false;
        }
      }
      return feature.state === "enabled" && !isUnprotectedDomain(topLevelHostname, feature.exceptions);
    }).concat(platformSpecificFeaturesNotInRemoteConfig);
    return enabledFeatures;
  }
  function parseFeatureSettings(data, enabledFeatures) {
    const featureSettings = {};
    const remoteFeatureNames = Object.keys(data.features);
    remoteFeatureNames.forEach((featureName) => {
      if (!enabledFeatures.includes(featureName)) {
        return;
      }
      featureSettings[featureName] = data.features[featureName].settings;
    });
    return featureSettings;
  }
  function isGloballyDisabled(args) {
    return args.site.allowlisted || args.site.isBroken;
  }
  var platformSpecificFeatures = ["windowsPermissionUsage", "messageBridge", "favicon"];
  function isPlatformSpecificFeature(featureName) {
    return platformSpecificFeatures.includes(featureName);
  }
  function createCustomEvent(eventName, eventDetail) {
    return new OriginalCustomEvent(eventName, eventDetail);
  }
  function legacySendMessage(messageType, options) {
    return originalWindowDispatchEvent && originalWindowDispatchEvent(
      createCustomEvent("sendMessageProxy" + messageSecret, { detail: JSON.stringify({ messageType, options }) })
    );
  }

  // src/features.js
  var baseFeatures = (
    /** @type {const} */
    [
      "fingerprintingAudio",
      "fingerprintingBattery",
      "fingerprintingCanvas",
      "googleRejected",
      "gpc",
      "fingerprintingHardware",
      "referrer",
      "fingerprintingScreenSize",
      "fingerprintingTemporaryStorage",
      "navigatorInterface",
      "elementHiding",
      "exceptionHandler",
      "apiManipulation"
    ]
  );
  var otherFeatures = (
    /** @type {const} */
    [
      "clickToLoad",
      "cookie",
      "messageBridge",
      "duckPlayer",
      "duckPlayerNative",
      "harmfulApis",
      "webCompat",
      "windowsPermissionUsage",
      "brokerProtection",
      "performanceMetrics",
      "breakageReporting",
      "autofillPasswordImport",
      "favicon",
      "scriptlets"
    ]
  );
  var platformSupport = {
    apple: ["webCompat", "duckPlayerNative", "scriptlets", ...baseFeatures],
    "apple-isolated": [
      "duckPlayer",
      "duckPlayerNative",
      "brokerProtection",
      "performanceMetrics",
      "clickToLoad",
      "messageBridge",
      "favicon"
    ],
    android: [...baseFeatures, "webCompat", "breakageReporting", "duckPlayer", "messageBridge"],
    "android-broker-protection": ["brokerProtection"],
    "android-autofill-password-import": ["autofillPasswordImport"],
    windows: [
      "cookie",
      ...baseFeatures,
      "windowsPermissionUsage",
      "duckPlayer",
      "brokerProtection",
      "breakageReporting",
      "messageBridge",
      "webCompat"
    ],
    firefox: ["cookie", ...baseFeatures, "clickToLoad"],
    chrome: ["cookie", ...baseFeatures, "clickToLoad"],
    "chrome-mv3": ["cookie", ...baseFeatures, "clickToLoad"],
    integration: [...baseFeatures, ...otherFeatures]
  };

  // src/performance.js
  var PerformanceMonitor = class {
    constructor() {
      this.marks = [];
    }
    /**
     * Create performance marker
     * @param {string} name
     * @returns {PerformanceMark}
     */
    mark(name) {
      const mark = new PerformanceMark(name);
      this.marks.push(mark);
      return mark;
    }
    /**
     * Measure all performance markers
     */
    measureAll() {
      this.marks.forEach((mark) => {
        mark.measure();
      });
    }
  };
  var PerformanceMark = class {
    /**
     * @param {string} name
     */
    constructor(name) {
      this.name = name;
      performance.mark(this.name + "Start");
    }
    end() {
      performance.mark(this.name + "End");
    }
    measure() {
      performance.measure(this.name, this.name + "Start", this.name + "End");
    }
  };

  // src/cookie.js
  var Cookie = class {
    constructor(cookieString) {
      this.parts = cookieString.split(";");
      this.parse();
    }
    parse() {
      const EXTRACT_ATTRIBUTES = /* @__PURE__ */ new Set(["max-age", "expires", "domain"]);
      this.attrIdx = {};
      this.parts.forEach((part, index) => {
        const kv = part.split("=", 1);
        const attribute = kv[0].trim();
        const value = part.slice(kv[0].length + 1);
        if (index === 0) {
          this.name = attribute;
          this.value = value;
        } else if (EXTRACT_ATTRIBUTES.has(attribute.toLowerCase())) {
          this[attribute.toLowerCase()] = value;
          this.attrIdx[attribute.toLowerCase()] = index;
        }
      });
    }
    getExpiry() {
      if (!this.maxAge && !this.expires) {
        return NaN;
      }
      const expiry = this.maxAge ? parseInt(this.maxAge) : (
        // @ts-expect-error expires is not defined in the type definition
        (new Date(this.expires) - /* @__PURE__ */ new Date()) / 1e3
      );
      return expiry;
    }
    get maxAge() {
      return this["max-age"];
    }
    set maxAge(value) {
      if (this.attrIdx["max-age"] > 0) {
        this.parts.splice(this.attrIdx["max-age"], 1, `max-age=${value}`);
      } else {
        this.parts.push(`max-age=${value}`);
      }
      this.parse();
    }
    toString() {
      return this.parts.join(";");
    }
  };

  // src/wrapper-utils.js
  var ddgShimMark = Symbol("ddgShimMark");
  function defineProperty(object, propertyName, descriptor) {
    objectDefineProperty(object, propertyName, descriptor);
  }
  function wrapToString(newFn, origFn, mockValue) {
    if (typeof newFn !== "function" || typeof origFn !== "function") {
      return newFn;
    }
    return new Proxy(newFn, { get: toStringGetTrap(origFn, mockValue) });
  }
  function toStringGetTrap(targetFn, mockValue) {
    return function get(target, prop, receiver) {
      if (prop === "toString") {
        const origToString = Reflect.get(targetFn, "toString", targetFn);
        const toStringProxy = new Proxy(origToString, {
          apply(target2, thisArg, argumentsList) {
            if (thisArg === receiver) {
              if (mockValue) {
                return mockValue;
              }
              return Reflect.apply(target2, targetFn, argumentsList);
            } else {
              return Reflect.apply(target2, thisArg, argumentsList);
            }
          },
          get(target2, prop2, receiver2) {
            if (prop2 === "toString") {
              const origToStringToString = Reflect.get(origToString, "toString", origToString);
              const toStringToStringProxy = new Proxy(origToStringToString, {
                apply(target3, thisArg, argumentsList) {
                  if (thisArg === toStringProxy) {
                    return Reflect.apply(target3, origToString, argumentsList);
                  } else {
                    return Reflect.apply(target3, thisArg, argumentsList);
                  }
                }
              });
              return toStringToStringProxy;
            }
            return Reflect.get(target2, prop2, receiver2);
          }
        });
        return toStringProxy;
      }
      return Reflect.get(target, prop, receiver);
    };
  }
  function wrapProperty(object, propertyName, descriptor, definePropertyFn) {
    if (!object) {
      return;
    }
    const origDescriptor = getOwnPropertyDescriptor(object, propertyName);
    if (!origDescriptor) {
      return;
    }
    if ("value" in origDescriptor && "value" in descriptor || "get" in origDescriptor && "get" in descriptor || "set" in origDescriptor && "set" in descriptor) {
      definePropertyFn(object, propertyName, {
        ...origDescriptor,
        ...descriptor
      });
      return origDescriptor;
    } else {
      throw new Error(`Property descriptor for ${propertyName} may only include the following keys: ${objectKeys(origDescriptor)}`);
    }
  }
  function wrapMethod(object, propertyName, wrapperFn, definePropertyFn) {
    if (!object) {
      return;
    }
    const origDescriptor = getOwnPropertyDescriptor(object, propertyName);
    if (!origDescriptor) {
      return;
    }
    const origFn = origDescriptor.value;
    if (!origFn || typeof origFn !== "function") {
      throw new Error(`Property ${propertyName} does not look like a method`);
    }
    const newFn = wrapToString(function() {
      return wrapperFn.call(this, origFn, ...arguments);
    }, origFn);
    definePropertyFn(object, propertyName, {
      ...origDescriptor,
      value: newFn
    });
    return origDescriptor;
  }
  function shimInterface(interfaceName, ImplClass, options, definePropertyFn, injectName) {
    if (injectName === "integration") {
      if (!globalThis.origInterfaceDescriptors) globalThis.origInterfaceDescriptors = {};
      const descriptor = Object.getOwnPropertyDescriptor(globalThis, interfaceName);
      globalThis.origInterfaceDescriptors[interfaceName] = descriptor;
      globalThis.ddgShimMark = ddgShimMark;
    }
    const defaultOptions = {
      allowConstructorCall: false,
      disallowConstructor: false,
      constructorErrorMessage: "Illegal constructor",
      wrapToString: true
    };
    const fullOptions = {
      interfaceDescriptorOptions: { writable: true, enumerable: false, configurable: true, value: ImplClass },
      ...defaultOptions,
      ...options
    };
    const proxyHandler = {};
    if (fullOptions.allowConstructorCall) {
      proxyHandler.apply = function(target, _thisArg, argumentsList) {
        return Reflect.construct(target, argumentsList, target);
      };
    }
    if (fullOptions.disallowConstructor) {
      proxyHandler.construct = function() {
        throw new TypeError(fullOptions.constructorErrorMessage);
      };
    }
    if (fullOptions.wrapToString) {
      for (const [prop, descriptor] of objectEntries(getOwnPropertyDescriptors(ImplClass.prototype))) {
        if (prop !== "constructor" && descriptor.writable && typeof descriptor.value === "function") {
          ImplClass.prototype[prop] = new Proxy(descriptor.value, {
            get: toStringGetTrap(descriptor.value, `function ${prop}() { [native code] }`)
          });
        }
      }
      Object.assign(proxyHandler, {
        get: toStringGetTrap(ImplClass, `function ${interfaceName}() { [native code] }`)
      });
    }
    const Interface = new Proxy(ImplClass, proxyHandler);
    if (ImplClass.prototype?.constructor === ImplClass) {
      const descriptor = getOwnPropertyDescriptor(ImplClass.prototype, "constructor");
      if (descriptor.writable) {
        ImplClass.prototype.constructor = Interface;
      }
    }
    if (injectName === "integration") {
      definePropertyFn(ImplClass, ddgShimMark, {
        value: true,
        configurable: false,
        enumerable: false,
        writable: false
      });
    }
    definePropertyFn(ImplClass, "name", {
      value: interfaceName,
      configurable: true,
      enumerable: false,
      writable: false
    });
    definePropertyFn(globalThis, interfaceName, { ...fullOptions.interfaceDescriptorOptions, value: Interface });
  }
  function shimProperty(baseObject, propertyName, implInstance, readOnly, definePropertyFn, injectName) {
    const ImplClass = implInstance.constructor;
    if (injectName === "integration") {
      if (!globalThis.origPropDescriptors) globalThis.origPropDescriptors = [];
      const descriptor2 = Object.getOwnPropertyDescriptor(baseObject, propertyName);
      globalThis.origPropDescriptors.push([baseObject, propertyName, descriptor2]);
      globalThis.ddgShimMark = ddgShimMark;
      if (ImplClass[ddgShimMark] !== true) {
        throw new TypeError("implInstance must be an instance of a shimmed class");
      }
    }
    const proxiedInstance = new Proxy(implInstance, {
      get: toStringGetTrap(implInstance, `[object ${ImplClass.name}]`)
    });
    let descriptor;
    if (readOnly) {
      const getter = function get() {
        return proxiedInstance;
      };
      const proxiedGetter = new Proxy(getter, {
        get: toStringGetTrap(getter, `function get ${propertyName}() { [native code] }`)
      });
      descriptor = {
        configurable: true,
        enumerable: true,
        get: proxiedGetter
      };
    } else {
      descriptor = {
        configurable: true,
        enumerable: true,
        writable: true,
        value: proxiedInstance
      };
    }
    definePropertyFn(baseObject, propertyName, descriptor);
  }

  // ../messaging/lib/windows.js
  var WindowsMessagingTransport = class {
    /**
     * @param {WindowsMessagingConfig} config
     * @param {import('../index.js').MessagingContext} messagingContext
     * @internal
     */
    constructor(config2, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config2;
      this.globals = {
        window,
        JSONparse: window.JSON.parse,
        JSONstringify: window.JSON.stringify,
        Promise: window.Promise,
        Error: window.Error,
        String: window.String
      };
      for (const [methodName, fn] of Object.entries(this.config.methods)) {
        if (typeof fn !== "function") {
          throw new Error("cannot create WindowsMessagingTransport, missing the method: " + methodName);
        }
      }
    }
    /**
     * @param {import('../index.js').NotificationMessage} msg
     */
    notify(msg) {
      const data = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
      const notification = WindowsNotification.fromNotification(msg, data);
      this.config.methods.postMessage(notification);
    }
    /**
     * @param {import('../index.js').RequestMessage} msg
     * @param {{signal?: AbortSignal}} opts
     * @return {Promise<any>}
     */
    request(msg, opts = {}) {
      const data = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
      const outgoing = WindowsRequestMessage.fromRequest(msg, data);
      this.config.methods.postMessage(outgoing);
      const comparator = (eventData) => {
        return eventData.featureName === msg.featureName && eventData.context === msg.context && eventData.id === msg.id;
      };
      function isMessageResponse(data2) {
        if ("result" in data2) return true;
        if ("error" in data2) return true;
        return false;
      }
      return new this.globals.Promise((resolve, reject) => {
        try {
          this._subscribe(comparator, opts, (value, unsubscribe) => {
            unsubscribe();
            if (!isMessageResponse(value)) {
              console.warn("unknown response type", value);
              return reject(new this.globals.Error("unknown response"));
            }
            if (value.result) {
              return resolve(value.result);
            }
            const message = this.globals.String(value.error?.message || "unknown error");
            reject(new this.globals.Error(message));
          });
        } catch (e) {
          reject(e);
        }
      });
    }
    /**
     * @param {import('../index.js').Subscription} msg
     * @param {(value: unknown | undefined) => void} callback
     */
    subscribe(msg, callback) {
      const comparator = (eventData) => {
        return eventData.featureName === msg.featureName && eventData.context === msg.context && eventData.subscriptionName === msg.subscriptionName;
      };
      const cb = (eventData) => {
        return callback(eventData.params);
      };
      return this._subscribe(comparator, {}, cb);
    }
    /**
     * @typedef {import('../index.js').MessageResponse | import('../index.js').SubscriptionEvent} Incoming
     */
    /**
     * @param {(eventData: any) => boolean} comparator
     * @param {{signal?: AbortSignal}} options
     * @param {(value: Incoming, unsubscribe: (()=>void)) => void} callback
     * @internal
     */
    _subscribe(comparator, options, callback) {
      if (options?.signal?.aborted) {
        throw new DOMException("Aborted", "AbortError");
      }
      let teardown;
      const idHandler = (event) => {
        if (this.messagingContext.env === "production") {
          if (event.origin !== null && event.origin !== void 0) {
            console.warn("ignoring because evt.origin is not `null` or `undefined`");
            return;
          }
        }
        if (!event.data) {
          console.warn("data absent from message");
          return;
        }
        if (comparator(event.data)) {
          if (!teardown) throw new Error("unreachable");
          callback(event.data, teardown);
        }
      };
      const abortHandler = () => {
        teardown?.();
        throw new DOMException("Aborted", "AbortError");
      };
      this.config.methods.addEventListener("message", idHandler);
      options?.signal?.addEventListener("abort", abortHandler);
      teardown = () => {
        this.config.methods.removeEventListener("message", idHandler);
        options?.signal?.removeEventListener("abort", abortHandler);
      };
      return () => {
        teardown?.();
      };
    }
  };
  var WindowsMessagingConfig = class {
    /**
     * @param {object} params
     * @param {WindowsInteropMethods} params.methods
     * @internal
     */
    constructor(params) {
      this.methods = params.methods;
      this.platform = "windows";
    }
  };
  var WindowsNotification = class {
    /**
     * @param {object} params
     * @param {string} params.Feature
     * @param {string} params.SubFeatureName
     * @param {string} params.Name
     * @param {Record<string, any>} [params.Data]
     * @internal
     */
    constructor(params) {
      this.Feature = params.Feature;
      this.SubFeatureName = params.SubFeatureName;
      this.Name = params.Name;
      this.Data = params.Data;
    }
    /**
     * Helper to convert a {@link NotificationMessage} to a format that Windows can support
     * @param {NotificationMessage} notification
     * @returns {WindowsNotification}
     */
    static fromNotification(notification, data) {
      const output = {
        Data: data,
        Feature: notification.context,
        SubFeatureName: notification.featureName,
        Name: notification.method
      };
      return output;
    }
  };
  var WindowsRequestMessage = class {
    /**
     * @param {object} params
     * @param {string} params.Feature
     * @param {string} params.SubFeatureName
     * @param {string} params.Name
     * @param {Record<string, any>} [params.Data]
     * @param {string} [params.Id]
     * @internal
     */
    constructor(params) {
      this.Feature = params.Feature;
      this.SubFeatureName = params.SubFeatureName;
      this.Name = params.Name;
      this.Data = params.Data;
      this.Id = params.Id;
    }
    /**
     * Helper to convert a {@link RequestMessage} to a format that Windows can support
     * @param {RequestMessage} msg
     * @param {Record<string, any>} data
     * @returns {WindowsRequestMessage}
     */
    static fromRequest(msg, data) {
      const output = {
        Data: data,
        Feature: msg.context,
        SubFeatureName: msg.featureName,
        Name: msg.method,
        Id: msg.id
      };
      return output;
    }
  };

  // ../messaging/schema.js
  var RequestMessage = class {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     * @internal
     */
    constructor(params) {
      this.context = params.context;
      this.featureName = params.featureName;
      this.method = params.method;
      this.id = params.id;
      this.params = params.params;
    }
  };
  var NotificationMessage = class {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {Record<string, any>} [params.params]
     * @internal
     */
    constructor(params) {
      this.context = params.context;
      this.featureName = params.featureName;
      this.method = params.method;
      this.params = params.params;
    }
  };
  var Subscription = class {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @internal
     */
    constructor(params) {
      this.context = params.context;
      this.featureName = params.featureName;
      this.subscriptionName = params.subscriptionName;
    }
  };
  function isResponseFor(request, data) {
    if ("result" in data) {
      return data.featureName === request.featureName && data.context === request.context && data.id === request.id;
    }
    if ("error" in data) {
      if ("message" in data.error) {
        return true;
      }
    }
    return false;
  }
  function isSubscriptionEventFor(sub, data) {
    if ("subscriptionName" in data) {
      return data.featureName === sub.featureName && data.context === sub.context && data.subscriptionName === sub.subscriptionName;
    }
    return false;
  }

  // ../messaging/lib/webkit.js
  var WebkitMessagingTransport = class {
    /**
     * @param {WebkitMessagingConfig} config
     * @param {import('../index.js').MessagingContext} messagingContext
     */
    constructor(config2, messagingContext) {
      /**
       * @type {{name: string, length: number}}
       * @internal
       */
      __publicField(this, "algoObj", {
        name: "AES-GCM",
        length: 256
      });
      this.messagingContext = messagingContext;
      this.config = config2;
      this.globals = captureGlobals();
      if (!this.config.hasModernWebkitAPI) {
        this.captureWebkitHandlers(this.config.webkitMessageHandlerNames);
      }
    }
    /**
     * Sends message to the webkit layer (fire and forget)
     * @param {String} handler
     * @param {*} data
     * @internal
     */
    wkSend(handler, data = {}) {
      if (!(handler in this.globals.window.webkit.messageHandlers)) {
        throw new MissingHandler(`Missing webkit handler: '${handler}'`, handler);
      }
      if (!this.config.hasModernWebkitAPI) {
        const outgoing = {
          ...data,
          messageHandling: {
            ...data.messageHandling,
            secret: this.config.secret
          }
        };
        if (!(handler in this.globals.capturedWebkitHandlers)) {
          throw new MissingHandler(`cannot continue, method ${handler} not captured on macos < 11`, handler);
        } else {
          return this.globals.capturedWebkitHandlers[handler](outgoing);
        }
      }
      return this.globals.window.webkit.messageHandlers[handler].postMessage?.(data);
    }
    /**
     * Sends message to the webkit layer and waits for the specified response
     * @param {String} handler
     * @param {import('../index.js').RequestMessage} data
     * @returns {Promise<*>}
     * @internal
     */
    async wkSendAndWait(handler, data) {
      if (this.config.hasModernWebkitAPI) {
        const response = await this.wkSend(handler, data);
        return this.globals.JSONparse(response || "{}");
      }
      try {
        const randMethodName = this.createRandMethodName();
        const key = await this.createRandKey();
        const iv = this.createRandIv();
        const { ciphertext, tag } = await new this.globals.Promise((resolve) => {
          this.generateRandomMethod(randMethodName, resolve);
          data.messageHandling = new SecureMessagingParams({
            methodName: randMethodName,
            secret: this.config.secret,
            key: this.globals.Arrayfrom(key),
            iv: this.globals.Arrayfrom(iv)
          });
          this.wkSend(handler, data);
        });
        const cipher = new this.globals.Uint8Array([...ciphertext, ...tag]);
        const decrypted = await this.decrypt(cipher, key, iv);
        return this.globals.JSONparse(decrypted || "{}");
      } catch (e) {
        if (e instanceof MissingHandler) {
          throw e;
        } else {
          console.error("decryption failed", e);
          console.error(e);
          return { error: e };
        }
      }
    }
    /**
     * @param {import('../index.js').NotificationMessage} msg
     */
    notify(msg) {
      this.wkSend(msg.context, msg);
    }
    /**
     * @param {import('../index.js').RequestMessage} msg
     */
    async request(msg) {
      const data = await this.wkSendAndWait(msg.context, msg);
      if (isResponseFor(msg, data)) {
        if (data.result) {
          return data.result || {};
        }
        if (data.error) {
          throw new Error(data.error.message);
        }
      }
      throw new Error("an unknown error occurred");
    }
    /**
     * Generate a random method name and adds it to the global scope
     * The native layer will use this method to send the response
     * @param {string | number} randomMethodName
     * @param {Function} callback
     * @internal
     */
    generateRandomMethod(randomMethodName, callback) {
      this.globals.ObjectDefineProperty(this.globals.window, randomMethodName, {
        enumerable: false,
        // configurable, To allow for deletion later
        configurable: true,
        writable: false,
        /**
         * @param {any[]} args
         */
        value: (...args) => {
          callback(...args);
          delete this.globals.window[randomMethodName];
        }
      });
    }
    /**
     * @internal
     * @return {string}
     */
    randomString() {
      return "" + this.globals.getRandomValues(new this.globals.Uint32Array(1))[0];
    }
    /**
     * @internal
     * @return {string}
     */
    createRandMethodName() {
      return "_" + this.randomString();
    }
    /**
     * @returns {Promise<Uint8Array>}
     * @internal
     */
    async createRandKey() {
      const key = await this.globals.generateKey(this.algoObj, true, ["encrypt", "decrypt"]);
      const exportedKey = await this.globals.exportKey("raw", key);
      return new this.globals.Uint8Array(exportedKey);
    }
    /**
     * @returns {Uint8Array}
     * @internal
     */
    createRandIv() {
      return this.globals.getRandomValues(new this.globals.Uint8Array(12));
    }
    /**
     * @param {BufferSource} ciphertext
     * @param {BufferSource} key
     * @param {Uint8Array} iv
     * @returns {Promise<string>}
     * @internal
     */
    async decrypt(ciphertext, key, iv) {
      const cryptoKey = await this.globals.importKey("raw", key, "AES-GCM", false, ["decrypt"]);
      const algo = {
        name: "AES-GCM",
        iv
      };
      const decrypted = await this.globals.decrypt(algo, cryptoKey, ciphertext);
      const dec = new this.globals.TextDecoder();
      return dec.decode(decrypted);
    }
    /**
     * When required (such as on macos 10.x), capture the `postMessage` method on
     * each webkit messageHandler
     *
     * @param {string[]} handlerNames
     */
    captureWebkitHandlers(handlerNames) {
      const handlers = window.webkit.messageHandlers;
      if (!handlers) throw new MissingHandler("window.webkit.messageHandlers was absent", "all");
      for (const webkitMessageHandlerName of handlerNames) {
        if (typeof handlers[webkitMessageHandlerName]?.postMessage === "function") {
          const original = handlers[webkitMessageHandlerName];
          const bound = handlers[webkitMessageHandlerName].postMessage?.bind(original);
          this.globals.capturedWebkitHandlers[webkitMessageHandlerName] = bound;
          delete handlers[webkitMessageHandlerName].postMessage;
        }
      }
    }
    /**
     * @param {import('../index.js').Subscription} msg
     * @param {(value: unknown) => void} callback
     */
    subscribe(msg, callback) {
      if (msg.subscriptionName in this.globals.window) {
        throw new this.globals.Error(`A subscription with the name ${msg.subscriptionName} already exists`);
      }
      this.globals.ObjectDefineProperty(this.globals.window, msg.subscriptionName, {
        enumerable: false,
        configurable: true,
        writable: false,
        value: (data) => {
          if (data && isSubscriptionEventFor(msg, data)) {
            callback(data.params);
          } else {
            console.warn("Received a message that did not match the subscription", data);
          }
        }
      });
      return () => {
        this.globals.ReflectDeleteProperty(this.globals.window, msg.subscriptionName);
      };
    }
  };
  var WebkitMessagingConfig = class {
    /**
     * @param {object} params
     * @param {boolean} params.hasModernWebkitAPI
     * @param {string[]} params.webkitMessageHandlerNames
     * @param {string} params.secret
     * @internal
     */
    constructor(params) {
      this.hasModernWebkitAPI = params.hasModernWebkitAPI;
      this.webkitMessageHandlerNames = params.webkitMessageHandlerNames;
      this.secret = params.secret;
    }
  };
  var SecureMessagingParams = class {
    /**
     * @param {object} params
     * @param {string} params.methodName
     * @param {string} params.secret
     * @param {number[]} params.key
     * @param {number[]} params.iv
     */
    constructor(params) {
      this.methodName = params.methodName;
      this.secret = params.secret;
      this.key = params.key;
      this.iv = params.iv;
    }
  };
  function captureGlobals() {
    const globals = {
      window,
      getRandomValues: window.crypto.getRandomValues.bind(window.crypto),
      TextEncoder,
      TextDecoder,
      Uint8Array,
      Uint16Array,
      Uint32Array,
      JSONstringify: window.JSON.stringify,
      JSONparse: window.JSON.parse,
      Arrayfrom: window.Array.from,
      Promise: window.Promise,
      Error: window.Error,
      ReflectDeleteProperty: window.Reflect.deleteProperty.bind(window.Reflect),
      ObjectDefineProperty: window.Object.defineProperty,
      addEventListener: window.addEventListener.bind(window),
      /** @type {Record<string, any>} */
      capturedWebkitHandlers: {}
    };
    if (isSecureContext) {
      globals.generateKey = window.crypto.subtle.generateKey.bind(window.crypto.subtle);
      globals.exportKey = window.crypto.subtle.exportKey.bind(window.crypto.subtle);
      globals.importKey = window.crypto.subtle.importKey.bind(window.crypto.subtle);
      globals.encrypt = window.crypto.subtle.encrypt.bind(window.crypto.subtle);
      globals.decrypt = window.crypto.subtle.decrypt.bind(window.crypto.subtle);
    }
    return globals;
  }

  // ../messaging/lib/android.js
  var AndroidMessagingTransport = class {
    /**
     * @param {AndroidMessagingConfig} config
     * @param {MessagingContext} messagingContext
     * @internal
     */
    constructor(config2, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config2;
    }
    /**
     * @param {NotificationMessage} msg
     */
    notify(msg) {
      try {
        this.config.sendMessageThrows?.(JSON.stringify(msg));
      } catch (e) {
        console.error(".notify failed", e);
      }
    }
    /**
     * @param {RequestMessage} msg
     * @return {Promise<any>}
     */
    request(msg) {
      return new Promise((resolve, reject) => {
        const unsub = this.config.subscribe(msg.id, handler);
        try {
          this.config.sendMessageThrows?.(JSON.stringify(msg));
        } catch (e) {
          unsub();
          reject(new Error("request failed to send: " + e.message || "unknown error"));
        }
        function handler(data) {
          if (isResponseFor(msg, data)) {
            if (data.result) {
              resolve(data.result || {});
              return unsub();
            }
            if (data.error) {
              reject(new Error(data.error.message));
              return unsub();
            }
            unsub();
            throw new Error("unreachable: must have `result` or `error` key by this point");
          }
        }
      });
    }
    /**
     * @param {Subscription} msg
     * @param {(value: unknown | undefined) => void} callback
     */
    subscribe(msg, callback) {
      const unsub = this.config.subscribe(msg.subscriptionName, (data) => {
        if (isSubscriptionEventFor(msg, data)) {
          callback(data.params || {});
        }
      });
      return () => {
        unsub();
      };
    }
  };
  var AndroidMessagingConfig = class {
    /**
     * @param {object} params
     * @param {Record<string, any>} params.target
     * @param {boolean} params.debug
     * @param {string} params.messageSecret - a secret to ensure that messages are only
     * processed by the correct handler
     * @param {string} params.javascriptInterface - the name of the javascript interface
     * registered on the native side
     * @param {string} params.messageCallback - the name of the callback that the native
     * side will use to send messages back to the javascript side
     */
    constructor(params) {
      /** @type {(json: string, secret: string) => void} */
      __publicField(this, "_capturedHandler");
      this.target = params.target;
      this.debug = params.debug;
      this.javascriptInterface = params.javascriptInterface;
      this.messageSecret = params.messageSecret;
      this.messageCallback = params.messageCallback;
      this.listeners = new globalThis.Map();
      this._captureGlobalHandler();
      this._assignHandlerMethod();
    }
    /**
     * The transport can call this to transmit a JSON payload along with a secret
     * to the native Android handler.
     *
     * Note: This can throw - it's up to the transport to handle the error.
     *
     * @type {(json: string) => void}
     * @throws
     * @internal
     */
    sendMessageThrows(json) {
      this._capturedHandler(json, this.messageSecret);
    }
    /**
     * A subscription on Android is just a named listener. All messages from
     * android -> are delivered through a single function, and this mapping is used
     * to route the messages to the correct listener.
     *
     * Note: Use this to implement request->response by unsubscribing after the first
     * response.
     *
     * @param {string} id
     * @param {(msg: MessageResponse | SubscriptionEvent) => void} callback
     * @returns {() => void}
     * @internal
     */
    subscribe(id, callback) {
      this.listeners.set(id, callback);
      return () => {
        this.listeners.delete(id);
      };
    }
    /**
     * Accept incoming messages and try to deliver it to a registered listener.
     *
     * This code is defensive to prevent any single handler from affecting another if
     * it throws (producer interference).
     *
     * @param {MessageResponse | SubscriptionEvent} payload
     * @internal
     */
    _dispatch(payload) {
      if (!payload) return this._log("no response");
      if ("id" in payload) {
        if (this.listeners.has(payload.id)) {
          this._tryCatch(() => this.listeners.get(payload.id)?.(payload));
        } else {
          this._log("no listeners for ", payload);
        }
      }
      if ("subscriptionName" in payload) {
        if (this.listeners.has(payload.subscriptionName)) {
          this._tryCatch(() => this.listeners.get(payload.subscriptionName)?.(payload));
        } else {
          this._log("no subscription listeners for ", payload);
        }
      }
    }
    /**
     *
     * @param {(...args: any[]) => any} fn
     * @param {string} [context]
     */
    _tryCatch(fn, context = "none") {
      try {
        return fn();
      } catch (e) {
        if (this.debug) {
          console.error("AndroidMessagingConfig error:", context);
          console.error(e);
        }
      }
    }
    /**
     * @param {...any} args
     */
    _log(...args) {
      if (this.debug) {
        console.log("AndroidMessagingConfig", ...args);
      }
    }
    /**
     * Capture the global handler and remove it from the global object.
     */
    _captureGlobalHandler() {
      const { target, javascriptInterface } = this;
      if (Object.prototype.hasOwnProperty.call(target, javascriptInterface)) {
        this._capturedHandler = target[javascriptInterface].process.bind(target[javascriptInterface]);
        delete target[javascriptInterface];
      } else {
        this._capturedHandler = () => {
          this._log("Android messaging interface not available", javascriptInterface);
        };
      }
    }
    /**
     * Assign the incoming handler method to the global object.
     * This is the method that Android will call to deliver messages.
     */
    _assignHandlerMethod() {
      const responseHandler = (providedSecret, response) => {
        if (providedSecret === this.messageSecret) {
          this._dispatch(response);
        }
      };
      Object.defineProperty(this.target, this.messageCallback, {
        value: responseHandler
      });
    }
  };

  // ../messaging/index.js
  var MessagingContext = class {
    /**
     * @param {object} params
     * @param {string} params.context
     * @param {string} params.featureName
     * @param {"production" | "development"} params.env
     * @internal
     */
    constructor(params) {
      this.context = params.context;
      this.featureName = params.featureName;
      this.env = params.env;
    }
  };
  var Messaging = class {
    /**
     * @param {MessagingContext} messagingContext
     * @param {MessagingConfig} config
     */
    constructor(messagingContext, config2) {
      this.messagingContext = messagingContext;
      this.transport = getTransport(config2, this.messagingContext);
    }
    /**
     * Send a 'fire-and-forget' message.
     * @throws {MissingHandler}
     *
     * @example
     *
     * ```ts
     * const messaging = new Messaging(config)
     * messaging.notify("foo", {bar: "baz"})
     * ```
     * @param {string} name
     * @param {Record<string, any>} [data]
     */
    notify(name, data = {}) {
      const message = new NotificationMessage({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        method: name,
        params: data
      });
      this.transport.notify(message);
    }
    /**
     * Send a request, and wait for a response
     * @throws {MissingHandler}
     *
     * @example
     * ```
     * const messaging = new Messaging(config)
     * const response = await messaging.request("foo", {bar: "baz"})
     * ```
     *
     * @param {string} name
     * @param {Record<string, any>} [data]
     * @return {Promise<any>}
     */
    request(name, data = {}) {
      const id = globalThis?.crypto?.randomUUID?.() || name + ".response";
      const message = new RequestMessage({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        method: name,
        params: data,
        id
      });
      return this.transport.request(message);
    }
    /**
     * @param {string} name
     * @param {(value: unknown) => void} callback
     * @return {() => void}
     */
    subscribe(name, callback) {
      const msg = new Subscription({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        subscriptionName: name
      });
      return this.transport.subscribe(msg, callback);
    }
  };
  var TestTransportConfig = class {
    /**
     * @param {MessagingTransport} impl
     */
    constructor(impl) {
      this.impl = impl;
    }
  };
  var TestTransport = class {
    /**
     * @param {TestTransportConfig} config
     * @param {MessagingContext} messagingContext
     */
    constructor(config2, messagingContext) {
      this.config = config2;
      this.messagingContext = messagingContext;
    }
    notify(msg) {
      return this.config.impl.notify(msg);
    }
    request(msg) {
      return this.config.impl.request(msg);
    }
    subscribe(msg, callback) {
      return this.config.impl.subscribe(msg, callback);
    }
  };
  function getTransport(config2, messagingContext) {
    if (config2 instanceof WebkitMessagingConfig) {
      return new WebkitMessagingTransport(config2, messagingContext);
    }
    if (config2 instanceof WindowsMessagingConfig) {
      return new WindowsMessagingTransport(config2, messagingContext);
    }
    if (config2 instanceof AndroidMessagingConfig) {
      return new AndroidMessagingTransport(config2, messagingContext);
    }
    if (config2 instanceof TestTransportConfig) {
      return new TestTransport(config2, messagingContext);
    }
    throw new Error("unreachable");
  }
  var MissingHandler = class extends Error {
    /**
     * @param {string} message
     * @param {string} handlerName
     */
    constructor(message, handlerName) {
      super(message);
      this.handlerName = handlerName;
    }
  };

  // src/sendmessage-transport.js
  function extensionConstructMessagingConfig() {
    const messagingTransport = new SendMessageMessagingTransport();
    return new TestTransportConfig(messagingTransport);
  }
  var SendMessageMessagingTransport = class {
    constructor() {
      /**
       * Queue of callbacks to be called with messages sent from the Platform.
       * This is used to connect requests with responses and to trigger subscriptions callbacks.
       */
      __publicField(this, "_queue", /* @__PURE__ */ new Set());
      this.globals = {
        window: globalThis,
        globalThis,
        JSONparse: globalThis.JSON.parse,
        JSONstringify: globalThis.JSON.stringify,
        Promise: globalThis.Promise,
        Error: globalThis.Error,
        String: globalThis.String
      };
    }
    /**
     * Callback for update() handler. This connects messages sent from the Platform
     * with callback functions in the _queue.
     * @param {any} response
     */
    onResponse(response) {
      this._queue.forEach((subscription) => subscription(response));
    }
    /**
     * @param {import('@duckduckgo/messaging').NotificationMessage} msg
     */
    notify(msg) {
      let params = msg.params;
      if (msg.method === "setYoutubePreviewsEnabled") {
        params = msg.params?.youtubePreviewsEnabled;
      }
      if (msg.method === "updateYouTubeCTLAddedFlag") {
        params = msg.params?.youTubeCTLAddedFlag;
      }
      legacySendMessage(msg.method, params);
    }
    /**
     * @param {import('@duckduckgo/messaging').RequestMessage} req
     * @return {Promise<any>}
     */
    request(req) {
      let comparator = (eventData) => {
        return eventData.responseMessageType === req.method;
      };
      let params = req.params;
      if (req.method === "getYouTubeVideoDetails") {
        comparator = (eventData) => {
          return eventData.responseMessageType === req.method && eventData.response && eventData.response.videoURL === req.params?.videoURL;
        };
        params = req.params?.videoURL;
      }
      legacySendMessage(req.method, params);
      return new this.globals.Promise((resolve) => {
        this._subscribe(comparator, (msgRes, unsubscribe) => {
          unsubscribe();
          return resolve(msgRes.response);
        });
      });
    }
    /**
     * @param {import('@duckduckgo/messaging').Subscription} msg
     * @param {(value: unknown | undefined) => void} callback
     */
    subscribe(msg, callback) {
      const comparator = (eventData) => {
        return eventData.messageType === msg.subscriptionName || eventData.responseMessageType === msg.subscriptionName;
      };
      const cb = (eventData) => {
        return callback(eventData.response);
      };
      return this._subscribe(comparator, cb);
    }
    /**
     * @param {(eventData: any) => boolean} comparator
     * @param {(value: any, unsubscribe: (()=>void)) => void} callback
     * @internal
     */
    _subscribe(comparator, callback) {
      let teardown;
      const idHandler = (event) => {
        if (!event) {
          console.warn("no message available");
          return;
        }
        if (comparator(event)) {
          if (!teardown) throw new this.globals.Error("unreachable");
          callback(event, teardown);
        }
      };
      this._queue.add(idHandler);
      teardown = () => {
        this._queue.delete(idHandler);
      };
      return () => {
        teardown?.();
      };
    }
  };

  // src/trackers.js
  function isTrackerOrigin(trackerLookup2, originHostname = getGlobal().document.location.hostname) {
    const parts = originHostname.split(".").reverse();
    let node = trackerLookup2;
    for (const sub of parts) {
      if (node[sub] === 1) {
        return true;
      } else if (node[sub]) {
        node = node[sub];
      } else {
        return false;
      }
    }
    return false;
  }

  // ../node_modules/immutable-json-patch/lib/esm/typeguards.js
  function isJSONArray(value) {
    return Array.isArray(value);
  }
  function isJSONObject(value) {
    return value !== null && typeof value === "object" && (value.constructor === void 0 || // for example Object.create(null)
    value.constructor.name === "Object");
  }

  // ../node_modules/immutable-json-patch/lib/esm/utils.js
  function isEqual(a2, b2) {
    return JSON.stringify(a2) === JSON.stringify(b2);
  }
  function initial(array) {
    return array.slice(0, array.length - 1);
  }
  function last(array) {
    return array[array.length - 1];
  }
  function isObjectOrArray(value) {
    return typeof value === "object" && value !== null;
  }

  // ../node_modules/immutable-json-patch/lib/esm/immutabilityHelpers.js
  function shallowClone(value) {
    if (isJSONArray(value)) {
      const copy2 = value.slice();
      Object.getOwnPropertySymbols(value).forEach((symbol) => {
        copy2[symbol] = value[symbol];
      });
      return copy2;
    } else if (isJSONObject(value)) {
      const copy2 = {
        ...value
      };
      Object.getOwnPropertySymbols(value).forEach((symbol) => {
        copy2[symbol] = value[symbol];
      });
      return copy2;
    } else {
      return value;
    }
  }
  function applyProp(object, key, value) {
    if (object[key] === value) {
      return object;
    } else {
      const updatedObject = shallowClone(object);
      updatedObject[key] = value;
      return updatedObject;
    }
  }
  function getIn(object, path) {
    let value = object;
    let i = 0;
    while (i < path.length) {
      if (isJSONObject(value)) {
        value = value[path[i]];
      } else if (isJSONArray(value)) {
        value = value[parseInt(path[i])];
      } else {
        value = void 0;
      }
      i++;
    }
    return value;
  }
  function setIn(object, path, value) {
    let createPath = arguments.length > 3 && arguments[3] !== void 0 ? arguments[3] : false;
    if (path.length === 0) {
      return value;
    }
    const key = path[0];
    const updatedValue = setIn(object ? object[key] : void 0, path.slice(1), value, createPath);
    if (isJSONObject(object) || isJSONArray(object)) {
      return applyProp(object, key, updatedValue);
    } else {
      if (createPath) {
        const newObject = IS_INTEGER_REGEX.test(key) ? [] : {};
        newObject[key] = updatedValue;
        return newObject;
      } else {
        throw new Error("Path does not exist");
      }
    }
  }
  var IS_INTEGER_REGEX = /^\d+$/;
  function updateIn(object, path, transform) {
    if (path.length === 0) {
      return transform(object);
    }
    if (!isObjectOrArray(object)) {
      throw new Error("Path doesn't exist");
    }
    const key = path[0];
    const updatedValue = updateIn(object[key], path.slice(1), transform);
    return applyProp(object, key, updatedValue);
  }
  function deleteIn(object, path) {
    if (path.length === 0) {
      return object;
    }
    if (!isObjectOrArray(object)) {
      throw new Error("Path does not exist");
    }
    if (path.length === 1) {
      const key2 = path[0];
      if (!(key2 in object)) {
        return object;
      } else {
        const updatedObject = shallowClone(object);
        if (isJSONArray(updatedObject)) {
          updatedObject.splice(parseInt(key2), 1);
        }
        if (isJSONObject(updatedObject)) {
          delete updatedObject[key2];
        }
        return updatedObject;
      }
    }
    const key = path[0];
    const updatedValue = deleteIn(object[key], path.slice(1));
    return applyProp(object, key, updatedValue);
  }
  function insertAt(document2, path, value) {
    const parentPath = path.slice(0, path.length - 1);
    const index = path[path.length - 1];
    return updateIn(document2, parentPath, (items) => {
      if (!Array.isArray(items)) {
        throw new TypeError("Array expected at path " + JSON.stringify(parentPath));
      }
      const updatedItems = shallowClone(items);
      updatedItems.splice(parseInt(index), 0, value);
      return updatedItems;
    });
  }
  function existsIn(document2, path) {
    if (document2 === void 0) {
      return false;
    }
    if (path.length === 0) {
      return true;
    }
    if (document2 === null) {
      return false;
    }
    return existsIn(document2[path[0]], path.slice(1));
  }

  // ../node_modules/immutable-json-patch/lib/esm/jsonPointer.js
  function parseJSONPointer(pointer) {
    const path = pointer.split("/");
    path.shift();
    return path.map((p) => p.replace(/~1/g, "/").replace(/~0/g, "~"));
  }
  function compileJSONPointer(path) {
    return path.map(compileJSONPointerProp).join("");
  }
  function compileJSONPointerProp(pathProp) {
    return "/" + String(pathProp).replace(/~/g, "~0").replace(/\//g, "~1");
  }

  // ../node_modules/immutable-json-patch/lib/esm/immutableJSONPatch.js
  function immutableJSONPatch(document2, operations, options) {
    let updatedDocument = document2;
    for (let i = 0; i < operations.length; i++) {
      validateJSONPatchOperation(operations[i]);
      let operation = operations[i];
      if (options && options.before) {
        const result = options.before(updatedDocument, operation);
        if (result !== void 0) {
          if (result.document !== void 0) {
            updatedDocument = result.document;
          }
          if (result.json !== void 0) {
            throw new Error('Deprecation warning: returned object property ".json" has been renamed to ".document"');
          }
          if (result.operation !== void 0) {
            operation = result.operation;
          }
        }
      }
      const previousDocument = updatedDocument;
      const path = parsePath(updatedDocument, operation.path);
      if (operation.op === "add") {
        updatedDocument = add(updatedDocument, path, operation.value);
      } else if (operation.op === "remove") {
        updatedDocument = remove(updatedDocument, path);
      } else if (operation.op === "replace") {
        updatedDocument = replace(updatedDocument, path, operation.value);
      } else if (operation.op === "copy") {
        updatedDocument = copy(updatedDocument, path, parseFrom(operation.from));
      } else if (operation.op === "move") {
        updatedDocument = move(updatedDocument, path, parseFrom(operation.from));
      } else if (operation.op === "test") {
        test(updatedDocument, path, operation.value);
      } else {
        throw new Error("Unknown JSONPatch operation " + JSON.stringify(operation));
      }
      if (options && options.after) {
        const result = options.after(updatedDocument, operation, previousDocument);
        if (result !== void 0) {
          updatedDocument = result;
        }
      }
    }
    return updatedDocument;
  }
  function replace(document2, path, value) {
    return setIn(document2, path, value);
  }
  function remove(document2, path) {
    return deleteIn(document2, path);
  }
  function add(document2, path, value) {
    if (isArrayItem(document2, path)) {
      return insertAt(document2, path, value);
    } else {
      return setIn(document2, path, value);
    }
  }
  function copy(document2, path, from) {
    const value = getIn(document2, from);
    if (isArrayItem(document2, path)) {
      return insertAt(document2, path, value);
    } else {
      const value2 = getIn(document2, from);
      return setIn(document2, path, value2);
    }
  }
  function move(document2, path, from) {
    const value = getIn(document2, from);
    const removedJson = deleteIn(document2, from);
    return isArrayItem(removedJson, path) ? insertAt(removedJson, path, value) : setIn(removedJson, path, value);
  }
  function test(document2, path, value) {
    if (value === void 0) {
      throw new Error(`Test failed: no value provided (path: "${compileJSONPointer(path)}")`);
    }
    if (!existsIn(document2, path)) {
      throw new Error(`Test failed: path not found (path: "${compileJSONPointer(path)}")`);
    }
    const actualValue = getIn(document2, path);
    if (!isEqual(actualValue, value)) {
      throw new Error(`Test failed, value differs (path: "${compileJSONPointer(path)}")`);
    }
  }
  function isArrayItem(document2, path) {
    if (path.length === 0) {
      return false;
    }
    const parent = getIn(document2, initial(path));
    return Array.isArray(parent);
  }
  function resolvePathIndex(document2, path) {
    if (last(path) !== "-") {
      return path;
    }
    const parentPath = initial(path);
    const parent = getIn(document2, parentPath);
    return parentPath.concat(parent.length);
  }
  function validateJSONPatchOperation(operation) {
    const ops = ["add", "remove", "replace", "copy", "move", "test"];
    if (!ops.includes(operation.op)) {
      throw new Error("Unknown JSONPatch op " + JSON.stringify(operation.op));
    }
    if (typeof operation.path !== "string") {
      throw new Error('Required property "path" missing or not a string in operation ' + JSON.stringify(operation));
    }
    if (operation.op === "copy" || operation.op === "move") {
      if (typeof operation.from !== "string") {
        throw new Error('Required property "from" missing or not a string in operation ' + JSON.stringify(operation));
      }
    }
  }
  function parsePath(document2, pointer) {
    return resolvePathIndex(document2, parseJSONPointer(pointer));
  }
  function parseFrom(fromPointer) {
    return parseJSONPointer(fromPointer);
  }

  // ../node_modules/urlpattern-polyfill/dist/urlpattern.js
  var Pe = Object.defineProperty;
  var a = (e, t) => Pe(e, "name", { value: t, configurable: true });
  var P = class {
    constructor(t, r, n, c, l, f) {
      __publicField(this, "type", 3);
      __publicField(this, "name", "");
      __publicField(this, "prefix", "");
      __publicField(this, "value", "");
      __publicField(this, "suffix", "");
      __publicField(this, "modifier", 3);
      this.type = t, this.name = r, this.prefix = n, this.value = c, this.suffix = l, this.modifier = f;
    }
    hasCustomName() {
      return this.name !== "" && typeof this.name != "number";
    }
  };
  a(P, "Part");
  var Re = /[$_\p{ID_Start}]/u;
  var Ee = /[$_\u200C\u200D\p{ID_Continue}]/u;
  var v = ".*";
  function Oe(e, t) {
    return (t ? /^[\x00-\xFF]*$/ : /^[\x00-\x7F]*$/).test(e);
  }
  a(Oe, "isASCII");
  function D(e, t = false) {
    let r = [], n = 0;
    for (; n < e.length; ) {
      let c = e[n], l = a(function(f) {
        if (!t) throw new TypeError(f);
        r.push({ type: "INVALID_CHAR", index: n, value: e[n++] });
      }, "ErrorOrInvalid");
      if (c === "*") {
        r.push({ type: "ASTERISK", index: n, value: e[n++] });
        continue;
      }
      if (c === "+" || c === "?") {
        r.push({ type: "OTHER_MODIFIER", index: n, value: e[n++] });
        continue;
      }
      if (c === "\\") {
        r.push({ type: "ESCAPED_CHAR", index: n++, value: e[n++] });
        continue;
      }
      if (c === "{") {
        r.push({ type: "OPEN", index: n, value: e[n++] });
        continue;
      }
      if (c === "}") {
        r.push({ type: "CLOSE", index: n, value: e[n++] });
        continue;
      }
      if (c === ":") {
        let f = "", s = n + 1;
        for (; s < e.length; ) {
          let i = e.substr(s, 1);
          if (s === n + 1 && Re.test(i) || s !== n + 1 && Ee.test(i)) {
            f += e[s++];
            continue;
          }
          break;
        }
        if (!f) {
          l(`Missing parameter name at ${n}`);
          continue;
        }
        r.push({ type: "NAME", index: n, value: f }), n = s;
        continue;
      }
      if (c === "(") {
        let f = 1, s = "", i = n + 1, o = false;
        if (e[i] === "?") {
          l(`Pattern cannot start with "?" at ${i}`);
          continue;
        }
        for (; i < e.length; ) {
          if (!Oe(e[i], false)) {
            l(`Invalid character '${e[i]}' at ${i}.`), o = true;
            break;
          }
          if (e[i] === "\\") {
            s += e[i++] + e[i++];
            continue;
          }
          if (e[i] === ")") {
            if (f--, f === 0) {
              i++;
              break;
            }
          } else if (e[i] === "(" && (f++, e[i + 1] !== "?")) {
            l(`Capturing groups are not allowed at ${i}`), o = true;
            break;
          }
          s += e[i++];
        }
        if (o) continue;
        if (f) {
          l(`Unbalanced pattern at ${n}`);
          continue;
        }
        if (!s) {
          l(`Missing pattern at ${n}`);
          continue;
        }
        r.push({ type: "REGEX", index: n, value: s }), n = i;
        continue;
      }
      r.push({ type: "CHAR", index: n, value: e[n++] });
    }
    return r.push({ type: "END", index: n, value: "" }), r;
  }
  a(D, "lexer");
  function F(e, t = {}) {
    let r = D(e);
    t.delimiter ??= "/#?", t.prefixes ??= "./";
    let n = `[^${x(t.delimiter)}]+?`, c = [], l = 0, f = 0, s = "", i = /* @__PURE__ */ new Set(), o = a((u) => {
      if (f < r.length && r[f].type === u) return r[f++].value;
    }, "tryConsume"), h = a(() => o("OTHER_MODIFIER") ?? o("ASTERISK"), "tryConsumeModifier"), p = a((u) => {
      let d = o(u);
      if (d !== void 0) return d;
      let { type: g, index: y } = r[f];
      throw new TypeError(`Unexpected ${g} at ${y}, expected ${u}`);
    }, "mustConsume"), A = a(() => {
      let u = "", d;
      for (; d = o("CHAR") ?? o("ESCAPED_CHAR"); ) u += d;
      return u;
    }, "consumeText"), xe = a((u) => u, "DefaultEncodePart"), N = t.encodePart || xe, H = "", $ = a((u) => {
      H += u;
    }, "appendToPendingFixedValue"), M = a(() => {
      H.length && (c.push(new P(3, "", "", N(H), "", 3)), H = "");
    }, "maybeAddPartFromPendingFixedValue"), X = a((u, d, g, y, Z) => {
      let m = 3;
      switch (Z) {
        case "?":
          m = 1;
          break;
        case "*":
          m = 0;
          break;
        case "+":
          m = 2;
          break;
      }
      if (!d && !g && m === 3) {
        $(u);
        return;
      }
      if (M(), !d && !g) {
        if (!u) return;
        c.push(new P(3, "", "", N(u), "", m));
        return;
      }
      let S;
      g ? g === "*" ? S = v : S = g : S = n;
      let k = 2;
      S === n ? (k = 1, S = "") : S === v && (k = 0, S = "");
      let E;
      if (d ? E = d : g && (E = l++), i.has(E)) throw new TypeError(`Duplicate name '${E}'.`);
      i.add(E), c.push(new P(k, E, N(u), S, N(y), m));
    }, "addPart");
    for (; f < r.length; ) {
      let u = o("CHAR"), d = o("NAME"), g = o("REGEX");
      if (!d && !g && (g = o("ASTERISK")), d || g) {
        let m = u ?? "";
        t.prefixes.indexOf(m) === -1 && ($(m), m = ""), M();
        let S = h();
        X(m, d, g, "", S);
        continue;
      }
      let y = u ?? o("ESCAPED_CHAR");
      if (y) {
        $(y);
        continue;
      }
      if (o("OPEN")) {
        let m = A(), S = o("NAME"), k = o("REGEX");
        !S && !k && (k = o("ASTERISK"));
        let E = A();
        p("CLOSE");
        let be = h();
        X(m, S, k, E, be);
        continue;
      }
      M(), p("END");
    }
    return c;
  }
  a(F, "parse");
  function x(e) {
    return e.replace(/([.+*?^${}()[\]|/\\])/g, "\\$1");
  }
  a(x, "escapeString");
  function B(e) {
    return e && e.ignoreCase ? "ui" : "u";
  }
  a(B, "flags");
  function q(e, t, r) {
    return W(F(e, r), t, r);
  }
  a(q, "stringToRegexp");
  function T(e) {
    switch (e) {
      case 0:
        return "*";
      case 1:
        return "?";
      case 2:
        return "+";
      case 3:
        return "";
    }
  }
  a(T, "modifierToString");
  function W(e, t, r = {}) {
    r.delimiter ??= "/#?", r.prefixes ??= "./", r.sensitive ??= false, r.strict ??= false, r.end ??= true, r.start ??= true, r.endsWith = "";
    let n = r.start ? "^" : "";
    for (let s of e) {
      if (s.type === 3) {
        s.modifier === 3 ? n += x(s.value) : n += `(?:${x(s.value)})${T(s.modifier)}`;
        continue;
      }
      t && t.push(s.name);
      let i = `[^${x(r.delimiter)}]+?`, o = s.value;
      if (s.type === 1 ? o = i : s.type === 0 && (o = v), !s.prefix.length && !s.suffix.length) {
        s.modifier === 3 || s.modifier === 1 ? n += `(${o})${T(s.modifier)}` : n += `((?:${o})${T(s.modifier)})`;
        continue;
      }
      if (s.modifier === 3 || s.modifier === 1) {
        n += `(?:${x(s.prefix)}(${o})${x(s.suffix)})`, n += T(s.modifier);
        continue;
      }
      n += `(?:${x(s.prefix)}`, n += `((?:${o})(?:`, n += x(s.suffix), n += x(s.prefix), n += `(?:${o}))*)${x(s.suffix)})`, s.modifier === 0 && (n += "?");
    }
    let c = `[${x(r.endsWith)}]|$`, l = `[${x(r.delimiter)}]`;
    if (r.end) return r.strict || (n += `${l}?`), r.endsWith.length ? n += `(?=${c})` : n += "$", new RegExp(n, B(r));
    r.strict || (n += `(?:${l}(?=${c}))?`);
    let f = false;
    if (e.length) {
      let s = e[e.length - 1];
      s.type === 3 && s.modifier === 3 && (f = r.delimiter.indexOf(s) > -1);
    }
    return f || (n += `(?=${l}|${c})`), new RegExp(n, B(r));
  }
  a(W, "partsToRegexp");
  var b = { delimiter: "", prefixes: "", sensitive: true, strict: true };
  var J = { delimiter: ".", prefixes: "", sensitive: true, strict: true };
  var Q = { delimiter: "/", prefixes: "/", sensitive: true, strict: true };
  function ee(e, t) {
    return e.length ? e[0] === "/" ? true : !t || e.length < 2 ? false : (e[0] == "\\" || e[0] == "{") && e[1] == "/" : false;
  }
  a(ee, "isAbsolutePathname");
  function te(e, t) {
    return e.startsWith(t) ? e.substring(t.length, e.length) : e;
  }
  a(te, "maybeStripPrefix");
  function ke(e, t) {
    return e.endsWith(t) ? e.substr(0, e.length - t.length) : e;
  }
  a(ke, "maybeStripSuffix");
  function _(e) {
    return !e || e.length < 2 ? false : e[0] === "[" || (e[0] === "\\" || e[0] === "{") && e[1] === "[";
  }
  a(_, "treatAsIPv6Hostname");
  var re = ["ftp", "file", "http", "https", "ws", "wss"];
  function U(e) {
    if (!e) return true;
    for (let t of re) if (e.test(t)) return true;
    return false;
  }
  a(U, "isSpecialScheme");
  function ne(e, t) {
    if (e = te(e, "#"), t || e === "") return e;
    let r = new URL("https://example.com");
    return r.hash = e, r.hash ? r.hash.substring(1, r.hash.length) : "";
  }
  a(ne, "canonicalizeHash");
  function se(e, t) {
    if (e = te(e, "?"), t || e === "") return e;
    let r = new URL("https://example.com");
    return r.search = e, r.search ? r.search.substring(1, r.search.length) : "";
  }
  a(se, "canonicalizeSearch");
  function ie(e, t) {
    return t || e === "" ? e : _(e) ? K(e) : j(e);
  }
  a(ie, "canonicalizeHostname");
  function ae(e, t) {
    if (t || e === "") return e;
    let r = new URL("https://example.com");
    return r.password = e, r.password;
  }
  a(ae, "canonicalizePassword");
  function oe(e, t) {
    if (t || e === "") return e;
    let r = new URL("https://example.com");
    return r.username = e, r.username;
  }
  a(oe, "canonicalizeUsername");
  function ce(e, t, r) {
    if (r || e === "") return e;
    if (t && !re.includes(t)) return new URL(`${t}:${e}`).pathname;
    let n = e[0] == "/";
    return e = new URL(n ? e : "/-" + e, "https://example.com").pathname, n || (e = e.substring(2, e.length)), e;
  }
  a(ce, "canonicalizePathname");
  function le(e, t, r) {
    return z(t) === e && (e = ""), r || e === "" ? e : G(e);
  }
  a(le, "canonicalizePort");
  function fe(e, t) {
    return e = ke(e, ":"), t || e === "" ? e : w(e);
  }
  a(fe, "canonicalizeProtocol");
  function z(e) {
    switch (e) {
      case "ws":
      case "http":
        return "80";
      case "wws":
      case "https":
        return "443";
      case "ftp":
        return "21";
      default:
        return "";
    }
  }
  a(z, "defaultPortForProtocol");
  function w(e) {
    if (e === "") return e;
    if (/^[-+.A-Za-z0-9]*$/.test(e)) return e.toLowerCase();
    throw new TypeError(`Invalid protocol '${e}'.`);
  }
  a(w, "protocolEncodeCallback");
  function he(e) {
    if (e === "") return e;
    let t = new URL("https://example.com");
    return t.username = e, t.username;
  }
  a(he, "usernameEncodeCallback");
  function ue(e) {
    if (e === "") return e;
    let t = new URL("https://example.com");
    return t.password = e, t.password;
  }
  a(ue, "passwordEncodeCallback");
  function j(e) {
    if (e === "") return e;
    if (/[\t\n\r #%/:<>?@[\]^\\|]/g.test(e)) throw new TypeError(`Invalid hostname '${e}'`);
    let t = new URL("https://example.com");
    return t.hostname = e, t.hostname;
  }
  a(j, "hostnameEncodeCallback");
  function K(e) {
    if (e === "") return e;
    if (/[^0-9a-fA-F[\]:]/g.test(e)) throw new TypeError(`Invalid IPv6 hostname '${e}'`);
    return e.toLowerCase();
  }
  a(K, "ipv6HostnameEncodeCallback");
  function G(e) {
    if (e === "" || /^[0-9]*$/.test(e) && parseInt(e) <= 65535) return e;
    throw new TypeError(`Invalid port '${e}'.`);
  }
  a(G, "portEncodeCallback");
  function de(e) {
    if (e === "") return e;
    let t = new URL("https://example.com");
    return t.pathname = e[0] !== "/" ? "/-" + e : e, e[0] !== "/" ? t.pathname.substring(2, t.pathname.length) : t.pathname;
  }
  a(de, "standardURLPathnameEncodeCallback");
  function pe(e) {
    return e === "" ? e : new URL(`data:${e}`).pathname;
  }
  a(pe, "pathURLPathnameEncodeCallback");
  function ge(e) {
    if (e === "") return e;
    let t = new URL("https://example.com");
    return t.search = e, t.search.substring(1, t.search.length);
  }
  a(ge, "searchEncodeCallback");
  function me(e) {
    if (e === "") return e;
    let t = new URL("https://example.com");
    return t.hash = e, t.hash.substring(1, t.hash.length);
  }
  a(me, "hashEncodeCallback");
  var _i, _n, _t, _e, _s, _l, _o, _d, _p, _g, _C_instances, r_fn, R_fn, b_fn, u_fn, m_fn, a_fn, P_fn, E_fn, S_fn, O_fn, k_fn, x_fn, h_fn, f_fn, T_fn, A_fn, y_fn, w_fn, c_fn, C_fn, _a;
  var C = (_a = class {
    constructor(t) {
      __privateAdd(this, _C_instances);
      __privateAdd(this, _i);
      __privateAdd(this, _n, []);
      __privateAdd(this, _t, {});
      __privateAdd(this, _e, 0);
      __privateAdd(this, _s, 1);
      __privateAdd(this, _l, 0);
      __privateAdd(this, _o, 0);
      __privateAdd(this, _d, 0);
      __privateAdd(this, _p, 0);
      __privateAdd(this, _g, false);
      __privateSet(this, _i, t);
    }
    get result() {
      return __privateGet(this, _t);
    }
    parse() {
      for (__privateSet(this, _n, D(__privateGet(this, _i), true)); __privateGet(this, _e) < __privateGet(this, _n).length; __privateSet(this, _e, __privateGet(this, _e) + __privateGet(this, _s))) {
        if (__privateSet(this, _s, 1), __privateGet(this, _n)[__privateGet(this, _e)].type === "END") {
          if (__privateGet(this, _o) === 0) {
            __privateMethod(this, _C_instances, b_fn).call(this), __privateMethod(this, _C_instances, f_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 9, 1) : __privateMethod(this, _C_instances, h_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 8, 1) : __privateMethod(this, _C_instances, r_fn).call(this, 7, 0);
            continue;
          } else if (__privateGet(this, _o) === 2) {
            __privateMethod(this, _C_instances, u_fn).call(this, 5);
            continue;
          }
          __privateMethod(this, _C_instances, r_fn).call(this, 10, 0);
          break;
        }
        if (__privateGet(this, _d) > 0) if (__privateMethod(this, _C_instances, A_fn).call(this)) __privateSet(this, _d, __privateGet(this, _d) - 1);
        else continue;
        if (__privateMethod(this, _C_instances, T_fn).call(this)) {
          __privateSet(this, _d, __privateGet(this, _d) + 1);
          continue;
        }
        switch (__privateGet(this, _o)) {
          case 0:
            __privateMethod(this, _C_instances, P_fn).call(this) && __privateMethod(this, _C_instances, u_fn).call(this, 1);
            break;
          case 1:
            if (__privateMethod(this, _C_instances, P_fn).call(this)) {
              __privateMethod(this, _C_instances, C_fn).call(this);
              let t = 7, r = 1;
              __privateMethod(this, _C_instances, E_fn).call(this) ? (t = 2, r = 3) : __privateGet(this, _g) && (t = 2), __privateMethod(this, _C_instances, r_fn).call(this, t, r);
            }
            break;
          case 2:
            __privateMethod(this, _C_instances, S_fn).call(this) ? __privateMethod(this, _C_instances, u_fn).call(this, 3) : (__privateMethod(this, _C_instances, x_fn).call(this) || __privateMethod(this, _C_instances, h_fn).call(this) || __privateMethod(this, _C_instances, f_fn).call(this)) && __privateMethod(this, _C_instances, u_fn).call(this, 5);
            break;
          case 3:
            __privateMethod(this, _C_instances, O_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 4, 1) : __privateMethod(this, _C_instances, S_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 5, 1);
            break;
          case 4:
            __privateMethod(this, _C_instances, S_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 5, 1);
            break;
          case 5:
            __privateMethod(this, _C_instances, y_fn).call(this) ? __privateSet(this, _p, __privateGet(this, _p) + 1) : __privateMethod(this, _C_instances, w_fn).call(this) && __privateSet(this, _p, __privateGet(this, _p) - 1), __privateMethod(this, _C_instances, k_fn).call(this) && !__privateGet(this, _p) ? __privateMethod(this, _C_instances, r_fn).call(this, 6, 1) : __privateMethod(this, _C_instances, x_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 7, 0) : __privateMethod(this, _C_instances, h_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 8, 1) : __privateMethod(this, _C_instances, f_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 9, 1);
            break;
          case 6:
            __privateMethod(this, _C_instances, x_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 7, 0) : __privateMethod(this, _C_instances, h_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 8, 1) : __privateMethod(this, _C_instances, f_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 9, 1);
            break;
          case 7:
            __privateMethod(this, _C_instances, h_fn).call(this) ? __privateMethod(this, _C_instances, r_fn).call(this, 8, 1) : __privateMethod(this, _C_instances, f_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 9, 1);
            break;
          case 8:
            __privateMethod(this, _C_instances, f_fn).call(this) && __privateMethod(this, _C_instances, r_fn).call(this, 9, 1);
            break;
          case 9:
            break;
          case 10:
            break;
        }
      }
      __privateGet(this, _t).hostname !== void 0 && __privateGet(this, _t).port === void 0 && (__privateGet(this, _t).port = "");
    }
  }, _i = new WeakMap(), _n = new WeakMap(), _t = new WeakMap(), _e = new WeakMap(), _s = new WeakMap(), _l = new WeakMap(), _o = new WeakMap(), _d = new WeakMap(), _p = new WeakMap(), _g = new WeakMap(), _C_instances = new WeakSet(), r_fn = function(t, r) {
    switch (__privateGet(this, _o)) {
      case 0:
        break;
      case 1:
        __privateGet(this, _t).protocol = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 2:
        break;
      case 3:
        __privateGet(this, _t).username = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 4:
        __privateGet(this, _t).password = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 5:
        __privateGet(this, _t).hostname = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 6:
        __privateGet(this, _t).port = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 7:
        __privateGet(this, _t).pathname = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 8:
        __privateGet(this, _t).search = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 9:
        __privateGet(this, _t).hash = __privateMethod(this, _C_instances, c_fn).call(this);
        break;
      case 10:
        break;
    }
    __privateGet(this, _o) !== 0 && t !== 10 && ([1, 2, 3, 4].includes(__privateGet(this, _o)) && [6, 7, 8, 9].includes(t) && (__privateGet(this, _t).hostname ??= ""), [1, 2, 3, 4, 5, 6].includes(__privateGet(this, _o)) && [8, 9].includes(t) && (__privateGet(this, _t).pathname ??= __privateGet(this, _g) ? "/" : ""), [1, 2, 3, 4, 5, 6, 7].includes(__privateGet(this, _o)) && t === 9 && (__privateGet(this, _t).search ??= "")), __privateMethod(this, _C_instances, R_fn).call(this, t, r);
  }, R_fn = function(t, r) {
    __privateSet(this, _o, t), __privateSet(this, _l, __privateGet(this, _e) + r), __privateSet(this, _e, __privateGet(this, _e) + r), __privateSet(this, _s, 0);
  }, b_fn = function() {
    __privateSet(this, _e, __privateGet(this, _l)), __privateSet(this, _s, 0);
  }, u_fn = function(t) {
    __privateMethod(this, _C_instances, b_fn).call(this), __privateSet(this, _o, t);
  }, m_fn = function(t) {
    return t < 0 && (t = __privateGet(this, _n).length - t), t < __privateGet(this, _n).length ? __privateGet(this, _n)[t] : __privateGet(this, _n)[__privateGet(this, _n).length - 1];
  }, a_fn = function(t, r) {
    let n = __privateMethod(this, _C_instances, m_fn).call(this, t);
    return n.value === r && (n.type === "CHAR" || n.type === "ESCAPED_CHAR" || n.type === "INVALID_CHAR");
  }, P_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), ":");
  }, E_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e) + 1, "/") && __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e) + 2, "/");
  }, S_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "@");
  }, O_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), ":");
  }, k_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), ":");
  }, x_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "/");
  }, h_fn = function() {
    if (__privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "?")) return true;
    if (__privateGet(this, _n)[__privateGet(this, _e)].value !== "?") return false;
    let t = __privateMethod(this, _C_instances, m_fn).call(this, __privateGet(this, _e) - 1);
    return t.type !== "NAME" && t.type !== "REGEX" && t.type !== "CLOSE" && t.type !== "ASTERISK";
  }, f_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "#");
  }, T_fn = function() {
    return __privateGet(this, _n)[__privateGet(this, _e)].type == "OPEN";
  }, A_fn = function() {
    return __privateGet(this, _n)[__privateGet(this, _e)].type == "CLOSE";
  }, y_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "[");
  }, w_fn = function() {
    return __privateMethod(this, _C_instances, a_fn).call(this, __privateGet(this, _e), "]");
  }, c_fn = function() {
    let t = __privateGet(this, _n)[__privateGet(this, _e)], r = __privateMethod(this, _C_instances, m_fn).call(this, __privateGet(this, _l)).index;
    return __privateGet(this, _i).substring(r, t.index);
  }, C_fn = function() {
    let t = {};
    Object.assign(t, b), t.encodePart = w;
    let r = q(__privateMethod(this, _C_instances, c_fn).call(this), void 0, t);
    __privateSet(this, _g, U(r));
  }, _a);
  a(C, "Parser");
  var V = ["protocol", "username", "password", "hostname", "port", "pathname", "search", "hash"];
  var O = "*";
  function Se(e, t) {
    if (typeof e != "string") throw new TypeError("parameter 1 is not of type 'string'.");
    let r = new URL(e, t);
    return { protocol: r.protocol.substring(0, r.protocol.length - 1), username: r.username, password: r.password, hostname: r.hostname, port: r.port, pathname: r.pathname, search: r.search !== "" ? r.search.substring(1, r.search.length) : void 0, hash: r.hash !== "" ? r.hash.substring(1, r.hash.length) : void 0 };
  }
  a(Se, "extractValues");
  function R(e, t) {
    return t ? I(e) : e;
  }
  a(R, "processBaseURLString");
  function L(e, t, r) {
    let n;
    if (typeof t.baseURL == "string") try {
      n = new URL(t.baseURL), t.protocol === void 0 && (e.protocol = R(n.protocol.substring(0, n.protocol.length - 1), r)), !r && t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && t.username === void 0 && (e.username = R(n.username, r)), !r && t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && t.username === void 0 && t.password === void 0 && (e.password = R(n.password, r)), t.protocol === void 0 && t.hostname === void 0 && (e.hostname = R(n.hostname, r)), t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && (e.port = R(n.port, r)), t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && t.pathname === void 0 && (e.pathname = R(n.pathname, r)), t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && t.pathname === void 0 && t.search === void 0 && (e.search = R(n.search.substring(1, n.search.length), r)), t.protocol === void 0 && t.hostname === void 0 && t.port === void 0 && t.pathname === void 0 && t.search === void 0 && t.hash === void 0 && (e.hash = R(n.hash.substring(1, n.hash.length), r));
    } catch {
      throw new TypeError(`invalid baseURL '${t.baseURL}'.`);
    }
    if (typeof t.protocol == "string" && (e.protocol = fe(t.protocol, r)), typeof t.username == "string" && (e.username = oe(t.username, r)), typeof t.password == "string" && (e.password = ae(t.password, r)), typeof t.hostname == "string" && (e.hostname = ie(t.hostname, r)), typeof t.port == "string" && (e.port = le(t.port, e.protocol, r)), typeof t.pathname == "string") {
      if (e.pathname = t.pathname, n && !ee(e.pathname, r)) {
        let c = n.pathname.lastIndexOf("/");
        c >= 0 && (e.pathname = R(n.pathname.substring(0, c + 1), r) + e.pathname);
      }
      e.pathname = ce(e.pathname, e.protocol, r);
    }
    return typeof t.search == "string" && (e.search = se(t.search, r)), typeof t.hash == "string" && (e.hash = ne(t.hash, r)), e;
  }
  a(L, "applyInit");
  function I(e) {
    return e.replace(/([+*?:{}()\\])/g, "\\$1");
  }
  a(I, "escapePatternString");
  function Te(e) {
    return e.replace(/([.+*?^${}()[\]|/\\])/g, "\\$1");
  }
  a(Te, "escapeRegexpString");
  function Ae(e, t) {
    t.delimiter ??= "/#?", t.prefixes ??= "./", t.sensitive ??= false, t.strict ??= false, t.end ??= true, t.start ??= true, t.endsWith = "";
    let r = ".*", n = `[^${Te(t.delimiter)}]+?`, c = /[$_\u200C\u200D\p{ID_Continue}]/u, l = "";
    for (let f = 0; f < e.length; ++f) {
      let s = e[f];
      if (s.type === 3) {
        if (s.modifier === 3) {
          l += I(s.value);
          continue;
        }
        l += `{${I(s.value)}}${T(s.modifier)}`;
        continue;
      }
      let i = s.hasCustomName(), o = !!s.suffix.length || !!s.prefix.length && (s.prefix.length !== 1 || !t.prefixes.includes(s.prefix)), h = f > 0 ? e[f - 1] : null, p = f < e.length - 1 ? e[f + 1] : null;
      if (!o && i && s.type === 1 && s.modifier === 3 && p && !p.prefix.length && !p.suffix.length) if (p.type === 3) {
        let A = p.value.length > 0 ? p.value[0] : "";
        o = c.test(A);
      } else o = !p.hasCustomName();
      if (!o && !s.prefix.length && h && h.type === 3) {
        let A = h.value[h.value.length - 1];
        o = t.prefixes.includes(A);
      }
      o && (l += "{"), l += I(s.prefix), i && (l += `:${s.name}`), s.type === 2 ? l += `(${s.value})` : s.type === 1 ? i || (l += `(${n})`) : s.type === 0 && (!i && (!h || h.type === 3 || h.modifier !== 3 || o || s.prefix !== "") ? l += "*" : l += `(${r})`), s.type === 1 && i && s.suffix.length && c.test(s.suffix[0]) && (l += "\\"), l += I(s.suffix), o && (l += "}"), s.modifier !== 3 && (l += T(s.modifier));
    }
    return l;
  }
  a(Ae, "partsToPattern");
  var _i2, _n2, _t2, _e2, _s2, _l2, _a2;
  var Y = (_a2 = class {
    constructor(t = {}, r, n) {
      __privateAdd(this, _i2);
      __privateAdd(this, _n2, {});
      __privateAdd(this, _t2, {});
      __privateAdd(this, _e2, {});
      __privateAdd(this, _s2, {});
      __privateAdd(this, _l2, false);
      try {
        let c;
        if (typeof r == "string" ? c = r : n = r, typeof t == "string") {
          let i = new C(t);
          if (i.parse(), t = i.result, c === void 0 && typeof t.protocol != "string") throw new TypeError("A base URL must be provided for a relative constructor string.");
          t.baseURL = c;
        } else {
          if (!t || typeof t != "object") throw new TypeError("parameter 1 is not of type 'string' and cannot convert to dictionary.");
          if (c) throw new TypeError("parameter 1 is not of type 'string'.");
        }
        typeof n > "u" && (n = { ignoreCase: false });
        let l = { ignoreCase: n.ignoreCase === true }, f = { pathname: O, protocol: O, username: O, password: O, hostname: O, port: O, search: O, hash: O };
        __privateSet(this, _i2, L(f, t, true)), z(__privateGet(this, _i2).protocol) === __privateGet(this, _i2).port && (__privateGet(this, _i2).port = "");
        let s;
        for (s of V) {
          if (!(s in __privateGet(this, _i2))) continue;
          let i = {}, o = __privateGet(this, _i2)[s];
          switch (__privateGet(this, _t2)[s] = [], s) {
            case "protocol":
              Object.assign(i, b), i.encodePart = w;
              break;
            case "username":
              Object.assign(i, b), i.encodePart = he;
              break;
            case "password":
              Object.assign(i, b), i.encodePart = ue;
              break;
            case "hostname":
              Object.assign(i, J), _(o) ? i.encodePart = K : i.encodePart = j;
              break;
            case "port":
              Object.assign(i, b), i.encodePart = G;
              break;
            case "pathname":
              U(__privateGet(this, _n2).protocol) ? (Object.assign(i, Q, l), i.encodePart = de) : (Object.assign(i, b, l), i.encodePart = pe);
              break;
            case "search":
              Object.assign(i, b, l), i.encodePart = ge;
              break;
            case "hash":
              Object.assign(i, b, l), i.encodePart = me;
              break;
          }
          try {
            __privateGet(this, _s2)[s] = F(o, i), __privateGet(this, _n2)[s] = W(__privateGet(this, _s2)[s], __privateGet(this, _t2)[s], i), __privateGet(this, _e2)[s] = Ae(__privateGet(this, _s2)[s], i), __privateSet(this, _l2, __privateGet(this, _l2) || __privateGet(this, _s2)[s].some((h) => h.type === 2));
          } catch {
            throw new TypeError(`invalid ${s} pattern '${__privateGet(this, _i2)[s]}'.`);
          }
        }
      } catch (c) {
        throw new TypeError(`Failed to construct 'URLPattern': ${c.message}`);
      }
    }
    get [Symbol.toStringTag]() {
      return "URLPattern";
    }
    test(t = {}, r) {
      let n = { pathname: "", protocol: "", username: "", password: "", hostname: "", port: "", search: "", hash: "" };
      if (typeof t != "string" && r) throw new TypeError("parameter 1 is not of type 'string'.");
      if (typeof t > "u") return false;
      try {
        typeof t == "object" ? n = L(n, t, false) : n = L(n, Se(t, r), false);
      } catch {
        return false;
      }
      let c;
      for (c of V) if (!__privateGet(this, _n2)[c].exec(n[c])) return false;
      return true;
    }
    exec(t = {}, r) {
      let n = { pathname: "", protocol: "", username: "", password: "", hostname: "", port: "", search: "", hash: "" };
      if (typeof t != "string" && r) throw new TypeError("parameter 1 is not of type 'string'.");
      if (typeof t > "u") return;
      try {
        typeof t == "object" ? n = L(n, t, false) : n = L(n, Se(t, r), false);
      } catch {
        return null;
      }
      let c = {};
      r ? c.inputs = [t, r] : c.inputs = [t];
      let l;
      for (l of V) {
        let f = __privateGet(this, _n2)[l].exec(n[l]);
        if (!f) return null;
        let s = {};
        for (let [i, o] of __privateGet(this, _t2)[l].entries()) if (typeof o == "string" || typeof o == "number") {
          let h = f[i + 1];
          s[o] = h;
        }
        c[l] = { input: n[l] ?? "", groups: s };
      }
      return c;
    }
    static compareComponent(t, r, n) {
      let c = a((i, o) => {
        for (let h of ["type", "modifier", "prefix", "value", "suffix"]) {
          if (i[h] < o[h]) return -1;
          if (i[h] === o[h]) continue;
          return 1;
        }
        return 0;
      }, "comparePart"), l = new P(3, "", "", "", "", 3), f = new P(0, "", "", "", "", 3), s = a((i, o) => {
        let h = 0;
        for (; h < Math.min(i.length, o.length); ++h) {
          let p = c(i[h], o[h]);
          if (p) return p;
        }
        return i.length === o.length ? 0 : c(i[h] ?? l, o[h] ?? l);
      }, "comparePartList");
      return !__privateGet(r, _e2)[t] && !__privateGet(n, _e2)[t] ? 0 : __privateGet(r, _e2)[t] && !__privateGet(n, _e2)[t] ? s(__privateGet(r, _s2)[t], [f]) : !__privateGet(r, _e2)[t] && __privateGet(n, _e2)[t] ? s([f], __privateGet(n, _s2)[t]) : s(__privateGet(r, _s2)[t], __privateGet(n, _s2)[t]);
    }
    get protocol() {
      return __privateGet(this, _e2).protocol;
    }
    get username() {
      return __privateGet(this, _e2).username;
    }
    get password() {
      return __privateGet(this, _e2).password;
    }
    get hostname() {
      return __privateGet(this, _e2).hostname;
    }
    get port() {
      return __privateGet(this, _e2).port;
    }
    get pathname() {
      return __privateGet(this, _e2).pathname;
    }
    get search() {
      return __privateGet(this, _e2).search;
    }
    get hash() {
      return __privateGet(this, _e2).hash;
    }
    get hasRegExpGroups() {
      return __privateGet(this, _l2);
    }
  }, _i2 = new WeakMap(), _n2 = new WeakMap(), _t2 = new WeakMap(), _e2 = new WeakMap(), _s2 = new WeakMap(), _l2 = new WeakMap(), _a2);
  a(Y, "URLPattern");

  // ../node_modules/urlpattern-polyfill/index.js
  if (!globalThis.URLPattern) {
    globalThis.URLPattern = Y;
  }

  // src/config-feature.js
  var _bundledConfig, _args;
  var ConfigFeature = class {
    /**
     * @param {string} name
     * @param {import('./content-scope-features.js').LoadArgs} args
     */
    constructor(name, args) {
      /** @type {import('./utils.js').RemoteConfig | undefined} */
      __privateAdd(this, _bundledConfig);
      /** @type {string} */
      __publicField(this, "name");
      /**
       * @type {{
       *   debug?: boolean,
       *   platform: import('./utils.js').Platform,
       *   desktopModeEnabled?: boolean,
       *   forcedZoomEnabled?: boolean,
       *   featureSettings?: Record<string, unknown>,
       *   assets?: import('./content-feature.js').AssetConfig | undefined,
       *   site: import('./content-feature.js').Site,
       *   messagingConfig?: import('@duckduckgo/messaging').MessagingConfig,
       *   currentCohorts?: [{feature: string, cohort: string, subfeature: string}],
       * } | null}
       */
      __privateAdd(this, _args);
      this.name = name;
      const { bundledConfig, site, platform } = args;
      __privateSet(this, _bundledConfig, bundledConfig);
      __privateSet(this, _args, args);
      if (__privateGet(this, _bundledConfig) && __privateGet(this, _args)) {
        const enabledFeatures = computeEnabledFeatures(bundledConfig, site.domain, platform.version);
        __privateGet(this, _args).featureSettings = parseFeatureSettings(bundledConfig, enabledFeatures);
      }
    }
    /**
     * Call this when the top URL has changed, to recompute the site object.
     * This is used to update the path matching for urlPattern.
     */
    recomputeSiteObject() {
      if (__privateGet(this, _args)) {
        __privateGet(this, _args).site = computeLimitedSiteObject();
      }
    }
    get args() {
      return __privateGet(this, _args);
    }
    set args(args) {
      __privateSet(this, _args, args);
    }
    get featureSettings() {
      return __privateGet(this, _args)?.featureSettings;
    }
    /**
     * Given a config key, interpret the value as a list of conditionals objects, and return the elements that match the current page
     * Consider in your feature using patchSettings instead as per `getFeatureSetting`.
     * @param {string} featureKeyName
     * @return {any[]}
     * @protected
     */
    matchConditionalFeatureSetting(featureKeyName) {
      const conditionalChanges = this._getFeatureSettings()?.[featureKeyName] || [];
      return conditionalChanges.filter((rule) => {
        let condition = rule.condition;
        if (condition === void 0 && "domain" in rule) {
          condition = this._domainToConditonBlocks(rule.domain);
        }
        return this._matchConditionalBlockOrArray(condition);
      });
    }
    /**
     * Takes a list of domains and returns a list of condition blocks
     * @param {string|string[]} domain
     * @returns {ConditionBlock[]}
     */
    _domainToConditonBlocks(domain) {
      if (Array.isArray(domain)) {
        return domain.map((domain2) => ({ domain: domain2 }));
      } else {
        return [{ domain }];
      }
    }
    /**
     * Used to match conditional changes for a settings feature.
     * @typedef {object} ConditionBlock
     * @property {string[] | string} [domain]
     * @property {object} [urlPattern]
     * @property {object} [minSupportedVersion]
     * @property {object} [experiment]
     * @property {string} [experiment.experimentName]
     * @property {string} [experiment.cohort]
     */
    /**
     * Takes multiple conditional blocks and returns true if any apply.
     * @param {ConditionBlock|ConditionBlock[]} conditionBlock
     * @returns {boolean}
     */
    _matchConditionalBlockOrArray(conditionBlock) {
      if (Array.isArray(conditionBlock)) {
        return conditionBlock.some((block) => this._matchConditionalBlock(block));
      }
      return this._matchConditionalBlock(conditionBlock);
    }
    /**
     * Takes a conditional block and returns true if it applies.
     * All conditions must be met to return true.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchConditionalBlock(conditionBlock) {
      const conditionChecks = {
        domain: this._matchDomainConditional,
        urlPattern: this._matchUrlPatternConditional,
        experiment: this._matchExperimentConditional,
        minSupportedVersion: this._matchMinSupportedVersion
      };
      for (const key in conditionBlock) {
        if (!conditionChecks[key]) {
          return false;
        } else if (!conditionChecks[key].call(this, conditionBlock)) {
          return false;
        }
      }
      return true;
    }
    /**
     * Takes a condition block and returns true if the current experiment matches the experimentName and cohort.
     * Expects:
     * ```json
     * {
     *   "experiment": {
     *      "experimentName": "experimentName",
     *      "cohort": "cohort-name"
     *    }
     * }
     * ```
     * Where featureName "contentScopeExperiments" has a subfeature "experimentName" and cohort "cohort-name"
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchExperimentConditional(conditionBlock) {
      if (!conditionBlock.experiment) return false;
      const experiment = conditionBlock.experiment;
      if (!experiment.experimentName || !experiment.cohort) return false;
      const currentCohorts = this.args?.currentCohorts;
      if (!currentCohorts) return false;
      return currentCohorts.some((cohort) => {
        return cohort.feature === "contentScopeExperiments" && cohort.subfeature === experiment.experimentName && cohort.cohort === experiment.cohort;
      });
    }
    /**
     * Takes a condtion block and returns true if the current url matches the urlPattern.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchUrlPatternConditional(conditionBlock) {
      const url = this.args?.site.url;
      if (!url) return false;
      if (typeof conditionBlock.urlPattern === "string") {
        return new Y(conditionBlock.urlPattern, url).test(url);
      }
      const pattern = new Y(conditionBlock.urlPattern);
      return pattern.test(url);
    }
    /**
     * Takes a condition block and returns true if the current domain matches the domain.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchDomainConditional(conditionBlock) {
      if (!conditionBlock.domain) return false;
      const domain = this.args?.site.domain;
      if (!domain) return false;
      if (Array.isArray(conditionBlock.domain)) {
        return false;
      }
      return matchHostname(domain, conditionBlock.domain);
    }
    /**
     * Takes a condition block and returns true if the platform version satisfies the `minSupportedFeature`
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchMinSupportedVersion(conditionBlock) {
      if (!conditionBlock.minSupportedVersion) return false;
      return isSupportedVersion(conditionBlock.minSupportedVersion, __privateGet(this, _args)?.platform?.version);
    }
    /**
     * Return the settings object for a feature
     * @param {string} [featureName] - The name of the feature to get the settings for; defaults to the name of the feature
     * @returns {any}
     */
    _getFeatureSettings(featureName) {
      const camelFeatureName = featureName || camelcase(this.name);
      return this.featureSettings?.[camelFeatureName];
    }
    /**
     * For simple boolean settings, return true if the setting is 'enabled'
     * For objects, verify the 'state' field is 'enabled'.
     * This allows for future forwards compatibility with more complex settings if required.
     * For example:
     * ```json
     * {
     *    "toggle": "enabled"
     * }
     * ```
     * Could become later (without breaking changes):
     * ```json
     * {
     *   "toggle": {
     *       "state": "enabled",
     *       "someOtherKey": 1
     *   }
     * }
     * ```
     * This also supports domain overrides as per `getFeatureSetting`.
     * @param {string} featureKeyName
     * @param {string} [featureName]
     * @returns {boolean}
     */
    getFeatureSettingEnabled(featureKeyName, featureName) {
      const result = this.getFeatureSetting(featureKeyName, featureName);
      if (typeof result === "object") {
        return result.state === "enabled";
      }
      return result === "enabled";
    }
    /**
     * Return a specific setting from the feature settings
     * If the "settings" key within the config has a "conditionalChanges" key, it will be used to override the settings.
     * This uses JSONPatch to apply the patches to settings before getting the setting value.
     * For example.com getFeatureSettings('val') will return 1:
     * ```json
     *  {
     *      "settings": {
     *         "conditionalChanges": [
     *             {
     *                "domain": "example.com",
     *                "patchSettings": [
     *                    { "op": "replace", "path": "/val", "value": 1 }
     *                ]
     *             }
     *         ]
     *      }
     *  }
     * ```
     * "domain" can either be a string or an array of strings.
     * Additionally we support urlPattern for more complex matching.
     * For example.com getFeatureSettings('val') will return 1:
     * ```json
     * {
     *    "settings": {
     *       "conditionalChanges": [
     *          {
     *            "condition": {
     *                "urlPattern": "https://example.com/*",
     *            },
     *            "patchSettings": [
     *                { "op": "replace", "path": "/val", "value": 1 }
     *            ]
     *          }
     *       ]
     *   }
     * }
     * ```
     * We also support multiple conditions:
     * ```json
     * {
     *    "settings": {
     *       "conditionalChanges": [
     *          {
     *            "condition": [
     *                {
     *                    "urlPattern": "https://example.com/*",
     *                },
     *                {
     *                    "urlPattern": "https://other.com/path/something",
     *                },
     *            ],
     *            "patchSettings": [
     *                { "op": "replace", "path": "/val", "value": 1 }
     *            ]
     *          }
     *       ]
     *   }
     * }
     * ```
     *
     * For boolean states you should consider using getFeatureSettingEnabled.
     * @param {string} featureKeyName
     * @param {string} [featureName]
     * @returns {any}
     */
    getFeatureSetting(featureKeyName, featureName) {
      let result = this._getFeatureSettings(featureName);
      if (featureKeyName in ["domains", "conditionalChanges"]) {
        throw new Error(`${featureKeyName} is a reserved feature setting key name`);
      }
      let conditionalMatches = [];
      if (result?.conditionalChanges) {
        conditionalMatches = this.matchConditionalFeatureSetting("conditionalChanges");
      } else {
        conditionalMatches = this.matchConditionalFeatureSetting("domains");
      }
      for (const match of conditionalMatches) {
        if (match.patchSettings === void 0) {
          continue;
        }
        try {
          result = immutableJSONPatch(result, match.patchSettings);
        } catch (e) {
          console.error("Error applying patch settings", e);
        }
      }
      return result?.[featureKeyName];
    }
    /**
     * @returns {import('./utils.js').RemoteConfig | undefined}
     **/
    get bundledConfig() {
      return __privateGet(this, _bundledConfig);
    }
  };
  _bundledConfig = new WeakMap();
  _args = new WeakMap();

  // src/content-feature.js
  var _messaging, _isDebugFlagSet, _importConfig;
  var ContentFeature = class extends ConfigFeature {
    constructor(featureName, importConfig, args) {
      super(featureName, args);
      /** @type {import('./utils.js').RemoteConfig | undefined} */
      /** @type {import('../../messaging').Messaging} */
      // eslint-disable-next-line no-unused-private-class-members
      __privateAdd(this, _messaging);
      /** @type {boolean} */
      __privateAdd(this, _isDebugFlagSet, false);
      /**
       * Set this to true if you wish to listen to top level URL changes for config matching.
       * @type {boolean}
       */
      __publicField(this, "listenForUrlChanges", false);
      /** @type {ImportMeta} */
      __privateAdd(this, _importConfig);
      this.setArgs(this.args);
      this.monitor = new PerformanceMonitor();
      __privateSet(this, _importConfig, importConfig);
    }
    get isDebug() {
      return this.args?.debug || false;
    }
    get desktopModeEnabled() {
      return this.args?.desktopModeEnabled || false;
    }
    get forcedZoomEnabled() {
      return this.args?.forcedZoomEnabled || false;
    }
    /**
     * @param {import('./utils').Platform} platform
     */
    set platform(platform) {
      this._platform = platform;
    }
    get platform() {
      return this._platform;
    }
    /**
     * @type {AssetConfig | undefined}
     */
    get assetConfig() {
      return this.args?.assets;
    }
    /**
     * @returns {ImportMeta['trackerLookup']}
     **/
    get trackerLookup() {
      return __privateGet(this, _importConfig).trackerLookup || {};
    }
    /**
     * @returns {ImportMeta['injectName']}
     */
    get injectName() {
      return __privateGet(this, _importConfig).injectName;
    }
    /**
     * @returns {boolean}
     */
    get documentOriginIsTracker() {
      return isTrackerOrigin(this.trackerLookup);
    }
    /**
     * @deprecated as we should make this internal to the class and not used externally
     * @return {MessagingContext}
     */
    _createMessagingContext() {
      const contextName = this.injectName === "apple-isolated" ? "contentScopeScriptsIsolated" : "contentScopeScripts";
      return new MessagingContext({
        context: contextName,
        env: this.isDebug ? "development" : "production",
        featureName: this.name
      });
    }
    /**
     * Lazily create a messaging instance for the given Platform + feature combo
     *
     * @return {import('@duckduckgo/messaging').Messaging}
     */
    get messaging() {
      if (this._messaging) return this._messaging;
      const messagingContext = this._createMessagingContext();
      let messagingConfig = this.args?.messagingConfig;
      if (!messagingConfig) {
        if (this.platform?.name !== "extension") throw new Error("Only extension messaging supported, all others should be passed in");
        messagingConfig = extensionConstructMessagingConfig();
      }
      this._messaging = new Messaging(messagingContext, messagingConfig);
      return this._messaging;
    }
    /**
     * Get the value of a config setting.
     * If the value is not set, return the default value.
     * If the value is not an object, return the value.
     * If the value is an object, check its type property.
     * @param {string} attrName
     * @param {any} defaultValue - The default value to use if the config setting is not set
     * @returns The value of the config setting or the default value
     */
    getFeatureAttr(attrName, defaultValue) {
      const configSetting = this.getFeatureSetting(attrName);
      return processAttr(configSetting, defaultValue);
    }
    init(_args2) {
    }
    callInit(args) {
      const mark = this.monitor.mark(this.name + "CallInit");
      this.setArgs(args);
      this.init(this.args);
      mark.end();
      this.measure();
    }
    setArgs(args) {
      this.args = args;
      this.platform = args.platform;
    }
    load(_args2) {
    }
    /**
     * This is a wrapper around `this.messaging.notify` that applies the
     * auto-generated types from the `src/types` folder. It's used
     * to provide per-feature type information based on the schemas
     * in `src/messages`
     *
     * @type {import("@duckduckgo/messaging").Messaging['notify']}
     */
    notify(...args) {
      const [name, params] = args;
      this.messaging.notify(name, params);
    }
    /**
     * This is a wrapper around `this.messaging.request` that applies the
     * auto-generated types from the `src/types` folder. It's used
     * to provide per-feature type information based on the schemas
     * in `src/messages`
     *
     * @type {import("@duckduckgo/messaging").Messaging['request']}
     */
    request(...args) {
      const [name, params] = args;
      return this.messaging.request(name, params);
    }
    /**
     * This is a wrapper around `this.messaging.subscribe` that applies the
     * auto-generated types from the `src/types` folder. It's used
     * to provide per-feature type information based on the schemas
     * in `src/messages`
     *
     * @type {import("@duckduckgo/messaging").Messaging['subscribe']}
     */
    subscribe(...args) {
      const [name, cb] = args;
      return this.messaging.subscribe(name, cb);
    }
    callLoad() {
      const mark = this.monitor.mark(this.name + "CallLoad");
      this.load(this.args);
      mark.end();
    }
    measure() {
      if (this.isDebug) {
        this.monitor.measureAll();
      }
    }
    /**
     * @deprecated - use messaging instead.
     */
    update() {
    }
    /**
     * Register a flag that will be added to page breakage reports
     */
    addDebugFlag() {
      if (__privateGet(this, _isDebugFlagSet)) return;
      __privateSet(this, _isDebugFlagSet, true);
      try {
        this.messaging?.notify("addDebugFlag", {
          flag: this.name
        });
      } catch (_e3) {
      }
    }
    /**
     * Define a property descriptor with debug flags.
     * Mainly used for defining new properties. For overriding existing properties, consider using wrapProperty(), wrapMethod() and wrapConstructor().
     * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.BatteryManager.prototype)
     * @param {string} propertyName
     * @param {import('./wrapper-utils').StrictPropertyDescriptor} descriptor - requires all descriptor options to be defined because we can't validate correctness based on TS types
     */
    defineProperty(object, propertyName, descriptor) {
      ["value", "get", "set"].forEach((k) => {
        const descriptorProp = descriptor[k];
        if (typeof descriptorProp === "function") {
          const addDebugFlag = this.addDebugFlag.bind(this);
          const wrapper = new Proxy2(descriptorProp, {
            apply(_2, thisArg, argumentsList) {
              addDebugFlag();
              return Reflect2.apply(descriptorProp, thisArg, argumentsList);
            }
          });
          descriptor[k] = wrapToString(wrapper, descriptorProp);
        }
      });
      return defineProperty(object, propertyName, descriptor);
    }
    /**
     * Wrap a `get`/`set` or `value` property descriptor. Only for data properties. For methods, use wrapMethod(). For constructors, use wrapConstructor().
     * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.Screen.prototype)
     * @param {string} propertyName
     * @param {Partial<PropertyDescriptor>} descriptor
     * @returns {PropertyDescriptor|undefined} original property descriptor, or undefined if it's not found
     */
    wrapProperty(object, propertyName, descriptor) {
      return wrapProperty(object, propertyName, descriptor, this.defineProperty.bind(this));
    }
    /**
     * Wrap a method descriptor. Only for function properties. For data properties, use wrapProperty(). For constructors, use wrapConstructor().
     * @param {any} object - object whose property we are wrapping (most commonly a prototype, e.g. globalThis.Bluetooth.prototype)
     * @param {string} propertyName
     * @param {(originalFn, ...args) => any } wrapperFn - wrapper function receives the original function as the first argument
     * @returns {PropertyDescriptor|undefined} original property descriptor, or undefined if it's not found
     */
    wrapMethod(object, propertyName, wrapperFn) {
      return wrapMethod(object, propertyName, wrapperFn, this.defineProperty.bind(this));
    }
    /**
     * @template {keyof typeof globalThis} StandardInterfaceName
     * @param {StandardInterfaceName} interfaceName - the name of the interface to shim (must be some known standard API, e.g. 'MediaSession')
     * @param {typeof globalThis[StandardInterfaceName]} ImplClass - the class to use as the shim implementation
     * @param {import('./wrapper-utils').DefineInterfaceOptions} options
     */
    shimInterface(interfaceName, ImplClass, options) {
      return shimInterface(interfaceName, ImplClass, options, this.defineProperty.bind(this), this.injectName);
    }
    /**
     * Define a missing standard property on a global (prototype) object. Only for data properties.
     * For constructors, use shimInterface().
     * Most of the time, you'd want to call shimInterface() first to shim the class itself (MediaSession), and then shimProperty() for the global singleton instance (Navigator.prototype.mediaSession).
     * @template Base
     * @template {keyof Base & string} K
     * @param {Base} instanceHost - object whose property we are shimming (most commonly a prototype object, e.g. Navigator.prototype)
     * @param {K} instanceProp - name of the property to shim (e.g. 'mediaSession')
     * @param {Base[K]} implInstance - instance to use as the shim (e.g. new MyMediaSession())
     * @param {boolean} [readOnly] - whether the property should be read-only (default: false)
     */
    shimProperty(instanceHost, instanceProp, implInstance, readOnly = false) {
      return shimProperty(instanceHost, instanceProp, implInstance, readOnly, this.defineProperty.bind(this), this.injectName);
    }
  };
  _messaging = new WeakMap();
  _isDebugFlagSet = new WeakMap();
  _importConfig = new WeakMap();

  // src/features/cookie.js
  function initialShouldBlockTrackerCookie() {
    const injectName = "firefox";
    return injectName === "firefox" || injectName === "chrome-mv3" || injectName === "windows";
  }
  var cookiePolicy = {
    debug: false,
    isFrame: isBeingFramed(),
    isTracker: false,
    shouldBlock: true,
    shouldBlockTrackerCookie: initialShouldBlockTrackerCookie(),
    shouldBlockNonTrackerCookie: false,
    isThirdPartyFrame: isThirdPartyFrame(),
    policy: {
      threshold: 604800,
      // 7 days
      maxAge: 604800
      // 7 days
    },
    trackerPolicy: {
      threshold: 86400,
      // 1 day
      maxAge: 86400
      // 1 day
    },
    allowlist: (
      /** @type {{ host: string }[]} */
      []
    )
  };
  var trackerLookup = {};
  var loadedPolicyResolve;
  function debugHelper(action, reason, ctx) {
    cookiePolicy.debug && postDebugMessage("jscookie", {
      action,
      reason,
      stack: ctx.stack,
      documentUrl: globalThis.document.location.href,
      value: ctx.value
    });
  }
  function shouldBlockTrackingCookie() {
    return cookiePolicy.shouldBlock && cookiePolicy.shouldBlockTrackerCookie && isTrackingCookie();
  }
  function shouldBlockNonTrackingCookie() {
    return cookiePolicy.shouldBlock && cookiePolicy.shouldBlockNonTrackerCookie && isNonTrackingCookie();
  }
  function isFirstPartyTrackerScript(scriptOrigins) {
    let matched = false;
    for (const scriptOrigin of scriptOrigins) {
      if (cookiePolicy.allowlist.find((allowlistOrigin) => matchHostname(allowlistOrigin.host, scriptOrigin))) {
        return false;
      }
      if (isTrackerOrigin(trackerLookup, scriptOrigin)) {
        matched = true;
      }
    }
    return matched;
  }
  function isTrackingCookie() {
    return cookiePolicy.isFrame && cookiePolicy.isTracker && cookiePolicy.isThirdPartyFrame;
  }
  function isNonTrackingCookie() {
    return cookiePolicy.isFrame && !cookiePolicy.isTracker && cookiePolicy.isThirdPartyFrame;
  }
  var CookieFeature = class extends ContentFeature {
    load() {
      if (this.documentOriginIsTracker) {
        cookiePolicy.isTracker = true;
      }
      if (this.trackerLookup) {
        trackerLookup = this.trackerLookup;
      }
      if (this.bundledConfig?.features?.cookie) {
        const { exceptions, settings } = this.bundledConfig.features.cookie;
        const tabHostname = getTabHostname();
        let tabExempted = true;
        if (tabHostname != null) {
          tabExempted = exceptions.some((exception) => {
            return matchHostname(tabHostname, exception.domain);
          });
        }
        const frameExempted = settings.excludedCookieDomains.some((exception) => {
          return matchHostname(globalThis.location.hostname, exception.domain);
        });
        cookiePolicy.shouldBlock = !frameExempted && !tabExempted;
        cookiePolicy.policy = settings.firstPartyCookiePolicy;
        cookiePolicy.trackerPolicy = settings.firstPartyTrackerCookiePolicy;
        cookiePolicy.allowlist = this.getFeatureSetting("allowlist", "adClickAttribution") || [];
      }
      const document2 = globalThis.document;
      const cookieSetter = Object.getOwnPropertyDescriptor(globalThis.Document.prototype, "cookie").set;
      const cookieGetter = Object.getOwnPropertyDescriptor(globalThis.Document.prototype, "cookie").get;
      const loadPolicy = new Promise((resolve) => {
        loadedPolicyResolve = resolve;
      });
      const loadPolicyThen = loadPolicy.then.bind(loadPolicy);
      function getCookiePolicy() {
        let getCookieContext = null;
        if (cookiePolicy.debug) {
          const stack = getStack();
          getCookieContext = {
            stack,
            value: "getter"
          };
        }
        if (shouldBlockTrackingCookie() || shouldBlockNonTrackingCookie()) {
          debugHelper("block", "3p frame", getCookieContext);
          return "";
        } else if (isTrackingCookie() || isNonTrackingCookie()) {
          debugHelper("ignore", "3p frame", getCookieContext);
        }
        return cookieGetter.call(this);
      }
      function setCookiePolicy(argValue) {
        let setCookieContext = null;
        if (!argValue?.toString || typeof argValue.toString() !== "string") {
          return;
        }
        const value = argValue.toString();
        if (cookiePolicy.debug) {
          const stack = getStack();
          setCookieContext = {
            stack,
            value
          };
        }
        if (shouldBlockTrackingCookie() || shouldBlockNonTrackingCookie()) {
          debugHelper("block", "3p frame", setCookieContext);
          return;
        } else if (isTrackingCookie() || isNonTrackingCookie()) {
          debugHelper("ignore", "3p frame", setCookieContext);
        }
        cookieSetter.call(this, argValue);
        try {
          loadPolicyThen(() => {
            const { shouldBlock, policy, trackerPolicy } = cookiePolicy;
            const stack = getStack();
            const scriptOrigins = getStackTraceOrigins(stack);
            const chosenPolicy = isFirstPartyTrackerScript(scriptOrigins) ? trackerPolicy : policy;
            if (!shouldBlock) {
              debugHelper("ignore", "disabled", setCookieContext);
              return;
            }
            const cookie = new Cookie(value);
            if (cookie.getExpiry() > chosenPolicy.threshold) {
              if (document2.cookie.split(";").findIndex((kv) => kv.trim().startsWith(cookie.parts[0].trim())) !== -1) {
                cookie.maxAge = chosenPolicy.maxAge;
                debugHelper("restrict", "expiry", setCookieContext);
                cookieSetter.apply(document2, [cookie.toString()]);
              } else {
                debugHelper("ignore", "dissappeared", setCookieContext);
              }
            } else {
              debugHelper("ignore", "expiry", setCookieContext);
            }
          });
        } catch (e) {
          debugHelper("ignore", "error", setCookieContext);
          console.warn("Error in cookie override", e);
        }
      }
      this.wrapProperty(globalThis.Document.prototype, "cookie", {
        set: setCookiePolicy,
        get: getCookiePolicy
      });
    }
    init(args) {
      const restOfPolicy = {
        debug: this.isDebug,
        shouldBlockTrackerCookie: this.getFeatureSettingEnabled("trackerCookie"),
        shouldBlockNonTrackerCookie: this.getFeatureSettingEnabled("nonTrackerCookie"),
        allowlist: this.getFeatureSetting("allowlist", "adClickAttribution") || [],
        policy: this.getFeatureSetting("firstPartyCookiePolicy"),
        trackerPolicy: this.getFeatureSetting("firstPartyTrackerCookiePolicy")
      };
      if (args.cookie) {
        const extensionCookiePolicy = (
          /** @type {ExtensionCookiePolicy} */
          args.cookie
        );
        cookiePolicy = {
          ...extensionCookiePolicy,
          ...restOfPolicy
        };
      } else {
        Object.keys(restOfPolicy).forEach((key) => {
          if (restOfPolicy[key]) {
            cookiePolicy[key] = restOfPolicy[key];
          }
        });
      }
      loadedPolicyResolve();
    }
  };

  // lib/sjcl.js
  var sjcl = (() => {
    "use strict";
    var sjcl2 = {
      /**
       * Symmetric ciphers.
       * @namespace
       */
      cipher: {},
      /**
       * Hash functions.  Right now only SHA256 is implemented.
       * @namespace
       */
      hash: {},
      /**
       * Key exchange functions.  Right now only SRP is implemented.
       * @namespace
       */
      keyexchange: {},
      /**
       * Cipher modes of operation.
       * @namespace
       */
      mode: {},
      /**
       * Miscellaneous.  HMAC and PBKDF2.
       * @namespace
       */
      misc: {},
      /**
       * Bit array encoders and decoders.
       * @namespace
       *
       * @description
       * The members of this namespace are functions which translate between
       * SJCL's bitArrays and other objects (usually strings).  Because it
       * isn't always clear which direction is encoding and which is decoding,
       * the method names are "fromBits" and "toBits".
       */
      codec: {},
      /**
       * Exceptions.
       * @namespace
       */
      exception: {
        /**
         * Ciphertext is corrupt.
         * @constructor
         */
        corrupt: function(message) {
          this.toString = function() {
            return "CORRUPT: " + this.message;
          };
          this.message = message;
        },
        /**
         * Invalid parameter.
         * @constructor
         */
        invalid: function(message) {
          this.toString = function() {
            return "INVALID: " + this.message;
          };
          this.message = message;
        },
        /**
         * Bug or missing feature in SJCL.
         * @constructor
         */
        bug: function(message) {
          this.toString = function() {
            return "BUG: " + this.message;
          };
          this.message = message;
        },
        /**
         * Something isn't ready.
         * @constructor
         */
        notReady: function(message) {
          this.toString = function() {
            return "NOT READY: " + this.message;
          };
          this.message = message;
        }
      }
    };
    sjcl2.bitArray = {
      /**
       * Array slices in units of bits.
       * @param {bitArray} a The array to slice.
       * @param {Number} bstart The offset to the start of the slice, in bits.
       * @param {Number} bend The offset to the end of the slice, in bits.  If this is undefined,
       * slice until the end of the array.
       * @return {bitArray} The requested slice.
       */
      bitSlice: function(a2, bstart, bend) {
        a2 = sjcl2.bitArray._shiftRight(a2.slice(bstart / 32), 32 - (bstart & 31)).slice(1);
        return bend === void 0 ? a2 : sjcl2.bitArray.clamp(a2, bend - bstart);
      },
      /**
       * Extract a number packed into a bit array.
       * @param {bitArray} a The array to slice.
       * @param {Number} bstart The offset to the start of the slice, in bits.
       * @param {Number} blength The length of the number to extract.
       * @return {Number} The requested slice.
       */
      extract: function(a2, bstart, blength) {
        var x2, sh = Math.floor(-bstart - blength & 31);
        if ((bstart + blength - 1 ^ bstart) & -32) {
          x2 = a2[bstart / 32 | 0] << 32 - sh ^ a2[bstart / 32 + 1 | 0] >>> sh;
        } else {
          x2 = a2[bstart / 32 | 0] >>> sh;
        }
        return x2 & (1 << blength) - 1;
      },
      /**
       * Concatenate two bit arrays.
       * @param {bitArray} a1 The first array.
       * @param {bitArray} a2 The second array.
       * @return {bitArray} The concatenation of a1 and a2.
       */
      concat: function(a1, a2) {
        if (a1.length === 0 || a2.length === 0) {
          return a1.concat(a2);
        }
        var last2 = a1[a1.length - 1], shift = sjcl2.bitArray.getPartial(last2);
        if (shift === 32) {
          return a1.concat(a2);
        } else {
          return sjcl2.bitArray._shiftRight(a2, shift, last2 | 0, a1.slice(0, a1.length - 1));
        }
      },
      /**
       * Find the length of an array of bits.
       * @param {bitArray} a The array.
       * @return {Number} The length of a, in bits.
       */
      bitLength: function(a2) {
        var l = a2.length, x2;
        if (l === 0) {
          return 0;
        }
        x2 = a2[l - 1];
        return (l - 1) * 32 + sjcl2.bitArray.getPartial(x2);
      },
      /**
       * Truncate an array.
       * @param {bitArray} a The array.
       * @param {Number} len The length to truncate to, in bits.
       * @return {bitArray} A new array, truncated to len bits.
       */
      clamp: function(a2, len) {
        if (a2.length * 32 < len) {
          return a2;
        }
        a2 = a2.slice(0, Math.ceil(len / 32));
        var l = a2.length;
        len = len & 31;
        if (l > 0 && len) {
          a2[l - 1] = sjcl2.bitArray.partial(len, a2[l - 1] & 2147483648 >> len - 1, 1);
        }
        return a2;
      },
      /**
       * Make a partial word for a bit array.
       * @param {Number} len The number of bits in the word.
       * @param {Number} x The bits.
       * @param {Number} [_end=0] Pass 1 if x has already been shifted to the high side.
       * @return {Number} The partial word.
       */
      partial: function(len, x2, _end) {
        if (len === 32) {
          return x2;
        }
        return (_end ? x2 | 0 : x2 << 32 - len) + len * 1099511627776;
      },
      /**
       * Get the number of bits used by a partial word.
       * @param {Number} x The partial word.
       * @return {Number} The number of bits used by the partial word.
       */
      getPartial: function(x2) {
        return Math.round(x2 / 1099511627776) || 32;
      },
      /**
       * Compare two arrays for equality in a predictable amount of time.
       * @param {bitArray} a The first array.
       * @param {bitArray} b The second array.
       * @return {boolean} true if a == b; false otherwise.
       */
      equal: function(a2, b2) {
        if (sjcl2.bitArray.bitLength(a2) !== sjcl2.bitArray.bitLength(b2)) {
          return false;
        }
        var x2 = 0, i;
        for (i = 0; i < a2.length; i++) {
          x2 |= a2[i] ^ b2[i];
        }
        return x2 === 0;
      },
      /** Shift an array right.
       * @param {bitArray} a The array to shift.
       * @param {Number} shift The number of bits to shift.
       * @param {Number} [carry=0] A byte to carry in
       * @param {bitArray} [out=[]] An array to prepend to the output.
       * @private
       */
      _shiftRight: function(a2, shift, carry, out) {
        var i, last2 = 0, shift2;
        if (out === void 0) {
          out = [];
        }
        for (; shift >= 32; shift -= 32) {
          out.push(carry);
          carry = 0;
        }
        if (shift === 0) {
          return out.concat(a2);
        }
        for (i = 0; i < a2.length; i++) {
          out.push(carry | a2[i] >>> shift);
          carry = a2[i] << 32 - shift;
        }
        last2 = a2.length ? a2[a2.length - 1] : 0;
        shift2 = sjcl2.bitArray.getPartial(last2);
        out.push(sjcl2.bitArray.partial(shift + shift2 & 31, shift + shift2 > 32 ? carry : out.pop(), 1));
        return out;
      },
      /** xor a block of 4 words together.
       * @private
       */
      _xor4: function(x2, y) {
        return [x2[0] ^ y[0], x2[1] ^ y[1], x2[2] ^ y[2], x2[3] ^ y[3]];
      },
      /** byteswap a word array inplace.
       * (does not handle partial words)
       * @param {sjcl.bitArray} a word array
       * @return {sjcl.bitArray} byteswapped array
       */
      byteswapM: function(a2) {
        var i, v2, m = 65280;
        for (i = 0; i < a2.length; ++i) {
          v2 = a2[i];
          a2[i] = v2 >>> 24 | v2 >>> 8 & m | (v2 & m) << 8 | v2 << 24;
        }
        return a2;
      }
    };
    sjcl2.codec.utf8String = {
      /** Convert from a bitArray to a UTF-8 string. */
      fromBits: function(arr) {
        var out = "", bl = sjcl2.bitArray.bitLength(arr), i, tmp;
        for (i = 0; i < bl / 8; i++) {
          if ((i & 3) === 0) {
            tmp = arr[i / 4];
          }
          out += String.fromCharCode(tmp >>> 8 >>> 8 >>> 8);
          tmp <<= 8;
        }
        return decodeURIComponent(escape(out));
      },
      /** Convert from a UTF-8 string to a bitArray. */
      toBits: function(str) {
        str = unescape(encodeURIComponent(str));
        var out = [], i, tmp = 0;
        for (i = 0; i < str.length; i++) {
          tmp = tmp << 8 | str.charCodeAt(i);
          if ((i & 3) === 3) {
            out.push(tmp);
            tmp = 0;
          }
        }
        if (i & 3) {
          out.push(sjcl2.bitArray.partial(8 * (i & 3), tmp));
        }
        return out;
      }
    };
    sjcl2.codec.hex = {
      /** Convert from a bitArray to a hex string. */
      fromBits: function(arr) {
        var out = "", i;
        for (i = 0; i < arr.length; i++) {
          out += ((arr[i] | 0) + 263882790666240).toString(16).substr(4);
        }
        return out.substr(0, sjcl2.bitArray.bitLength(arr) / 4);
      },
      /** Convert from a hex string to a bitArray. */
      toBits: function(str) {
        var i, out = [], len;
        str = str.replace(/\s|0x/g, "");
        len = str.length;
        str = str + "00000000";
        for (i = 0; i < str.length; i += 8) {
          out.push(parseInt(str.substr(i, 8), 16) ^ 0);
        }
        return sjcl2.bitArray.clamp(out, len * 4);
      }
    };
    sjcl2.hash.sha256 = function(hash) {
      if (!this._key[0]) {
        this._precompute();
      }
      if (hash) {
        this._h = hash._h.slice(0);
        this._buffer = hash._buffer.slice(0);
        this._length = hash._length;
      } else {
        this.reset();
      }
    };
    sjcl2.hash.sha256.hash = function(data) {
      return new sjcl2.hash.sha256().update(data).finalize();
    };
    sjcl2.hash.sha256.prototype = {
      /**
       * The hash's block size, in bits.
       * @constant
       */
      blockSize: 512,
      /**
       * Reset the hash state.
       * @return this
       */
      reset: function() {
        this._h = this._init.slice(0);
        this._buffer = [];
        this._length = 0;
        return this;
      },
      /**
       * Input several words to the hash.
       * @param {bitArray|String} data the data to hash.
       * @return this
       */
      update: function(data) {
        if (typeof data === "string") {
          data = sjcl2.codec.utf8String.toBits(data);
        }
        var i, b2 = this._buffer = sjcl2.bitArray.concat(this._buffer, data), ol = this._length, nl = this._length = ol + sjcl2.bitArray.bitLength(data);
        if (nl > 9007199254740991) {
          throw new sjcl2.exception.invalid("Cannot hash more than 2^53 - 1 bits");
        }
        if (typeof Uint32Array !== "undefined") {
          var c = new Uint32Array(b2);
          var j2 = 0;
          for (i = 512 + ol - (512 + ol & 511); i <= nl; i += 512) {
            this._block(c.subarray(16 * j2, 16 * (j2 + 1)));
            j2 += 1;
          }
          b2.splice(0, 16 * j2);
        } else {
          for (i = 512 + ol - (512 + ol & 511); i <= nl; i += 512) {
            this._block(b2.splice(0, 16));
          }
        }
        return this;
      },
      /**
       * Complete hashing and output the hash value.
       * @return {bitArray} The hash value, an array of 8 big-endian words.
       */
      finalize: function() {
        var i, b2 = this._buffer, h = this._h;
        b2 = sjcl2.bitArray.concat(b2, [sjcl2.bitArray.partial(1, 1)]);
        for (i = b2.length + 2; i & 15; i++) {
          b2.push(0);
        }
        b2.push(Math.floor(this._length / 4294967296));
        b2.push(this._length | 0);
        while (b2.length) {
          this._block(b2.splice(0, 16));
        }
        this.reset();
        return h;
      },
      /**
       * The SHA-256 initialization vector, to be precomputed.
       * @private
       */
      _init: [],
      /*
      _init:[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],
      */
      /**
       * The SHA-256 hash key, to be precomputed.
       * @private
       */
      _key: [],
      /*
      _key:
        [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
         0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
         0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
         0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
         0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
         0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
         0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
         0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2],
      */
      /**
       * Function to precompute _init and _key.
       * @private
       */
      _precompute: function() {
        var i = 0, prime = 2, factor, isPrime;
        function frac(x2) {
          return (x2 - Math.floor(x2)) * 4294967296 | 0;
        }
        for (; i < 64; prime++) {
          isPrime = true;
          for (factor = 2; factor * factor <= prime; factor++) {
            if (prime % factor === 0) {
              isPrime = false;
              break;
            }
          }
          if (isPrime) {
            if (i < 8) {
              this._init[i] = frac(Math.pow(prime, 1 / 2));
            }
            this._key[i] = frac(Math.pow(prime, 1 / 3));
            i++;
          }
        }
      },
      /**
       * Perform one cycle of SHA-256.
       * @param {Uint32Array|bitArray} w one block of words.
       * @private
       */
      _block: function(w2) {
        var i, tmp, a2, b2, h = this._h, k = this._key, h0 = h[0], h1 = h[1], h2 = h[2], h3 = h[3], h4 = h[4], h5 = h[5], h6 = h[6], h7 = h[7];
        for (i = 0; i < 64; i++) {
          if (i < 16) {
            tmp = w2[i];
          } else {
            a2 = w2[i + 1 & 15];
            b2 = w2[i + 14 & 15];
            tmp = w2[i & 15] = (a2 >>> 7 ^ a2 >>> 18 ^ a2 >>> 3 ^ a2 << 25 ^ a2 << 14) + (b2 >>> 17 ^ b2 >>> 19 ^ b2 >>> 10 ^ b2 << 15 ^ b2 << 13) + w2[i & 15] + w2[i + 9 & 15] | 0;
          }
          tmp = tmp + h7 + (h4 >>> 6 ^ h4 >>> 11 ^ h4 >>> 25 ^ h4 << 26 ^ h4 << 21 ^ h4 << 7) + (h6 ^ h4 & (h5 ^ h6)) + k[i];
          h7 = h6;
          h6 = h5;
          h5 = h4;
          h4 = h3 + tmp | 0;
          h3 = h2;
          h2 = h1;
          h1 = h0;
          h0 = tmp + (h1 & h2 ^ h3 & (h1 ^ h2)) + (h1 >>> 2 ^ h1 >>> 13 ^ h1 >>> 22 ^ h1 << 30 ^ h1 << 19 ^ h1 << 10) | 0;
        }
        h[0] = h[0] + h0 | 0;
        h[1] = h[1] + h1 | 0;
        h[2] = h[2] + h2 | 0;
        h[3] = h[3] + h3 | 0;
        h[4] = h[4] + h4 | 0;
        h[5] = h[5] + h5 | 0;
        h[6] = h[6] + h6 | 0;
        h[7] = h[7] + h7 | 0;
      }
    };
    sjcl2.misc.hmac = function(key, Hash) {
      this._hash = Hash = Hash || sjcl2.hash.sha256;
      var exKey = [[], []], i, bs = Hash.prototype.blockSize / 32;
      this._baseHash = [new Hash(), new Hash()];
      if (key.length > bs) {
        key = Hash.hash(key);
      }
      for (i = 0; i < bs; i++) {
        exKey[0][i] = key[i] ^ 909522486;
        exKey[1][i] = key[i] ^ 1549556828;
      }
      this._baseHash[0].update(exKey[0]);
      this._baseHash[1].update(exKey[1]);
      this._resultHash = new Hash(this._baseHash[0]);
    };
    sjcl2.misc.hmac.prototype.encrypt = sjcl2.misc.hmac.prototype.mac = function(data) {
      if (!this._updated) {
        this.update(data);
        return this.digest(data);
      } else {
        throw new sjcl2.exception.invalid("encrypt on already updated hmac called!");
      }
    };
    sjcl2.misc.hmac.prototype.reset = function() {
      this._resultHash = new this._hash(this._baseHash[0]);
      this._updated = false;
    };
    sjcl2.misc.hmac.prototype.update = function(data) {
      this._updated = true;
      this._resultHash.update(data);
    };
    sjcl2.misc.hmac.prototype.digest = function() {
      var w2 = this._resultHash.finalize(), result = new this._hash(this._baseHash[1]).update(w2).finalize();
      this.reset();
      return result;
    };
    return sjcl2;
  })();

  // src/crypto.js
  function getDataKeySync(sessionKey, domainKey, inputData) {
    const hmac = new sjcl.misc.hmac(sjcl.codec.utf8String.toBits(sessionKey + domainKey), sjcl.hash.sha256);
    return sjcl.codec.hex.fromBits(hmac.encrypt(inputData));
  }

  // src/features/fingerprinting-audio.js
  var FingerprintingAudio = class extends ContentFeature {
    init(args) {
      const { sessionKey, site } = args;
      const domainKey = site.domain;
      function transformArrayData(channelData, domainKey2, sessionKey2, thisArg) {
        let { audioKey } = getCachedResponse(thisArg, args);
        if (!audioKey) {
          let cdSum = 0;
          for (const k in channelData) {
            cdSum += channelData[k];
          }
          if (cdSum === 0) {
            return;
          }
          audioKey = getDataKeySync(sessionKey2, domainKey2, cdSum);
          setCache(thisArg, args, audioKey);
        }
        iterateDataKey(audioKey, (item, byte) => {
          const itemAudioIndex = item % channelData.length;
          let factor = byte * 1e-7;
          if (byte ^ 1) {
            factor = 0 - factor;
          }
          channelData[itemAudioIndex] = channelData[itemAudioIndex] + factor;
        });
      }
      const copyFromChannelProxy = new DDGProxy(this, AudioBuffer.prototype, "copyFromChannel", {
        apply(target, thisArg, args2) {
          const [source, channelNumber, startInChannel] = args2;
          if (
            // If channelNumber is longer than arrayBuffer number of channels then call the default method to throw
            // @ts-expect-error - error TS18048: 'thisArg' is possibly 'undefined'
            channelNumber > thisArg.numberOfChannels || // If startInChannel is longer than the arrayBuffer length then call the default method to throw
            // @ts-expect-error - error TS18048: 'thisArg' is possibly 'undefined'
            startInChannel > thisArg.length
          ) {
            return DDGReflect.apply(target, thisArg, args2);
          }
          try {
            thisArg.getChannelData(channelNumber).slice(startInChannel).forEach((val, index) => {
              source[index] = val;
            });
          } catch {
            return DDGReflect.apply(target, thisArg, args2);
          }
        }
      });
      copyFromChannelProxy.overload();
      const cacheExpiry = 60;
      const cacheData = /* @__PURE__ */ new WeakMap();
      function getCachedResponse(thisArg, args2) {
        const data = cacheData.get(thisArg);
        const timeNow = Date.now();
        if (data && data.args === JSON.stringify(args2) && data.expires > timeNow) {
          data.expires = timeNow + cacheExpiry;
          cacheData.set(thisArg, data);
          return data;
        }
        return { audioKey: null };
      }
      function setCache(thisArg, args2, audioKey) {
        cacheData.set(thisArg, { args: JSON.stringify(args2), expires: Date.now() + cacheExpiry, audioKey });
      }
      const getChannelDataProxy = new DDGProxy(this, AudioBuffer.prototype, "getChannelData", {
        apply(target, thisArg, args2) {
          const channelData = DDGReflect.apply(target, thisArg, args2);
          try {
            transformArrayData(channelData, domainKey, sessionKey, thisArg, args2);
          } catch {
          }
          return channelData;
        }
      });
      getChannelDataProxy.overload();
      const audioMethods = ["getByteTimeDomainData", "getFloatTimeDomainData", "getByteFrequencyData", "getFloatFrequencyData"];
      for (const methodName of audioMethods) {
        const proxy = new DDGProxy(this, AnalyserNode.prototype, methodName, {
          apply(target, thisArg, args2) {
            DDGReflect.apply(target, thisArg, args2);
            try {
              transformArrayData(args2[0], domainKey, sessionKey, thisArg, args2);
            } catch {
            }
          }
        });
        proxy.overload();
      }
    }
  };

  // src/features/fingerprinting-battery.js
  var FingerprintingBattery = class extends ContentFeature {
    init() {
      if (globalThis.navigator.getBattery) {
        const BatteryManager = globalThis.BatteryManager;
        const spoofedValues = {
          charging: true,
          chargingTime: 0,
          dischargingTime: Infinity,
          level: 1
        };
        const eventProperties = ["onchargingchange", "onchargingtimechange", "ondischargingtimechange", "onlevelchange"];
        for (const [prop, val] of Object.entries(spoofedValues)) {
          try {
            this.defineProperty(BatteryManager.prototype, prop, {
              enumerable: true,
              configurable: true,
              get: () => {
                return val;
              }
            });
          } catch (e) {
          }
        }
        for (const eventProp of eventProperties) {
          try {
            this.defineProperty(BatteryManager.prototype, eventProp, {
              enumerable: true,
              configurable: true,
              set: (x2) => x2,
              // noop
              get: () => {
                return null;
              }
            });
          } catch (e) {
          }
        }
      }
    }
  };

  // src/canvas.js
  var import_seedrandom = __toESM(require_seedrandom2(), 1);
  function computeOffScreenCanvas(canvas, domainKey, sessionKey, getImageDataProxy, ctx) {
    if (!ctx) {
      ctx = canvas.getContext("2d");
    }
    const offScreenCanvas = document.createElement("canvas");
    offScreenCanvas.width = canvas.width;
    offScreenCanvas.height = canvas.height;
    const offScreenCtx = offScreenCanvas.getContext("2d");
    let rasterizedCtx = ctx;
    const rasterizeToCanvas = !(ctx instanceof CanvasRenderingContext2D);
    if (rasterizeToCanvas) {
      rasterizedCtx = offScreenCtx;
      offScreenCtx.drawImage(canvas, 0, 0);
    }
    let imageData = getImageDataProxy._native.apply(rasterizedCtx, [0, 0, canvas.width, canvas.height]);
    imageData = modifyPixelData(imageData, sessionKey, domainKey, canvas.width);
    if (rasterizeToCanvas) {
      clearCanvas(offScreenCtx);
    }
    offScreenCtx.putImageData(imageData, 0, 0);
    return { offScreenCanvas, offScreenCtx };
  }
  function clearCanvas(canvasContext) {
    canvasContext.save();
    canvasContext.globalCompositeOperation = "destination-out";
    canvasContext.fillStyle = "rgb(255,255,255)";
    canvasContext.fillRect(0, 0, canvasContext.canvas.width, canvasContext.canvas.height);
    canvasContext.restore();
  }
  function modifyPixelData(imageData, domainKey, sessionKey, width) {
    const d = imageData.data;
    const length = d.length / 4;
    let checkSum = 0;
    const mappingArray = [];
    for (let i = 0; i < length; i += 4) {
      if (!shouldIgnorePixel(d, i) && !adjacentSame(d, i, width)) {
        mappingArray.push(i);
        checkSum += d[i] + d[i + 1] + d[i + 2] + d[i + 3];
      }
    }
    const windowHash = getDataKeySync(sessionKey, domainKey, checkSum);
    const rng = new import_seedrandom.default(windowHash);
    for (let i = 0; i < mappingArray.length; i++) {
      const rand = rng();
      const byte = Math.floor(rand * 10);
      const channel = byte % 3;
      const pixelCanvasIndex = mappingArray[i] + channel;
      d[pixelCanvasIndex] = d[pixelCanvasIndex] ^ byte & 1;
    }
    return imageData;
  }
  function adjacentSame(imageData, index, width) {
    const widthPixel = width * 4;
    const x2 = index % widthPixel;
    const maxLength = imageData.length;
    if (x2 < widthPixel) {
      const right = index + 4;
      if (!pixelsSame(imageData, index, right)) {
        return false;
      }
      const diagonalRightUp = right - widthPixel;
      if (diagonalRightUp > 0 && !pixelsSame(imageData, index, diagonalRightUp)) {
        return false;
      }
      const diagonalRightDown = right + widthPixel;
      if (diagonalRightDown < maxLength && !pixelsSame(imageData, index, diagonalRightDown)) {
        return false;
      }
    }
    if (x2 > 0) {
      const left = index - 4;
      if (!pixelsSame(imageData, index, left)) {
        return false;
      }
      const diagonalLeftUp = left - widthPixel;
      if (diagonalLeftUp > 0 && !pixelsSame(imageData, index, diagonalLeftUp)) {
        return false;
      }
      const diagonalLeftDown = left + widthPixel;
      if (diagonalLeftDown < maxLength && !pixelsSame(imageData, index, diagonalLeftDown)) {
        return false;
      }
    }
    const up = index - widthPixel;
    if (up > 0 && !pixelsSame(imageData, index, up)) {
      return false;
    }
    const down = index + widthPixel;
    if (down < maxLength && !pixelsSame(imageData, index, down)) {
      return false;
    }
    return true;
  }
  function pixelsSame(imageData, index, index2) {
    return imageData[index] === imageData[index2] && imageData[index + 1] === imageData[index2 + 1] && imageData[index + 2] === imageData[index2 + 2] && imageData[index + 3] === imageData[index2 + 3];
  }
  function shouldIgnorePixel(imageData, index) {
    if (imageData[index + 3] === 0) {
      return true;
    }
    return false;
  }

  // src/features/fingerprinting-canvas.js
  var FingerprintingCanvas = class extends ContentFeature {
    init(args) {
      const { sessionKey, site } = args;
      const domainKey = site.domain;
      const additionalEnabledCheck = this.getFeatureSettingEnabled("additionalEnabledCheck");
      if (!additionalEnabledCheck) {
        return;
      }
      const supportsWebGl = this.getFeatureSettingEnabled("webGl");
      const unsafeCanvases = /* @__PURE__ */ new WeakSet();
      const canvasContexts = /* @__PURE__ */ new WeakMap();
      const canvasCache = /* @__PURE__ */ new WeakMap();
      function clearCache(canvas) {
        canvasCache.delete(canvas);
      }
      function treatAsUnsafe(canvas) {
        unsafeCanvases.add(canvas);
        clearCache(canvas);
      }
      const proxy = new DDGProxy(this, HTMLCanvasElement.prototype, "getContext", {
        apply(target, thisArg, args2) {
          const context = DDGReflect.apply(target, thisArg, args2);
          try {
            canvasContexts.set(thisArg, context);
          } catch {
          }
          return context;
        }
      });
      proxy.overload();
      const safeMethods = this.getFeatureSetting("safeMethods") ?? ["putImageData", "drawImage"];
      for (const methodName of safeMethods) {
        const safeMethodProxy = new DDGProxy(this, CanvasRenderingContext2D.prototype, methodName, {
          apply(target, thisArg, args2) {
            if (methodName === "drawImage" && args2[0] && args2[0] instanceof HTMLCanvasElement) {
              treatAsUnsafe(args2[0]);
            } else {
              clearCache(thisArg.canvas);
            }
            return DDGReflect.apply(target, thisArg, args2);
          }
        });
        safeMethodProxy.overload();
      }
      const unsafeMethods = this.getFeatureSetting("unsafeMethods") ?? [
        "strokeRect",
        "bezierCurveTo",
        "quadraticCurveTo",
        "arcTo",
        "ellipse",
        "rect",
        "fill",
        "stroke",
        "lineTo",
        "beginPath",
        "closePath",
        "arc",
        "fillText",
        "fillRect",
        "strokeText",
        "createConicGradient",
        "createLinearGradient",
        "createRadialGradient",
        "createPattern"
      ];
      for (const methodName of unsafeMethods) {
        if (methodName in CanvasRenderingContext2D.prototype) {
          const unsafeProxy = new DDGProxy(this, CanvasRenderingContext2D.prototype, methodName, {
            apply(target, thisArg, args2) {
              treatAsUnsafe(thisArg.canvas);
              return DDGReflect.apply(target, thisArg, args2);
            }
          });
          unsafeProxy.overload();
        }
      }
      if (supportsWebGl) {
        const unsafeGlMethods = this.getFeatureSetting("unsafeGlMethods") ?? [
          "commit",
          "compileShader",
          "shaderSource",
          "attachShader",
          "createProgram",
          "linkProgram",
          "drawElements",
          "drawArrays"
        ];
        const glContexts = [WebGLRenderingContext];
        if ("WebGL2RenderingContext" in globalThis) {
          glContexts.push(WebGL2RenderingContext);
        }
        for (const context of glContexts) {
          for (const methodName of unsafeGlMethods) {
            if (methodName in context.prototype) {
              const unsafeProxy = new DDGProxy(this, context.prototype, methodName, {
                apply(target, thisArg, args2) {
                  treatAsUnsafe(thisArg.canvas);
                  return DDGReflect.apply(target, thisArg, args2);
                }
              });
              unsafeProxy.overload();
            }
          }
        }
      }
      const getImageDataProxy = new DDGProxy(this, CanvasRenderingContext2D.prototype, "getImageData", {
        apply(target, thisArg, args2) {
          if (!unsafeCanvases.has(thisArg.canvas)) {
            return DDGReflect.apply(target, thisArg, args2);
          }
          try {
            const { offScreenCtx } = getCachedOffScreenCanvasOrCompute(thisArg.canvas, domainKey, sessionKey);
            return DDGReflect.apply(target, offScreenCtx, args2);
          } catch {
          }
          return DDGReflect.apply(target, thisArg, args2);
        }
      });
      getImageDataProxy.overload();
      function getCachedOffScreenCanvasOrCompute(canvas, domainKey2, sessionKey2) {
        let result;
        if (canvasCache.has(canvas)) {
          result = canvasCache.get(canvas);
        } else {
          const ctx = canvasContexts.get(canvas);
          result = computeOffScreenCanvas(canvas, domainKey2, sessionKey2, getImageDataProxy, ctx);
          canvasCache.set(canvas, result);
        }
        return result;
      }
      const canvasMethods = this.getFeatureSetting("canvasMethods") ?? ["toDataURL", "toBlob"];
      for (const methodName of canvasMethods) {
        const proxy2 = new DDGProxy(this, HTMLCanvasElement.prototype, methodName, {
          apply(target, thisArg, args2) {
            if (!unsafeCanvases.has(thisArg)) {
              return DDGReflect.apply(target, thisArg, args2);
            }
            try {
              const { offScreenCanvas } = getCachedOffScreenCanvasOrCompute(thisArg, domainKey, sessionKey);
              return DDGReflect.apply(target, offScreenCanvas, args2);
            } catch {
              return DDGReflect.apply(target, thisArg, args2);
            }
          }
        });
        proxy2.overload();
      }
    }
  };

  // src/features/google-rejected.js
  var GoogleRejected = class extends ContentFeature {
    init() {
      try {
        if ("browsingTopics" in Document.prototype) {
          delete Document.prototype.browsingTopics;
        }
        if ("joinAdInterestGroup" in Navigator.prototype) {
          delete Navigator.prototype.joinAdInterestGroup;
        }
        if ("leaveAdInterestGroup" in Navigator.prototype) {
          delete Navigator.prototype.leaveAdInterestGroup;
        }
        if ("updateAdInterestGroups" in Navigator.prototype) {
          delete Navigator.prototype.updateAdInterestGroups;
        }
        if ("runAdAuction" in Navigator.prototype) {
          delete Navigator.prototype.runAdAuction;
        }
        if ("adAuctionComponents" in Navigator.prototype) {
          delete Navigator.prototype.adAuctionComponents;
        }
      } catch {
      }
    }
  };

  // src/features/gpc.js
  var GlobalPrivacyControl = class extends ContentFeature {
    init(args) {
      try {
        if (args.globalPrivacyControlValue) {
          if (navigator.globalPrivacyControl) return;
          this.defineProperty(Navigator.prototype, "globalPrivacyControl", {
            get: () => true,
            configurable: true,
            enumerable: true
          });
        } else {
          if (typeof navigator.globalPrivacyControl !== "undefined") return;
          this.defineProperty(Navigator.prototype, "globalPrivacyControl", {
            get: () => false,
            configurable: true,
            enumerable: true
          });
        }
      } catch {
      }
    }
  };

  // src/features/fingerprinting-hardware.js
  var FingerprintingHardware = class extends ContentFeature {
    init() {
      this.wrapProperty(globalThis.Navigator.prototype, "keyboard", {
        get: () => {
          return this.getFeatureAttr("keyboard");
        }
      });
      this.wrapProperty(globalThis.Navigator.prototype, "hardwareConcurrency", {
        get: () => {
          return this.getFeatureAttr("hardwareConcurrency", 2);
        }
      });
      this.wrapProperty(globalThis.Navigator.prototype, "deviceMemory", {
        get: () => {
          return this.getFeatureAttr("deviceMemory", 8);
        }
      });
    }
  };

  // src/features/referrer.js
  var Referrer = class extends ContentFeature {
    init() {
      if (document.referrer && new URL(document.URL).hostname !== new URL(document.referrer).hostname) {
        const trimmedReferer = new URL(document.referrer).origin + "/";
        this.wrapProperty(Document.prototype, "referrer", {
          get: () => trimmedReferer
        });
      }
    }
  };

  // src/features/fingerprinting-screen-size.js
  var FingerprintingScreenSize = class extends ContentFeature {
    constructor() {
      super(...arguments);
      __publicField(this, "origPropertyValues", {});
    }
    init() {
      this.origPropertyValues.availTop = globalThis.screen.availTop;
      this.wrapProperty(globalThis.Screen.prototype, "availTop", {
        get: () => this.getFeatureAttr("availTop", 0)
      });
      this.origPropertyValues.availLeft = globalThis.screen.availLeft;
      this.wrapProperty(globalThis.Screen.prototype, "availLeft", {
        get: () => this.getFeatureAttr("availLeft", 0)
      });
      this.origPropertyValues.availWidth = globalThis.screen.availWidth;
      const forcedAvailWidthValue = globalThis.screen.width;
      this.wrapProperty(globalThis.Screen.prototype, "availWidth", {
        get: () => forcedAvailWidthValue
      });
      this.origPropertyValues.availHeight = globalThis.screen.availHeight;
      const forcedAvailHeightValue = globalThis.screen.height;
      this.wrapProperty(globalThis.Screen.prototype, "availHeight", {
        get: () => forcedAvailHeightValue
      });
      this.origPropertyValues.colorDepth = globalThis.screen.colorDepth;
      this.wrapProperty(globalThis.Screen.prototype, "colorDepth", {
        get: () => this.getFeatureAttr("colorDepth", 24)
      });
      this.origPropertyValues.pixelDepth = globalThis.screen.pixelDepth;
      this.wrapProperty(globalThis.Screen.prototype, "pixelDepth", {
        get: () => this.getFeatureAttr("pixelDepth", 24)
      });
      globalThis.window.addEventListener("resize", () => {
        this.setWindowDimensions();
      });
      this.setWindowDimensions();
    }
    /**
     * normalize window dimensions, if more than one monitor is in play.
     *  X/Y values are set in the browser based on distance to the main monitor top or left, which
     * can mean second or more monitors have very large or negative values. This function maps a given
     * given coordinate value to the proper place on the main screen.
     */
    normalizeWindowDimension(value, targetDimension) {
      if (value > targetDimension) {
        return value % targetDimension;
      }
      if (value < 0) {
        return targetDimension + value;
      }
      return value;
    }
    setWindowPropertyValue(property, value) {
      try {
        this.defineProperty(globalThis, property, {
          get: () => value,
          set: () => {
          },
          configurable: true,
          enumerable: true
        });
      } catch (e) {
      }
    }
    /**
     * Fix window dimensions. The extension runs in a different JS context than the
     * page, so we can inject the correct screen values as the window is resized,
     * ensuring that no information is leaked as the dimensions change, but also that the
     * values change correctly for valid use cases.
     */
    setWindowDimensions() {
      try {
        const window2 = globalThis;
        const top = globalThis.top;
        const normalizedY = this.normalizeWindowDimension(window2.screenY, window2.screen.height);
        const normalizedX = this.normalizeWindowDimension(window2.screenX, window2.screen.width);
        if (normalizedY <= this.origPropertyValues.availTop) {
          this.setWindowPropertyValue("screenY", 0);
          this.setWindowPropertyValue("screenTop", 0);
        } else {
          this.setWindowPropertyValue("screenY", normalizedY);
          this.setWindowPropertyValue("screenTop", normalizedY);
        }
        if (top.window.outerHeight >= this.origPropertyValues.availHeight - 1) {
          this.setWindowPropertyValue("outerHeight", top.window.screen.height);
        } else {
          try {
            this.setWindowPropertyValue("outerHeight", top.window.outerHeight);
          } catch (e) {
          }
        }
        if (normalizedX <= this.origPropertyValues.availLeft) {
          this.setWindowPropertyValue("screenX", 0);
          this.setWindowPropertyValue("screenLeft", 0);
        } else {
          this.setWindowPropertyValue("screenX", normalizedX);
          this.setWindowPropertyValue("screenLeft", normalizedX);
        }
        if (top.window.outerWidth >= this.origPropertyValues.availWidth - 1) {
          this.setWindowPropertyValue("outerWidth", top.window.screen.width);
        } else {
          try {
            this.setWindowPropertyValue("outerWidth", top.window.outerWidth);
          } catch (e) {
          }
        }
      } catch (e) {
      }
    }
  };

  // src/features/fingerprinting-temporary-storage.js
  var FingerprintingTemporaryStorage = class extends ContentFeature {
    init() {
      const navigator2 = globalThis.navigator;
      const Navigator2 = globalThis.Navigator;
      if (navigator2.webkitTemporaryStorage) {
        try {
          const org = navigator2.webkitTemporaryStorage.queryUsageAndQuota;
          const tStorage = navigator2.webkitTemporaryStorage;
          tStorage.queryUsageAndQuota = function queryUsageAndQuota(callback, err) {
            const modifiedCallback = function(usedBytes, grantedBytes) {
              const maxBytesGranted = 4 * 1024 * 1024 * 1024;
              const spoofedGrantedBytes = Math.min(grantedBytes, maxBytesGranted);
              callback(usedBytes, spoofedGrantedBytes);
            };
            org.call(navigator2.webkitTemporaryStorage, modifiedCallback, err);
          };
          this.defineProperty(Navigator2.prototype, "webkitTemporaryStorage", {
            get: () => tStorage,
            enumerable: true,
            configurable: true
          });
        } catch (e) {
        }
      }
    }
  };

  // src/type-utils.js
  function isObject(input) {
    return toString.call(input) === "[object Object]";
  }
  function isString(input) {
    return typeof input === "string";
  }

  // src/features/message-bridge/schema.js
  var _InstallProxy = class _InstallProxy {
    get name() {
      return _InstallProxy.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.id
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.id)) return null;
      return new _InstallProxy({ featureName: params.featureName, id: params.id });
    }
  };
  __publicField(_InstallProxy, "NAME", "INSTALL_BRIDGE");
  var InstallProxy = _InstallProxy;
  var _DidInstall = class _DidInstall {
    get name() {
      return _DidInstall.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.id
     */
    constructor(params) {
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.id)) return null;
      return new _DidInstall({ id: params.id });
    }
  };
  __publicField(_DidInstall, "NAME", "DID_INSTALL");
  var DidInstall = _DidInstall;
  var _ProxyRequest = class _ProxyRequest {
    get name() {
      return _ProxyRequest.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.method = params.method;
      this.params = params.params;
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.method)) return null;
      if (!isString(params.id)) return null;
      if (params.params && !isObject(params.params)) return null;
      return new _ProxyRequest({
        featureName: params.featureName,
        method: params.method,
        params: params.params,
        id: params.id
      });
    }
  };
  __publicField(_ProxyRequest, "NAME", "PROXY_REQUEST");
  var ProxyRequest = _ProxyRequest;
  var _ProxyResponse = class _ProxyResponse {
    get name() {
      return _ProxyResponse.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {string} params.id
     * @param {Record<string, any>} [params.result]
     * @param {import("@duckduckgo/messaging").MessageError} [params.error]
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.method = params.method;
      this.result = params.result;
      this.error = params.error;
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.method)) return null;
      if (!isString(params.id)) return null;
      if (params.result && !isObject(params.result)) return null;
      if (params.error && !isObject(params.error)) return null;
      return new _ProxyResponse({
        featureName: params.featureName,
        method: params.method,
        result: params.result,
        error: params.error,
        id: params.id
      });
    }
  };
  __publicField(_ProxyResponse, "NAME", "PROXY_RESPONSE");
  var ProxyResponse = _ProxyResponse;
  var _ProxyNotification = class _ProxyNotification {
    get name() {
      return _ProxyNotification.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.method
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.method = params.method;
      this.params = params.params;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.method)) return null;
      if (params.params && !isObject(params.params)) return null;
      return new _ProxyNotification({
        featureName: params.featureName,
        method: params.method,
        params: params.params
      });
    }
  };
  __publicField(_ProxyNotification, "NAME", "PROXY_NOTIFICATION");
  var ProxyNotification = _ProxyNotification;
  var _SubscriptionRequest = class _SubscriptionRequest {
    get name() {
      return _SubscriptionRequest.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @param {string} params.id
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.subscriptionName = params.subscriptionName;
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.subscriptionName)) return null;
      if (!isString(params.id)) return null;
      return new _SubscriptionRequest({
        featureName: params.featureName,
        subscriptionName: params.subscriptionName,
        id: params.id
      });
    }
  };
  __publicField(_SubscriptionRequest, "NAME", "SUBSCRIPTION_REQUEST");
  var SubscriptionRequest = _SubscriptionRequest;
  var _SubscriptionResponse = class _SubscriptionResponse {
    get name() {
      return _SubscriptionResponse.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.featureName
     * @param {string} params.subscriptionName
     * @param {string} params.id
     * @param {Record<string, any>} [params.params]
     */
    constructor(params) {
      this.featureName = params.featureName;
      this.subscriptionName = params.subscriptionName;
      this.id = params.id;
      this.params = params.params;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.featureName)) return null;
      if (!isString(params.subscriptionName)) return null;
      if (!isString(params.id)) return null;
      if (params.params && !isObject(params.params)) return null;
      return new _SubscriptionResponse({
        featureName: params.featureName,
        subscriptionName: params.subscriptionName,
        params: params.params,
        id: params.id
      });
    }
  };
  __publicField(_SubscriptionResponse, "NAME", "SUBSCRIPTION_RESPONSE");
  var SubscriptionResponse = _SubscriptionResponse;
  var _SubscriptionUnsubscribe = class _SubscriptionUnsubscribe {
    get name() {
      return _SubscriptionUnsubscribe.NAME;
    }
    /**
     * @param {object} params
     * @param {string} params.id
     */
    constructor(params) {
      this.id = params.id;
    }
    /**
     * @param {unknown} params
     */
    static create(params) {
      if (!isObject(params)) return null;
      if (!isString(params.id)) return null;
      return new _SubscriptionUnsubscribe({
        id: params.id
      });
    }
  };
  __publicField(_SubscriptionUnsubscribe, "NAME", "SUBSCRIPTION_UNSUBSCRIBE");
  var SubscriptionUnsubscribe = _SubscriptionUnsubscribe;

  // src/features/message-bridge/create-page-world-bridge.js
  var captured = captured_globals_exports;
  var ERROR_MSG = "Did not install Message Bridge";
  function createPageWorldBridge(featureName, token) {
    if (typeof featureName !== "string" || !token) {
      throw new captured.Error(ERROR_MSG);
    }
    if (isBeingFramed() || !isSecureContext) {
      throw new captured.Error(ERROR_MSG);
    }
    const appendToken = (eventName) => {
      return `${eventName}-${token}`;
    };
    const send = (incoming) => {
      if (!token) return;
      const event = new captured.CustomEvent(appendToken(incoming.name), { detail: incoming });
      captured.dispatchEvent(event);
    };
    let installed = false;
    const id = random();
    const evt = new InstallProxy({ featureName, id });
    const evtName = appendToken(DidInstall.NAME + "-" + id);
    const didInstall = (e) => {
      const result = DidInstall.create(e.detail);
      if (result && result.id === id) {
        installed = true;
      }
      captured.removeEventListener(evtName, didInstall);
    };
    captured.addEventListener(evtName, didInstall);
    send(evt);
    if (!installed) {
      throw new captured.Error(ERROR_MSG);
    }
    return createMessagingInterface(featureName, send, appendToken);
  }
  function random() {
    if (typeof captured.randomUUID !== "function") throw new Error("unreachable");
    return captured.randomUUID();
  }
  function createMessagingInterface(featureName, send, appendToken) {
    return {
      /**
       * @param {string} method
       * @param {Record<string, any>} params
       */
      notify(method, params) {
        send(
          new ProxyNotification({
            method,
            params,
            featureName
          })
        );
      },
      /**
       * @param {string} method
       * @param {Record<string, any>} params
       * @returns {Promise<any>}
       */
      request(method, params) {
        const id = random();
        send(
          new ProxyRequest({
            method,
            params,
            featureName,
            id
          })
        );
        return new Promise((resolve, reject) => {
          const responseName = appendToken(ProxyResponse.NAME + "-" + id);
          const handler = (e) => {
            const response = ProxyResponse.create(e.detail);
            if (response && response.id === id) {
              if ("error" in response && response.error) {
                reject(new Error(response.error.message));
              } else if ("result" in response) {
                resolve(response.result);
              }
              captured.removeEventListener(responseName, handler);
            }
          };
          captured.addEventListener(responseName, handler);
        });
      },
      /**
       * @param {string} name
       * @param {(d: any) => void} callback
       * @returns {() => void}
       */
      subscribe(name, callback) {
        const id = random();
        send(
          new SubscriptionRequest({
            subscriptionName: name,
            featureName,
            id
          })
        );
        const handler = (e) => {
          const subscriptionEvent = SubscriptionResponse.create(e.detail);
          if (subscriptionEvent) {
            const { id: eventId, params } = subscriptionEvent;
            if (eventId === id) {
              callback(params);
            }
          }
        };
        const type = appendToken(SubscriptionResponse.NAME + "-" + id);
        captured.addEventListener(type, handler);
        return () => {
          captured.removeEventListener(type, handler);
          const evt = new SubscriptionUnsubscribe({ id });
          send(evt);
        };
      }
    };
  }

  // src/features/navigator-interface.js
  var NavigatorInterface = class extends ContentFeature {
    load(args) {
      if (this.matchConditionalFeatureSetting("privilegedDomains").length) {
        this.injectNavigatorInterface(args);
      }
    }
    init(args) {
      this.injectNavigatorInterface(args);
    }
    injectNavigatorInterface(args) {
      try {
        if (navigator.duckduckgo) {
          return;
        }
        if (!args.platform || !args.platform.name) {
          return;
        }
        this.defineProperty(Navigator.prototype, "duckduckgo", {
          value: {
            platform: args.platform.name,
            isDuckDuckGo() {
              return DDGPromise.resolve(true);
            },
            /**
             * @import { MessagingInterface } from "./message-bridge/schema.js"
             * @param {string} featureName
             * @return {MessagingInterface}
             * @throws {Error}
             */
            createMessageBridge(featureName) {
              return createPageWorldBridge(featureName, args.messageSecret);
            }
          },
          enumerable: true,
          configurable: false,
          writable: false
        });
      } catch {
      }
    }
  };

  // src/features/element-hiding.js
  var adLabelStrings = [];
  var parser = new DOMParser();
  var hiddenElements = /* @__PURE__ */ new WeakMap();
  var modifiedElements = /* @__PURE__ */ new WeakMap();
  var appliedRules = /* @__PURE__ */ new Set();
  var shouldInjectStyleTag = false;
  var mediaAndFormSelectors = "video,canvas,embed,object,audio,map,form,input,textarea,select,option,button";
  var hideTimeouts = [0, 100, 300, 500, 1e3, 2e3, 3e3];
  var unhideTimeouts = [1250, 2250, 3e3];
  var featureInstance;
  function collapseDomNode(element, rule, previousElement) {
    if (!element) {
      return;
    }
    const type = rule.type;
    const alreadyHidden = hiddenElements.has(element);
    const alreadyModified = modifiedElements.has(element) && modifiedElements.get(element) === rule.type;
    if (alreadyHidden || alreadyModified) {
      return;
    }
    switch (type) {
      case "hide":
        hideNode(element);
        break;
      case "hide-empty":
        if (isDomNodeEmpty(element)) {
          hideNode(element);
          appliedRules.add(rule);
        }
        break;
      case "closest-empty":
        if (isDomNodeEmpty(element)) {
          collapseDomNode(element.parentNode, rule, element);
        } else if (previousElement) {
          hideNode(previousElement);
          appliedRules.add(rule);
        }
        break;
      case "modify-attr":
        modifyAttribute(element, rule.values);
        break;
      case "modify-style":
        modifyStyle(element, rule.values);
        break;
      default:
        break;
    }
  }
  function expandNonEmptyDomNode(element, rule) {
    if (!element) {
      return;
    }
    const type = rule.type;
    const alreadyHidden = hiddenElements.has(element);
    switch (type) {
      case "hide":
        break;
      case "hide-empty":
      case "closest-empty":
        if (alreadyHidden && !isDomNodeEmpty(element)) {
          unhideNode(element);
        } else if (type === "closest-empty") {
          expandNonEmptyDomNode(element.parentNode, rule);
        }
        break;
      default:
        break;
    }
  }
  function hideNode(element) {
    const cachedDisplayProperties = {
      display: element.style.display,
      "min-height": element.style.minHeight,
      height: element.style.height
    };
    hiddenElements.set(element, cachedDisplayProperties);
    element.style.setProperty("display", "none", "important");
    element.style.setProperty("min-height", "0px", "important");
    element.style.setProperty("height", "0px", "important");
    element.hidden = true;
    featureInstance.addDebugFlag();
  }
  function unhideNode(element) {
    const cachedDisplayProperties = hiddenElements.get(element);
    if (!cachedDisplayProperties) {
      return;
    }
    for (const prop in cachedDisplayProperties) {
      element.style.setProperty(prop, cachedDisplayProperties[prop]);
    }
    hiddenElements.delete(element);
    element.hidden = false;
  }
  function isDomNodeEmpty(node) {
    if (node.tagName === "BODY") {
      return false;
    }
    const parsedNode = parser.parseFromString(node.outerHTML, "text/html").documentElement;
    parsedNode.querySelectorAll("base,link,meta,script,style,template,title,desc").forEach((el) => {
      el.remove();
    });
    const visibleText = parsedNode.innerText.trim().toLocaleLowerCase().replace(/:$/, "");
    const mediaAndFormContent = parsedNode.querySelector(mediaAndFormSelectors);
    const frameElements = [...parsedNode.querySelectorAll("iframe")];
    const imageElements = [...node.querySelectorAll("img,svg")];
    const noFramesWithContent = frameElements.every((frame) => {
      return frame.hidden || frame.src === "about:blank";
    });
    const visibleImages = imageElements.some((image) => {
      return image.getBoundingClientRect().width > 20 || image.getBoundingClientRect().height > 20;
    });
    if ((visibleText === "" || adLabelStrings.includes(visibleText)) && mediaAndFormContent === null && noFramesWithContent && !visibleImages) {
      return true;
    }
    return false;
  }
  function modifyAttribute(element, values) {
    values.forEach((item) => {
      element.setAttribute(item.property, item.value);
    });
    modifiedElements.set(element, "modify-attr");
  }
  function modifyStyle(element, values) {
    values.forEach((item) => {
      element.style.setProperty(item.property, item.value, "important");
    });
    modifiedElements.set(element, "modify-style");
  }
  function extractTimeoutRules(rules) {
    if (!shouldInjectStyleTag) {
      return rules;
    }
    const strictHideRules = [];
    const timeoutRules = [];
    rules.forEach((rule) => {
      if (rule.type === "hide") {
        strictHideRules.push(rule);
      } else {
        timeoutRules.push(rule);
      }
    });
    injectStyleTag(strictHideRules);
    return timeoutRules;
  }
  function injectStyleTag(rules) {
    let selector = "";
    rules.forEach((rule, i) => {
      if (i !== rules.length - 1) {
        selector = selector.concat(rule.selector, ",");
      } else {
        selector = selector.concat(rule.selector);
      }
    });
    const styleTagProperties = "display:none!important;min-height:0!important;height:0!important;";
    const styleTagContents = `${forgivingSelector(selector)} {${styleTagProperties}}`;
    injectGlobalStyles(styleTagContents);
  }
  function hideAdNodes(rules) {
    const document2 = globalThis.document;
    rules.forEach((rule) => {
      const selector = forgivingSelector(rule.selector);
      const matchingElementArray = [...document2.querySelectorAll(selector)];
      matchingElementArray.forEach((element) => {
        collapseDomNode(element, rule);
      });
    });
  }
  function unhideLoadedAds() {
    const document2 = globalThis.document;
    appliedRules.forEach((rule) => {
      const selector = forgivingSelector(rule.selector);
      const matchingElementArray = [...document2.querySelectorAll(selector)];
      matchingElementArray.forEach((element) => {
        expandNonEmptyDomNode(element, rule);
      });
    });
  }
  function forgivingSelector(selector) {
    return `:is(${selector})`;
  }
  var ElementHiding = class extends ContentFeature {
    init() {
      featureInstance = this;
      if (isBeingFramed()) {
        return;
      }
      let activeRules;
      const globalRules = this.getFeatureSetting("rules");
      adLabelStrings = this.getFeatureSetting("adLabelStrings");
      shouldInjectStyleTag = this.getFeatureSetting("useStrictHideStyleTag");
      hideTimeouts = this.getFeatureSetting("hideTimeouts") || hideTimeouts;
      unhideTimeouts = this.getFeatureSetting("unhideTimeouts") || unhideTimeouts;
      mediaAndFormSelectors = this.getFeatureSetting("mediaAndFormSelectors") || mediaAndFormSelectors;
      if (shouldInjectStyleTag) {
        shouldInjectStyleTag = this.matchConditionalFeatureSetting("styleTagExceptions").length === 0;
      }
      const activeDomainRules = this.matchConditionalFeatureSetting("domains").flatMap((item) => item.rules);
      const overrideRules = activeDomainRules.filter((rule) => {
        return rule.type === "override";
      });
      const disableDefault = activeDomainRules.some((rule) => {
        return rule.type === "disable-default";
      });
      if (disableDefault) {
        activeRules = activeDomainRules.filter((rule) => {
          return rule.type !== "disable-default";
        });
      } else {
        activeRules = activeDomainRules.concat(globalRules);
      }
      overrideRules.forEach((override) => {
        activeRules = activeRules.filter((rule) => {
          return rule.selector !== override.selector;
        });
      });
      const applyRules = this.applyRules.bind(this);
      if (document.readyState === "loading") {
        window.addEventListener("DOMContentLoaded", () => {
          applyRules(activeRules);
        });
      } else {
        applyRules(activeRules);
      }
      this.activeRules = activeRules;
    }
    urlChanged() {
      if (this.activeRules) {
        this.applyRules(this.activeRules);
      }
    }
    /**
     * Apply relevant hiding rules to page at set intervals
     * @param {Object[]} rules
     * @param {string} rules[].selector
     * @param {string} rules[].type
     */
    applyRules(rules) {
      const timeoutRules = extractTimeoutRules(rules);
      const clearCacheTimer = unhideTimeouts.concat(hideTimeouts).reduce((a2, b2) => Math.max(a2, b2), 0) + 100;
      hideTimeouts.forEach((timeout) => {
        setTimeout(() => {
          hideAdNodes(timeoutRules);
        }, timeout);
      });
      unhideTimeouts.forEach((timeout) => {
        setTimeout(() => {
          unhideLoadedAds(timeoutRules);
        }, timeout);
      });
      setTimeout(() => {
        appliedRules = /* @__PURE__ */ new Set();
        hiddenElements = /* @__PURE__ */ new WeakMap();
        modifiedElements = /* @__PURE__ */ new WeakMap();
      }, clearCacheTimer);
    }
  };

  // src/features/exception-handler.js
  var ExceptionHandler = class extends ContentFeature {
    init() {
      const handleUncaughtException = (e) => {
        postDebugMessage(
          "jsException",
          {
            documentUrl: document.location.href,
            message: e.message,
            filename: e.filename,
            lineno: e.lineno,
            colno: e.colno,
            stack: e.error?.stack
          },
          true
        );
        this.addDebugFlag();
      };
      globalThis.addEventListener("error", handleUncaughtException);
    }
  };

  // src/features/api-manipulation.js
  var ApiManipulation = class extends ContentFeature {
    constructor() {
      super(...arguments);
      __publicField(this, "listenForUrlChanges", true);
    }
    init() {
      const apiChanges = this.getFeatureSetting("apiChanges");
      if (apiChanges) {
        for (const scope in apiChanges) {
          const change = apiChanges[scope];
          if (!this.checkIsValidAPIChange(change)) {
            continue;
          }
          this.applyApiChange(scope, change);
        }
      }
    }
    urlChanged() {
      this.init();
    }
    /**
     * Checks if the config API change is valid.
     * @param {any} change
     * @returns {change is APIChange}
     */
    checkIsValidAPIChange(change) {
      if (typeof change !== "object") {
        return false;
      }
      if (change.type === "remove") {
        return true;
      }
      if (change.type === "descriptor") {
        if (change.enumerable && typeof change.enumerable !== "boolean") {
          return false;
        }
        if (change.configurable && typeof change.configurable !== "boolean") {
          return false;
        }
        if ("define" in change && typeof change.define !== "boolean") {
          return false;
        }
        return typeof change.getterValue !== "undefined";
      }
      return false;
    }
    // TODO move this to schema definition imported from the privacy-config
    // Additionally remove checkIsValidAPIChange when this change happens.
    // See: https://app.asana.com/0/1201614831475344/1208715421518231/f
    /**
     * @typedef {Object} APIChange
     * @property {"remove"|"descriptor"} type
     * @property {import('../utils.js').ConfigSetting} [getterValue] - The value returned from a getter.
     * @property {boolean} [enumerable] - Whether the property is enumerable.
     * @property {boolean} [configurable] - Whether the property is configurable.
     * @property {boolean} [define] - Whether to define the property if it does not exist.
     */
    /**
     * Applies a change to DOM APIs.
     * @param {string} scope
     * @param {APIChange} change
     * @returns {void}
     */
    applyApiChange(scope, change) {
      const response = this.getGlobalObject(scope);
      if (!response) {
        return;
      }
      const [obj, key] = response;
      if (change.type === "remove") {
        this.removeApiMethod(obj, key);
      } else if (change.type === "descriptor") {
        this.wrapApiDescriptor(obj, key, change);
      }
    }
    /**
     * Removes a method from an API.
     * @param {object} api
     * @param {string} key
     */
    removeApiMethod(api, key) {
      try {
        if (hasOwnProperty.call(api, key)) {
          delete api[key];
        }
      } catch (e) {
      }
    }
    /**
     * Wraps a property with descriptor.
     * @param {object} api
     * @param {string} key
     * @param {APIChange} change
     */
    wrapApiDescriptor(api, key, change) {
      const getterValue = change.getterValue;
      if (getterValue) {
        const descriptor = {
          get: () => processAttr(getterValue, void 0)
        };
        if ("enumerable" in change) {
          descriptor.enumerable = change.enumerable;
        }
        if ("configurable" in change) {
          descriptor.configurable = change.configurable;
        }
        if (change.define === true && !(key in api)) {
          const defineDescriptor = {
            ...descriptor,
            enumerable: typeof descriptor.enumerable !== "boolean" ? true : descriptor.enumerable,
            configurable: typeof descriptor.configurable !== "boolean" ? true : descriptor.configurable
          };
          this.defineProperty(api, key, defineDescriptor);
          return;
        }
        this.wrapProperty(api, key, descriptor);
      }
    }
    /**
     * Looks up a global object from a scope, e.g. 'Navigator.prototype'.
     * @param {string} scope the scope of the object to get to.
     * @returns {[object, string]|null} the object at the scope.
     */
    getGlobalObject(scope) {
      const parts = scope.split(".");
      const lastPart = parts.pop();
      if (!lastPart) {
        return null;
      }
      let obj = window;
      for (const part of parts) {
        obj = obj[part];
        if (!obj) {
          return null;
        }
      }
      return [obj, lastPart];
    }
  };

  // src/features/click-to-load/ctl-assets.js
  var logoImg = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFQAAABUCAYAAAAcaxDBAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAABNTSURBVHgBzV0LcFPXmf6PJFt+gkEY8wrYMSEbgst7m02ywZnOZiEJCQlJC+QB25lNs7OzlEJ2ptmZLGayfUy3EEhmW5rM7gCZBtjJgzxmSTvTRSST9IF5pCE0TUosmmBjHIKNZFmWLN2e78hHPvfqXuleSdfONyNLV7q6uve7//uc85vRlwAda25oTFK8lZGn0UPaLI2okUhrTH/KGnU7M+olTevlL0KaeM3e01LaKa/PE2p64dgpGmMwGgN0rGqtS1Ve2cB/fhk/gVbSqI5KAU4wvxlBTdNe9VJ5sOnAb0I0yhg1QiWJTGN3E0gcHQRTpO0dTXJdJ7RjzZJWflHrGaNVdiTRN2kalTfOIU9VLfnqp5ruM9TTxR+dlIqGKX7uI7IDLrl7PFS2zW1iXSMURGqkbaUc0uiprqWqxa1UOXcxVcxdxAmcRoUApMZDH9HAmeMU+8NxQbYV3Ca25ITCwaRY4immcYk0AUgcv3wtJ3CxeLgBEBw++jpF249akusWsSUltGPNoq0aY5vMVLviusU04b5HbJMoVLo/ItRaBUyBp7rGtjTHuNSGj75BkbdeN/2ckdbWdODENioRSkIopFLThl4hpi0wflZzy0pO5D9aEiDsIFfXQagtf4CAXCqronzWHHFc3CQ/f53rZuGYl198zorYEKOyW0shrUUT2rFu8bc1jdqMUplLIkFi9NhRCvOLA4mp/jCVAjAn+N2qJa1UvXSZkGYjQOylfTu4OQjqPxAhl7atef+JnVQEiiK0Y+2ipzSNq7gCXFT9o1vFRRkB6evnFxJ5642SkWgF4fD4OUxYba4dEW4GLr/0bJY2FGsCCiIUMaVWEX6FDB4cF1D/T1uzJANE4uTxPBaoWbbSlNgcZiDIYsl7mg6d6iWHcEyolb0MPLyFxq1Yq9sXqg31ihx9nb4MsCK298VnxQ3XQaNTjJXd49SuOiJUkEmJIyRy7TSgWg2bf5xlK/sO76defpJuq7ZTgMy61Y9Q7bI7de/Dlndvf8xoAhw7K9uECjX3R46okomTm/rEbt0dh1TixIzqDeI9lSPZD/ZDWDT0uT2PXmqYSSvI7HryUT2pkNTB5K121d82oZ+sWQzJbJXbZmRa3GWBces2UuXX7qOKigryeDy6z0A+wqbosaDIdEYLZtdgSiq3qVcfOH6rnWPaIlQE7MTacp1ImHvuL/Ztz63iE+qpZtN2qp8z13IX6Siix4OjYi7gQCdy+6+aADNSecKys3l/+3fyHc+bb4d0nMl+KLfNyIS9vPTfPyAtEbc8jvjevz5F45r/inIBpqF6aSvV/M1twiTYLX4UCpwzYlIRw17TMnIOS5aJ8E5eE5e8Gza2TO17+nTXb3IdLyehaSeUOsBfVsj3pv77z6hsWmNmH5AJycwFQeb3nqfBqvHU399P4XBYPMfjcWK8DOXz+bK+I4mFCo2GGRh479dZpFbMbhGkSvBzvWHTvFkHd53+zNKe5lR5bjc7SPHoE7h3rOPZjwTU/POftlE+4ORS5ZVEly+OvDm1UTw0bldRsmtoaCC/32/6/SvQgDw3rVSY9GibTv2zfps7qasPHl9o9X1LCYXd5HxnKkbIyQPrt2Q+h325uOOxnGqeOQfsE+vXvxnhN7krROzd/6PUlJkU9nOJrK4mrzf7lPxcaiCt0IxE57msgkkpAQdZNf9G8tYFMr8Ns5PoDKV3YDRl47zp7OnTnUGz75tK6HC82SG3jXbTwhM6Q0U1sZvvFERVz77e1PtbwSptLBVwndN/+PNMxocb+OnGu0acJM/7mVa20Cw+Nb2CFCW2qtsIhFUndPml5wq/mAmTiT2yjep2HKKZ/7CF6r+ylKqqqmyTCdRwlcQNRmXfDeDaEP5JgFjUJzLghSDUfM2+m3UVkE4uthvkNvJz1aZAOgpNJbWv3U/jnnyeZi5bQRMmTHBEohFprfmZa6RC9eFwJcCDmg2igI5RCeP3sq7IKJ2BhzdnXosY0Zjz2gHUm0vltAe/TYFAoCgiVUByQGqhQyf5gBxftddwyiqGh3j056RuGKUTjqhoVR8mc8bf/r2wk6VGmtTdIpIoNWRxRwISCk4UtBqlVEeoUTpRaZcAkYWoOtQ8MG+xaaxZKuCmj1u+ltwArlmtS6icABjRVbczhNqRTqfQFvGM57avU21t6aXnvTOd9PKb79O+l9rpnfYOGn/7WlekFFDNnBxykcDweMeqBZnRigyhmAqjHsSY2xbkiLh0Tpw4MbMZiQ5yAo7T1h2/oG89/iL9aHeQLvQ4jynfaQ8JEqsry6lhUi2dPXeJdr/4vmtSCgnVSalqS+HxK30b5GZGD73E1mvyTcNdKEg6m3hsOeWqjKqDuMf+43VOQA09vHoJNTcGqKbKL0h2ipuWNIqHEaloC115c78rRRUM3UhO8Cyyv+HfYZqG2TBiLEpIaDqQHynNVfHCwMhJhrMHtOzguqUi85GAet52y7W0/Ym7aP7caYJMQD6XAnBQmDjhBhAuqh7foA2tUu0FoVnqrngyjE4WdMeb5upy83uXt3DJdGdigwpjJb5UAJn9nAuJSsMIhVR7QejwBC4BqLsaLPcXIp0Az7vLy8szm1Pq3XEYRoh5US45J3UwT6q9BFf7VjynCfWMqDvGtVUUVDrjhWRx8BIF8FaQTk46OGxD7TEBwg1gQoaq9jrzwkjYSU/H/UsXqJMUVGcEz1aIumt1k/OSibDnP3cfoZ/se7cgTw/8ZN+vRdjUzb+/ekUL/fJouhjtFqFylouETu05h/BFnqQv1ah+ya+czKBL1XKQsIV7/F+89VFGygrx9t09V8RzJBrnEnpEhFOAf9a15BZUTjBjUEWSkq0ebj914+uq/SxmYkIqlbL87J3joczrmqp0Ovpue4icAtGCBGJRue1WwQRQJdRYQ2CkNfpI0+bLqqhRVYod4gWpZqof6R8pSr/85u/F880mcWU+IJ6Fs4NkNs8KZKIIT1UNuQWjTwGpsr6B9QE+D6M6GdAbp9Cod8MJWO9FzL+0JHT1innC/kmAlBsLIBRAbIuHCjte3sMVo2o2FyLuP+N8ZCbyAdmCsTgEIZTv8ZHhRp8mVlukRdQ4Pl0wBqLiCYNwZkWRe5d/RQT0cEwNnMx7V7RQKWE26068P0xi7fXc/l2l/8wuoQC4kVzpfwsqz1gdDYuoOqc9FY1QwcD4USxKiUTCchczySoVZGjjG8clqIGTN4M7qsnZJErEPiVHwPA2pSPDrHUAPquFBEXnw5zUoaEhKhpJfh69PEMZ5BoT78q/L394+H6z/oVLj42sNsWDi543yRFyDBI2ulek5KOEA5OnU8EY4Pb7Uz58Gy4s0rBLZtdBrsJ9VDK4R+jlnsIl9NIbRKE2chNQc0hmKckE3CP0Qkh4eTgmNafPi3ina2RCIsOnecHnT87tpl1wQrVQ1npKoqILDKzjA+HrBgYGnBHamb/2CmLiF7Pf940f/jyW3gfSl+DJ1BB/xP6cfi4FrKIIjNfrJBQr1Ea+VGRwzFUenn5w0OFxon/M+XHPYWchjhvAsh4JlTMuQb08rmchua16r5IMzXZ1UCwWc/adpHW4BiLHmkxAF6/rskkW8nC1PCc3jVMHiya185xwTI6cU611ETrp8N64AWN6rg+htD5O6IiEGrMjY23UMTrOiCfYUdsIWFfcx/PTKZ9MYwqjkKnpOefyFCc0FVJ3UEkttmoDxyR+NJ5/hl4GkNDASsuPpz/Mk5QVY0esWi82ajQv3Z3yeSkV1JRZjQNnTvBxmfRd8BdbqEUKygP8ft9sMQXHNq7azE+EO6eoeXGm5vr0A148zn3f4MW0V0+ZlFSRfiLILxufjgJkwA+v7zRDAlROsopHzBPyNR04Ffpk7eJemYKiBioHuuT4TFFpKFf7IT6+ZFV5MoWXhyXXvcBvxrPcsVnPpfINk4SCh2MUsOQN4ZIqoQNqKY+HTGjRIa5QS1FQvq8OGZdkfIYH+ACmgDvGtEeIWl7LaQIKQR/n4dIRcgzjWixdAV4jMSSaFhkPy4yPwmupO9beUtzFsDPHxLMjO6qinJufxq1pYhvbKOUp7AbDHIBI5O5fHEkH/06hrl+F/VT9Da/WH8KzCOw9/qE9WsybmUCKzgjyblRhVe/zRag97GhvD7ejPmd21AhO7BAfVTn/X9sxeCMKw3BM/vqRDEkFCEOWBBuLrMoss3ICaCtWOEuEs6YmpYL4Kwht2nOqt2PN4qCcPYKJ+hOGFyfgQDW33CneKxgfHKOhm253ZkdNgAmw8sYiF3crHzcDpFNNOdEtYgQsCF+EV5mrSzH2aua1Qe2rTZZqO0IxdlSBKOyOEdRpjMYmCYxSe+XrDKFQe9FkahjqFL5i+4MUbUfHGMapnWFl7VIaaXUHMoRC7bmnykip8S4Yp0M7grSjRUqom8PDuZBr4jGPvvZIdQd0Bo0XSvao2+o0RpPp0M4AO+o0rzfAqo+TEVE/o8MLy+hHd1fQQHlxXUDyTzxO6ro/6AhtOtAe5D8flNvG6dCB9ZsLr5MO5/XFSGmlDbMTvN5H2+73c0J99FmAie1CASKdSCdg4nKZjnHVlsLLFar6Mq93XM5TYMxUVFyqZfTMCj+9/NUynVT+9pq864MtYVyfpS5gSCOZ1Zsk69d2ne4MbWqZhuk5YtkwCqh+brvkglks1Ut378ozAmnEUEJMwk1yUurq9AOtF/o76YVP/ofe7v5/ev/ySUqk+LCJ10/Vvuzi9Nnuk/Re8iy9P8tLA34PNfSlhBTubS2n7rps+QC5X/04RZVxjZwg3R5pRHgw4bbvtT2Z7bR0ntxr/J7F0sQFjRrznpT5PSTjqmde0y3VO//dBxxPhtBu30DE49GpU6dSZWVl5v21h2+niC87cbi69hq6a+b91DJxIb392a/of//8PEWTepMBovq9Gnm81vHtA28nOKn2bbedpZiMkk1GdQdMzwI7ahrbJbdBYM9PR6QbxDZs+bFzezpsR41qf2HA/MZ8Ev6Ydn7wfXrglytp95mdWWQCkMBYbIA0zVoCv6ix75hwTcZ+AMb1Wbzuuc2MTPF9skDzgfY2fhsyDU5RNFGX6qFoEnhoMzmBtKNqwRnqXiwY81Aibj1LxQmhgYe2GMh81rgCJiS4sUDOPJBpyXvUYB+NBlSvj0YoaC9kG4hHOamQUDndcUr1NF7tym/ftBzTI7EkPJkjHBuwOeiKa6lR5uijAILliRlgFTIlc/YeyUmoUP2UpvNkxiYt6NXkiNTO9BCWGj5VeXOPjKLrg1bE53ZiUWPfKeOKZCCXqkvkrVQ0HzyxU2Oks6dGA40TwfJnOzaV/SGdhqpqP6V6ak4bCAlM8LTVah9I+1AiwR/mUjoxYn3sdGu5tiwys5q4cDKb97fn7Ytnq/TTvP/4JjXgN/tBqP/0H/w8/0hpV0iM10ej0cxbC+qXWpIhfo+rM8iMRvqFrcQjPhinAX6MSDhMc88O0sLzTLy+0ttHUS79g7FBcUyQXTFobi7kEvGaPB1xUE3KZTdV2I56Ny1peJWSnuX85RRspxeEHRXdY6Rkym4yObvZIB6dM5+0unqxOrmsrIy+iH1O73QeobLyMt2uIDHGJXmiN0Dfv/lp6rzyKSUScQqU1dOc2rnU0j+RVh3ppjs/9tEN5710z4c+uraH0cRwWmL7tDhFEjF6sJ1R3aBe7TGii4Y0+RthsVNscGjFrg8v2MpIHLZq4/EpeXWt2nBCaNVmLFzkamOh3XgH0R3rafz48aLoHEmE6Y5DN9G4upFKMSQQZK6evY6+Oe+fqaYs25zgpp3/7jpyAtx0ZHvGPn1wtt07HjMW0kNwQvnspgpHedmu0xd6N83jkso8raRIavhXL4lbo+baINhKWhk88l//HSWTSUEqsqKTF39H3dEu7q2TQpUDvkn0vZt20arZ3xCfm558XcBR1obsZ8rjT5v26et55t/0DWkgmSy5wgmZ4tqoAHRsWFBHMe8rmqHdpZO2ktoTe7jeVdGMGTPEZLKPL39IG498U5zQfXMepK9f+5CpVBoByep68ls597FqDisTluy1rCzIYkOj0+5Sxdk1S9qYoU2EVfdDQG3Dlly2WqSh6D2CBwDVt0OiEecfX5c1Rg7VxtBNtaFXiARI7Nm9LWusjJvtXc0Hj2+iAlF0y+Cz31i0iXnYVuPUcozBoF+JmdcXDu2zEEXG1YsYEk2wioHsbgYSy2fO4TdzZXpw0WTaoWVzWNEy2F5olAslamqd7awkrMxAKSGXDMp/KGCGdAOa58wbKQh7yVXcob00Q0kIlTAzARIgtparoFu9662Qs10xpJIXgezGmHZQUkKBYWlt4y/Xm30OSUWDA0ygcLPnEqbJXDls3d2BW5pDpCW/Uwqp1B2XXEI+YgHZigNeGJOwCiUY6hw7c0KQCGeTe1IGwzDPNgz3kAtwjVAJO8SqQFkQzgVk+yZZ/HOVz7sEacbpMJYQveq4RBLb6xaRIz81SgCxSfK0esmzXqN09wP3waWRpV6lgdSeQmLKgn6RxgAZcpnnbkFuCf9BFR8KD3K/f3Q0SdSfwpcAHevQVSLVmNLYAg+j+SBYLOrlNQ0TskP4k15swUIp0s5hFvZY/YcvI/4CeAZjCToTSnsAAAAASUVORK5CYII=";
  var loadingImages = {
    darkMode: "data:image/svg+xml;utf8,%3Csvg%20width%3D%2220%22%20height%3D%2220%22%20viewBox%3D%220%200%2020%2020%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%20%20%20%20%20%20%20%20%3Cstyle%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%40keyframes%20rotate%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20from%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20transform%3A%20rotate%280deg%29%3B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20to%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20transform%3A%20rotate%28359deg%29%3B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%3C%2Fstyle%3E%0A%20%20%20%20%20%20%20%20%3Cg%20style%3D%22transform-origin%3A%2050%25%2050%25%3B%20animation%3A%20rotate%201s%20infinite%20reverse%20linear%3B%22%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2218.0968%22%20y%3D%2216.0861%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%28136.161%2018.0968%2016.0861%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.1%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.49878%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.4%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2219.9976%22%20y%3D%228.37451%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2890%2019.9976%208.37451%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.2%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2216.1727%22%20y%3D%221.9917%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2846.1607%2016.1727%201.9917%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.3%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.91309%22%20y%3D%226.88501%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%28136.161%208.91309%206.88501%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.6%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%226.79602%22%20y%3D%2210.996%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2846.1607%206.79602%2010.996%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.7%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%227%22%20y%3D%228.62549%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2890%207%208.62549%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.8%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.49878%22%20y%3D%2213%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.9%22%2F%3E%0A%20%20%20%20%20%20%20%20%3C%2Fg%3E%0A%20%20%20%20%3C%2Fsvg%3E",
    lightMode: "data:image/svg+xml;utf8,%3Csvg%20width%3D%2220%22%20height%3D%2220%22%20viewBox%3D%220%200%2020%2020%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%20%20%20%20%20%20%20%20%3Cstyle%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%40keyframes%20rotate%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20from%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20transform%3A%20rotate%280deg%29%3B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20to%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20transform%3A%20rotate%28359deg%29%3B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%20%20%20%20%3C%2Fstyle%3E%0A%20%20%20%20%20%20%20%20%3Cg%20style%3D%22transform-origin%3A%2050%25%2050%25%3B%20animation%3A%20rotate%201s%20infinite%20reverse%20linear%3B%22%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2218.0968%22%20y%3D%2216.0861%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%28136.161%2018.0968%2016.0861%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.1%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.49878%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.4%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2219.9976%22%20y%3D%228.37451%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2890%2019.9976%208.37451%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.2%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%2216.1727%22%20y%3D%221.9917%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2846.1607%2016.1727%201.9917%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.3%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.91309%22%20y%3D%226.88501%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%28136.161%208.91309%206.88501%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.6%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%226.79602%22%20y%3D%2210.996%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2846.1607%206.79602%2010.996%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.7%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%227%22%20y%3D%228.62549%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20transform%3D%22rotate%2890%207%208.62549%29%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.8%22%2F%3E%0A%20%20%20%20%20%20%20%20%20%20%20%20%3Crect%20x%3D%228.49878%22%20y%3D%2213%22%20width%3D%223%22%20height%3D%227%22%20rx%3D%221.5%22%20fill%3D%22%23111111%22%20fill-opacity%3D%220.9%22%2F%3E%0A%20%20%20%20%20%20%20%20%3C%2Fg%3E%0A%20%20%20%20%3C%2Fsvg%3E"
    // 'data:application/octet-stream;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHZpZXdCb3g9IjAgMCAyMCAyMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KCTxzdHlsZT4KCQlAa2V5ZnJhbWVzIHJvdGF0ZSB7CgkJCWZyb20gewoJCQkJdHJhbnNmb3JtOiByb3RhdGUoMGRlZyk7CgkJCX0KCQkJdG8gewoJCQkJdHJhbnNmb3JtOiByb3RhdGUoMzU5ZGVnKTsKCQkJfQoJCX0KCTwvc3R5bGU+Cgk8ZyBzdHlsZT0idHJhbnNmb3JtLW9yaWdpbjogNTAlIDUwJTsgYW5pbWF0aW9uOiByb3RhdGUgMXMgaW5maW5pdGUgcmV2ZXJzZSBsaW5lYXI7Ij4KCQk8cmVjdCB4PSIxOC4wOTY4IiB5PSIxNi4wODYxIiB3aWR0aD0iMyIgaGVpZ2h0PSI3IiByeD0iMS41IiB0cmFuc2Zvcm09InJvdGF0ZSgxMzYuMTYxIDE4LjA5NjggMTYuMDg2MSkiIGZpbGw9IiNmZmZmZmYiIGZpbGwtb3BhY2l0eT0iMC4xIi8+CQoJCTxyZWN0IHg9IjguNDk4NzgiIHdpZHRoPSIzIiBoZWlnaHQ9IjciIHJ4PSIxLjUiIGZpbGw9IiNmZmZmZmYiIGZpbGwtb3BhY2l0eT0iMC40Ii8+CgkJPHJlY3QgeD0iMTkuOTk3NiIgeT0iOC4zNzQ1MSIgd2lkdGg9IjMiIGhlaWdodD0iNyIgcng9IjEuNSIgdHJhbnNmb3JtPSJyb3RhdGUoOTAgMTkuOTk3NiA4LjM3NDUxKSIgZmlsbD0iI2ZmZmZmZiIgZmlsbC1vcGFjaXR5PSIwLjIiLz4KCQk8cmVjdCB4PSIxNi4xNzI3IiB5PSIxLjk5MTciIHdpZHRoPSIzIiBoZWlnaHQ9IjciIHJ4PSIxLjUiIHRyYW5zZm9ybT0icm90YXRlKDQ2LjE2MDcgMTYuMTcyNyAxLjk5MTcpIiBmaWxsPSIjZmZmZmZmIiBmaWxsLW9wYWNpdHk9IjAuMyIvPgoJCTxyZWN0IHg9IjguOTEzMDkiIHk9IjYuODg1MDEiIHdpZHRoPSIzIiBoZWlnaHQ9IjciIHJ4PSIxLjUiIHRyYW5zZm9ybT0icm90YXRlKDEzNi4xNjEgOC45MTMwOSA2Ljg4NTAxKSIgZmlsbD0iI2ZmZmZmZiIgZmlsbC1vcGFjaXR5PSIwLjYiLz4KCQk8cmVjdCB4PSI2Ljc5NjAyIiB5PSIxMC45OTYiIHdpZHRoPSIzIiBoZWlnaHQ9IjciIHJ4PSIxLjUiIHRyYW5zZm9ybT0icm90YXRlKDQ2LjE2MDcgNi43OTYwMiAxMC45OTYpIiBmaWxsPSIjZmZmZmZmIiBmaWxsLW9wYWNpdHk9IjAuNyIvPgoJCTxyZWN0IHg9IjciIHk9IjguNjI1NDkiIHdpZHRoPSIzIiBoZWlnaHQ9IjciIHJ4PSIxLjUiIHRyYW5zZm9ybT0icm90YXRlKDkwIDcgOC42MjU0OSkiIGZpbGw9IiNmZmZmZmYiIGZpbGwtb3BhY2l0eT0iMC44Ii8+CQkKCQk8cmVjdCB4PSI4LjQ5ODc4IiB5PSIxMyIgd2lkdGg9IjMiIGhlaWdodD0iNyIgcng9IjEuNSIgZmlsbD0iI2ZmZmZmZiIgZmlsbC1vcGFjaXR5PSIwLjkiLz4KCTwvZz4KPC9zdmc+Cg=='
  };
  var closeIcon = "data:image/svg+xml;utf8,%3Csvg%20width%3D%2212%22%20height%3D%2212%22%20viewBox%3D%220%200%2012%2012%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%3Cpath%20fill-rule%3D%22evenodd%22%20clip-rule%3D%22evenodd%22%20d%3D%22M5.99998%204.58578L10.2426%200.34314C10.6331%20-0.0473839%2011.2663%20-0.0473839%2011.6568%200.34314C12.0474%200.733665%2012.0474%201.36683%2011.6568%201.75735L7.41419%205.99999L11.6568%2010.2426C12.0474%2010.6332%2012.0474%2011.2663%2011.6568%2011.6568C11.2663%2012.0474%2010.6331%2012.0474%2010.2426%2011.6568L5.99998%207.41421L1.75734%2011.6568C1.36681%2012.0474%200.733649%2012.0474%200.343125%2011.6568C-0.0473991%2011.2663%20-0.0473991%2010.6332%200.343125%2010.2426L4.58577%205.99999L0.343125%201.75735C-0.0473991%201.36683%20-0.0473991%200.733665%200.343125%200.34314C0.733649%20-0.0473839%201.36681%20-0.0473839%201.75734%200.34314L5.99998%204.58578Z%22%20fill%3D%22%23222222%22%2F%3E%0A%3C%2Fsvg%3E";
  var blockedFBLogo = "data:image/svg+xml;utf8,%3Csvg%20width%3D%2280%22%20height%3D%2280%22%20viewBox%3D%220%200%2080%2080%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%3Ccircle%20cx%3D%2240%22%20cy%3D%2240%22%20r%3D%2240%22%20fill%3D%22white%22%2F%3E%0A%3Cg%20clip-path%3D%22url%28%23clip0%29%22%3E%0A%3Cpath%20d%3D%22M73.8457%2039.974C73.8457%2021.284%2058.7158%206.15405%2040.0258%206.15405C21.3358%206.15405%206.15344%2021.284%206.15344%2039.974C6.15344%2056.884%2018.5611%2070.8622%2034.7381%2073.4275V49.764H26.0999V39.974H34.7381V32.5399C34.7381%2024.0587%2039.764%2019.347%2047.5122%2019.347C51.2293%2019.347%2055.0511%2020.0799%2055.0511%2020.0799V28.3517H50.8105C46.6222%2028.3517%2045.2611%2030.9693%2045.2611%2033.6393V39.974H54.6846L53.1664%2049.764H45.2611V73.4275C61.4381%2070.9146%2073.8457%2056.884%2073.8457%2039.974Z%22%20fill%3D%22%231877F2%22%2F%3E%0A%3C%2Fg%3E%0A%3Crect%20x%3D%223.01295%22%20y%3D%2211.7158%22%20width%3D%2212.3077%22%20height%3D%2292.3077%22%20rx%3D%226.15385%22%20transform%3D%22rotate%28-45%203.01295%2011.7158%29%22%20fill%3D%22%23666666%22%20stroke%3D%22white%22%20stroke-width%3D%226.15385%22%2F%3E%0A%3Cdefs%3E%0A%3CclipPath%20id%3D%22clip0%22%3E%0A%3Crect%20width%3D%2267.6923%22%20height%3D%2267.6923%22%20fill%3D%22white%22%20transform%3D%22translate%286.15344%206.15405%29%22%2F%3E%0A%3C%2FclipPath%3E%0A%3C%2Fdefs%3E%0A%3C%2Fsvg%3E";
  var facebookLogo = "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjEiIGhlaWdodD0iMjAiIHZpZXdCb3g9IjAgMCAyMSAyMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTguODUgMTkuOUM0LjEgMTkuMDUgMC41IDE0Ljk1IDAuNSAxMEMwLjUgNC41IDUgMCAxMC41IDBDMTYgMCAyMC41IDQuNSAyMC41IDEwQzIwLjUgMTQuOTUgMTYuOSAxOS4wNSAxMi4xNSAxOS45TDExLjYgMTkuNDVIOS40TDguODUgMTkuOVoiIGZpbGw9IiMxODc3RjIiLz4KPHBhdGggZD0iTTE0LjQgMTIuOEwxNC44NSAxMEgxMi4yVjguMDVDMTIuMiA3LjI1IDEyLjUgNi42NSAxMy43IDYuNjVIMTVWNC4xQzE0LjMgNCAxMy41IDMuOSAxMi44IDMuOUMxMC41IDMuOSA4LjkgNS4zIDguOSA3LjhWMTBINi40VjEyLjhIOC45VjE5Ljg1QzkuNDUgMTkuOTUgMTAgMjAgMTAuNTUgMjBDMTEuMSAyMCAxMS42NSAxOS45NSAxMi4yIDE5Ljg1VjEyLjhIMTQuNFoiIGZpbGw9IndoaXRlIi8+Cjwvc3ZnPgo=";
  var blockedYTVideo = "data:image/svg+xml;utf8,%3Csvg%20width%3D%2275%22%20height%3D%2275%22%20viewBox%3D%220%200%2075%2075%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%20%20%3Crect%20x%3D%226.75%22%20y%3D%2215.75%22%20width%3D%2256.25%22%20height%3D%2239%22%20rx%3D%2213.5%22%20fill%3D%22%23DE5833%22%2F%3E%0A%20%20%3Cmask%20id%3D%22path-2-outside-1_885_11045%22%20maskUnits%3D%22userSpaceOnUse%22%20x%3D%2223.75%22%20y%3D%2222.5%22%20width%3D%2224%22%20height%3D%2226%22%20fill%3D%22black%22%3E%0A%20%20%3Crect%20fill%3D%22white%22%20x%3D%2223.75%22%20y%3D%2222.5%22%20width%3D%2224%22%20height%3D%2226%22%2F%3E%0A%20%20%3Cpath%20d%3D%22M41.9425%2037.5279C43.6677%2036.492%2043.6677%2033.9914%2041.9425%2032.9555L31.0394%2026.4088C29.262%2025.3416%2027%2026.6218%2027%2028.695L27%2041.7884C27%2043.8615%2029.262%2045.1418%2031.0394%2044.0746L41.9425%2037.5279Z%22%2F%3E%0A%20%20%3C%2Fmask%3E%0A%20%20%3Cpath%20d%3D%22M41.9425%2037.5279C43.6677%2036.492%2043.6677%2033.9914%2041.9425%2032.9555L31.0394%2026.4088C29.262%2025.3416%2027%2026.6218%2027%2028.695L27%2041.7884C27%2043.8615%2029.262%2045.1418%2031.0394%2044.0746L41.9425%2037.5279Z%22%20fill%3D%22white%22%2F%3E%0A%20%20%3Cpath%20d%3D%22M30.0296%2044.6809L31.5739%2047.2529L30.0296%2044.6809ZM30.0296%2025.8024L31.5739%2023.2304L30.0296%2025.8024ZM42.8944%2036.9563L44.4387%2039.5283L42.8944%2036.9563ZM41.35%2036.099L28.4852%2028.3744L31.5739%2023.2304L44.4387%2030.955L41.35%2036.099ZM30%2027.5171L30%2042.9663L24%2042.9663L24%2027.5171L30%2027.5171ZM28.4852%2042.1089L41.35%2034.3843L44.4387%2039.5283L31.5739%2047.2529L28.4852%2042.1089ZM30%2042.9663C30%2042.1888%2029.1517%2041.7087%2028.4852%2042.1089L31.5739%2047.2529C28.2413%2049.2539%2024%2046.8535%2024%2042.9663L30%2042.9663ZM28.4852%2028.3744C29.1517%2028.7746%2030%2028.2945%2030%2027.5171L24%2027.5171C24%2023.6299%2028.2413%2021.2294%2031.5739%2023.2304L28.4852%2028.3744ZM44.4387%2030.955C47.6735%2032.8974%2047.6735%2037.586%2044.4387%2039.5283L41.35%2034.3843C40.7031%2034.7728%2040.7031%2035.7105%2041.35%2036.099L44.4387%2030.955Z%22%20fill%3D%22%23BC4726%22%20mask%3D%22url(%23path-2-outside-1_885_11045)%22%2F%3E%0A%20%20%3Ccircle%20cx%3D%2257.75%22%20cy%3D%2252.5%22%20r%3D%2213.5%22%20fill%3D%22%23E0E0E0%22%2F%3E%0A%20%20%3Crect%20x%3D%2248.75%22%20y%3D%2250.25%22%20width%3D%2218%22%20height%3D%224.5%22%20rx%3D%221.5%22%20fill%3D%22%23666666%22%2F%3E%0A%20%20%3Cpath%20fill-rule%3D%22evenodd%22%20clip-rule%3D%22evenodd%22%20d%3D%22M57.9853%2015.8781C58.2046%2016.1015%2058.5052%2016.2262%2058.8181%2016.2238C59.1311%2016.2262%2059.4316%2016.1015%2059.6509%2015.8781L62.9821%2012.5469C63.2974%2012.2532%2063.4272%2011.8107%2063.3206%2011.3931C63.2139%2010.9756%2062.8879%2010.6495%2062.4703%2010.5429C62.0528%2010.4363%2061.6103%2010.5661%2061.3165%2010.8813L57.9853%2014.2125C57.7627%2014.4325%2057.6374%2014.7324%2057.6374%2015.0453C57.6374%2015.3583%2057.7627%2015.6582%2057.9853%2015.8781ZM61.3598%2018.8363C61.388%2019.4872%2061.9385%2019.9919%2062.5893%2019.9637L62.6915%2019.9559L66.7769%2019.6023C67.4278%2019.5459%2067.9097%2018.9726%2067.8533%2018.3217C67.7968%2017.6708%2067.2235%2017.1889%2066.5726%2017.2453L62.4872%2017.6067C61.8363%2017.6349%2061.3316%2018.1854%2061.3598%2018.8363Z%22%20fill%3D%22%23AAAAAA%22%20fill-opacity%3D%220.6%22%2F%3E%0A%20%20%3Cpath%20fill-rule%3D%22evenodd%22%20clip-rule%3D%22evenodd%22%20d%3D%22M10.6535%2015.8781C10.4342%2016.1015%2010.1336%2016.2262%209.82067%2016.2238C9.5077%2016.2262%209.20717%2016.1015%208.98787%2015.8781L5.65667%2012.5469C5.34138%2012.2532%205.2116%2011.8107%205.31823%2011.3931C5.42487%2010.9756%205.75092%2010.6495%206.16847%2010.5429C6.58602%2010.4363%207.02848%2010.5661%207.32227%2010.8813L10.6535%2014.2125C10.8761%2014.4325%2011.0014%2014.7324%2011.0014%2015.0453C11.0014%2015.3583%2010.8761%2015.6582%2010.6535%2015.8781ZM7.2791%2018.8362C7.25089%2019.4871%206.7004%2019.9919%206.04954%2019.9637L5.9474%2019.9558L1.86197%2019.6023C1.44093%2019.5658%201.07135%2019.3074%200.892432%2018.9246C0.713515%2018.5417%200.752449%2018.0924%200.994567%2017.7461C1.23669%2017.3997%201.6452%2017.2088%202.06624%2017.2453L6.15167%2017.6067C6.80254%2017.6349%207.3073%2018.1854%207.2791%2018.8362Z%22%20fill%3D%22%23AAAAAA%22%20fill-opacity%3D%220.6%22%2F%3E%0A%3C%2Fsvg%3E%0A";
  var videoPlayDark = "data:image/svg+xml;utf8,%3Csvg%20width%3D%2222%22%20height%3D%2226%22%20viewBox%3D%220%200%2022%2026%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%20%20%3Cpath%20d%3D%22M21%2011.2679C22.3333%2012.0377%2022.3333%2013.9622%2021%2014.732L3%2025.1244C1.66667%2025.8942%202.59376e-06%2024.9319%202.66105e-06%2023.3923L3.56958e-06%202.60769C3.63688e-06%201.06809%201.66667%200.105844%203%200.875644L21%2011.2679Z%22%20fill%3D%22%23222222%22%2F%3E%0A%3C%2Fsvg%3E%0A";
  var videoPlayLight = "data:image/svg+xml;utf8,%3Csvg%20width%3D%2222%22%20height%3D%2226%22%20viewBox%3D%220%200%2022%2026%22%20fill%3D%22none%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%0A%20%20%3Cpath%20d%3D%22M21%2011.2679C22.3333%2012.0377%2022.3333%2013.9622%2021%2014.732L3%2025.1244C1.66667%2025.8942%202.59376e-06%2024.9319%202.66105e-06%2023.3923L3.56958e-06%202.60769C3.63688e-06%201.06809%201.66667%200.105844%203%200.875644L21%2011.2679Z%22%20fill%3D%22%23FFFFFF%22%2F%3E%0A%3C%2Fsvg%3E";

  // ../build/locales/ctl-locales.js
  var ctl_locales_default = `{"bg":{"facebook.json":{"informationalModalMessageTitle":"\u041F\u0440\u0438 \u0432\u043B\u0438\u0437\u0430\u043D\u0435 \u0440\u0430\u0437\u0440\u0435\u0448\u0430\u0432\u0430\u0442\u0435 \u043D\u0430 Facebook \u0434\u0430 \u0412\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430","informationalModalMessageBody":"\u0421\u043B\u0435\u0434 \u043A\u0430\u0442\u043E \u0432\u043B\u0435\u0437\u0435\u0442\u0435, DuckDuckGo \u043D\u0435 \u043C\u043E\u0436\u0435 \u0434\u0430 \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435\u0442\u043E \u043E\u0442 Facebook \u0432 \u0441\u044A\u0434\u044A\u0440\u0436\u0430\u043D\u0438\u0435\u0442\u043E \u043D\u0430 \u0442\u043E\u0437\u0438 \u0441\u0430\u0439\u0442.","informationalModalConfirmButtonText":"\u0412\u0445\u043E\u0434","informationalModalRejectButtonText":"\u041D\u0430\u0437\u0430\u0434","loginButtonText":"\u0412\u0445\u043E\u0434 \u0432\u044A\u0432 Facebook","loginBodyText":"Facebook \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430 \u0412\u0430\u0448\u0430\u0442\u0430 \u0430\u043A\u0442\u0438\u0432\u043D\u043E\u0441\u0442 \u0432 \u0441\u044A\u043E\u0442\u0432\u0435\u0442\u043D\u0438\u044F \u0441\u0430\u0439\u0442, \u043A\u043E\u0433\u0430\u0442\u043E \u0433\u043E \u0438\u0437\u043F\u043E\u043B\u0437\u0432\u0430\u0442\u0435 \u0437\u0430 \u0432\u0445\u043E\u0434.","buttonTextUnblockContent":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0441\u044A\u0434\u044A\u0440\u0436\u0430\u043D\u0438\u0435 \u043E\u0442 Facebook","buttonTextUnblockComment":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u043A\u043E\u043C\u0435\u043D\u0442\u0430\u0440 \u0432\u044A\u0432 Facebook","buttonTextUnblockComments":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u043A\u043E\u043C\u0435\u043D\u0442\u0430\u0440\u0438 \u0432\u044A\u0432 Facebook","buttonTextUnblockPost":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u043F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u044F \u043E\u0442 Facebook","buttonTextUnblockVideo":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0432\u0438\u0434\u0435\u043E \u043E\u0442 Facebook","buttonTextUnblockLogin":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0432\u0445\u043E\u0434 \u0441 Facebook","infoTitleUnblockContent":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u043E\u0432\u0430 \u0441\u044A\u0434\u044A\u0440\u0436\u0430\u043D\u0438\u0435, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Facebook","infoTitleUnblockComment":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u043E\u0437\u0438 \u043A\u043E\u043C\u0435\u043D\u0442\u0430\u0440, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Facebook","infoTitleUnblockComments":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u0435\u0437\u0438 \u043A\u043E\u043C\u0435\u043D\u0442\u0430\u0440\u0438, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Facebook","infoTitleUnblockPost":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u0430\u0437\u0438 \u043F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u044F, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Facebook","infoTitleUnblockVideo":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u043E\u0432\u0430 \u0432\u0438\u0434\u0435\u043E, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Facebook","infoTextUnblockContent":"\u0411\u043B\u043E\u043A\u0438\u0440\u0430\u0445\u043C\u0435 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435\u0442\u043E \u043E\u0442 Facebook \u043F\u0440\u0438 \u0437\u0430\u0440\u0435\u0436\u0434\u0430\u043D\u0435 \u043D\u0430 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u0430\u0442\u0430. \u0410\u043A\u043E \u0440\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u0442\u0435 \u0442\u043E\u0432\u0430 \u0441\u044A\u0434\u044A\u0440\u0436\u0430\u043D\u0438\u0435, Facebook \u0449\u0435 \u0441\u043B\u0435\u0434\u0438 \u0412\u0430\u0448\u0430\u0442\u0430 \u0430\u043A\u0442\u0438\u0432\u043D\u043E\u0441\u0442."},"shared.json":{"learnMore":"\u041D\u0430\u0443\u0447\u0435\u0442\u0435 \u043F\u043E\u0432\u0435\u0447\u0435","readAbout":"\u041F\u0440\u043E\u0447\u0435\u0442\u0435\u0442\u0435 \u0437\u0430 \u0442\u0430\u0437\u0438 \u0437\u0430\u0449\u0438\u0442\u0430 \u043D\u0430 \u043F\u043E\u0432\u0435\u0440\u0438\u0442\u0435\u043B\u043D\u043E\u0441\u0442\u0442\u0430","shareFeedback":"\u0421\u043F\u043E\u0434\u0435\u043B\u044F\u043D\u0435 \u043D\u0430 \u043E\u0442\u0437\u0438\u0432"},"youtube.json":{"informationalModalMessageTitle":"\u0410\u043A\u0442\u0438\u0432\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0432\u0441\u0438\u0447\u043A\u0438 \u043F\u0440\u0435\u0433\u043B\u0435\u0434\u0438 \u0432 YouTube?","informationalModalMessageBody":"\u041F\u043E\u043A\u0430\u0437\u0432\u0430\u043D\u0435\u0442\u043E \u043D\u0430 \u043F\u0440\u0435\u0433\u043B\u0435\u0434 \u043F\u043E\u0437\u0432\u043E\u043B\u044F\u0432\u0430 \u043D\u0430 Google (\u0441\u043E\u0431\u0441\u0442\u0432\u0435\u043D\u0438\u043A \u043D\u0430 YouTube) \u0434\u0430 \u0432\u0438\u0434\u0438 \u0447\u0430\u0441\u0442 \u043E\u0442 \u0438\u043D\u0444\u043E\u0440\u043C\u0430\u0446\u0438\u044F\u0442\u0430 \u0437\u0430 \u0412\u0430\u0448\u0435\u0442\u043E \u0443\u0441\u0442\u0440\u043E\u0439\u0441\u0442\u0432\u043E, \u043D\u043E \u0432\u0441\u0435 \u043F\u0430\u043A \u043E\u0441\u0438\u0433\u0443\u0440\u044F\u0432\u0430 \u043F\u043E\u0432\u0435\u0447\u0435 \u043F\u043E\u0432\u0435\u0440\u0438\u0442\u0435\u043B\u043D\u043E\u0441\u0442 \u043E\u0442\u043A\u043E\u043B\u043A\u043E\u0442\u043E \u043F\u0440\u0438 \u0432\u044A\u0437\u043F\u0440\u043E\u0438\u0437\u0432\u0435\u0436\u0434\u0430\u043D\u0435 \u043D\u0430 \u0432\u0438\u0434\u0435\u043E\u043A\u043B\u0438\u043F\u0430.","informationalModalConfirmButtonText":"\u0410\u043A\u0442\u0438\u0432\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0432\u0441\u0438\u0447\u043A\u0438 \u043F\u0440\u0435\u0433\u043B\u0435\u0434\u0438","informationalModalRejectButtonText":"\u041D\u0435, \u0431\u043B\u0430\u0433\u043E\u0434\u0430\u0440\u044F","buttonTextUnblockVideo":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u043D\u0435 \u043D\u0430 \u0432\u0438\u0434\u0435\u043E \u043E\u0442 YouTube","infoTitleUnblockVideo":"DuckDuckGo \u0431\u043B\u043E\u043A\u0438\u0440\u0430 \u0442\u043E\u0437\u0438 \u0432\u0438\u0434\u0435\u043E\u043A\u043B\u0438\u043F \u0432 YouTube, \u0437\u0430 \u0434\u0430 \u043F\u0440\u0435\u0434\u043E\u0442\u0432\u0440\u0430\u0442\u0438 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435 \u043E\u0442 Google","infoTextUnblockVideo":"\u0411\u043B\u043E\u043A\u0438\u0440\u0430\u0445\u043C\u0435 \u043F\u0440\u043E\u0441\u043B\u0435\u0434\u044F\u0432\u0430\u043D\u0435\u0442\u043E \u043E\u0442 Google (\u0441\u043E\u0431\u0441\u0442\u0432\u0435\u043D\u0438\u043A \u043D\u0430 YouTube) \u043F\u0440\u0438 \u0437\u0430\u0440\u0435\u0436\u0434\u0430\u043D\u0435 \u043D\u0430 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u0430\u0442\u0430. \u0410\u043A\u043E \u0440\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u0430\u0442\u0435 \u0442\u043E\u0437\u0438 \u0432\u0438\u0434\u0435\u043E\u043A\u043B\u0438\u043F, Google \u0449\u0435 \u0441\u043B\u0435\u0434\u0438 \u0412\u0430\u0448\u0430\u0442\u0430 \u0430\u043A\u0442\u0438\u0432\u043D\u043E\u0441\u0442.","infoPreviewToggleText":"\u041F\u0440\u0435\u0433\u043B\u0435\u0434\u0438\u0442\u0435 \u0441\u0430 \u0434\u0435\u0430\u043A\u0442\u0438\u0432\u0438\u0440\u0430\u043D\u0438 \u0437\u0430 \u043E\u0441\u0438\u0433\u0443\u0440\u044F\u0432\u0430\u043D\u0435 \u043D\u0430 \u0434\u043E\u043F\u044A\u043B\u043D\u0438\u0442\u0435\u043B\u043D\u0430 \u043F\u043E\u0432\u0435\u0440\u0438\u0442\u0435\u043B\u043D\u043E\u0441\u0442","infoPreviewToggleEnabledText":"\u041F\u0440\u0435\u0433\u043B\u0435\u0434\u0438\u0442\u0435 \u0441\u0430 \u0430\u043A\u0442\u0438\u0432\u0438\u0440\u0430\u043D\u0438","infoPreviewToggleEnabledDuckDuckGoText":"\u0412\u0438\u0437\u0443\u0430\u043B\u0438\u0437\u0430\u0446\u0438\u0438\u0442\u0435 \u043E\u0442 YouTube \u0441\u0430 \u0430\u043A\u0442\u0438\u0432\u0438\u0440\u0430\u043D\u0438 \u0432 DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">\u041D\u0430\u0443\u0447\u0435\u0442\u0435 \u043F\u043E\u0432\u0435\u0447\u0435</a> \u0437\u0430 \u0432\u0433\u0440\u0430\u0434\u0435\u043D\u0430\u0442\u0430 \u0437\u0430\u0449\u0438\u0442\u0430 \u043E\u0442 \u0441\u043E\u0446\u0438\u0430\u043B\u043D\u0438 \u043C\u0435\u0434\u0438\u0438 \u043D\u0430 DuckDuckGo"}},"cs":{"facebook.json":{"informationalModalMessageTitle":"Kdy\u017E se p\u0159ihl\xE1s\xED\u0161 p\u0159es Facebook, bude t\u011B moct sledovat","informationalModalMessageBody":"Po p\u0159ihl\xE1\u0161en\xED u\u017E DuckDuckGo nem\u016F\u017Ee br\xE1nit Facebooku, aby t\u011B na t\xE9hle str\xE1nce sledoval.","informationalModalConfirmButtonText":"P\u0159ihl\xE1sit se","informationalModalRejectButtonText":"Zp\u011Bt","loginButtonText":"P\u0159ihl\xE1sit se pomoc\xED Facebooku","loginBodyText":"Facebook sleduje tvou aktivitu na webu, kdy\u017E se p\u0159ihl\xE1s\xED\u0161 jeho prost\u0159ednictv\xEDm.","buttonTextUnblockContent":"Odblokovat obsah na Facebooku","buttonTextUnblockComment":"Odblokovat koment\xE1\u0159 na Facebooku","buttonTextUnblockComments":"Odblokovat koment\xE1\u0159e na Facebooku","buttonTextUnblockPost":"Odblokovat p\u0159\xEDsp\u011Bvek na Facebooku","buttonTextUnblockVideo":"Odblokovat video na Facebooku","buttonTextUnblockLogin":"Odblokovat p\u0159ihl\xE1\u0161en\xED k\xA0Facebooku","infoTitleUnblockContent":"DuckDuckGo zablokoval tenhle obsah, aby Facebooku zabr\xE1nil t\u011B sledovat","infoTitleUnblockComment":"Slu\u017Eba DuckDuckGo zablokovala tento koment\xE1\u0159, aby Facebooku zabr\xE1nila ve tv\xE9m sledov\xE1n\xED","infoTitleUnblockComments":"Slu\u017Eba DuckDuckGo zablokovala tyto koment\xE1\u0159e, aby Facebooku zabr\xE1nila ve tv\xE9m sledov\xE1n\xED","infoTitleUnblockPost":"DuckDuckGo zablokoval tenhle p\u0159\xEDsp\u011Bvek, aby Facebooku zabr\xE1nil t\u011B sledovat","infoTitleUnblockVideo":"DuckDuckGo zablokoval tohle video, aby Facebooku zabr\xE1nil t\u011B sledovat","infoTextUnblockContent":"P\u0159i na\u010D\xEDt\xE1n\xED str\xE1nky jsme Facebooku zabr\xE1nili, aby t\u011B sledoval. Kdy\u017E tenhle obsah odblokuje\u0161, Facebook bude m\xEDt p\u0159\xEDstup ke tv\xE9 aktivit\u011B."},"shared.json":{"learnMore":"V\xEDce informac\xED","readAbout":"P\u0159e\u010Dti si o\xA0t\xE9hle ochran\u011B soukrom\xED","shareFeedback":"Pod\u011Blte se o zp\u011Btnou vazbu"},"youtube.json":{"informationalModalMessageTitle":"Zapnout v\u0161echny n\xE1hledy YouTube?","informationalModalMessageBody":"Zobrazov\xE1n\xED n\xE1hled\u016F umo\u017En\xED spole\u010Dnosti Google (kter\xE1 vlastn\xED YouTube) zobrazit n\u011Bkter\xE9 informace o\xA0tv\xE9m za\u0159\xEDzen\xED, ale po\u0159\xE1d jde o\xA0diskr\xE9tn\u011Bj\u0161\xED volbu, ne\u017E je p\u0159ehr\xE1v\xE1n\xED videa.","informationalModalConfirmButtonText":"Zapnout v\u0161echny n\xE1hledy","informationalModalRejectButtonText":"Ne, d\u011Bkuji","buttonTextUnblockVideo":"Odblokovat video na YouTube","infoTitleUnblockVideo":"DuckDuckGo zablokoval tohle video z\xA0YouTube, aby Googlu zabr\xE1nil t\u011B sledovat","infoTextUnblockVideo":"Zabr\xE1nili jsme spole\u010Dnosti Google (kter\xE1 vlastn\xED YouTube), aby t\u011B p\u0159i na\u010D\xEDt\xE1n\xED str\xE1nky sledovala. Pokud toto video odblokuje\u0161, Google z\xEDsk\xE1 p\u0159\xEDstup ke tv\xE9 aktivit\u011B.","infoPreviewToggleText":"N\xE1hledy jsou pro v\u011Bt\u0161\xED soukrom\xED vypnut\xE9","infoPreviewToggleEnabledText":"N\xE1hledy jsou zapnut\xE9","infoPreviewToggleEnabledDuckDuckGoText":"N\xE1hledy YouTube jsou v\xA0DuckDuckGo povolen\xE9.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Dal\u0161\xED informace</a> o\xA0ochran\u011B DuckDuckGo p\u0159ed sledov\xE1n\xEDm prost\u0159ednictv\xEDm vlo\u017Een\xE9ho obsahu ze soci\xE1ln\xEDch m\xE9di\xED"}},"da":{"facebook.json":{"informationalModalMessageTitle":"N\xE5r du logger ind med Facebook, kan de spore dig","informationalModalMessageBody":"N\xE5r du er logget ind, kan DuckDuckGo ikke blokere for, at indhold fra Facebook sporer dig p\xE5 dette websted.","informationalModalConfirmButtonText":"Log p\xE5","informationalModalRejectButtonText":"G\xE5 tilbage","loginButtonText":"Log ind med Facebook","loginBodyText":"Facebook sporer din aktivitet p\xE5 et websted, n\xE5r du bruger dem til at logge ind.","buttonTextUnblockContent":"Bloker ikke Facebook-indhold","buttonTextUnblockComment":"Bloker ikke Facebook-kommentar","buttonTextUnblockComments":"Bloker ikke Facebook-kommentarer","buttonTextUnblockPost":"Bloker ikke Facebook-opslag","buttonTextUnblockVideo":"Bloker ikke Facebook-video","buttonTextUnblockLogin":"Bloker ikke Facebook-login","infoTitleUnblockContent":"DuckDuckGo har blokeret dette indhold for at forhindre Facebook i at spore dig","infoTitleUnblockComment":"DuckDuckGo har blokeret denne kommentar for at forhindre Facebook i at spore dig","infoTitleUnblockComments":"DuckDuckGo har blokeret disse kommentarer for at forhindre Facebook i at spore dig","infoTitleUnblockPost":"DuckDuckGo blokerede dette indl\xE6g for at forhindre Facebook i at spore dig","infoTitleUnblockVideo":"DuckDuckGo har blokeret denne video for at forhindre Facebook i at spore dig","infoTextUnblockContent":"Vi blokerede for, at Facebook sporede dig, da siden blev indl\xE6st. Hvis du oph\xE6ver blokeringen af dette indhold, vil Facebook kende din aktivitet."},"shared.json":{"learnMore":"Mere info","readAbout":"L\xE6s om denne beskyttelse af privatlivet","shareFeedback":"Del feedback"},"youtube.json":{"informationalModalMessageTitle":"Vil du aktivere alle YouTube-forh\xE5ndsvisninger?","informationalModalMessageBody":"Med forh\xE5ndsvisninger kan Google (som ejer YouTube) se nogle af enhedens oplysninger, men det er stadig mere privat end at afspille videoen.","informationalModalConfirmButtonText":"Aktiv\xE9r alle forh\xE5ndsvisninger","informationalModalRejectButtonText":"Nej tak.","buttonTextUnblockVideo":"Bloker ikke YouTube-video","infoTitleUnblockVideo":"DuckDuckGo har blokeret denne YouTube-video for at forhindre Google i at spore dig","infoTextUnblockVideo":"Vi blokerede Google (som ejer YouTube) fra at spore dig, da siden blev indl\xE6st. Hvis du fjerner blokeringen af denne video, vil Google f\xE5 kendskab til din aktivitet.","infoPreviewToggleText":"Forh\xE5ndsvisninger er deaktiveret for at give yderligere privatliv","infoPreviewToggleEnabledText":"Forh\xE5ndsvisninger er deaktiveret","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-forh\xE5ndsvisninger er aktiveret i DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">F\xE5 mere at vide p\xE5</a> om DuckDuckGos indbyggede beskyttelse p\xE5 sociale medier"}},"de":{"facebook.json":{"informationalModalMessageTitle":"Wenn du dich bei Facebook anmeldest, kann Facebook dich tracken","informationalModalMessageBody":"Sobald du angemeldet bist, kann DuckDuckGo nicht mehr verhindern, dass Facebook-Inhalte dich auf dieser Website tracken.","informationalModalConfirmButtonText":"Anmelden","informationalModalRejectButtonText":"Zur\xFCck","loginButtonText":"Mit Facebook anmelden","loginBodyText":"Facebook trackt deine Aktivit\xE4t auf einer Website, wenn du dich \xFCber Facebook dort anmeldest.","buttonTextUnblockContent":"Facebook-Inhalt entsperren","buttonTextUnblockComment":"Facebook-Kommentar entsperren","buttonTextUnblockComments":"Facebook-Kommentare entsperren","buttonTextUnblockPost":"Facebook-Beitrag entsperren","buttonTextUnblockVideo":"Facebook-Video entsperren","buttonTextUnblockLogin":"Facebook-Anmeldung entsperren","infoTitleUnblockContent":"DuckDuckGo hat diesen Inhalt blockiert, um zu verhindern, dass Facebook dich trackt","infoTitleUnblockComment":"DuckDuckGo hat diesen Kommentar blockiert, um zu verhindern, dass Facebook dich trackt","infoTitleUnblockComments":"DuckDuckGo hat diese Kommentare blockiert, um zu verhindern, dass Facebook dich trackt","infoTitleUnblockPost":"DuckDuckGo hat diesen Beitrag blockiert, um zu verhindern, dass Facebook dich trackt","infoTitleUnblockVideo":"DuckDuckGo hat dieses Video blockiert, um zu verhindern, dass Facebook dich trackt","infoTextUnblockContent":"Wir haben Facebook daran gehindert, dich zu tracken, als die Seite geladen wurde. Wenn du die Blockierung f\xFCr diesen Inhalt aufhebst, kennt Facebook deine Aktivit\xE4ten."},"shared.json":{"learnMore":"Mehr erfahren","readAbout":"Weitere Informationen \xFCber diesen Datenschutz","shareFeedback":"Feedback teilen"},"youtube.json":{"informationalModalMessageTitle":"Alle YouTube-Vorschauen aktivieren?","informationalModalMessageBody":"Durch das Anzeigen von Vorschauen kann Google (dem YouTube geh\xF6rt) einige Informationen zu deinem Ger\xE4t sehen. Dies ist aber immer noch privater als das Abspielen des Videos.","informationalModalConfirmButtonText":"Alle Vorschauen aktivieren","informationalModalRejectButtonText":"Nein, danke","buttonTextUnblockVideo":"YouTube-Video entsperren","infoTitleUnblockVideo":"DuckDuckGo hat dieses YouTube-Video blockiert, um zu verhindern, dass Google dich trackt.","infoTextUnblockVideo":"Wir haben Google (dem YouTube geh\xF6rt) daran gehindert, dich beim Laden der Seite zu tracken. Wenn du die Blockierung f\xFCr dieses Video aufhebst, kennt Google deine Aktivit\xE4ten.","infoPreviewToggleText":"Vorschau f\xFCr mehr Privatsph\xE4re deaktiviert","infoPreviewToggleEnabledText":"Vorschau aktiviert","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-Vorschauen sind in DuckDuckGo aktiviert.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Erfahre mehr</a> \xFCber den DuckDuckGo-Schutz vor eingebetteten Social Media-Inhalten"}},"el":{"facebook.json":{"informationalModalMessageTitle":"\u0397 \u03C3\u03CD\u03BD\u03B4\u03B5\u03C3\u03B7 \u03BC\u03AD\u03C3\u03C9 Facebook \u03C4\u03BF\u03C5\u03C2 \u03B5\u03C0\u03B9\u03C4\u03C1\u03AD\u03C0\u03B5\u03B9 \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03BF\u03CD\u03BD","informationalModalMessageBody":"\u039C\u03CC\u03BB\u03B9\u03C2 \u03C3\u03C5\u03BD\u03B4\u03B5\u03B8\u03B5\u03AF\u03C4\u03B5, \u03C4\u03BF DuckDuckGo \u03B4\u03B5\u03BD \u03BC\u03C0\u03BF\u03C1\u03B5\u03AF \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF \u03C0\u03B5\u03C1\u03B9\u03B5\u03C7\u03CC\u03BC\u03B5\u03BD\u03BF \u03C4\u03BF\u03C5 Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF \u03C3\u03B5 \u03B1\u03C5\u03C4\u03CC\u03BD \u03C4\u03BF\u03BD \u03B9\u03C3\u03C4\u03CC\u03C4\u03BF\u03C0\u03BF.","informationalModalConfirmButtonText":"\u03A3\u03CD\u03BD\u03B4\u03B5\u03C3\u03B7","informationalModalRejectButtonText":"\u0395\u03C0\u03B9\u03C3\u03C4\u03C1\u03BF\u03C6\u03AE","loginButtonText":"\u03A3\u03CD\u03BD\u03B4\u03B5\u03C3\u03B7 \u03BC\u03AD\u03C3\u03C9 Facebook","loginBodyText":"\u03A4\u03BF Facebook \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF \u03C4\u03B7 \u03B4\u03C1\u03B1\u03C3\u03C4\u03B7\u03C1\u03B9\u03CC\u03C4\u03B7\u03C4\u03AC \u03C3\u03B1\u03C2 \u03C3\u03B5 \u03AD\u03BD\u03B1\u03BD \u03B9\u03C3\u03C4\u03CC\u03C4\u03BF\u03C0\u03BF \u03CC\u03C4\u03B1\u03BD \u03C4\u03BF\u03BD \u03C7\u03C1\u03B7\u03C3\u03B9\u03BC\u03BF\u03C0\u03BF\u03B9\u03B5\u03AF\u03C4\u03B5 \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03C3\u03C5\u03BD\u03B4\u03B5\u03B8\u03B5\u03AF\u03C4\u03B5.","buttonTextUnblockContent":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03C0\u03B5\u03C1\u03B9\u03B5\u03C7\u03BF\u03BC\u03AD\u03BD\u03BF\u03C5 \u03C3\u03C4\u03BF Facebook","buttonTextUnblockComment":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03C3\u03C7\u03CC\u03BB\u03B9\u03BF\u03C5 \u03C3\u03C4\u03BF Facebook","buttonTextUnblockComments":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03C3\u03C7\u03BF\u03BB\u03AF\u03C9\u03BD \u03C3\u03C4\u03BF Facebook","buttonTextUnblockPost":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03B1\u03BD\u03AC\u03C1\u03C4\u03B7\u03C3\u03B7\u03C2 \u03C3\u03C4\u03BF Facebook","buttonTextUnblockVideo":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF \u03C3\u03C4\u03BF Facebook","buttonTextUnblockLogin":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03C3\u03CD\u03BD\u03B4\u03B5\u03C3\u03B7\u03C2 \u03C3\u03C4\u03BF Facebook","infoTitleUnblockContent":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03BF \u03C0\u03B5\u03C1\u03B9\u03B5\u03C7\u03CC\u03BC\u03B5\u03BD\u03BF \u03B1\u03C5\u03C4\u03CC \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTitleUnblockComment":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03BF \u03C3\u03C7\u03CC\u03BB\u03B9\u03BF \u03B1\u03C5\u03C4\u03CC \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTitleUnblockComments":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03B1 \u03C3\u03C7\u03CC\u03BB\u03B9\u03B1 \u03B1\u03C5\u03C4\u03AC \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTitleUnblockPost":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03B7\u03BD \u03B1\u03BD\u03AC\u03C1\u03C4\u03B7\u03C3\u03B7 \u03B1\u03C5\u03C4\u03AE \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTitleUnblockVideo":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03BF \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF \u03B1\u03C5\u03C4\u03CC \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTextUnblockContent":"\u0391\u03C0\u03BF\u03BA\u03BB\u03B5\u03AF\u03C3\u03B1\u03BC\u03B5 \u03C4\u03BF Facebook \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF \u03CC\u03C4\u03B1\u03BD \u03C6\u03BF\u03C1\u03C4\u03CE\u03B8\u03B7\u03BA\u03B5 \u03B7 \u03C3\u03B5\u03BB\u03AF\u03B4\u03B1. \u0395\u03AC\u03BD \u03BA\u03AC\u03BD\u03B5\u03C4\u03B5 \u03AC\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03B3\u03B9' \u03B1\u03C5\u03C4\u03CC \u03C4\u03BF \u03C0\u03B5\u03C1\u03B9\u03B5\u03C7\u03CC\u03BC\u03B5\u03BD\u03BF, \u03C4\u03BF Facebook \u03B8\u03B1 \u03B3\u03BD\u03C9\u03C1\u03AF\u03B6\u03B5\u03B9 \u03C4\u03B7 \u03B4\u03C1\u03B1\u03C3\u03C4\u03B7\u03C1\u03B9\u03CC\u03C4\u03B7\u03C4\u03AC \u03C3\u03B1\u03C2."},"shared.json":{"learnMore":"\u039C\u03AC\u03B8\u03B5\u03C4\u03B5 \u03C0\u03B5\u03C1\u03B9\u03C3\u03C3\u03CC\u03C4\u03B5\u03C1\u03B1","readAbout":"\u0394\u03B9\u03B1\u03B2\u03AC\u03C3\u03C4\u03B5 \u03C3\u03C7\u03B5\u03C4\u03B9\u03BA\u03AC \u03BC\u03B5 \u03C4\u03B7\u03BD \u03C0\u03B1\u03C1\u03BF\u03CD\u03C3\u03B1 \u03C0\u03C1\u03BF\u03C3\u03C4\u03B1\u03C3\u03AF\u03B1\u03C2 \u03C0\u03C1\u03BF\u03C3\u03C9\u03C0\u03B9\u03BA\u03CE\u03BD \u03B4\u03B5\u03B4\u03BF\u03BC\u03AD\u03BD\u03C9\u03BD","shareFeedback":"\u039A\u03BF\u03B9\u03BD\u03BF\u03C0\u03BF\u03AF\u03B7\u03C3\u03B7 \u03C3\u03C7\u03BF\u03BB\u03AF\u03BF\u03C5"},"youtube.json":{"informationalModalMessageTitle":"\u0395\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03AF\u03B7\u03C3\u03B7 \u03CC\u03BB\u03C9\u03BD \u03C4\u03C9\u03BD \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03C9\u03BD \u03C4\u03BF\u03C5 YouTube;","informationalModalMessageBody":"\u0397 \u03C0\u03C1\u03BF\u03B2\u03BF\u03BB\u03AE \u03C4\u03C9\u03BD \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03C9\u03BD \u03B8\u03B1 \u03B5\u03C0\u03B9\u03C4\u03C1\u03AD\u03C8\u03B5\u03B9 \u03C3\u03C4\u03B7\u03BD Google (\u03C3\u03C4\u03B7\u03BD \u03BF\u03C0\u03BF\u03AF\u03B1 \u03B1\u03BD\u03AE\u03BA\u03B5\u03B9 \u03C4\u03BF YouTube) \u03BD\u03B1 \u03B2\u03BB\u03AD\u03C0\u03B5\u03B9 \u03BF\u03C1\u03B9\u03C3\u03BC\u03AD\u03BD\u03B5\u03C2 \u03B1\u03C0\u03CC \u03C4\u03B9\u03C2 \u03C0\u03BB\u03B7\u03C1\u03BF\u03C6\u03BF\u03C1\u03AF\u03B5\u03C2 \u03C4\u03B7\u03C2 \u03C3\u03C5\u03C3\u03BA\u03B5\u03C5\u03AE\u03C2 \u03C3\u03B1\u03C2, \u03C9\u03C3\u03C4\u03CC\u03C3\u03BF \u03B5\u03BE\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF \u03BD\u03B1 \u03B5\u03AF\u03BD\u03B1\u03B9 \u03C0\u03B9\u03BF \u03B9\u03B4\u03B9\u03C9\u03C4\u03B9\u03BA\u03AE \u03B1\u03C0\u03CC \u03C4\u03B7\u03BD \u03B1\u03BD\u03B1\u03C0\u03B1\u03C1\u03B1\u03B3\u03C9\u03B3\u03AE \u03C4\u03BF\u03C5 \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF.","informationalModalConfirmButtonText":"\u0395\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03AF\u03B7\u03C3\u03B7 \u03CC\u03BB\u03C9\u03BD \u03C4\u03C9\u03BD \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03C9\u03BD","informationalModalRejectButtonText":"\u038C\u03C7\u03B9, \u03B5\u03C5\u03C7\u03B1\u03C1\u03B9\u03C3\u03C4\u03CE","buttonTextUnblockVideo":"\u0386\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF YouTube","infoTitleUnblockVideo":"\u03A4\u03BF DuckDuckGo \u03B1\u03C0\u03AD\u03BA\u03BB\u03B5\u03B9\u03C3\u03B5 \u03C4\u03BF \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF \u03B1\u03C5\u03C4\u03CC \u03C3\u03C4\u03BF YouTube \u03B3\u03B9\u03B1 \u03BD\u03B1 \u03B5\u03BC\u03C0\u03BF\u03B4\u03AF\u03C3\u03B5\u03B9 \u03C4\u03B7\u03BD Google \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF","infoTextUnblockVideo":"\u0391\u03C0\u03BF\u03BA\u03BB\u03B5\u03AF\u03C3\u03B1\u03BC\u03B5 \u03C4\u03B7\u03BD Google (\u03C3\u03C4\u03B7\u03BD \u03BF\u03C0\u03BF\u03AF\u03B1 \u03B1\u03BD\u03AE\u03BA\u03B5\u03B9 \u03C4\u03BF YouTube) \u03B1\u03C0\u03CC \u03C4\u03BF \u03BD\u03B1 \u03C3\u03B1\u03C2 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03C5\u03B8\u03B5\u03AF \u03CC\u03C4\u03B1\u03BD \u03C6\u03BF\u03C1\u03C4\u03CE\u03B8\u03B7\u03BA\u03B5 \u03B7 \u03C3\u03B5\u03BB\u03AF\u03B4\u03B1. \u0395\u03AC\u03BD \u03BA\u03AC\u03BD\u03B5\u03C4\u03B5 \u03AC\u03C1\u03C3\u03B7 \u03B1\u03C0\u03BF\u03BA\u03BB\u03B5\u03B9\u03C3\u03BC\u03BF\u03CD \u03B3\u03B9' \u03B1\u03C5\u03C4\u03CC \u03C4\u03BF \u03B2\u03AF\u03BD\u03C4\u03B5\u03BF, \u03B7 Google \u03B8\u03B1 \u03B3\u03BD\u03C9\u03C1\u03AF\u03B6\u03B5\u03B9 \u03C4\u03B7 \u03B4\u03C1\u03B1\u03C3\u03C4\u03B7\u03C1\u03B9\u03CC\u03C4\u03B7\u03C4\u03AC \u03C3\u03B1\u03C2.","infoPreviewToggleText":"\u039F\u03B9 \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03B9\u03C2 \u03B1\u03C0\u03B5\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03B9\u03AE\u03B8\u03B7\u03BA\u03B1\u03BD \u03B3\u03B9\u03B1 \u03C0\u03C1\u03CC\u03C3\u03B8\u03B5\u03C4\u03B7 \u03C0\u03C1\u03BF\u03C3\u03C4\u03B1\u03C3\u03AF\u03B1 \u03C4\u03C9\u03BD \u03C0\u03C1\u03BF\u03C3\u03C9\u03C0\u03B9\u03BA\u03CE\u03BD \u03B4\u03B5\u03B4\u03BF\u03BC\u03AD\u03BD\u03C9\u03BD","infoPreviewToggleEnabledText":"\u039F\u03B9 \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03B9\u03C2 \u03B5\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03B9\u03AE\u03B8\u03B7\u03BA\u03B1\u03BD","infoPreviewToggleEnabledDuckDuckGoText":"\u039F\u03B9 \u03C0\u03C1\u03BF\u03B5\u03C0\u03B9\u03C3\u03BA\u03BF\u03C0\u03AE\u03C3\u03B5\u03B9\u03C2 YouTube \u03B5\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03B9\u03AE\u03B8\u03B7\u03BA\u03B1\u03BD \u03C3\u03C4\u03BF DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">\u039C\u03AC\u03B8\u03B5\u03C4\u03B5 \u03C0\u03B5\u03C1\u03B9\u03C3\u03C3\u03CC\u03C4\u03B5\u03C1\u03B1</a> \u03B3\u03B9\u03B1 \u03C4\u03B7\u03BD \u03B5\u03BD\u03C3\u03C9\u03BC\u03B1\u03C4\u03C9\u03BC\u03AD\u03BD\u03B7 \u03C0\u03C1\u03BF\u03C3\u03C4\u03B1\u03C3\u03AF\u03B1 \u03BA\u03BF\u03B9\u03BD\u03C9\u03BD\u03B9\u03BA\u03CE\u03BD \u03BC\u03AD\u03C3\u03C9\u03BD DuckDuckGo"}},"en":{"facebook.json":{"informationalModalMessageTitle":"Logging in with Facebook lets them track you","informationalModalMessageBody":"Once you're logged in, DuckDuckGo can't block Facebook content from tracking you on this site.","informationalModalConfirmButtonText":"Log In","informationalModalRejectButtonText":"Go back","loginButtonText":"Log in with Facebook","loginBodyText":"Facebook tracks your activity on a site when you use them to login.","buttonTextUnblockContent":"Unblock Facebook Content","buttonTextUnblockComment":"Unblock Facebook Comment","buttonTextUnblockComments":"Unblock Facebook Comments","buttonTextUnblockPost":"Unblock Facebook Post","buttonTextUnblockVideo":"Unblock Facebook Video","buttonTextUnblockLogin":"Unblock Facebook Login","infoTitleUnblockContent":"DuckDuckGo blocked this content to prevent Facebook from tracking you","infoTitleUnblockComment":"DuckDuckGo blocked this comment to prevent Facebook from tracking you","infoTitleUnblockComments":"DuckDuckGo blocked these comments to prevent Facebook from tracking you","infoTitleUnblockPost":"DuckDuckGo blocked this post to prevent Facebook from tracking you","infoTitleUnblockVideo":"DuckDuckGo blocked this video to prevent Facebook from tracking you","infoTextUnblockContent":"We blocked Facebook from tracking you when the page loaded. If you unblock this content, Facebook will know your activity."},"shared.json":{"learnMore":"Learn More","readAbout":"Read about this privacy protection","shareFeedback":"Share Feedback"},"youtube.json":{"informationalModalMessageTitle":"Enable all YouTube previews?","informationalModalMessageBody":"Showing previews will allow Google (which owns YouTube) to see some of your device\u2019s information, but is still more private than playing the video.","informationalModalConfirmButtonText":"Enable All Previews","informationalModalRejectButtonText":"No Thanks","buttonTextUnblockVideo":"Unblock YouTube Video","infoTitleUnblockVideo":"DuckDuckGo blocked this YouTube video to prevent Google from tracking you","infoTextUnblockVideo":"We blocked Google (which owns YouTube) from tracking you when the page loaded. If you unblock this video, Google will know your activity.","infoPreviewToggleText":"Previews disabled for additional privacy","infoPreviewToggleEnabledText":"Previews enabled","infoPreviewToggleEnabledDuckDuckGoText":"YouTube previews enabled in DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Learn more</a> about DuckDuckGo Embedded Social Media Protection"}},"es":{"facebook.json":{"informationalModalMessageTitle":"Al iniciar sesi\xF3n en Facebook, les permites que te rastreen","informationalModalMessageBody":"Una vez que hayas iniciado sesi\xF3n, DuckDuckGo no puede bloquear el contenido de Facebook para que no te rastree en este sitio.","informationalModalConfirmButtonText":"Iniciar sesi\xF3n","informationalModalRejectButtonText":"Volver atr\xE1s","loginButtonText":"Iniciar sesi\xF3n con Facebook","loginBodyText":"Facebook rastrea tu actividad en un sitio web cuando lo usas para iniciar sesi\xF3n.","buttonTextUnblockContent":"Desbloquear contenido de Facebook","buttonTextUnblockComment":"Desbloquear comentario de Facebook","buttonTextUnblockComments":"Desbloquear comentarios de Facebook","buttonTextUnblockPost":"Desbloquear publicaci\xF3n de Facebook","buttonTextUnblockVideo":"Desbloquear v\xEDdeo de Facebook","buttonTextUnblockLogin":"Desbloquear inicio de sesi\xF3n de Facebook","infoTitleUnblockContent":"DuckDuckGo ha bloqueado este contenido para evitar que Facebook te rastree","infoTitleUnblockComment":"DuckDuckGo ha bloqueado este comentario para evitar que Facebook te rastree","infoTitleUnblockComments":"DuckDuckGo ha bloqueado estos comentarios para evitar que Facebook te rastree","infoTitleUnblockPost":"DuckDuckGo ha bloqueado esta publicaci\xF3n para evitar que Facebook te rastree","infoTitleUnblockVideo":"DuckDuckGo ha bloqueado este v\xEDdeo para evitar que Facebook te rastree","infoTextUnblockContent":"Hemos bloqueado el rastreo de Facebook cuando se ha cargado la p\xE1gina. Si desbloqueas este contenido, Facebook tendr\xE1 conocimiento de tu actividad."},"shared.json":{"learnMore":"M\xE1s informaci\xF3n","readAbout":"Lee acerca de esta protecci\xF3n de privacidad","shareFeedback":"Compartir opiniones"},"youtube.json":{"informationalModalMessageTitle":"\xBFHabilitar todas las vistas previas de YouTube?","informationalModalMessageBody":"Mostrar vistas previas permitir\xE1 a Google (que es el propietario de YouTube) ver parte de la informaci\xF3n de tu dispositivo, pero sigue siendo m\xE1s privado que reproducir el v\xEDdeo.","informationalModalConfirmButtonText":"Habilitar todas las vistas previas","informationalModalRejectButtonText":"No, gracias","buttonTextUnblockVideo":"Desbloquear v\xEDdeo de YouTube","infoTitleUnblockVideo":"DuckDuckGo ha bloqueado este v\xEDdeo de YouTube para evitar que Google te rastree","infoTextUnblockVideo":"Hemos bloqueado el rastreo de Google (que es el propietario de YouTube) al cargarse la p\xE1gina. Si desbloqueas este v\xEDdeo, Goggle tendr\xE1 conocimiento de tu actividad.","infoPreviewToggleText":"Vistas previas desactivadas para mayor privacidad","infoPreviewToggleEnabledText":"Vistas previas activadas","infoPreviewToggleEnabledDuckDuckGoText":"Vistas previas de YouTube habilitadas en DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">M\xE1s informaci\xF3n</a> sobre la protecci\xF3n integrada de redes sociales DuckDuckGo"}},"et":{"facebook.json":{"informationalModalMessageTitle":"Kui logid Facebookiga sisse, saab Facebook sind j\xE4lgida","informationalModalMessageBody":"Kui oled sisse logitud, ei saa DuckDuckGo blokeerida Facebooki sisu sind j\xE4lgimast.","informationalModalConfirmButtonText":"Logi sisse","informationalModalRejectButtonText":"Mine tagasi","loginButtonText":"Logi sisse Facebookiga","loginBodyText":"Kui logid sisse Facebookiga, saab Facebook sinu tegevust saidil j\xE4lgida.","buttonTextUnblockContent":"Deblokeeri Facebooki sisu","buttonTextUnblockComment":"Deblokeeri Facebooki kommentaar","buttonTextUnblockComments":"Deblokeeri Facebooki kommentaarid","buttonTextUnblockPost":"Deblokeeri Facebooki postitus","buttonTextUnblockVideo":"Deblokeeri Facebooki video","buttonTextUnblockLogin":"Deblokeeri Facebooki sisselogimine","infoTitleUnblockContent":"DuckDuckGo blokeeris selle sisu, et Facebook ei saaks sind j\xE4lgida","infoTitleUnblockComment":"DuckDuckGo blokeeris selle kommentaari, et Facebook ei saaks sind j\xE4lgida","infoTitleUnblockComments":"DuckDuckGo blokeeris need kommentaarid, et Facebook ei saaks sind j\xE4lgida","infoTitleUnblockPost":"DuckDuckGo blokeeris selle postituse, et Facebook ei saaks sind j\xE4lgida","infoTitleUnblockVideo":"DuckDuckGo blokeeris selle video, et Facebook ei saaks sind j\xE4lgida","infoTextUnblockContent":"Blokeerisime lehe laadimise ajal Facebooki jaoks sinu j\xE4lgimise. Kui sa selle sisu deblokeerid, saab Facebook sinu tegevust j\xE4lgida."},"shared.json":{"learnMore":"Loe edasi","readAbout":"Loe selle privaatsuskaitse kohta","shareFeedback":"Jaga tagasisidet"},"youtube.json":{"informationalModalMessageTitle":"Kas lubada k\xF5ik YouTube\u2019i eelvaated?","informationalModalMessageBody":"Eelvaate n\xE4itamine v\xF5imaldab Google\u2019il (kellele YouTube kuulub) n\xE4ha osa sinu seadme teabest, kuid see on siiski privaatsem kui video esitamine.","informationalModalConfirmButtonText":"Luba k\xF5ik eelvaated","informationalModalRejectButtonText":"Ei ait\xE4h","buttonTextUnblockVideo":"Deblokeeri YouTube\u2019i video","infoTitleUnblockVideo":"DuckDuckGo blokeeris selle YouTube\u2019i video, et takistada Google\u2019it sind j\xE4lgimast","infoTextUnblockVideo":"Me blokeerisime lehe laadimise ajal Google\u2019i (kellele YouTube kuulub) j\xE4lgimise. Kui sa selle video deblokeerid, saab Google sinu tegevusest teada.","infoPreviewToggleText":"Eelvaated on t\xE4iendava privaatsuse tagamiseks keelatud","infoPreviewToggleEnabledText":"Eelvaated on lubatud","infoPreviewToggleEnabledDuckDuckGoText":"YouTube\u2019i eelvaated on DuckDuckGos lubatud.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Lisateave</a> DuckDuckGo sisseehitatud sotsiaalmeediakaitse kohta"}},"fi":{"facebook.json":{"informationalModalMessageTitle":"Kun kirjaudut sis\xE4\xE4n Facebook-tunnuksilla, Facebook voi seurata sinua","informationalModalMessageBody":"Kun olet kirjautunut sis\xE4\xE4n, DuckDuckGo ei voi est\xE4\xE4 Facebook-sis\xE4lt\xF6\xE4 seuraamasta sinua t\xE4ll\xE4 sivustolla.","informationalModalConfirmButtonText":"Kirjaudu sis\xE4\xE4n","informationalModalRejectButtonText":"Edellinen","loginButtonText":"Kirjaudu sis\xE4\xE4n Facebook-tunnuksilla","loginBodyText":"Facebook seuraa toimintaasi sivustolla, kun kirjaudut sis\xE4\xE4n sen kautta.","buttonTextUnblockContent":"Poista Facebook-sis\xE4ll\xF6n esto","buttonTextUnblockComment":"Poista Facebook-kommentin esto","buttonTextUnblockComments":"Poista Facebook-kommenttien esto","buttonTextUnblockPost":"Poista Facebook-julkaisun esto","buttonTextUnblockVideo":"Poista Facebook-videon esto","buttonTextUnblockLogin":"Poista Facebook-kirjautumisen esto","infoTitleUnblockContent":"DuckDuckGo esti t\xE4m\xE4n sis\xE4ll\xF6n est\xE4\xE4kseen Facebookia seuraamasta sinua","infoTitleUnblockComment":"DuckDuckGo esti t\xE4m\xE4n kommentin est\xE4\xE4kseen Facebookia seuraamasta sinua","infoTitleUnblockComments":"DuckDuckGo esti n\xE4m\xE4 kommentit est\xE4\xE4kseen Facebookia seuraamasta sinua","infoTitleUnblockPost":"DuckDuckGo esti t\xE4m\xE4n julkaisun est\xE4\xE4kseen Facebookia seuraamasta sinua","infoTitleUnblockVideo":"DuckDuckGo esti t\xE4m\xE4n videon est\xE4\xE4kseen Facebookia seuraamasta sinua","infoTextUnblockContent":"Estimme Facebookia seuraamasta sinua, kun sivua ladattiin. Jos poistat t\xE4m\xE4n sis\xE4ll\xF6n eston, Facebook saa tiet\xE4\xE4 toimintasi."},"shared.json":{"learnMore":"Lue lis\xE4\xE4","readAbout":"Lue t\xE4st\xE4 yksityisyydensuojasta","shareFeedback":"Jaa palaute"},"youtube.json":{"informationalModalMessageTitle":"Otetaanko k\xE4ytt\xF6\xF6n kaikki YouTube-esikatselut?","informationalModalMessageBody":"Kun sallit esikatselun, Google (joka omistaa YouTuben) voi n\xE4hd\xE4 joitakin laitteesi tietoja, mutta se on silti yksityisemp\xE4\xE4 kuin videon toistaminen.","informationalModalConfirmButtonText":"Ota k\xE4ytt\xF6\xF6n kaikki esikatselut","informationalModalRejectButtonText":"Ei kiitos","buttonTextUnblockVideo":"Poista YouTube-videon esto","infoTitleUnblockVideo":"DuckDuckGo esti t\xE4m\xE4n YouTube-videon, jotta Google ei voi seurata sinua","infoTextUnblockVideo":"Estimme Googlea (joka omistaa YouTuben) seuraamasta sinua, kun sivua ladattiin. Jos poistat t\xE4m\xE4n videon eston, Google tiet\xE4\xE4 toimintasi.","infoPreviewToggleText":"Esikatselut on poistettu k\xE4yt\xF6st\xE4 yksityisyyden lis\xE4\xE4miseksi","infoPreviewToggleEnabledText":"Esikatselut k\xE4yt\xF6ss\xE4","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-esikatselut k\xE4yt\xF6ss\xE4 DuckDuckGossa.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Lue lis\xE4\xE4</a> DuckDuckGon upotetusta sosiaalisen median suojauksesta"}},"fr":{"facebook.json":{"informationalModalMessageTitle":"L'identification via Facebook leur permet de vous pister","informationalModalMessageBody":"Une fois que vous \xEAtes connect\xE9(e), DuckDuckGo ne peut pas emp\xEAcher le contenu Facebook de vous pister sur ce site.","informationalModalConfirmButtonText":"Connexion","informationalModalRejectButtonText":"Revenir en arri\xE8re","loginButtonText":"S'identifier avec Facebook","loginBodyText":"Facebook piste votre activit\xE9 sur un site lorsque vous l'utilisez pour vous identifier.","buttonTextUnblockContent":"D\xE9bloquer le contenu Facebook","buttonTextUnblockComment":"D\xE9bloquer le commentaire Facebook","buttonTextUnblockComments":"D\xE9bloquer les commentaires Facebook","buttonTextUnblockPost":"D\xE9bloquer la publication Facebook","buttonTextUnblockVideo":"D\xE9bloquer la vid\xE9o Facebook","buttonTextUnblockLogin":"D\xE9bloquer la connexion Facebook","infoTitleUnblockContent":"DuckDuckGo a bloqu\xE9 ce contenu pour emp\xEAcher Facebook de vous suivre","infoTitleUnblockComment":"DuckDuckGo a bloqu\xE9 ce commentaire pour emp\xEAcher Facebook de vous suivre","infoTitleUnblockComments":"DuckDuckGo a bloqu\xE9 ces commentaires pour emp\xEAcher Facebook de vous suivre","infoTitleUnblockPost":"DuckDuckGo a bloqu\xE9 cette publication pour emp\xEAcher Facebook de vous pister","infoTitleUnblockVideo":"DuckDuckGo a bloqu\xE9 cette vid\xE9o pour emp\xEAcher Facebook de vous pister","infoTextUnblockContent":"Nous avons emp\xEAch\xE9 Facebook de vous pister lors du chargement de la page. Si vous d\xE9bloquez ce contenu, Facebook conna\xEEtra votre activit\xE9."},"shared.json":{"learnMore":"En savoir plus","readAbout":"En savoir plus sur cette protection de la confidentialit\xE9","shareFeedback":"Partagez vos commentaires"},"youtube.json":{"informationalModalMessageTitle":"Activer tous les aper\xE7us YouTube\xA0?","informationalModalMessageBody":"L'affichage des aper\xE7us permettra \xE0 Google (propri\xE9taire de YouTube) de voir certaines informations de votre appareil, mais cela reste davantage confidentiel qu'en lisant la vid\xE9o.","informationalModalConfirmButtonText":"Activer tous les aper\xE7us","informationalModalRejectButtonText":"Non merci","buttonTextUnblockVideo":"D\xE9bloquer la vid\xE9o YouTube","infoTitleUnblockVideo":"DuckDuckGo a bloqu\xE9 cette vid\xE9o YouTube pour emp\xEAcher Google de vous pister","infoTextUnblockVideo":"Nous avons emp\xEAch\xE9 Google (propri\xE9taire de YouTube) de vous pister lors du chargement de la page. Si vous d\xE9bloquez cette vid\xE9o, Google conna\xEEtra votre activit\xE9.","infoPreviewToggleText":"Aper\xE7us d\xE9sactiv\xE9s pour plus de confidentialit\xE9","infoPreviewToggleEnabledText":"Aper\xE7us activ\xE9s","infoPreviewToggleEnabledDuckDuckGoText":"Les aper\xE7us YouTube sont activ\xE9s dans DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">En savoir plus</a> sur la protection int\xE9gr\xE9e DuckDuckGo des r\xE9seaux sociaux"}},"hr":{"facebook.json":{"informationalModalMessageTitle":"Prijava putem Facebooka omogu\u0107uje im da te prate","informationalModalMessageBody":"Nakon \u0161to se prijavi\u0161, DuckDuckGo ne mo\u017Ee blokirati Facebookov sadr\u017Eaj da te prati na Facebooku.","informationalModalConfirmButtonText":"Prijavljivanje","informationalModalRejectButtonText":"Vrati se","loginButtonText":"Prijavi se putem Facebooka","loginBodyText":"Facebook prati tvoju aktivnost na toj web lokaciji kad je koristi\u0161 za prijavu.","buttonTextUnblockContent":"Deblokiraj sadr\u017Eaj na Facebooku","buttonTextUnblockComment":"Deblokiraj komentar na Facebooku","buttonTextUnblockComments":"Deblokiraj komentare na Facebooku","buttonTextUnblockPost":"Deblokiraj objavu na Facebooku","buttonTextUnblockVideo":"Deblokiraj videozapis na Facebooku","buttonTextUnblockLogin":"Deblokiraj prijavu na Facebook","infoTitleUnblockContent":"DuckDuckGo je blokirao ovaj sadr\u017Eaj kako bi sprije\u010Dio Facebook da te prati","infoTitleUnblockComment":"DuckDuckGo je blokirao ovaj komentar kako bi sprije\u010Dio Facebook da te prati","infoTitleUnblockComments":"DuckDuckGo je blokirao ove komentare kako bi sprije\u010Dio Facebook da te prati","infoTitleUnblockPost":"DuckDuckGo je blokirao ovu objavu kako bi sprije\u010Dio Facebook da te prati","infoTitleUnblockVideo":"DuckDuckGo je blokirao ovaj video kako bi sprije\u010Dio Facebook da te prati","infoTextUnblockContent":"Blokirali smo Facebook da te prati kad se stranica u\u010Dita. Ako deblokira\u0161 ovaj sadr\u017Eaj, Facebook \u0107e znati tvoju aktivnost."},"shared.json":{"learnMore":"Saznajte vi\u0161e","readAbout":"Pro\u010Ditaj vi\u0161e o ovoj za\u0161titi privatnosti","shareFeedback":"Podijeli povratne informacije"},"youtube.json":{"informationalModalMessageTitle":"Omogu\u0107iti sve YouTube pretpreglede?","informationalModalMessageBody":"Prikazivanje pretpregleda omogu\u0107it \u0107e Googleu (u \u010Dijem je vlasni\u0161tvu YouTube) da vidi neke podatke o tvom ure\u0111aju, ali je i dalje privatnija opcija od reprodukcije videozapisa.","informationalModalConfirmButtonText":"Omogu\u0107i sve pretpreglede","informationalModalRejectButtonText":"Ne, hvala","buttonTextUnblockVideo":"Deblokiraj YouTube videozapis","infoTitleUnblockVideo":"DuckDuckGo je blokirao ovaj YouTube videozapis kako bi sprije\u010Dio Google da te prati","infoTextUnblockVideo":"Blokirali smo Google (u \u010Dijem je vlasni\u0161tvu YouTube) da te prati kad se stranica u\u010Dita. Ako deblokira\u0161 ovaj videozapis, Google \u0107e znati tvoju aktivnost.","infoPreviewToggleText":"Pretpregledi su onemogu\u0107eni radi dodatne privatnosti","infoPreviewToggleEnabledText":"Pretpregledi su omogu\u0107eni","infoPreviewToggleEnabledDuckDuckGoText":"YouTube pretpregledi omogu\u0107eni su u DuckDuckGou.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Saznaj vi\u0161e</a> o uklju\u010Denoj DuckDuckGo za\u0161titi od dru\u0161tvenih medija"}},"hu":{"facebook.json":{"informationalModalMessageTitle":"A Facebookkal val\xF3 bejelentkez\xE9skor a Facebook nyomon k\xF6vethet","informationalModalMessageBody":"Miut\xE1n bejelentkezel, a DuckDuckGo nem fogja tudni blokkolni a Facebook-tartalmat, amely nyomon k\xF6vet ezen az oldalon.","informationalModalConfirmButtonText":"Bejelentkez\xE9s","informationalModalRejectButtonText":"Visszal\xE9p\xE9s","loginButtonText":"Bejelentkez\xE9s Facebookkal","loginBodyText":"Ha a Facebookkal jelentkezel be, nyomon k\xF6vetik a webhelyen v\xE9gzett tev\xE9kenys\xE9gedet.","buttonTextUnblockContent":"Facebook-tartalom felold\xE1sa","buttonTextUnblockComment":"Facebook-hozz\xE1sz\xF3l\xE1s felold\xE1sa","buttonTextUnblockComments":"Facebook-hozz\xE1sz\xF3l\xE1sok felold\xE1sa","buttonTextUnblockPost":"Facebook-bejegyz\xE9s felold\xE1sa","buttonTextUnblockVideo":"Facebook-vide\xF3 felold\xE1sa","buttonTextUnblockLogin":"Facebook-bejelentkez\xE9s felold\xE1sa","infoTitleUnblockContent":"A DuckDuckGo blokkolta ezt a tartalmat, hogy megakad\xE1lyozza a Facebookot a nyomon k\xF6vet\xE9sedben","infoTitleUnblockComment":"A DuckDuckGo blokkolta ezt a hozz\xE1sz\xF3l\xE1st, hogy megakad\xE1lyozza a Facebookot a nyomon k\xF6vet\xE9sedben","infoTitleUnblockComments":"A DuckDuckGo blokkolta ezeket a hozz\xE1sz\xF3l\xE1sokat, hogy megakad\xE1lyozza a Facebookot a nyomon k\xF6vet\xE9sedben","infoTitleUnblockPost":"A DuckDuckGo blokkolta ezt a bejegyz\xE9st, hogy megakad\xE1lyozza a Facebookot a nyomon k\xF6vet\xE9sedben","infoTitleUnblockVideo":"A DuckDuckGo blokkolta ezt a vide\xF3t, hogy megakad\xE1lyozza a Facebookot a nyomon k\xF6vet\xE9sedben","infoTextUnblockContent":"Az oldal bet\xF6lt\xE9sekor blokkoltuk a Facebookot a nyomon k\xF6vet\xE9sedben. Ha feloldod ezt a tartalmat, a Facebook tudni fogja, hogy milyen tev\xE9kenys\xE9get v\xE9gzel."},"shared.json":{"learnMore":"Tov\xE1bbi r\xE9szletek","readAbout":"Tudj meg t\xF6bbet err\u0151l az adatv\xE9delemr\u0151l","shareFeedback":"Visszajelz\xE9s megoszt\xE1sa"},"youtube.json":{"informationalModalMessageTitle":"Enged\xE9lyezed minden YouTube-vide\xF3 el\u0151n\xE9zet\xE9t?","informationalModalMessageBody":"Az el\u0151n\xE9zetek megjelen\xEDt\xE9s\xE9vel a Google (a YouTube tulajdonosa) l\xE1thatja a k\xE9sz\xFCl\xE9k n\xE9h\xE1ny adat\xE1t, de ez adatv\xE9delmi szempontb\xF3l m\xE9g mindig el\u0151ny\xF6sebb, mint a vide\xF3 lej\xE1tsz\xE1sa.","informationalModalConfirmButtonText":"Minden el\u0151n\xE9zet enged\xE9lyez\xE9se","informationalModalRejectButtonText":"Nem, k\xF6sz\xF6n\xF6m","buttonTextUnblockVideo":"YouTube-vide\xF3 felold\xE1sa","infoTitleUnblockVideo":"A DuckDuckGo blokkolta a YouTube-vide\xF3t, hogy a Google ne k\xF6vethessen nyomon","infoTextUnblockVideo":"Blokkoltuk, hogy a Google (a YouTube tulajdonosa) nyomon k\xF6vethessen az oldal bet\xF6lt\xE9sekor. Ha feloldod a vide\xF3 blokkol\xE1s\xE1t, a Google tudni fogja, hogy milyen tev\xE9kenys\xE9get v\xE9gzel.","infoPreviewToggleText":"Az el\u0151n\xE9zetek a fokozott adatv\xE9delem \xE9rdek\xE9ben letiltva","infoPreviewToggleEnabledText":"Az el\u0151n\xE9zetek enged\xE9lyezve","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-el\u0151n\xE9zetek enged\xE9lyezve a DuckDuckGo-ban.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Tov\xE1bbi tudnival\xF3k</a> a DuckDuckGo be\xE1gyazott k\xF6z\xF6ss\xE9gi m\xE9dia elleni v\xE9delm\xE9r\u0151l"}},"it":{"facebook.json":{"informationalModalMessageTitle":"L'accesso con Facebook consente di tracciarti","informationalModalMessageBody":"Dopo aver effettuato l'accesso, DuckDuckGo non pu\xF2 bloccare il tracciamento dei contenuti di Facebook su questo sito.","informationalModalConfirmButtonText":"Accedi","informationalModalRejectButtonText":"Torna indietro","loginButtonText":"Accedi con Facebook","loginBodyText":"Facebook tiene traccia della tua attivit\xE0 su un sito quando lo usi per accedere.","buttonTextUnblockContent":"Sblocca i contenuti di Facebook","buttonTextUnblockComment":"Sblocca il commento di Facebook","buttonTextUnblockComments":"Sblocca i commenti di Facebook","buttonTextUnblockPost":"Sblocca post di Facebook","buttonTextUnblockVideo":"Sblocca video di Facebook","buttonTextUnblockLogin":"Sblocca l'accesso a Facebook","infoTitleUnblockContent":"DuckDuckGo ha bloccato questo contenuto per impedire a Facebook di tracciarti","infoTitleUnblockComment":"DuckDuckGo ha bloccato questo commento per impedire a Facebook di tracciarti","infoTitleUnblockComments":"DuckDuckGo ha bloccato questi commenti per impedire a Facebook di tracciarti","infoTitleUnblockPost":"DuckDuckGo ha bloccato questo post per impedire a Facebook di tracciarti","infoTitleUnblockVideo":"DuckDuckGo ha bloccato questo video per impedire a Facebook di tracciarti","infoTextUnblockContent":"Abbiamo impedito a Facebook di tracciarti al caricamento della pagina. Se sblocchi questo contenuto, Facebook conoscer\xE0 la tua attivit\xE0."},"shared.json":{"learnMore":"Ulteriori informazioni","readAbout":"Leggi di pi\xF9 su questa protezione della privacy","shareFeedback":"Condividi feedback"},"youtube.json":{"informationalModalMessageTitle":"Abilitare tutte le anteprime di YouTube?","informationalModalMessageBody":"La visualizzazione delle anteprime consentir\xE0 a Google (che possiede YouTube) di vedere alcune delle informazioni del tuo dispositivo, ma \xE8 comunque pi\xF9 privato rispetto alla riproduzione del video.","informationalModalConfirmButtonText":"Abilita tutte le anteprime","informationalModalRejectButtonText":"No, grazie","buttonTextUnblockVideo":"Sblocca video YouTube","infoTitleUnblockVideo":"DuckDuckGo ha bloccato questo video di YouTube per impedire a Google di tracciarti","infoTextUnblockVideo":"Abbiamo impedito a Google (che possiede YouTube) di tracciarti quando la pagina \xE8 stata caricata. Se sblocchi questo video, Google conoscer\xE0 la tua attivit\xE0.","infoPreviewToggleText":"Anteprime disabilitate per una maggiore privacy","infoPreviewToggleEnabledText":"Anteprime abilitate","infoPreviewToggleEnabledDuckDuckGoText":"Anteprime YouTube abilitate in DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Scopri di pi\xF9</a> sulla protezione dai social media integrata di DuckDuckGo"}},"lt":{"facebook.json":{"informationalModalMessageTitle":"Prisijung\u0119 prie \u201EFacebook\u201C galite b\u016Bti sekami","informationalModalMessageBody":"Kai esate prisijung\u0119, \u201EDuckDuckGo\u201C negali u\u017Eblokuoti \u201EFacebook\u201C turinio, tod\u0117l esate sekami \u0161ioje svetain\u0117je.","informationalModalConfirmButtonText":"Prisijungti","informationalModalRejectButtonText":"Gr\u012F\u017Eti atgal","loginButtonText":"Prisijunkite su \u201EFacebook\u201C","loginBodyText":"\u201EFacebook\u201C seka j\u016Bs\u0173 veikl\u0105 svetain\u0117je, kai prisijungiate su \u0161ia svetaine.","buttonTextUnblockContent":"Atblokuoti \u201EFacebook\u201C turin\u012F","buttonTextUnblockComment":"Atblokuoti \u201EFacebook\u201C komentar\u0105","buttonTextUnblockComments":"Atblokuoti \u201EFacebook\u201C komentarus","buttonTextUnblockPost":"Atblokuoti \u201EFacebook\u201C \u012Fra\u0161\u0105","buttonTextUnblockVideo":"Atblokuoti \u201EFacebook\u201C vaizdo \u012Fra\u0161\u0105","buttonTextUnblockLogin":"Atblokuoti \u201EFacebook\u201C prisijungim\u0105","infoTitleUnblockContent":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161\u012F turin\u012F, kad \u201EFacebook\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTitleUnblockComment":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161\u012F komentar\u0105, kad \u201EFacebook\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTitleUnblockComments":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161iuos komentarus, kad \u201EFacebook\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTitleUnblockPost":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161\u012F \u012Fra\u0161\u0105, kad \u201EFacebook\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTitleUnblockVideo":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161\u012F vaizdo \u012Fra\u0161\u0105, kad \u201EFacebook\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTextUnblockContent":"U\u017Eblokavome \u201EFacebook\u201C, kad negal\u0117t\u0173 j\u016Bs\u0173 sekti, kai puslapis buvo \u012Fkeltas. Jei atblokuosite \u0161\u012F turin\u012F, \u201EFacebook\u201C \u017Einos apie j\u016Bs\u0173 veikl\u0105."},"shared.json":{"learnMore":"Su\u017Einoti daugiau","readAbout":"Skaitykite apie \u0161i\u0105 privatumo apsaug\u0105","shareFeedback":"Bendrinti atsiliepim\u0105"},"youtube.json":{"informationalModalMessageTitle":"\u012Ejungti visas \u201EYouTube\u201C per\u017Ei\u016Bras?","informationalModalMessageBody":"Per\u017Ei\u016Br\u0173 rodymas leis \u201EGoogle\u201C (kuriai priklauso \u201EYouTube\u201C) matyti tam tikr\u0105 j\u016Bs\u0173 \u012Frenginio informacij\u0105, ta\u010Diau ji vis tiek bus privatesn\u0117 nei leid\u017Eiant vaizdo \u012Fra\u0161\u0105.","informationalModalConfirmButtonText":"\u012Ejungti visas per\u017Ei\u016Bras","informationalModalRejectButtonText":"Ne, d\u0117koju","buttonTextUnblockVideo":"Atblokuoti \u201EYouTube\u201C vaizdo \u012Fra\u0161\u0105","infoTitleUnblockVideo":"\u201EDuckDuckGo\u201C u\u017Eblokavo \u0161\u012F \u201EYouTube\u201C vaizdo \u012Fra\u0161\u0105, kad \u201EGoogle\u201C negal\u0117t\u0173 j\u016Bs\u0173 sekti","infoTextUnblockVideo":"U\u017Eblokavome \u201EGoogle\u201C (kuriai priklauso \u201EYouTube\u201C) galimyb\u0119 sekti jus, kai puslapis buvo \u012Fkeltas. Jei atblokuosite \u0161\u012F vaizdo \u012Fra\u0161\u0105, \u201EGoogle\u201C su\u017Einos apie j\u016Bs\u0173 veikl\u0105.","infoPreviewToggleText":"Per\u017Ei\u016Bros i\u0161jungtos d\u0117l papildomo privatumo","infoPreviewToggleEnabledText":"Per\u017Ei\u016Bros \u012Fjungtos","infoPreviewToggleEnabledDuckDuckGoText":"\u201EYouTube\u201C per\u017Ei\u016Bros \u012Fjungtos \u201EDuckDuckGo\u201C.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Su\u017Einokite daugiau</a> apie \u201EDuckDuckGo\u201C \u012Fd\u0117t\u0105j\u0105 socialin\u0117s \u017Einiasklaidos apsaug\u0105"}},"lv":{"facebook.json":{"informationalModalMessageTitle":"Ja pieteiksies ar Facebook, vi\u0146i var\u0113s tevi izsekot","informationalModalMessageBody":"Kad tu piesakies, DuckDuckGo nevar nov\u0113rst, ka Facebook saturs tevi izseko \u0161aj\u0101 vietn\u0113.","informationalModalConfirmButtonText":"Pieteikties","informationalModalRejectButtonText":"Atgriezties","loginButtonText":"Pieteikties ar Facebook","loginBodyText":"Facebook izseko tavas aktivit\u0101tes vietn\u0113, kad esi pieteicies ar Facebook.","buttonTextUnblockContent":"Atblo\u0137\u0113t Facebook saturu","buttonTextUnblockComment":"Atblo\u0137\u0113t Facebook koment\u0101ru","buttonTextUnblockComments":"Atblo\u0137\u0113t Facebook koment\u0101rus","buttonTextUnblockPost":"Atblo\u0137\u0113t Facebook zi\u0146u","buttonTextUnblockVideo":"Atblo\u0137\u0113t Facebook video","buttonTextUnblockLogin":"Atblo\u0137\u0113t Facebook pieteik\u0161anos","infoTitleUnblockContent":"DuckDuckGo blo\u0137\u0113ja \u0161o saturu, lai ne\u013Cautu Facebook tevi izsekot","infoTitleUnblockComment":"DuckDuckGo blo\u0137\u0113ja \u0161o koment\u0101ru, lai ne\u013Cautu Facebook tevi izsekot","infoTitleUnblockComments":"DuckDuckGo blo\u0137\u0113ja \u0161os koment\u0101rus, lai ne\u013Cautu Facebook tevi izsekot","infoTitleUnblockPost":"DuckDuckGo blo\u0137\u0113ja \u0161o zi\u0146u, lai ne\u013Cautu Facebook tevi izsekot","infoTitleUnblockVideo":"DuckDuckGo blo\u0137\u0113ja \u0161o videoklipu, lai ne\u013Cautu Facebook tevi izsekot","infoTextUnblockContent":"M\u0113s blo\u0137\u0113j\u0101m Facebook iesp\u0113ju tevi izsekot, iel\u0101d\u0113jot lapu. Ja atblo\u0137\u0113si \u0161o saturu, Facebook redz\u0113s, ko tu dari."},"shared.json":{"learnMore":"Uzzin\u0101t vair\u0101k","readAbout":"Lasi par \u0161o priv\u0101tuma aizsardz\u012Bbu","shareFeedback":"Kop\u012Bgot atsauksmi"},"youtube.json":{"informationalModalMessageTitle":"Vai iesp\u0113jot visus YouTube priek\u0161skat\u012Bjumus?","informationalModalMessageBody":"Priek\u0161skat\u012Bjumu r\u0101d\u012B\u0161ana \u013Caus Google (kam pieder YouTube) redz\u0113t da\u013Cu tavas ier\u012Bces inform\u0101cijas, ta\u010Du tas t\u0101pat ir priv\u0101t\u0101k par videoklipa atska\u0146o\u0161anu.","informationalModalConfirmButtonText":"Iesp\u0113jot visus priek\u0161skat\u012Bjumus","informationalModalRejectButtonText":"N\u0113, paldies","buttonTextUnblockVideo":"Atblo\u0137\u0113t YouTube videoklipu","infoTitleUnblockVideo":"DuckDuckGo blo\u0137\u0113ja \u0161o YouTube videoklipu, lai ne\u013Cautu Google tevi izsekot","infoTextUnblockVideo":"M\u0113s ne\u013C\u0101v\u0101m Google (kam pieder YouTube) tevi izsekot, kad lapa tika iel\u0101d\u0113ta. Ja atblo\u0137\u0113si \u0161o videoklipu, Google zin\u0101s, ko tu dari.","infoPreviewToggleText":"Priek\u0161skat\u012Bjumi ir atsp\u0113joti, lai nodro\u0161in\u0101tu papildu konfidencialit\u0101ti","infoPreviewToggleEnabledText":"Priek\u0161skat\u012Bjumi ir iesp\u0113joti","infoPreviewToggleEnabledDuckDuckGoText":"DuckDuckGo iesp\u0113joti YouTube priek\u0161skat\u012Bjumi.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Uzzini vair\u0101k</a> par DuckDuckGo iegulto soci\u0101lo mediju aizsardz\u012Bbu"}},"nb":{"facebook.json":{"informationalModalMessageTitle":"N\xE5r du logger p\xE5 med Facebook, kan de spore deg","informationalModalMessageBody":"N\xE5r du er logget p\xE5, kan ikke DuckDuckGo hindre Facebook-innhold i \xE5 spore deg p\xE5 dette nettstedet.","informationalModalConfirmButtonText":"Logg inn","informationalModalRejectButtonText":"G\xE5 tilbake","loginButtonText":"Logg p\xE5 med Facebook","loginBodyText":"N\xE5r du logger p\xE5 med Facebook, sporer de aktiviteten din p\xE5 nettstedet.","buttonTextUnblockContent":"Fjern blokkering av Facebook-innhold","buttonTextUnblockComment":"Fjern blokkering av Facebook-kommentar","buttonTextUnblockComments":"Fjern blokkering av Facebook-kommentarer","buttonTextUnblockPost":"Fjern blokkering av Facebook-innlegg","buttonTextUnblockVideo":"Fjern blokkering av Facebook-video","buttonTextUnblockLogin":"Fjern blokkering av Facebook-p\xE5logging","infoTitleUnblockContent":"DuckDuckGo blokkerte dette innholdet for \xE5 hindre Facebook i \xE5 spore deg","infoTitleUnblockComment":"DuckDuckGo blokkerte denne kommentaren for \xE5 hindre Facebook i \xE5 spore deg","infoTitleUnblockComments":"DuckDuckGo blokkerte disse kommentarene for \xE5 hindre Facebook i \xE5 spore deg","infoTitleUnblockPost":"DuckDuckGo blokkerte dette innlegget for \xE5 hindre Facebook i \xE5 spore deg","infoTitleUnblockVideo":"DuckDuckGo blokkerte denne videoen for \xE5 hindre Facebook i \xE5 spore deg","infoTextUnblockContent":"Vi hindret Facebook i \xE5 spore deg da siden ble lastet. Hvis du opphever blokkeringen av dette innholdet, f\xE5r Facebook vite om aktiviteten din."},"shared.json":{"learnMore":"Finn ut mer","readAbout":"Les om denne personvernfunksjonen","shareFeedback":"Del tilbakemelding"},"youtube.json":{"informationalModalMessageTitle":"Vil du aktivere alle YouTube-forh\xE5ndsvisninger?","informationalModalMessageBody":"Forh\xE5ndsvisninger gj\xF8r det mulig for Google (som eier YouTube) \xE5 se enkelte opplysninger om enheten din, men det er likevel mer privat enn \xE5 spille av videoen.","informationalModalConfirmButtonText":"Aktiver alle forh\xE5ndsvisninger","informationalModalRejectButtonText":"Nei takk","buttonTextUnblockVideo":"Fjern blokkering av YouTube-video","infoTitleUnblockVideo":"DuckDuckGo blokkerte denne YouTube-videoen for \xE5 hindre Google i \xE5 spore deg","infoTextUnblockVideo":"Vi blokkerte Google (som eier YouTube) mot \xE5 spore deg da siden ble lastet. Hvis du opphever blokkeringen av denne videoen, f\xE5r Google vite om aktiviteten din.","infoPreviewToggleText":"Forh\xE5ndsvisninger er deaktivert for \xE5 gi deg ekstra personvern","infoPreviewToggleEnabledText":"Forh\xE5ndsvisninger er aktivert","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-forh\xE5ndsvisninger er aktivert i DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Finn ut mer</a> om DuckDuckGos innebygde beskyttelse for sosiale medier"}},"nl":{"facebook.json":{"informationalModalMessageTitle":"Als je inlogt met Facebook, kunnen zij je volgen","informationalModalMessageBody":"Als je eenmaal bent ingelogd, kan DuckDuckGo niet voorkomen dat Facebook je op deze site volgt.","informationalModalConfirmButtonText":"Inloggen","informationalModalRejectButtonText":"Terug","loginButtonText":"Inloggen met Facebook","loginBodyText":"Facebook volgt je activiteit op een site als je Facebook gebruikt om in te loggen.","buttonTextUnblockContent":"Facebook-inhoud deblokkeren","buttonTextUnblockComment":"Facebook-opmerkingen deblokkeren","buttonTextUnblockComments":"Facebook-opmerkingen deblokkeren","buttonTextUnblockPost":"Facebook-bericht deblokkeren","buttonTextUnblockVideo":"Facebook-video deblokkeren","buttonTextUnblockLogin":"Facebook-aanmelding deblokkeren","infoTitleUnblockContent":"DuckDuckGo heeft deze inhoud geblokkeerd om te voorkomen dat Facebook je kan volgen","infoTitleUnblockComment":"DuckDuckGo heeft deze opmerking geblokkeerd om te voorkomen dat Facebook je kan volgen","infoTitleUnblockComments":"DuckDuckGo heeft deze opmerkingen geblokkeerd om te voorkomen dat Facebook je kan volgen","infoTitleUnblockPost":"DuckDuckGo heeft dit bericht geblokkeerd om te voorkomen dat Facebook je kan volgen","infoTitleUnblockVideo":"DuckDuckGo heeft deze video geblokkeerd om te voorkomen dat Facebook je kan volgen","infoTextUnblockContent":"We hebben voorkomen dat Facebook je volgde toen de pagina werd geladen. Als je deze inhoud deblokkeert, kan Facebook je activiteit zien."},"shared.json":{"learnMore":"Meer informatie","readAbout":"Lees meer over deze privacybescherming","shareFeedback":"Feedback delen"},"youtube.json":{"informationalModalMessageTitle":"Alle YouTube-voorbeelden inschakelen?","informationalModalMessageBody":"Bij het tonen van voorbeelden kan Google (eigenaar van YouTube) een deel van de informatie over je apparaat zien, maar blijft je privacy beter beschermd dan als je de video zou afspelen.","informationalModalConfirmButtonText":"Alle voorbeelden inschakelen","informationalModalRejectButtonText":"Nee, bedankt","buttonTextUnblockVideo":"YouTube-video deblokkeren","infoTitleUnblockVideo":"DuckDuckGo heeft deze YouTube-video geblokkeerd om te voorkomen dat Google je kan volgen","infoTextUnblockVideo":"We hebben voorkomen dat Google (eigenaar van YouTube) je volgde toen de pagina werd geladen. Als je deze video deblokkeert, kan Google je activiteit zien.","infoPreviewToggleText":"Voorbeelden uitgeschakeld voor extra privacy","infoPreviewToggleEnabledText":"Voorbeelden ingeschakeld","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-voorbeelden ingeschakeld in DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Meer informatie</a> over DuckDuckGo's bescherming tegen ingesloten social media"}},"pl":{"facebook.json":{"informationalModalMessageTitle":"Je\u015Bli zalogujesz si\u0119 za po\u015Brednictwem Facebooka, b\u0119dzie on m\xF3g\u0142 \u015Bledzi\u0107 Twoj\u0105 aktywno\u015B\u0107","informationalModalMessageBody":"Po zalogowaniu si\u0119 DuckDuckGo nie mo\u017Ce zablokowa\u0107 mo\u017Cliwo\u015Bci \u015Bledzenia Ci\u0119 przez Facebooka na tej stronie.","informationalModalConfirmButtonText":"Zaloguj si\u0119","informationalModalRejectButtonText":"Wr\xF3\u0107","loginButtonText":"Zaloguj si\u0119 za po\u015Brednictwem Facebooka","loginBodyText":"Facebook \u015Bledzi Twoj\u0105 aktywno\u015B\u0107 na stronie, gdy logujesz si\u0119 za jego po\u015Brednictwem.","buttonTextUnblockContent":"Odblokuj tre\u015B\u0107 na Facebooku","buttonTextUnblockComment":"Odblokuj komentarz na Facebooku","buttonTextUnblockComments":"Odblokuj komentarze na Facebooku","buttonTextUnblockPost":"Odblokuj post na Facebooku","buttonTextUnblockVideo":"Odblokuj wideo na Facebooku","buttonTextUnblockLogin":"Odblokuj logowanie na Facebooku","infoTitleUnblockContent":"DuckDuckGo zablokowa\u0142 t\u0119 tre\u015B\u0107, aby Facebook nie m\xF3g\u0142 Ci\u0119 \u015Bledzi\u0107","infoTitleUnblockComment":"DuckDuckGo zablokowa\u0142 ten komentarz, aby Facebook nie m\xF3g\u0142 Ci\u0119 \u015Bledzi\u0107","infoTitleUnblockComments":"DuckDuckGo zablokowa\u0142 te komentarze, aby Facebook nie m\xF3g\u0142 Ci\u0119 \u015Bledzi\u0107","infoTitleUnblockPost":"DuckDuckGo zablokowa\u0142 ten post, aby Facebook nie m\xF3g\u0142 Ci\u0119 \u015Bledzi\u0107","infoTitleUnblockVideo":"DuckDuckGo zablokowa\u0142 t\u0119 tre\u015B\u0107 wideo, aby Facebook nie m\xF3g\u0142 Ci\u0119 \u015Bledzi\u0107.","infoTextUnblockContent":"Zablokowali\u015Bmy Facebookowi mo\u017Cliwo\u015B\u0107 \u015Bledzenia Ci\u0119 podczas \u0142adowania strony. Je\u015Bli odblokujesz t\u0119 tre\u015B\u0107, Facebook uzyska informacje o Twojej aktywno\u015Bci."},"shared.json":{"learnMore":"Dowiedz si\u0119 wi\u0119cej","readAbout":"Dowiedz si\u0119 wi\u0119cej o tej ochronie prywatno\u015Bci","shareFeedback":"Podziel si\u0119 opini\u0105"},"youtube.json":{"informationalModalMessageTitle":"W\u0142\u0105czy\u0107 wszystkie podgl\u0105dy w YouTube?","informationalModalMessageBody":"Wy\u015Bwietlanie podgl\u0105du pozwala Google (kt\xF3ry jest w\u0142a\u015Bcicielem YouTube) zobaczy\u0107 niekt\xF3re informacje o Twoim urz\u0105dzeniu, ale nadal jest to bardziej prywatne ni\u017C odtwarzanie filmu.","informationalModalConfirmButtonText":"W\u0142\u0105cz wszystkie podgl\u0105dy","informationalModalRejectButtonText":"Nie, dzi\u0119kuj\u0119","buttonTextUnblockVideo":"Odblokuj wideo w YouTube","infoTitleUnblockVideo":"DuckDuckGo zablokowa\u0142 ten film w YouTube, aby uniemo\u017Cliwi\u0107 Google \u015Bledzenie Twojej aktywno\u015Bci","infoTextUnblockVideo":"Zablokowali\u015Bmy mo\u017Cliwo\u015B\u0107 \u015Bledzenia Ci\u0119 przez Google (w\u0142a\u015Bciciela YouTube) podczas \u0142adowania strony. Je\u015Bli odblokujesz ten film, Google zobaczy Twoj\u0105 aktywno\u015B\u0107.","infoPreviewToggleText":"Podgl\u0105dy zosta\u0142y wy\u0142\u0105czone, aby zapewni\u0107 wi\u0119ksz\u0105 ptywatno\u015B\u0107","infoPreviewToggleEnabledText":"Podgl\u0105dy w\u0142\u0105czone","infoPreviewToggleEnabledDuckDuckGoText":"Podgl\u0105dy YouTube w\u0142\u0105czone w DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Dowiedz si\u0119 wi\u0119cej</a> o zabezpieczeniu osadzonych tre\u015Bci spo\u0142eczno\u015Bciowych DuckDuckGo"}},"pt":{"facebook.json":{"informationalModalMessageTitle":"Iniciar sess\xE3o no Facebook permite que este te rastreie","informationalModalMessageBody":"Depois de iniciares sess\xE3o, o DuckDuckGo n\xE3o poder\xE1 bloquear o rastreio por parte do conte\xFAdo do Facebook neste site.","informationalModalConfirmButtonText":"Iniciar sess\xE3o","informationalModalRejectButtonText":"Retroceder","loginButtonText":"Iniciar sess\xE3o com o Facebook","loginBodyText":"O Facebook rastreia a tua atividade num site quando o usas para iniciares sess\xE3o.","buttonTextUnblockContent":"Desbloquear Conte\xFAdo do Facebook","buttonTextUnblockComment":"Desbloquear Coment\xE1rio do Facebook","buttonTextUnblockComments":"Desbloquear Coment\xE1rios do Facebook","buttonTextUnblockPost":"Desbloquear Publica\xE7\xE3o no Facebook","buttonTextUnblockVideo":"Desbloquear V\xEDdeo do Facebook","buttonTextUnblockLogin":"Desbloquear In\xEDcio de Sess\xE3o no Facebook","infoTitleUnblockContent":"O DuckDuckGo bloqueou este conte\xFAdo para evitar que o Facebook te rastreie","infoTitleUnblockComment":"O DuckDuckGo bloqueou este coment\xE1rio para evitar que o Facebook te rastreie","infoTitleUnblockComments":"O DuckDuckGo bloqueou estes coment\xE1rios para evitar que o Facebook te rastreie","infoTitleUnblockPost":"O DuckDuckGo bloqueou esta publica\xE7\xE3o para evitar que o Facebook te rastreie","infoTitleUnblockVideo":"O DuckDuckGo bloqueou este v\xEDdeo para evitar que o Facebook te rastreie","infoTextUnblockContent":"Bloque\xE1mos o rastreio por parte do Facebook quando a p\xE1gina foi carregada. Se desbloqueares este conte\xFAdo, o Facebook fica a saber a tua atividade."},"shared.json":{"learnMore":"Saiba mais","readAbout":"Ler mais sobre esta prote\xE7\xE3o de privacidade","shareFeedback":"Partilhar coment\xE1rios"},"youtube.json":{"informationalModalMessageTitle":"Ativar todas as pr\xE9-visualiza\xE7\xF5es do YouTube?","informationalModalMessageBody":"Mostrar visualiza\xE7\xF5es permite \xE0 Google (que det\xE9m o YouTube) ver algumas das informa\xE7\xF5es do teu dispositivo, mas ainda \xE9 mais privado do que reproduzir o v\xEDdeo.","informationalModalConfirmButtonText":"Ativar todas as pr\xE9-visualiza\xE7\xF5es","informationalModalRejectButtonText":"N\xE3o, obrigado","buttonTextUnblockVideo":"Desbloquear V\xEDdeo do YouTube","infoTitleUnblockVideo":"O DuckDuckGo bloqueou este v\xEDdeo do YouTube para impedir que a Google te rastreie","infoTextUnblockVideo":"Bloque\xE1mos o rastreio por parte da Google (que det\xE9m o YouTube) quando a p\xE1gina foi carregada. Se desbloqueares este v\xEDdeo, a Google fica a saber a tua atividade.","infoPreviewToggleText":"Pr\xE9-visualiza\xE7\xF5es desativadas para privacidade adicional","infoPreviewToggleEnabledText":"Pr\xE9-visualiza\xE7\xF5es ativadas","infoPreviewToggleEnabledDuckDuckGoText":"Pr\xE9-visualiza\xE7\xF5es do YouTube ativadas no DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Saiba mais</a> sobre a Prote\xE7\xE3o contra conte\xFAdos de redes sociais incorporados do DuckDuckGo"}},"ro":{"facebook.json":{"informationalModalMessageTitle":"Conectarea cu Facebook \xEEi permite s\u0103 te urm\u0103reasc\u0103","informationalModalMessageBody":"Odat\u0103 ce te-ai conectat, DuckDuckGo nu poate \xEEmpiedica con\u021Binutul Facebook s\u0103 te urm\u0103reasc\u0103 pe acest site.","informationalModalConfirmButtonText":"Autentificare","informationalModalRejectButtonText":"\xCEnapoi","loginButtonText":"Conecteaz\u0103-te cu Facebook","loginBodyText":"Facebook urm\u0103re\u0219te activitatea ta pe un site atunci c\xE2nd \xEEl utilizezi pentru a te conecta.","buttonTextUnblockContent":"Deblocheaz\u0103 con\u021Binutul Facebook","buttonTextUnblockComment":"Deblocheaz\u0103 comentariul de pe Facebook","buttonTextUnblockComments":"Deblocheaz\u0103 comentariile de pe Facebook","buttonTextUnblockPost":"Deblocheaz\u0103 postarea de pe Facebook","buttonTextUnblockVideo":"Deblocheaz\u0103 videoclipul de pe Facebook","buttonTextUnblockLogin":"Deblocheaz\u0103 conectarea cu Facebook","infoTitleUnblockContent":"DuckDuckGo a blocat acest con\u021Binut pentru a \xEEmpiedica Facebook s\u0103 te urm\u0103reasc\u0103","infoTitleUnblockComment":"DuckDuckGo a blocat acest comentariu pentru a \xEEmpiedica Facebook s\u0103 te urm\u0103reasc\u0103","infoTitleUnblockComments":"DuckDuckGo a blocat aceste comentarii pentru a \xEEmpiedica Facebook s\u0103 te urm\u0103reasc\u0103","infoTitleUnblockPost":"DuckDuckGo a blocat aceast\u0103 postare pentru a \xEEmpiedica Facebook s\u0103 te urm\u0103reasc\u0103","infoTitleUnblockVideo":"DuckDuckGo a blocat acest videoclip pentru a \xEEmpiedica Facebook s\u0103 te urm\u0103reasc\u0103","infoTextUnblockContent":"Am \xEEmpiedicat Facebook s\u0103 te urm\u0103reasc\u0103 atunci c\xE2nd pagina a fost \xEEnc\u0103rcat\u0103. Dac\u0103 deblochezi acest con\u021Binut, Facebook \xEE\u021Bi va cunoa\u0219te activitatea."},"shared.json":{"learnMore":"Afl\u0103 mai multe","readAbout":"Cite\u0219te despre aceast\u0103 protec\u021Bie a confiden\u021Bialit\u0103\u021Bii","shareFeedback":"Partajeaz\u0103 feedback"},"youtube.json":{"informationalModalMessageTitle":"Activezi toate previzualiz\u0103rile YouTube?","informationalModalMessageBody":"Afi\u0219area previzualiz\u0103rilor va permite ca Google (care de\u021Bine YouTube) s\u0103 vad\u0103 unele dintre informa\u021Biile despre dispozitivul t\u0103u, dar este totu\u0219i mai privat\u0103 dec\xE2t redarea videoclipului.","informationalModalConfirmButtonText":"Activeaz\u0103 toate previzualiz\u0103rile","informationalModalRejectButtonText":"Nu, mul\u021Bumesc","buttonTextUnblockVideo":"Deblocheaz\u0103 videoclipul de pe YouTube","infoTitleUnblockVideo":"DuckDuckGo a blocat acest videoclip de pe YouTube pentru a \xEEmpiedica Google s\u0103 te urm\u0103reasc\u0103","infoTextUnblockVideo":"Am \xEEmpiedicat Google (care de\u021Bine YouTube) s\u0103 te urm\u0103reasc\u0103 atunci c\xE2nd s-a \xEEnc\u0103rcat pagina. Dac\u0103 deblochezi acest videoclip, Google va cunoa\u0219te activitatea ta.","infoPreviewToggleText":"Previzualiz\u0103rile au fost dezactivate pentru o confiden\u021Bialitate suplimentar\u0103","infoPreviewToggleEnabledText":"Previzualiz\u0103ri activate","infoPreviewToggleEnabledDuckDuckGoText":"Previzualiz\u0103rile YouTube sunt activate \xEEn DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Afl\u0103 mai multe</a> despre Protec\u021Bia integrat\u0103 DuckDuckGo pentru re\u021Belele sociale"}},"ru":{"facebook.json":{"informationalModalMessageTitle":"\u0412\u0445\u043E\u0434 \u0447\u0435\u0440\u0435\u0437 Facebook \u043F\u043E\u0437\u0432\u043E\u043B\u044F\u0435\u0442 \u044D\u0442\u043E\u0439 \u0441\u043E\u0446\u0438\u0430\u043B\u044C\u043D\u043E\u0439 \u0441\u0435\u0442\u0438 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u0442\u044C \u0432\u0430\u0441","informationalModalMessageBody":"\u041F\u043E\u0441\u043B\u0435 \u0432\u0445\u043E\u0434\u0430 DuckDuckGo \u043D\u0435 \u0441\u043C\u043E\u0436\u0435\u0442 \u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043D\u0438\u0435 \u0432\u0430\u0448\u0438\u0445 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0439 \u0441 \u043A\u043E\u043D\u0442\u0435\u043D\u0442\u043E\u043C \u043D\u0430 Facebook.","informationalModalConfirmButtonText":"\u0412\u043E\u0439\u0442\u0438","informationalModalRejectButtonText":"\u0412\u0435\u0440\u043D\u0443\u0442\u044C\u0441\u044F","loginButtonText":"\u0412\u043E\u0439\u0442\u0438 \u0447\u0435\u0440\u0435\u0437 Facebook","loginBodyText":"\u041F\u0440\u0438 \u0438\u0441\u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u043D\u0438\u0438 \u0443\u0447\u0451\u0442\u043D\u043E\u0439 \u0437\u0430\u043F\u0438\u0441\u0438 Facebook \u0434\u043B\u044F \u0432\u0445\u043E\u0434\u0430 \u043D\u0430 \u0441\u0430\u0439\u0442\u044B \u044D\u0442\u0430 \u0441\u043E\u0446\u0438\u0430\u043B\u044C\u043D\u0430\u044F \u0441\u0435\u0442\u044C \u0441\u043C\u043E\u0436\u0435\u0442 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u0442\u044C \u043D\u0430 \u043D\u0438\u0445 \u0432\u0430\u0448\u0438 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u044F.","buttonTextUnblockContent":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043A\u043E\u043D\u0442\u0435\u043D\u0442 \u0438\u0437 Facebook","buttonTextUnblockComment":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0439 \u0438\u0437 Facebook","buttonTextUnblockComments":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0438 \u0438\u0437 Facebook","buttonTextUnblockPost":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u044E \u0438\u0437 Facebook","buttonTextUnblockVideo":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432\u0438\u0434\u0435\u043E \u0438\u0437 Facebook","buttonTextUnblockLogin":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043E\u043A\u043D\u043E \u0432\u0445\u043E\u0434\u0430 \u0432 Facebook","infoTitleUnblockContent":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u043E\u0442 \u043A\u043E\u043D\u0442\u0435\u043D\u0442, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Facebook","infoTitleUnblockComment":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u043E\u0442 \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0439, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Facebook","infoTitleUnblockComments":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u0438 \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0438, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Facebook","infoTitleUnblockPost":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u0443 \u043F\u0443\u0431\u043B\u0438\u043A\u0430\u0446\u0438\u044E, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Facebook","infoTitleUnblockVideo":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u043E \u0432\u0438\u0434\u0435\u043E, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Facebook","infoTextUnblockContent":"\u0412\u043E \u0432\u0440\u0435\u043C\u044F \u0437\u0430\u0433\u0440\u0443\u0437\u043A\u0438 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u044B \u043C\u044B \u043F\u043E\u043C\u0435\u0448\u0430\u043B\u0438 Facebook \u043E\u0442\u0441\u043B\u0435\u0434\u0438\u0442\u044C \u0432\u0430\u0448\u0438 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u044F. \u0415\u0441\u043B\u0438 \u0440\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u044D\u0442\u043E\u0442 \u043A\u043E\u043D\u0442\u0435\u043D\u0442, Facebook \u0441\u043C\u043E\u0436\u0435\u0442 \u0444\u0438\u043A\u0441\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432\u0430\u0448\u0443 \u0430\u043A\u0442\u0438\u0432\u043D\u043E\u0441\u0442\u044C."},"shared.json":{"learnMore":"\u0423\u0437\u043D\u0430\u0442\u044C \u0431\u043E\u043B\u044C\u0448\u0435","readAbout":"\u041F\u043E\u0434\u0440\u043E\u0431\u043D\u0435\u0435 \u043E\u0431 \u044D\u0442\u043E\u043C \u0432\u0438\u0434\u0435 \u0437\u0430\u0449\u0438\u0442\u044B \u043A\u043E\u043D\u0444\u0438\u0434\u0435\u043D\u0446\u0438\u0430\u043B\u044C\u043D\u043E\u0441\u0442\u0438","shareFeedback":"\u041E\u0441\u0442\u0430\u0432\u044C\u0442\u0435 \u043D\u0430\u043C \u043E\u0442\u0437\u044B\u0432"},"youtube.json":{"informationalModalMessageTitle":"\u0412\u043A\u043B\u044E\u0447\u0438\u0442\u044C \u043F\u0440\u0435\u0434\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440 \u0432\u0438\u0434\u0435\u043E \u0438\u0437 YouTube?","informationalModalMessageBody":"\u0412\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u0435 \u043F\u0440\u0435\u0434\u0432\u0430\u0440\u0438\u0442\u0435\u043B\u044C\u043D\u043E\u0433\u043E \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0430 \u043F\u043E\u0437\u0432\u043E\u043B\u0438\u0442 Google (\u0432\u043B\u0430\u0434\u0435\u043B\u044C\u0446\u0443 YouTube) \u043F\u043E\u043B\u0443\u0447\u0438\u0442\u044C \u043D\u0435\u043A\u043E\u0442\u043E\u0440\u044B\u0435 \u0441\u0432\u0435\u0434\u0435\u043D\u0438\u044F \u043E \u0432\u0430\u0448\u0435\u043C \u0443\u0441\u0442\u0440\u043E\u0439\u0441\u0442\u0432\u0435, \u043E\u0434\u043D\u0430\u043A\u043E \u044D\u0442\u043E \u0431\u043E\u043B\u0435\u0435 \u0431\u0435\u0437\u043E\u043F\u0430\u0441\u043D\u044B\u0439 \u0432\u0430\u0440\u0438\u0430\u043D\u0442, \u0447\u0435\u043C \u0432\u043E\u0441\u043F\u0440\u043E\u0438\u0437\u0432\u0435\u0434\u0435\u043D\u0438\u0435 \u0432\u0438\u0434\u0435\u043E \u0446\u0435\u043B\u0438\u043A\u043E\u043C.","informationalModalConfirmButtonText":"\u0412\u043A\u043B\u044E\u0447\u0438\u0442\u044C \u043F\u0440\u0435\u0434\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440","informationalModalRejectButtonText":"\u041D\u0435\u0442, \u0441\u043F\u0430\u0441\u0438\u0431\u043E","buttonTextUnblockVideo":"\u0420\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432\u0438\u0434\u0435\u043E \u0438\u0437 YouTube","infoTitleUnblockVideo":"DuckDuckGo \u0437\u0430\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u043B \u044D\u0442\u043E \u0432\u0438\u0434\u0435\u043E \u0438\u0437 YouTube, \u0447\u0442\u043E\u0431\u044B \u0432\u0430\u0441 \u043D\u0435 \u043E\u0442\u0441\u043B\u0435\u0436\u0438\u0432\u0430\u043B Google","infoTextUnblockVideo":"\u0412\u043E \u0432\u0440\u0435\u043C\u044F \u0437\u0430\u0433\u0440\u0443\u0437\u043A\u0438 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u044B \u043C\u044B \u043F\u043E\u043C\u0435\u0448\u0430\u043B\u0438 Google (\u0432\u043B\u0430\u0434\u0435\u043B\u044C\u0446\u0443 YouTube) \u043E\u0442\u0441\u043B\u0435\u0434\u0438\u0442\u044C \u0432\u0430\u0448\u0438 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u044F. \u0415\u0441\u043B\u0438 \u0440\u0430\u0437\u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432\u0438\u0434\u0435\u043E, Google \u0441\u043C\u043E\u0436\u0435\u0442 \u0444\u0438\u043A\u0441\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432\u0430\u0448\u0443 \u0430\u043A\u0442\u0438\u0432\u043D\u043E\u0441\u0442\u044C.","infoPreviewToggleText":"\u041F\u0440\u0435\u0434\u0432\u0430\u0440\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440 \u043E\u0442\u043A\u043B\u044E\u0447\u0451\u043D \u0434\u043B\u044F \u0434\u043E\u043F\u043E\u043B\u043D\u0438\u0442\u0435\u043B\u044C\u043D\u043E\u0439 \u0437\u0430\u0449\u0438\u0442\u044B \u043A\u043E\u043D\u0444\u0438\u0434\u0435\u043D\u0446\u0438\u0430\u043B\u044C\u043D\u043E\u0441\u0442\u0438","infoPreviewToggleEnabledText":"\u041F\u0440\u0435\u0434\u0432\u0430\u0440\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440 \u0432\u043A\u043B\u044E\u0447\u0451\u043D","infoPreviewToggleEnabledDuckDuckGoText":"\u0412 DuckDuckGo \u0432\u043A\u043B\u044E\u0447\u0451\u043D \u043F\u0440\u0435\u0434\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440 \u0432\u0438\u0434\u0435\u043E \u0438\u0437 YouTube.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">\u041F\u043E\u0434\u0440\u043E\u0431\u043D\u0435\u0435</a> \u043E \u0437\u0430\u0449\u0438\u0442\u0435 DuckDuckGo \u043E\u0442 \u0432\u043D\u0435\u0434\u0440\u0451\u043D\u043D\u043E\u0433\u043E \u043A\u043E\u043D\u0442\u0435\u043D\u0442\u0430 \u0441\u043E\u0446\u0441\u0435\u0442\u0435\u0439"}},"sk":{"facebook.json":{"informationalModalMessageTitle":"Prihl\xE1senie cez Facebook mu umo\u017En\xED sledova\u0165 v\xE1s","informationalModalMessageBody":"DuckDuckGo po prihl\xE1sen\xED nem\xF4\u017Ee na tejto lokalite zablokova\u0165 sledovanie va\u0161ej osoby obsahom Facebooku.","informationalModalConfirmButtonText":"Prihl\xE1si\u0165 sa","informationalModalRejectButtonText":"Prejs\u0165 sp\xE4\u0165","loginButtonText":"Prihl\xE1ste sa pomocou slu\u017Eby Facebook","loginBodyText":"Ke\u010F pou\u017Eijete prihlasovanie cez Facebook, Facebook bude na lokalite sledova\u0165 va\u0161u aktivitu.","buttonTextUnblockContent":"Odblokova\u0165 obsah Facebooku","buttonTextUnblockComment":"Odblokova\u0165 koment\xE1r na Facebooku","buttonTextUnblockComments":"Odblokova\u0165 koment\xE1re na Facebooku","buttonTextUnblockPost":"Odblokova\u0165 pr\xEDspevok na Facebooku","buttonTextUnblockVideo":"Odblokovanie videa na Facebooku","buttonTextUnblockLogin":"Odblokova\u0165 prihl\xE1senie na Facebook","infoTitleUnblockContent":"DuckDuckGo zablokoval tento obsah, aby v\xE1s Facebook nesledoval","infoTitleUnblockComment":"DuckDuckGo zablokoval tento koment\xE1r, aby zabr\xE1nil sledovaniu zo strany Facebooku","infoTitleUnblockComments":"DuckDuckGo zablokoval tieto koment\xE1re, aby v\xE1s Facebook nesledoval","infoTitleUnblockPost":"DuckDuckGo zablokoval tento pr\xEDspevok, aby v\xE1s Facebook nesledoval","infoTitleUnblockVideo":"DuckDuckGo zablokoval toto video, aby v\xE1s Facebook nesledoval","infoTextUnblockContent":"Pri na\u010D\xEDtan\xED str\xE1nky sme zablokovali Facebook, aby v\xE1s nesledoval. Ak tento obsah odblokujete, Facebook bude vedie\u0165 o va\u0161ej aktivite."},"shared.json":{"learnMore":"Zistite viac","readAbout":"Pre\u010D\xEDtajte si o tejto ochrane s\xFAkromia","shareFeedback":"Zdie\u013Ea\u0165 sp\xE4tn\xFA v\xE4zbu"},"youtube.json":{"informationalModalMessageTitle":"Chcete povoli\u0165 v\u0161etky uk\xE1\u017Eky zo slu\u017Eby YouTube?","informationalModalMessageBody":"Zobrazenie uk\xE1\u017Eok umo\u017En\xED spolo\u010Dnosti Google (ktor\xE1 vlastn\xED YouTube) vidie\u0165 niektor\xE9 inform\xE1cie o va\u0161om zariaden\xED, ale st\xE1le je to s\xFAkromnej\u0161ie ako prehr\xE1vanie videa.","informationalModalConfirmButtonText":"Povoli\u0165 v\u0161etky uk\xE1\u017Eky","informationalModalRejectButtonText":"Nie, \u010Fakujem","buttonTextUnblockVideo":"Odblokova\u0165 YouTube video","infoTitleUnblockVideo":"DuckDuckGo toto video v slu\u017Ebe YouTube zablokoval s cie\u013Eom pred\xEDs\u0165 tomu, aby v\xE1s spolo\u010Dnos\u0165 Google mohla sledova\u0165","infoTextUnblockVideo":"Zablokovali sme pre spolo\u010Dnos\u0165 Google (ktor\xE1 vlastn\xED YouTube), aby v\xE1s nemohla sledova\u0165, ke\u010F sa str\xE1nka na\u010D\xEDta. Ak toto video odblokujete, Google bude pozna\u0165 va\u0161u aktivitu.","infoPreviewToggleText":"Uk\xE1\u017Eky s\xFA zak\xE1zan\xE9 s cie\u013Eom zv\xFD\u0161i\u0165 ochranu s\xFAkromia","infoPreviewToggleEnabledText":"Uk\xE1\u017Eky s\xFA povolen\xE9","infoPreviewToggleEnabledDuckDuckGoText":"Uk\xE1\u017Eky YouTube s\xFA v DuckDuckGo povolen\xE9.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Z\xEDskajte viac inform\xE1ci\xED</a> o DuckDuckGo, vlo\u017Eenej ochrane soci\xE1lnych m\xE9di\xED"}},"sl":{"facebook.json":{"informationalModalMessageTitle":"\u010Ce se prijavite s Facebookom, vam Facebook lahko sledi","informationalModalMessageBody":"Ko ste enkrat prijavljeni, DuckDuckGo ne more blokirati Facebookove vsebine, da bi vam sledila na tem spletnem mestu.","informationalModalConfirmButtonText":"Prijava","informationalModalRejectButtonText":"Pojdi nazaj","loginButtonText":"Prijavite se s Facebookom","loginBodyText":"\u010Ce se prijavite s Facebookom, bo nato spremljal va\u0161a dejanja na spletnem mestu.","buttonTextUnblockContent":"Odblokiraj vsebino na Facebooku","buttonTextUnblockComment":"Odblokiraj komentar na Facebooku","buttonTextUnblockComments":"Odblokiraj komentarje na Facebooku","buttonTextUnblockPost":"Odblokiraj objavo na Facebooku","buttonTextUnblockVideo":"Odblokiraj videoposnetek na Facebooku","buttonTextUnblockLogin":"Odblokiraj prijavo na Facebooku","infoTitleUnblockContent":"DuckDuckGo je blokiral to vsebino, da bi Facebooku prepre\u010Dil sledenje","infoTitleUnblockComment":"DuckDuckGo je blokiral ta komentar, da bi Facebooku prepre\u010Dil sledenje","infoTitleUnblockComments":"DuckDuckGo je blokiral te komentarje, da bi Facebooku prepre\u010Dil sledenje","infoTitleUnblockPost":"DuckDuckGo je blokiral to objavo, da bi Facebooku prepre\u010Dil sledenje","infoTitleUnblockVideo":"DuckDuckGo je blokiral ta videoposnetek, da bi Facebooku prepre\u010Dil sledenje","infoTextUnblockContent":"Ko se je stran nalo\u017Eila, smo Facebooku prepre\u010Dili, da bi vam sledil. \u010Ce to vsebino odblokirate, bo Facebook izvedel za va\u0161a dejanja."},"shared.json":{"learnMore":"Ve\u010D","readAbout":"Preberite ve\u010D o tej za\u0161\u010Diti zasebnosti","shareFeedback":"Deli povratne informacije"},"youtube.json":{"informationalModalMessageTitle":"\u017Delite omogo\u010Diti vse YouTubove predoglede?","informationalModalMessageBody":"Prikaz predogledov omogo\u010Da Googlu (ki je lastnik YouTuba) vpogled v nekatere podatke o napravi, vendar je \u0161e vedno bolj zasebno kot predvajanje videoposnetka.","informationalModalConfirmButtonText":"Omogo\u010Di vse predoglede","informationalModalRejectButtonText":"Ne, hvala","buttonTextUnblockVideo":"Odblokiraj videoposnetek na YouTubu","infoTitleUnblockVideo":"DuckDuckGo je blokiral ta videoposnetek v YouTubu, da bi Googlu prepre\u010Dil sledenje","infoTextUnblockVideo":"Googlu (ki je lastnik YouTuba) smo prepre\u010Dili, da bi vam sledil, ko se je stran nalo\u017Eila. \u010Ce odblokirate ta videoposnetek, bo Google izvedel za va\u0161o dejavnost.","infoPreviewToggleText":"Predogledi so zaradi dodatne zasebnosti onemogo\u010Deni","infoPreviewToggleEnabledText":"Predogledi so omogo\u010Deni","infoPreviewToggleEnabledDuckDuckGoText":"YouTubovi predogledi so omogo\u010Deni v DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">Ve\u010D</a> o vgrajeni za\u0161\u010Diti dru\u017Ebenih medijev DuckDuckGo"}},"sv":{"facebook.json":{"informationalModalMessageTitle":"Om du loggar in med Facebook kan de sp\xE5ra dig","informationalModalMessageBody":"N\xE4r du v\xE4l \xE4r inloggad kan DuckDuckGo inte hindra Facebooks inneh\xE5ll fr\xE5n att sp\xE5ra dig p\xE5 den h\xE4r webbplatsen.","informationalModalConfirmButtonText":"Logga in","informationalModalRejectButtonText":"G\xE5 tillbaka","loginButtonText":"Logga in med Facebook","loginBodyText":"Facebook sp\xE5rar din aktivitet p\xE5 en webbplats om du anv\xE4nder det f\xF6r att logga in.","buttonTextUnblockContent":"Avblockera Facebook-inneh\xE5ll","buttonTextUnblockComment":"Avblockera Facebook-kommentar","buttonTextUnblockComments":"Avblockera Facebook-kommentarer","buttonTextUnblockPost":"Avblockera Facebook-inl\xE4gg","buttonTextUnblockVideo":"Avblockera Facebook-video","buttonTextUnblockLogin":"Avblockera Facebook-inloggning","infoTitleUnblockContent":"DuckDuckGo blockerade det h\xE4r inneh\xE5llet f\xF6r att f\xF6rhindra att Facebook sp\xE5rar dig","infoTitleUnblockComment":"DuckDuckGo blockerade den h\xE4r kommentaren f\xF6r att f\xF6rhindra att Facebook sp\xE5rar dig","infoTitleUnblockComments":"DuckDuckGo blockerade de h\xE4r kommentarerna f\xF6r att f\xF6rhindra att Facebook sp\xE5rar dig","infoTitleUnblockPost":"DuckDuckGo blockerade det h\xE4r inl\xE4gget f\xF6r att f\xF6rhindra att Facebook sp\xE5rar dig","infoTitleUnblockVideo":"DuckDuckGo blockerade den h\xE4r videon f\xF6r att f\xF6rhindra att Facebook sp\xE5rar dig","infoTextUnblockContent":"Vi hindrade Facebook fr\xE5n att sp\xE5ra dig n\xE4r sidan l\xE4stes in. Om du avblockerar det h\xE4r inneh\xE5llet kommer Facebook att k\xE4nna till din aktivitet."},"shared.json":{"learnMore":"L\xE4s mer","readAbout":"L\xE4s mer om detta integritetsskydd","shareFeedback":"Ber\xE4tta vad du tycker"},"youtube.json":{"informationalModalMessageTitle":"Aktivera alla f\xF6rhandsvisningar f\xF6r YouTube?","informationalModalMessageBody":"Genom att visa f\xF6rhandsvisningar kan Google (som \xE4ger YouTube) se en del av enhetens information, men det \xE4r \xE4nd\xE5 mer privat \xE4n att spela upp videon.","informationalModalConfirmButtonText":"Aktivera alla f\xF6rhandsvisningar","informationalModalRejectButtonText":"Nej tack","buttonTextUnblockVideo":"Avblockera YouTube-video","infoTitleUnblockVideo":"DuckDuckGo blockerade den h\xE4r YouTube-videon f\xF6r att f\xF6rhindra att Google sp\xE5rar dig","infoTextUnblockVideo":"Vi hindrade Google (som \xE4ger YouTube) fr\xE5n att sp\xE5ra dig n\xE4r sidan laddades. Om du tar bort blockeringen av videon kommer Google att k\xE4nna till din aktivitet.","infoPreviewToggleText":"F\xF6rhandsvisningar har inaktiverats f\xF6r ytterligare integritet","infoPreviewToggleEnabledText":"F\xF6rhandsvisningar aktiverade","infoPreviewToggleEnabledDuckDuckGoText":"YouTube-f\xF6rhandsvisningar aktiverade i DuckDuckGo.","infoPreviewInfoText":"<a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">L\xE4s mer</a> om DuckDuckGos skydd mot inb\xE4ddade sociala medier"}},"tr":{"facebook.json":{"informationalModalMessageTitle":"Facebook ile giri\u015F yapmak, sizi takip etmelerini sa\u011Flar","informationalModalMessageBody":"Giri\u015F yapt\u0131ktan sonra, DuckDuckGo Facebook i\xE7eri\u011Finin sizi bu sitede izlemesini engelleyemez.","informationalModalConfirmButtonText":"Oturum A\xE7","informationalModalRejectButtonText":"Geri d\xF6n","loginButtonText":"Facebook ile giri\u015F yap\u0131n","loginBodyText":"Facebook, giri\u015F yapmak i\xE7in kulland\u0131\u011F\u0131n\u0131zda bir sitedeki etkinli\u011Finizi izler.","buttonTextUnblockContent":"Facebook \u0130\xE7eri\u011Finin Engelini Kald\u0131r","buttonTextUnblockComment":"Facebook Yorumunun Engelini Kald\u0131r","buttonTextUnblockComments":"Facebook Yorumlar\u0131n\u0131n Engelini Kald\u0131r","buttonTextUnblockPost":"Facebook G\xF6nderisinin Engelini Kald\u0131r","buttonTextUnblockVideo":"Facebook Videosunun Engelini Kald\u0131r","buttonTextUnblockLogin":"Facebook Giri\u015Finin Engelini Kald\u0131r","infoTitleUnblockContent":"DuckDuckGo, Facebook'un sizi izlemesini \xF6nlemek i\xE7in bu i\xE7eri\u011Fi engelledi","infoTitleUnblockComment":"DuckDuckGo, Facebook'un sizi izlemesini \xF6nlemek i\xE7in bu yorumu engelledi","infoTitleUnblockComments":"DuckDuckGo, Facebook'un sizi izlemesini \xF6nlemek i\xE7in bu yorumlar\u0131 engelledi","infoTitleUnblockPost":"DuckDuckGo, Facebook'un sizi izlemesini \xF6nlemek i\xE7in bu g\xF6nderiyi engelledi","infoTitleUnblockVideo":"DuckDuckGo, Facebook'un sizi izlemesini \xF6nlemek i\xE7in bu videoyu engelledi","infoTextUnblockContent":"Sayfa y\xFCklendi\u011Finde Facebook'un sizi izlemesini engelledik. Bu i\xE7eri\u011Fin engelini kald\u0131r\u0131rsan\u0131z Facebook etkinli\u011Finizi \xF6\u011Frenecektir."},"shared.json":{"learnMore":"Daha Fazla Bilgi","readAbout":"Bu gizlilik korumas\u0131 hakk\u0131nda bilgi edinin","shareFeedback":"Geri Bildirim Payla\u015F"},"youtube.json":{"informationalModalMessageTitle":"T\xFCm YouTube \xF6nizlemeleri etkinle\u015Ftirilsin mi?","informationalModalMessageBody":"\xD6nizlemelerin g\xF6sterilmesi Google'\u0131n (YouTube'un sahibi) cihaz\u0131n\u0131z\u0131n baz\u0131 bilgilerini g\xF6rmesine izin verir, ancak yine de videoyu oynatmaktan daha \xF6zeldir.","informationalModalConfirmButtonText":"T\xFCm \xD6nizlemeleri Etkinle\u015Ftir","informationalModalRejectButtonText":"Hay\u0131r Te\u015Fekk\xFCrler","buttonTextUnblockVideo":"YouTube Videosunun Engelini Kald\u0131r","infoTitleUnblockVideo":"DuckDuckGo, Google'\u0131n sizi izlemesini \xF6nlemek i\xE7in bu YouTube videosunu engelledi","infoTextUnblockVideo":"Sayfa y\xFCklendi\u011Finde Google'\u0131n (YouTube'un sahibi) sizi izlemesini engelledik. Bu videonun engelini kald\u0131r\u0131rsan\u0131z, Google etkinli\u011Finizi \xF6\u011Frenecektir.","infoPreviewToggleText":"Ek gizlilik i\xE7in \xF6nizlemeler devre d\u0131\u015F\u0131 b\u0131rak\u0131ld\u0131","infoPreviewToggleEnabledText":"\xD6nizlemeler etkinle\u015Ftirildi","infoPreviewToggleEnabledDuckDuckGoText":"DuckDuckGo'da YouTube \xF6nizlemeleri etkinle\u015Ftirildi.","infoPreviewInfoText":"DuckDuckGo Yerle\u015Fik Sosyal Medya Korumas\u0131 hakk\u0131nda <a href=\\"https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/\\">daha fazla bilgi edinin</a>"}}}`;

  // src/features/click-to-load/ctl-config.js
  function getStyles(assets) {
    let fontStyle = "";
    let regularFontFamily = "system, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol'";
    let boldFontFamily = regularFontFamily;
    if (assets?.regularFontUrl && assets?.boldFontUrl) {
      fontStyle = `
        @font-face{
            font-family: DuckDuckGoPrivacyEssentials;
            src: url(${assets.regularFontUrl});
        }
        @font-face{
            font-family: DuckDuckGoPrivacyEssentialsBold;
            font-weight: bold;
            src: url(${assets.boldFontUrl});
        }
    `;
      regularFontFamily = "DuckDuckGoPrivacyEssentials";
      boldFontFamily = "DuckDuckGoPrivacyEssentialsBold";
    }
    return {
      fontStyle,
      darkMode: {
        background: `
            background: #111111;
        `,
        textFont: `
            color: rgba(255, 255, 255, 0.9);
        `,
        buttonFont: `
            color: #111111;
        `,
        linkFont: `
            color: #7295F6;
        `,
        buttonBackground: `
            background: #5784FF;
        `,
        buttonBackgroundHover: `
            background: #557FF3;
        `,
        buttonBackgroundPress: `
            background: #3969EF;
        `,
        toggleButtonText: `
            color: #EEEEEE;
        `,
        toggleButtonBgState: {
          active: `
                background: #5784FF;
            `,
          inactive: `
                background-color: #666666;
            `
        }
      },
      lightMode: {
        background: `
            background: #FFFFFF;
        `,
        textFont: `
            color: #222222;
        `,
        buttonFont: `
            color: #FFFFFF;
        `,
        linkFont: `
            color: #3969EF;
        `,
        buttonBackground: `
            background: #3969EF;
        `,
        buttonBackgroundHover: `
            background: #2B55CA;
        `,
        buttonBackgroundPress: `
            background: #1E42A4;
        `,
        toggleButtonText: `
            color: #666666;
        `,
        toggleButtonBgState: {
          active: `
                background: #3969EF;
            `,
          inactive: `
                background-color: #666666;
            `
        }
      },
      loginMode: {
        buttonBackground: `
            background: #666666;
        `,
        buttonFont: `
            color: #FFFFFF;
        `
      },
      cancelMode: {
        buttonBackground: `
            background: rgba(34, 34, 34, 0.1);
        `,
        buttonFont: `
            color: #222222;
        `,
        buttonBackgroundHover: `
            background: rgba(0, 0, 0, 0.12);
        `,
        buttonBackgroundPress: `
            background: rgba(0, 0, 0, 0.18);
        `
      },
      button: `
        border-radius: 8px;

        padding: 11px 22px;
        font-weight: bold;
        margin: 0px auto;
        border-color: #3969EF;
        border: none;

        font-family: ${boldFontFamily};
        font-size: 14px;

        position: relative;
        cursor: pointer;
        box-shadow: none;
        z-index: 2147483646;
    `,
      circle: `
        border-radius: 50%;
        width: 18px;
        height: 18px;
        background: #E0E0E0;
        border: 1px solid #E0E0E0;
        position: absolute;
        top: -8px;
        right: -8px;
    `,
      loginIcon: `
        position: absolute;
        top: -13px;
        right: -10px;
        height: 28px;
        width: 28px;
    `,
      rectangle: `
        width: 12px;
        height: 3px;
        background: #666666;
        position: relative;
        top: 42.5%;
        margin: auto;
    `,
      textBubble: `
        background: #FFFFFF;
        border: 1px solid rgba(0, 0, 0, 0.1);
        border-radius: 16px;
        box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.12), 0px 8px 16px rgba(0, 0, 0, 0.08);
        width: 360px;
        margin-top: 10px;
        z-index: 2147483647;
        position: absolute;
        line-height: normal;
    `,
      textBubbleWidth: 360,
      // Should match the width rule in textBubble
      textBubbleLeftShift: 100,
      // Should match the CSS left: rule in textBubble
      textArrow: `
        display: inline-block;
        background: #FFFFFF;
        border: solid rgba(0, 0, 0, 0.1);
        border-width: 0 1px 1px 0;
        padding: 5px;
        transform: rotate(-135deg);
        -webkit-transform: rotate(-135deg);
        position: relative;
        top: -9px;
    `,
      arrowDefaultLocationPercent: 50,
      hoverTextTitle: `
        padding: 0px 12px 12px;
        margin-top: -5px;
    `,
      hoverTextBody: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        margin: auto;
        padding: 17px;
        text-align: left;
    `,
      hoverContainer: `
        padding-bottom: 10px;
    `,
      buttonTextContainer: `
        display: flex;
        flex-direction: row;
        align-items: center;
        border: none;
        padding: 0;
        margin: 0;
    `,
      headerRow: `

    `,
      block: `
        box-sizing: border-box;
        border: 1px solid rgba(0,0,0,0.1);
        border-radius: 12px;
        max-width: 600px;
        min-height: 300px;
        margin: auto;
        display: flex;
        flex-direction: column;

        font-family: ${regularFontFamily};
        line-height: 1;
    `,
      youTubeDialogBlock: `
        height: calc(100% - 30px);
        max-width: initial;
        min-height: initial;
    `,
      imgRow: `
        display: flex;
        flex-direction: column;
        margin: 20px 0px;
    `,
      content: `
        display: flex;
        flex-direction: column;
        padding: 16px 0;
        flex: 1 1 1px;
    `,
      feedbackLink: `
        font-family: ${regularFontFamily};
        font-style: normal;
        font-weight: 400;
        font-size: 12px;
        line-height: 12px;
        color: #ABABAB;
        text-decoration: none;
    `,
      feedbackRow: `
        height: 30px;
        display: flex;
        justify-content: flex-end;
        align-items: center;
    `,
      titleBox: `
        display: flex;
        padding: 12px;
        max-height: 44px;
        border-bottom: 1px solid;
        border-color: rgba(196, 196, 196, 0.3);
        margin: 0;
        margin-bottom: 4px;
    `,
      title: `
        font-family: ${regularFontFamily};
        line-height: 1.4;
        font-size: 14px;
        margin: auto 10px;
        flex-basis: 100%;
        height: 1.4em;
        flex-wrap: wrap;
        overflow: hidden;
        text-align: left;
        border: none;
        padding: 0;
    `,
      buttonRow: `
        display: flex;
        height: 100%
        flex-direction: row;
        margin: 20px auto 0px;
        height: 100%;
        align-items: flex-start;
    `,
      modalContentTitle: `
        font-family: ${boldFontFamily};
        font-size: 17px;
        font-weight: bold;
        line-height: 21px;
        margin: 10px auto;
        text-align: center;
        border: none;
        padding: 0px 32px;
    `,
      modalContentText: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        margin: 0px auto 14px;
        text-align: center;
        border: none;
        padding: 0;
    `,
      modalButtonRow: `
        border: none;
        padding: 0;
        margin: auto;
        width: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
    `,
      modalButton: `
        width: 100%;
        display: flex;
        justify-content: center;
        align-items: center;
    `,
      modalIcon: `
        display: block;
    `,
      contentTitle: `
        font-family: ${boldFontFamily};
        font-size: 17px;
        font-weight: bold;
        margin: 20px auto 10px;
        padding: 0px 30px;
        text-align: center;
        margin-top: auto;
    `,
      contentText: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        padding: 0px 40px;
        text-align: center;
        margin: 0 auto auto;
    `,
      icon: `
        height: 80px;
        width: 80px;
        margin: auto;
    `,
      closeIcon: `
        height: 12px;
        width: 12px;
        margin: auto;
    `,
      closeButton: `
        display: flex;
        justify-content: center;
        align-items: center;
        min-width: 20px;
        height: 21px;
        border: 0;
        background: transparent;
        cursor: pointer;
    `,
      logo: `
        flex-basis: 0%;
        min-width: 20px;
        height: 21px;
        border: none;
        padding: 0;
        margin: 0;
    `,
      logoImg: `
        height: 21px;
        width: 21px;
    `,
      loadingImg: `
        display: block;
        margin: 0px 8px 0px 0px;
        height: 14px;
        width: 14px;
    `,
      modal: `
        width: 340px;
        padding: 0;
        margin: auto;
        background-color: #FFFFFF;
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        display: block;
        box-shadow: 0px 1px 3px rgba(0, 0, 0, 0.08), 0px 2px 4px rgba(0, 0, 0, 0.1);
        border-radius: 12px;
        border: none;
    `,
      modalContent: `
        padding: 24px;
        display: flex;
        flex-direction: column;
        border: none;
        margin: 0;
    `,
      overlay: `
        height: 100%;
        width: 100%;
        background-color: #666666;
        opacity: .5;
        display: block;
        position: fixed;
        top: 0;
        right: 0;
        border: none;
        padding: 0;
        margin: 0;
    `,
      modalContainer: `
        height: 100vh;
        width: 100vw;
        box-sizing: border-box;
        z-index: 2147483647;
        display: block;
        position: fixed;
        border: 0;
        margin: 0;
        padding: 0;
    `,
      headerLinkContainer: `
        flex-basis: 100%;
        display: grid;
        justify-content: flex-end;
    `,
      headerLink: `
        line-height: 1.4;
        font-size: 14px;
        font-weight: bold;
        font-family: ${boldFontFamily};
        text-decoration: none;
        cursor: pointer;
        min-width: 100px;
        text-align: end;
        float: right;
        display: none;
    `,
      generalLink: `
        line-height: 1.4;
        font-size: 14px;
        font-weight: bold;
        font-family: ${boldFontFamily};
        cursor: pointer;
        text-decoration: none;
    `,
      wrapperDiv: `
        display: inline-block;
        border: 0;
        padding: 0;
        margin: 0;
        max-width: 600px;
        min-height: 300px;
    `,
      toggleButtonWrapper: `
        display: flex;
        align-items: center;
        cursor: pointer;
    `,
      toggleButton: `
        cursor: pointer;
        position: relative;
        width: 30px;
        height: 16px;
        margin-top: -3px;
        margin: 0;
        padding: 0;
        border: none;
        background-color: transparent;
        text-align: left;
    `,
      toggleButtonBg: `
        right: 0;
        width: 30px;
        height: 16px;
        overflow: visible;
        border-radius: 10px;
    `,
      toggleButtonText: `
        display: inline-block;
        margin: 0 0 0 7px;
        padding: 0;
    `,
      toggleButtonKnob: `
        position: absolute;
        display: inline-block;
        width: 14px;
        height: 14px;
        border-radius: 10px;
        background-color: #ffffff;
        margin-top: 1px;
        top: calc(50% - 14px/2 - 1px);
        box-shadow: 0px 0px 1px rgba(0, 0, 0, 0.05), 0px 1px 1px rgba(0, 0, 0, 0.1);
    `,
      toggleButtonKnobState: {
        active: `
            right: 1px;
        `,
        inactive: `
            left: 1px;
        `
      },
      placeholderWrapperDiv: `
        position: relative;
        overflow: hidden;
        border-radius: 12px;
        box-sizing: border-box;
        max-width: initial;
        min-width: 380px;
        min-height: 300px;
        margin: auto;
    `,
      youTubeWrapperDiv: `
        position: relative;
        overflow: hidden;
        max-width: initial;
        min-width: 380px;
        min-height: 300px;
        height: 100%;
    `,
      youTubeDialogDiv: `
        position: relative;
        overflow: hidden;
        border-radius: 12px;
        max-width: initial;
        min-height: initial;
        height: calc(100% - 30px);
    `,
      youTubeDialogBottomRow: `
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        margin-top: auto;
    `,
      youTubePlaceholder: `
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
        position: relative;
        width: 100%;
        height: 100%;
        background: rgba(45, 45, 45, 0.8);
    `,
      youTubePreviewWrapperImg: `
        position: absolute;
        display: flex;
        justify-content: center;
        align-items: center;
        width: 100%;
        height: 100%;
    `,
      youTubePreviewImg: `
        min-width: 100%;
        min-height: 100%;
        height: auto;
    `,
      youTubeTopSection: `
        font-family: ${boldFontFamily};
        flex: 1;
        display: flex;
        justify-content: space-between;
        position: relative;
        padding: 18px 12px 0;
    `,
      youTubeTitle: `
        font-size: 14px;
        font-weight: bold;
        line-height: 14px;
        color: #FFFFFF;
        margin: 0;
        width: 100%;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        box-sizing: border-box;
    `,
      youTubePlayButtonRow: `
        flex: 2;
        display: flex;
        align-items: center;
        justify-content: center;
    `,
      youTubePlayButton: `
        display: flex;
        justify-content: center;
        align-items: center;
        height: 48px;
        width: 80px;
        padding: 0px 24px;
        border-radius: 8px;
    `,
      youTubePreviewToggleRow: `
        flex: 1;
        display: flex;
        flex-direction: column;
        justify-content: flex-end;
        align-items: center;
        padding: 0 12px 18px;
    `,
      youTubePreviewToggleText: `
        color: #EEEEEE;
        font-weight: 400;
    `,
      youTubePreviewInfoText: `
        color: #ABABAB;
    `
    };
  }
  function getConfig(locale) {
    const allLocales = JSON.parse(ctl_locales_default);
    const localeStrings = allLocales[locale] || allLocales.en;
    const fbStrings = localeStrings["facebook.json"];
    const ytStrings = localeStrings["youtube.json"];
    const sharedStrings2 = localeStrings["shared.json"];
    const config2 = {
      "Facebook, Inc.": {
        informationalModal: {
          icon: blockedFBLogo,
          messageTitle: fbStrings.informationalModalMessageTitle,
          messageBody: fbStrings.informationalModalMessageBody,
          confirmButtonText: fbStrings.informationalModalConfirmButtonText,
          rejectButtonText: fbStrings.informationalModalRejectButtonText
        },
        elementData: {
          "FB Like Button": {
            selectors: [".fb-like"],
            replaceSettings: {
              type: "blank"
            }
          },
          "FB Button iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/like.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/like.php']",
              "iframe[src*='//www.facebook.com/plugins/share_button.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/share_button.php']"
            ],
            replaceSettings: {
              type: "blank"
            }
          },
          "FB Save Button": {
            selectors: [".fb-save"],
            replaceSettings: {
              type: "blank"
            }
          },
          "FB Share Button": {
            selectors: [".fb-share-button"],
            replaceSettings: {
              type: "blank"
            }
          },
          "FB Page iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/page.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/page.php']"
            ],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockContent,
              infoTitle: fbStrings.infoTitleUnblockContent,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "originalElement"
            }
          },
          "FB Page Div": {
            selectors: [".fb-page"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockContent,
              infoTitle: fbStrings.infoTitleUnblockContent,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "iFrame",
              targetURL: "https://www.facebook.com/plugins/page.php?href=data-href&tabs=data-tabs&width=data-width&height=data-height",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-tabs": {
                  default: "timeline"
                },
                "data-height": {
                  default: "500"
                },
                "data-width": {
                  default: "500"
                }
              },
              styleDataAttributes: {
                width: {
                  name: "data-width",
                  unit: "px"
                },
                height: {
                  name: "data-height",
                  unit: "px"
                }
              }
            }
          },
          "FB Comment iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/comment_embed.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/comment_embed.php']"
            ],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockComment,
              infoTitle: fbStrings.infoTitleUnblockComment,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "originalElement"
            }
          },
          "FB Comments": {
            selectors: [".fb-comments", "fb\\:comments"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockComments,
              infoTitle: fbStrings.infoTitleUnblockComments,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "allowFull",
              targetURL: "https://www.facebook.com/v9.0/plugins/comments.php?href=data-href&numposts=data-numposts&sdk=joey&version=v9.0&width=data-width",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-numposts": {
                  default: 10
                },
                "data-width": {
                  default: "500"
                }
              }
            }
          },
          "FB Embedded Comment Div": {
            selectors: [".fb-comment-embed"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockComment,
              infoTitle: fbStrings.infoTitleUnblockComment,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "iFrame",
              targetURL: "https://www.facebook.com/v9.0/plugins/comment_embed.php?href=data-href&sdk=joey&width=data-width&include_parent=data-include-parent",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-width": {
                  default: "500"
                },
                "data-include-parent": {
                  default: "false"
                }
              },
              styleDataAttributes: {
                width: {
                  name: "data-width",
                  unit: "px"
                }
              }
            }
          },
          "FB Post iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/post.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/post.php']"
            ],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockPost,
              infoTitle: fbStrings.infoTitleUnblockPost,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "originalElement"
            }
          },
          "FB Posts Div": {
            selectors: [".fb-post"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockPost,
              infoTitle: fbStrings.infoTitleUnblockPost,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "allowFull",
              targetURL: "https://www.facebook.com/v9.0/plugins/post.php?href=data-href&sdk=joey&show_text=true&width=data-width",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-width": {
                  default: "500"
                }
              },
              styleDataAttributes: {
                width: {
                  name: "data-width",
                  unit: "px"
                },
                height: {
                  name: "data-height",
                  unit: "px",
                  fallbackAttribute: "data-width"
                }
              }
            }
          },
          "FB Video iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/video.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/video.php']"
            ],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockVideo,
              infoTitle: fbStrings.infoTitleUnblockVideo,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "originalElement"
            }
          },
          "FB Video": {
            selectors: [".fb-video"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockVideo,
              infoTitle: fbStrings.infoTitleUnblockVideo,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "iFrame",
              targetURL: "https://www.facebook.com/plugins/video.php?href=data-href&show_text=true&width=data-width",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-width": {
                  default: "500"
                }
              },
              styleDataAttributes: {
                width: {
                  name: "data-width",
                  unit: "px"
                },
                height: {
                  name: "data-height",
                  unit: "px",
                  fallbackAttribute: "data-width"
                }
              }
            }
          },
          "FB Group iFrames": {
            selectors: [
              "iframe[src*='//www.facebook.com/plugins/group.php']",
              "iframe[src*='//www.facebook.com/v2.0/plugins/group.php']"
            ],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockContent,
              infoTitle: fbStrings.infoTitleUnblockContent,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "originalElement"
            }
          },
          "FB Group": {
            selectors: [".fb-group"],
            replaceSettings: {
              type: "dialog",
              buttonText: fbStrings.buttonTextUnblockContent,
              infoTitle: fbStrings.infoTitleUnblockContent,
              infoText: fbStrings.infoTextUnblockContent
            },
            clickAction: {
              type: "iFrame",
              targetURL: "https://www.facebook.com/plugins/group.php?href=data-href&width=data-width",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-width": {
                  default: "500"
                }
              },
              styleDataAttributes: {
                width: {
                  name: "data-width",
                  unit: "px"
                }
              }
            }
          },
          "FB Login Button": {
            selectors: [".fb-login-button"],
            replaceSettings: {
              type: "loginButton",
              icon: blockedFBLogo,
              buttonText: fbStrings.loginButtonText,
              buttonTextUnblockLogin: fbStrings.buttonTextUnblockLogin,
              popupBodyText: fbStrings.loginBodyText
            },
            clickAction: {
              type: "allowFull",
              targetURL: "https://www.facebook.com/v9.0/plugins/login_button.php?app_id=app_id_replace&auto_logout_link=false&button_type=continue_with&sdk=joey&size=large&use_continue_as=false&width=",
              urlDataAttributesToPreserve: {
                "data-href": {
                  default: "",
                  required: true
                },
                "data-width": {
                  default: "500"
                },
                app_id_replace: {
                  default: "null"
                }
              }
            }
          }
        }
      },
      Youtube: {
        informationalModal: {
          icon: blockedYTVideo,
          messageTitle: ytStrings.informationalModalMessageTitle,
          messageBody: ytStrings.informationalModalMessageBody,
          confirmButtonText: ytStrings.informationalModalConfirmButtonText,
          rejectButtonText: ytStrings.informationalModalRejectButtonText
        },
        elementData: {
          "YouTube embedded video": {
            selectors: [
              "iframe[src*='//youtube.com/embed']",
              "iframe[src*='//youtube-nocookie.com/embed']",
              "iframe[src*='//www.youtube.com/embed']",
              "iframe[src*='//www.youtube-nocookie.com/embed']",
              "iframe[data-src*='//youtube.com/embed']",
              "iframe[data-src*='//youtube-nocookie.com/embed']",
              "iframe[data-src*='//www.youtube.com/embed']",
              "iframe[data-src*='//www.youtube-nocookie.com/embed']"
            ],
            replaceSettings: {
              type: "youtube-video",
              buttonText: ytStrings.buttonTextUnblockVideo,
              infoTitle: ytStrings.infoTitleUnblockVideo,
              infoText: ytStrings.infoTextUnblockVideo,
              previewToggleText: ytStrings.infoPreviewToggleText,
              placeholder: {
                previewToggleEnabledText: ytStrings.infoPreviewToggleEnabledText,
                previewInfoText: ytStrings.infoPreviewInfoText,
                previewToggleEnabledDuckDuckGoText: ytStrings.infoPreviewToggleEnabledText,
                videoPlayIcon: {
                  lightMode: videoPlayLight,
                  darkMode: videoPlayDark
                }
              }
            },
            clickAction: {
              type: "youtube-video"
            }
          },
          "YouTube embedded subscription button": {
            selectors: [
              "iframe[src*='//youtube.com/subscribe_embed']",
              "iframe[src*='//youtube-nocookie.com/subscribe_embed']",
              "iframe[src*='//www.youtube.com/subscribe_embed']",
              "iframe[src*='//www.youtube-nocookie.com/subscribe_embed']",
              "iframe[data-src*='//youtube.com/subscribe_embed']",
              "iframe[data-src*='//youtube-nocookie.com/subscribe_embed']",
              "iframe[data-src*='//www.youtube.com/subscribe_embed']",
              "iframe[data-src*='//www.youtube-nocookie.com/subscribe_embed']"
            ],
            replaceSettings: {
              type: "blank"
            }
          }
        }
      }
    };
    return { config: config2, sharedStrings: sharedStrings2 };
  }

  // src/dom-utils.js
  var Template = class _Template {
    constructor(strings, values) {
      this.values = values;
      this.strings = strings;
    }
    /**
     * Escapes any occurrences of &, ", <, > or / with XML entities.
     *
     * @param {string} str
     *        The string to escape.
     * @return {string} The escaped string.
     */
    escapeXML(str) {
      const replacements = {
        "&": "&amp;",
        '"': "&quot;",
        "'": "&apos;",
        "<": "&lt;",
        ">": "&gt;",
        "/": "&#x2F;"
      };
      return String(str).replace(/[&"'<>/]/g, (m) => replacements[m]);
    }
    potentiallyEscape(value) {
      if (typeof value === "object") {
        if (value instanceof Array) {
          return value.map((val) => this.potentiallyEscape(val)).join("");
        }
        if (value instanceof _Template) {
          return value;
        }
        throw new Error("Unknown object to escape");
      }
      return this.escapeXML(value);
    }
    toString() {
      const result = [];
      for (const [i, string] of this.strings.entries()) {
        result.push(string);
        if (i < this.values.length) {
          result.push(this.potentiallyEscape(this.values[i]));
        }
      }
      return result.join("");
    }
  };
  function html(strings, ...values) {
    return new Template(strings, values);
  }

  // src/features/click-to-load/assets/shared.css
  var shared_default = ":host {\n    /* Color palette */\n    --ddg-shade-06: rgba(0, 0, 0, 0.06);\n    --ddg-shade-12: rgba(0, 0, 0, 0.12);\n    --ddg-shade-18: rgba(0, 0, 0, 0.18);\n    --ddg-shade-36: rgba(0, 0, 0, 0.36);\n    --ddg-shade-84: rgba(0, 0, 0, 0.84);\n    --ddg-tint-12: rgba(255, 255, 255, 0.12);\n    --ddg-tint-18: rgba(255, 255, 255, 0.18);\n    --ddg-tint-24: rgba(255, 255, 255, 0.24);\n    --ddg-tint-84: rgba(255, 255, 255, 0.84);\n    /* Tokens */\n    --ddg-color-primary: #3969ef;\n    --ddg-color-bg-01: #ffffff;\n    --ddg-color-bg-02: #ababab;\n    --ddg-color-border: var(--ddg-shade-12);\n    --ddg-color-txt: var(--ddg-shade-84);\n    --ddg-color-txt-link-02: #ababab;\n}\n@media (prefers-color-scheme: dark) {\n    :host {\n        --ddg-color-primary: #7295f6;\n        --ddg-color-bg-01: #222222;\n        --ddg-color-bg-02: #444444;\n        --ddg-color-border: var(--ddg-tint-12);\n        --ddg-color-txt: var(--ddg-tint-84);\n    }\n}\n\n/* SHARED STYLES */\n/* Text Link */\n.ddg-text-link {\n    line-height: 1.4;\n    font-size: 14px;\n    font-weight: 700;\n    cursor: pointer;\n    text-decoration: none;\n    color: var(--ddg-color-primary);\n}\n\n/* Button */\n.DuckDuckGoButton {\n    border-radius: 8px;\n    padding: 8px 16px;\n    border-color: var(--ddg-color-primary);\n    border: none;\n    min-height: 36px;\n\n    position: relative;\n    cursor: pointer;\n    box-shadow: none;\n    z-index: 2147483646;\n}\n.DuckDuckGoButton > div {\n    display: flex;\n    flex-direction: row;\n    align-items: center;\n    border: none;\n    padding: 0;\n    margin: 0;\n}\n.DuckDuckGoButton,\n.DuckDuckGoButton > div {\n    font-size: 14px;\n    font-family: DuckDuckGoPrivacyEssentialsBold;\n    font-weight: 600;\n}\n.DuckDuckGoButton.tertiary {\n    color: var(--ddg-color-txt);\n    background-color: transparent;\n    display: flex;\n    justify-content: center;\n    align-items: center;\n    border: 1px solid var(--ddg-color-border);\n    border-radius: 8px;\n}\n.DuckDuckGoButton.tertiary:hover {\n    background: var(--ddg-shade-06);\n    border-color: var(--ddg-shade-18);\n}\n@media (prefers-color-scheme: dark) {\n    .DuckDuckGoButton.tertiary:hover {\n        background: var(--ddg-tint-18);\n        border-color: var(--ddg-tint-24);\n    }\n}\n.DuckDuckGoButton.tertiary:active {\n    background: var(--ddg-shade-12);\n    border-color: var(--ddg-shade-36);\n}\n@media (prefers-color-scheme: dark) {\n    .DuckDuckGoButton.tertiary:active {\n        background: var(--ddg-tint-24);\n        border-color: var(--ddg-tint-24);\n    }\n}\n";

  // src/features/click-to-load/assets/ctl-placeholder-block.css
  var ctl_placeholder_block_default = ":host,\n* {\n    font-family: DuckDuckGoPrivacyEssentials, system, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto,\n        Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol';\n    box-sizing: border-box;\n    font-weight: normal;\n    font-style: normal;\n    margin: 0;\n    padding: 0;\n    text-align: left;\n}\n\n:host,\n.DuckDuckGoSocialContainer {\n    display: inline-block;\n    border: 0;\n    padding: 0;\n    margin: auto;\n    inset: initial;\n    max-width: 600px;\n    min-height: 180px;\n}\n\n/* SHARED STYLES */\n/* Toggle Button */\n.ddg-toggle-button-container {\n    display: flex;\n    align-items: center;\n    cursor: pointer;\n}\n.ddg-toggle-button {\n    cursor: pointer;\n    position: relative;\n    margin-top: -3px;\n    margin: 0;\n    padding: 0;\n    border: none;\n    background-color: transparent;\n    text-align: left;\n}\n.ddg-toggle-button,\n.ddg-toggle-button.md,\n.ddg-toggle-button-bg,\n.ddg-toggle-button.md .ddg-toggle-button-bg {\n    width: 32px;\n    height: 16px;\n    border-radius: 20px;\n}\n.ddg-toggle-button.lg,\n.ddg-toggle-button.lg .ddg-toggle-button-bg {\n    width: 56px;\n    height: 34px;\n    border-radius: 50px;\n}\n.ddg-toggle-button-bg {\n    right: 0;\n    overflow: visible;\n}\n.ddg-toggle-button.active .ddg-toggle-button-bg {\n    background: var(--ddg-color-primary);\n}\n.ddg-toggle-button.inactive .ddg-toggle-button-bg {\n    background: var(--ddg-color-bg-02);\n}\n.ddg-toggle-button-knob {\n    --ddg-toggle-knob-margin: 2px;\n    position: absolute;\n    display: inline-block;\n    border-radius: 50%;\n    background-color: #ffffff;\n    margin-top: var(--ddg-toggle-knob-margin);\n}\n.ddg-toggle-button-knob,\n.ddg-toggle-button.md .ddg-toggle-button-knob {\n    width: 12px;\n    height: 12px;\n    top: calc(50% - 16px / 2);\n}\n.ddg-toggle-button.lg .ddg-toggle-button-knob {\n    --ddg-toggle-knob-margin: 4px;\n    width: 26px;\n    height: 26px;\n    top: calc(50% - 34px / 2);\n}\n.ddg-toggle-button.active .ddg-toggle-button-knob {\n    right: var(--ddg-toggle-knob-margin);\n}\n.ddg-toggle-button.inactive .ddg-toggle-button-knob {\n    left: var(--ddg-toggle-knob-margin);\n}\n.ddg-toggle-button-label {\n    font-size: 14px;\n    line-height: 20px;\n    color: var(--ddg-color-txt);\n    margin-left: 12px;\n}\n\n/* Styles for DDGCtlPlaceholderBlocked */\n.DuckDuckGoButton.ddg-ctl-unblock-btn {\n    width: 100%;\n    margin: 0 auto;\n}\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .DuckDuckGoButton.ddg-ctl-unblock-btn {\n    width: auto;\n}\n\n.ddg-ctl-placeholder-card {\n    height: 100%;\n    overflow: auto;\n    padding: 16px;\n    color: var(--ddg-color-txt);\n    background: var(--ddg-color-bg-01);\n    border: 1px solid var(--ddg-color-border);\n    border-radius: 12px;\n    margin: auto;\n    display: grid;\n    justify-content: center;\n    align-items: center;\n    line-height: 1;\n}\n.ddg-ctl-placeholder-card.slim-card {\n    padding: 12px;\n}\n.DuckDuckGoSocialContainer.size-xs .ddg-ctl-placeholder-card-body {\n    margin: auto;\n}\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-placeholder-card.with-feedback-link {\n    height: calc(100% - 30px);\n    max-width: initial;\n    min-height: initial;\n}\n\n.ddg-ctl-placeholder-card-header {\n    width: 100%;\n    display: flex;\n    align-items: center;\n    margin: auto;\n    margin-bottom: 8px;\n    text-align: left;\n}\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-placeholder-card-header {\n    flex-direction: column;\n    align-items: center;\n    justify-content: center;\n    margin-bottom: 12px;\n    width: 80%;\n    text-align: center;\n}\n\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-placeholder-card-header .ddg-ctl-placeholder-card-title,\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-placeholder-card-header .ddg-text-link {\n    text-align: center;\n}\n\n/* Show Learn More link in the header on mobile and\n * tablet size screens and hide it on desktop size */\n.DuckDuckGoSocialContainer.size-lg .ddg-ctl-placeholder-card-header .ddg-learn-more {\n    display: none;\n}\n\n.ddg-ctl-placeholder-card-title,\n.ddg-ctl-placeholder-card-title .ddg-text-link {\n    font-family: DuckDuckGoPrivacyEssentialsBold;\n    font-weight: 700;\n    font-size: 16px;\n    line-height: 24px;\n}\n\n.ddg-ctl-placeholder-card-header-dax {\n    align-self: flex-start;\n    width: 48px;\n    height: 48px;\n    margin: 0 8px 0 0;\n}\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-placeholder-card-header-dax {\n    align-self: inherit;\n    margin: 0 0 12px 0;\n}\n\n.DuckDuckGoSocialContainer.size-lg .ddg-ctl-placeholder-card-header-dax {\n    width: 56px;\n    height: 56px;\n}\n\n.ddg-ctl-placeholder-card-body-text {\n    font-size: 16px;\n    line-height: 24px;\n    text-align: center;\n    margin: 0 auto 12px;\n\n    display: none;\n}\n.DuckDuckGoSocialContainer.size-lg .ddg-ctl-placeholder-card-body-text {\n    width: 80%;\n    display: block;\n}\n\n.ddg-ctl-placeholder-card-footer {\n    width: 100%;\n    margin-top: 12px;\n    display: flex;\n    align-items: center;\n    justify-content: flex-start;\n    align-self: end;\n}\n\n/* Only display the unblock button on really small placeholders */\n.DuckDuckGoSocialContainer.size-xs .ddg-ctl-placeholder-card-header,\n.DuckDuckGoSocialContainer.size-xs .ddg-ctl-placeholder-card-body-text,\n.DuckDuckGoSocialContainer.size-xs .ddg-ctl-placeholder-card-footer {\n    display: none;\n}\n\n.ddg-ctl-feedback-row {\n    display: none;\n}\n.DuckDuckGoSocialContainer:is(.size-md, .size-lg) .ddg-ctl-feedback-row {\n    height: 30px;\n    justify-content: flex-end;\n    align-items: center;\n    display: flex;\n}\n\n.ddg-ctl-feedback-link {\n    font-style: normal;\n    font-weight: 400;\n    font-size: 12px;\n    line-height: 12px;\n    color: var(--ddg-color-txt-link-02);\n    text-decoration: none;\n    display: inline;\n    background-color: transparent;\n    border: 0;\n    padding: 0;\n    cursor: pointer;\n}\n";

  // src/features/click-to-load/components/ctl-placeholder-blocked.js
  var _DDGCtlPlaceholderBlockedElement = class _DDGCtlPlaceholderBlockedElement extends HTMLElement {
    /**
     * @param {object} params - Params for building a custom element
     *                          with a placeholder for blocked content
     * @param {boolean} params.devMode - Used to create the Shadow DOM on 'open'(true) or 'closed'(false) mode
     * @param {string} params.title - Card title text
     * @param {string} params.body - Card body text
     * @param {string} params.unblockBtnText - Unblock button text
     * @param {boolean=} params.useSlimCard - Flag for using less padding on card (ie YT CTL on mobile)
     * @param {HTMLElement} params.originalElement - The original element this placeholder is replacing.
     * @param {LearnMoreParams} params.learnMore - Localized strings for "Learn More" link.
     * @param {WithToggleParams=} params.withToggle - Toggle config to be displayed in the bottom of the placeholder
     * @param {WithFeedbackParams=} params.withFeedback - Shows feedback link on tablet and desktop sizes,
     * @param {(originalElement: HTMLIFrameElement | HTMLElement, replacementElement: HTMLElement) => (e: any) => void} params.onButtonClick
     */
    constructor(params) {
      super();
      /**
       * Placeholder element for blocked content
       * @type {HTMLDivElement}
       */
      __publicField(this, "placeholderBlocked");
      /**
       * Size variant of the latest calculated size of the placeholder.
       * This is used to add the appropriate CSS class to the placeholder container
       * and adapt the layout for each size.
       * @type {placeholderSize}
       */
      __publicField(this, "size", null);
      /**
       * Creates a placeholder for content blocked by Click to Load.
       * Note: We're using arrow functions () => {} in this class due to a bug
       * found in Firefox where it is getting the wrong "this" context on calls in the constructor.
       * This is a temporary workaround.
       * @returns {HTMLDivElement}
       */
      __publicField(this, "createPlaceholder", () => {
        const { title, body, unblockBtnText, useSlimCard, withToggle, withFeedback } = this.params;
        const container = document.createElement("div");
        container.classList.add("DuckDuckGoSocialContainer");
        const cardClassNames = [
          ["slim-card", !!useSlimCard],
          ["with-feedback-link", !!withFeedback]
        ].map(([className, active]) => active ? className : "").join(" ");
        const cardFooterSection = withToggle ? html`<div class="ddg-ctl-placeholder-card-footer">${this.createToggleButton()}</div> ` : "";
        const learnMoreLink = this.createLearnMoreLink();
        container.innerHTML = html`
            <div class="ddg-ctl-placeholder-card ${cardClassNames}">
                <div class="ddg-ctl-placeholder-card-header">
                    <img class="ddg-ctl-placeholder-card-header-dax" src=${logoImg} alt="DuckDuckGo Dax" />
                    <div class="ddg-ctl-placeholder-card-title">${title}. ${learnMoreLink}</div>
                </div>
                <div class="ddg-ctl-placeholder-card-body">
                    <div class="ddg-ctl-placeholder-card-body-text">${body} ${learnMoreLink}</div>
                    <button class="DuckDuckGoButton tertiary ddg-ctl-unblock-btn" type="button">
                        <div>${unblockBtnText}</div>
                    </button>
                </div>
                ${cardFooterSection}
            </div>
        `.toString();
        return container;
      });
      /**
       * Creates a template string for Learn More link.
       */
      __publicField(this, "createLearnMoreLink", () => {
        const { learnMore } = this.params;
        return html`<a
            class="ddg-text-link ddg-learn-more"
            aria-label="${learnMore.readAbout}"
            href="https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/"
            target="_blank"
            >${learnMore.learnMore}</a
        >`;
      });
      /**
       * Creates a Feedback Link container row
       * @returns {HTMLDivElement}
       */
      __publicField(this, "createShareFeedbackLink", () => {
        const { withFeedback } = this.params;
        const container = document.createElement("div");
        container.classList.add("ddg-ctl-feedback-row");
        container.innerHTML = html`
            <button class="ddg-ctl-feedback-link" type="button">${withFeedback?.label || "Share Feedback"}</button>
        `.toString();
        return container;
      });
      /**
       * Creates a template string for a toggle button with text.
       */
      __publicField(this, "createToggleButton", () => {
        const { withToggle } = this.params;
        if (!withToggle) return;
        const { isActive, dataKey, label, size: toggleSize = "md" } = withToggle;
        const toggleButton = html`
            <div class="ddg-toggle-button-container">
                <button
                    class="ddg-toggle-button ${isActive ? "active" : "inactive"} ${toggleSize}"
                    type="button"
                    aria-pressed=${!!isActive}
                    data-key=${dataKey}
                >
                    <div class="ddg-toggle-button-bg"></div>
                    <div class="ddg-toggle-button-knob"></div>
                </button>
                <div class="ddg-toggle-button-label">${label}</div>
            </div>
        `;
        return toggleButton;
      });
      /**
       *
       * @param {HTMLElement} containerElement
       * @param {HTMLElement?} feedbackLink
       */
      __publicField(this, "setupEventListeners", (containerElement, feedbackLink) => {
        const { withToggle, withFeedback, originalElement, onButtonClick } = this.params;
        containerElement.querySelector("button.ddg-ctl-unblock-btn")?.addEventListener("click", onButtonClick(originalElement, this));
        if (withToggle) {
          containerElement.querySelector(".ddg-toggle-button-container")?.addEventListener("click", withToggle.onClick);
        }
        if (withFeedback && feedbackLink) {
          feedbackLink.querySelector(".ddg-ctl-feedback-link")?.addEventListener("click", withFeedback.onClick);
        }
      });
      /**
       * Use JS to calculate the width and height of the root element placeholder. We could use a CSS Container Query, but full
       * support to it was only added recently, so we're not using it for now.
       * https://caniuse.com/css-container-queries
       */
      __publicField(this, "updatePlaceholderSize", () => {
        let newSize = null;
        const { height, width } = this.getBoundingClientRect();
        if (height && height < _DDGCtlPlaceholderBlockedElement.MIN_CONTENT_HEIGHT) {
          newSize = "size-xs";
        } else if (width) {
          if (width < _DDGCtlPlaceholderBlockedElement.MAX_CONTENT_WIDTH_SMALL) {
            newSize = "size-sm";
          } else if (width < _DDGCtlPlaceholderBlockedElement.MAX_CONTENT_WIDTH_MEDIUM) {
            newSize = "size-md";
          } else {
            newSize = "size-lg";
          }
        }
        if (newSize && newSize !== this.size) {
          if (this.size) {
            this.placeholderBlocked.classList.remove(this.size);
          }
          this.placeholderBlocked.classList.add(newSize);
          this.size = newSize;
        }
      });
      this.params = params;
      const shadow = this.attachShadow({
        mode: this.params.devMode ? "open" : "closed"
      });
      const style = document.createElement("style");
      style.innerText = shared_default + ctl_placeholder_block_default;
      this.placeholderBlocked = this.createPlaceholder();
      const feedbackLink = this.params.withFeedback ? this.createShareFeedbackLink() : null;
      this.setupEventListeners(this.placeholderBlocked, feedbackLink);
      feedbackLink && this.placeholderBlocked.appendChild(feedbackLink);
      shadow.appendChild(this.placeholderBlocked);
      shadow.appendChild(style);
    }
    /**
     * Set observed attributes that will trigger attributeChangedCallback()
     */
    static get observedAttributes() {
      return ["style"];
    }
    /**
     * Web Component lifecycle function.
     * When element is first added to the DOM, trigger this callback and
     * update the element CSS size class.
     */
    connectedCallback() {
      this.updatePlaceholderSize();
    }
    /**
     * Web Component lifecycle function.
     * When the root element gets the 'style' attribute updated, reflect that in the container
     * element inside the shadow root. This way, we can copy the size and other styles from the root
     * element and have the inner context be able to use the same sizes to adapt the template layout.
     * @param {string} attr Observed attribute key
     * @param {*} _ Attribute old value, ignored
     * @param {*} newValue Attribute new value
     */
    attributeChangedCallback(attr, _2, newValue) {
      if (attr === "style") {
        this.placeholderBlocked[attr].cssText = newValue;
        this.updatePlaceholderSize();
      }
    }
  };
  __publicField(_DDGCtlPlaceholderBlockedElement, "CUSTOM_TAG_NAME", "ddg-ctl-placeholder-blocked");
  /**
   * Min height that the placeholder needs to have in order to
   * have enough room to display content.
   */
  __publicField(_DDGCtlPlaceholderBlockedElement, "MIN_CONTENT_HEIGHT", 110);
  __publicField(_DDGCtlPlaceholderBlockedElement, "MAX_CONTENT_WIDTH_SMALL", 480);
  __publicField(_DDGCtlPlaceholderBlockedElement, "MAX_CONTENT_WIDTH_MEDIUM", 650);
  var DDGCtlPlaceholderBlockedElement = _DDGCtlPlaceholderBlockedElement;

  // src/features/click-to-load/assets/ctl-login-button.css
  var ctl_login_button_default = ":host,\n* {\n    font-family: DuckDuckGoPrivacyEssentials, system, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto,\n        Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol';\n    box-sizing: border-box;\n    font-weight: normal;\n    font-style: normal;\n    margin: 0;\n    padding: 0;\n    text-align: left;\n}\n\n/* SHARED STYLES */\n/* Popover */\n.ddg-popover {\n    background: #ffffff;\n    border: 1px solid rgba(0, 0, 0, 0.1);\n    border-radius: 16px;\n    box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.12), 0px 8px 16px rgba(0, 0, 0, 0.08);\n    width: 360px;\n    margin-top: 10px;\n    z-index: 2147483647;\n    position: absolute;\n    line-height: normal;\n}\n.ddg-popover-arrow {\n    display: inline-block;\n    background: #ffffff;\n    border: solid rgba(0, 0, 0, 0.1);\n    border-width: 0 1px 1px 0;\n    padding: 5px;\n    transform: rotate(-135deg);\n    -webkit-transform: rotate(-135deg);\n    position: relative;\n    top: -9px;\n}\n.ddg-popover .ddg-title-header {\n    padding: 0px 12px 12px;\n    margin-top: -5px;\n}\n.ddg-popover-body {\n    font-size: 14px;\n    line-height: 21px;\n    margin: auto;\n    padding: 17px;\n    text-align: left;\n}\n\n/* DDG common header */\n.ddg-title-header {\n    display: flex;\n    padding: 12px;\n    max-height: 44px;\n    border-bottom: 1px solid;\n    border-color: rgba(196, 196, 196, 0.3);\n    margin: 0;\n    margin-bottom: 4px;\n}\n.ddg-title-header .ddg-title-text {\n    line-height: 1.4;\n    font-size: 14px;\n    margin: auto 10px;\n    flex-basis: 100%;\n    height: 1.4em;\n    flex-wrap: wrap;\n    overflow: hidden;\n    text-align: left;\n    border: none;\n    padding: 0;\n}\n.ddg-title-header .ddg-logo {\n    flex-basis: 0%;\n    min-width: 20px;\n    height: 21px;\n    border: none;\n    padding: 0;\n    margin: 0;\n}\n.ddg-title-header .ddg-logo .ddg-logo-img {\n    height: 21px;\n    width: 21px;\n}\n\n/* CTL Login Button styles */\n#DuckDuckGoPrivacyEssentialsHoverable {\n    padding-bottom: 10px;\n}\n\n#DuckDuckGoPrivacyEssentialsHoverableText {\n    display: none;\n}\n#DuckDuckGoPrivacyEssentialsHoverable:hover #DuckDuckGoPrivacyEssentialsHoverableText {\n    display: block;\n}\n\n.DuckDuckGoButton.tertiary.ddg-ctl-fb-login-btn {\n    background-color: var(--ddg-color-bg-01);\n}\n@media (prefers-color-scheme: dark) {\n    .DuckDuckGoButton.tertiary.ddg-ctl-fb-login-btn {\n        background: #111111;\n    }\n}\n.DuckDuckGoButton.tertiary:hover {\n    background: rgb(238, 238, 238);\n    border-color: var(--ddg-shade-18);\n}\n@media (prefers-color-scheme: dark) {\n    .DuckDuckGoButton.tertiary:hover {\n        background: rgb(39, 39, 39);\n        border-color: var(--ddg-tint-24);\n    }\n}\n.DuckDuckGoButton.tertiary:active {\n    background: rgb(220, 220, 220);\n    border-color: var(--ddg-shade-36);\n}\n@media (prefers-color-scheme: dark) {\n    .DuckDuckGoButton.tertiary:active {\n        background: rgb(65, 65, 65);\n        border-color: var(--ddg-tint-24);\n    }\n}\n\n.ddg-ctl-button-login-icon {\n    margin-right: 8px;\n    height: 20px;\n    width: 20px;\n}\n\n.ddg-fb-login-container {\n    position: relative;\n    margin: auto;\n    width: auto;\n}\n";

  // src/features/click-to-load/components/ctl-login-button.js
  var _element;
  var DDGCtlLoginButton = class {
    /**
     * @param {object} params - Params for building a custom element with
     *                          a placeholder for a blocked login button
     * @param {boolean} params.devMode - Used to create the Shadow DOM on 'open'(true) or 'closed'(false) mode
     * @param {string} params.label - Button text
     * @param {string} params.logoIcon - Logo image to be displayed in the Login Button to the left of the label text
     * @param {string} params.hoverText - Text for popover on button hover
     * @param {boolean=} params.useSlimCard - Flag for using less padding on card (ie YT CTL on mobile)
     * @param {HTMLElement} params.originalElement - The original element this placeholder is replacing.
     * @param {LearnMoreParams} params.learnMore - Localized strings for "Learn More" link.
     * @param {(originalElement: HTMLIFrameElement | HTMLElement, replacementElement: HTMLElement) => (e: any) => void} params.onClick
     */
    constructor(params) {
      /**
       * Placeholder container element for blocked login button
       * @type {HTMLDivElement}
       */
      __privateAdd(this, _element);
      this.params = params;
      this.element = document.createElement("div");
      const shadow = this.element.attachShadow({
        mode: this.params.devMode ? "open" : "closed"
      });
      const style = document.createElement("style");
      style.innerText = shared_default + ctl_login_button_default;
      const loginButton = this._createLoginButton();
      this._setupEventListeners(loginButton);
      shadow.appendChild(loginButton);
      shadow.appendChild(style);
    }
    /**
     * @returns {HTMLDivElement}
     */
    get element() {
      return __privateGet(this, _element);
    }
    /**
     * @param {HTMLDivElement} el - New placeholder element
     */
    set element(el) {
      __privateSet(this, _element, el);
    }
    /**
     * Creates a placeholder Facebook login button. When clicked, a warning dialog
     * is displayed to the user. The login flow only continues if the user clicks to
     * proceed.
     * @returns {HTMLDivElement}
     */
    _createLoginButton() {
      const { label, hoverText, logoIcon, learnMore } = this.params;
      const { popoverStyle, arrowStyle } = this._calculatePopoverPosition();
      const container = document.createElement("div");
      container.classList.add("ddg-fb-login-container");
      container.innerHTML = html`
            <div id="DuckDuckGoPrivacyEssentialsHoverable">
                <!-- Login Button -->
                <button class="DuckDuckGoButton tertiary ddg-ctl-fb-login-btn">
                    <img class="ddg-ctl-button-login-icon" height="20px" width="20px" src="${logoIcon}" />
                    <div>${label}</div>
                </button>

                <!-- Popover - hover box -->
                <div id="DuckDuckGoPrivacyEssentialsHoverableText" class="ddg-popover" style="${popoverStyle}">
                    <div class="ddg-popover-arrow" style="${arrowStyle}"></div>

                    <div class="ddg-title-header">
                        <div class="ddg-logo">
                            <img class="ddg-logo-img" src="${logoImg}" height="21px" />
                        </div>
                        <div id="DuckDuckGoPrivacyEssentialsCTLElementTitle" class="ddg-title-text">DuckDuckGo</div>
                    </div>

                    <div class="ddg-popover-body">
                        ${hoverText}
                        <a
                            class="ddg-text-link"
                            aria-label="${learnMore.readAbout}"
                            href="https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/"
                            target="_blank"
                            id="learnMoreLink"
                        >
                            ${learnMore.learnMore}
                        </a>
                    </div>
                </div>
            </div>
        `.toString();
      return container;
    }
    /**
     * The left side of the popover may go offscreen if the
     * login button is all the way on the left side of the page. This
     * If that is the case, dynamically shift the box right so it shows
     * properly.
     * @returns {{
     *  popoverStyle: string, // CSS styles to be applied in the Popover container
     *  arrowStyle: string,   // CSS styles to be applied in the Popover arrow
     * }}
     */
    _calculatePopoverPosition() {
      const { originalElement } = this.params;
      const rect = originalElement.getBoundingClientRect();
      const textBubbleWidth = 360;
      const textBubbleLeftShift = 100;
      const arrowDefaultLocationPercent = 50;
      let popoverStyle;
      let arrowStyle;
      if (rect.left < textBubbleLeftShift) {
        const leftShift = -rect.left + 10;
        popoverStyle = `left: ${leftShift}px;`;
        const change = (1 - rect.left / textBubbleLeftShift) * (100 - arrowDefaultLocationPercent);
        arrowStyle = `left: ${Math.max(10, arrowDefaultLocationPercent - change)}%;`;
      } else if (rect.left + textBubbleWidth - textBubbleLeftShift > window.innerWidth) {
        const rightShift = rect.left + textBubbleWidth - textBubbleLeftShift;
        const diff = Math.min(rightShift - window.innerWidth, textBubbleLeftShift);
        const rightMargin = 20;
        popoverStyle = `left: -${textBubbleLeftShift + diff + rightMargin}px;`;
        const change = diff / textBubbleLeftShift * (100 - arrowDefaultLocationPercent);
        arrowStyle = `left: ${Math.max(10, arrowDefaultLocationPercent + change)}%;`;
      } else {
        popoverStyle = `left: -${textBubbleLeftShift}px;`;
        arrowStyle = `left: ${arrowDefaultLocationPercent}%;`;
      }
      return { popoverStyle, arrowStyle };
    }
    /**
     *
     * @param {HTMLElement} loginButton
     */
    _setupEventListeners(loginButton) {
      const { originalElement, onClick } = this.params;
      loginButton.querySelector(".ddg-ctl-fb-login-btn")?.addEventListener("click", onClick(originalElement, this.element));
    }
  };
  _element = new WeakMap();

  // src/features/click-to-load/components/index.js
  function registerCustomElements() {
    if (!customElements.get(DDGCtlPlaceholderBlockedElement.CUSTOM_TAG_NAME)) {
      customElements.define(DDGCtlPlaceholderBlockedElement.CUSTOM_TAG_NAME, DDGCtlPlaceholderBlockedElement);
    }
  }

  // src/features/click-to-load.js
  var devMode = false;
  var isYoutubePreviewsEnabled = false;
  var appID;
  var titleID = "DuckDuckGoPrivacyEssentialsCTLElementTitle";
  var config = null;
  var sharedStrings = null;
  var styles = null;
  var platformsWithNativeModalSupport = ["android", "ios"];
  var platformsWithWebComponentsEnabled = ["android", "ios"];
  var mobilePlatforms = ["android", "ios"];
  var entities = [];
  var entityData = {};
  var knownTrackingElements = /* @__PURE__ */ new WeakSet();
  var readyToDisplayPlaceholdersResolver;
  var readyToDisplayPlaceholders = new Promise((resolve) => {
    readyToDisplayPlaceholdersResolver = resolve;
  });
  var afterPageLoadResolver;
  var afterPageLoad = new Promise((resolve) => {
    afterPageLoadResolver = resolve;
  });
  var _messagingModuleScope;
  var _addDebugFlag;
  var ctl = {
    /**
     * @return {import("@duckduckgo/messaging").Messaging}
     */
    get messaging() {
      if (!_messagingModuleScope) throw new Error("Messaging not initialized");
      return _messagingModuleScope;
    },
    addDebugFlag() {
      if (!_addDebugFlag) throw new Error("addDebugFlag not initialized");
      return _addDebugFlag();
    }
  };
  var DuckWidget = class {
    /**
     * @param {Object} widgetData
     *   The configuration for this "widget" as determined in ctl-config.js.
     * @param {HTMLElement} originalElement
     *   The original tracking element to replace with a placeholder.
     * @param {string} entity
     *   The entity behind the tracking element (e.g. "Facebook, Inc.").
     * @param {import('../utils').Platform} platform
     *   The platform where Click to Load and the Duck Widget is running on (ie Extension, Android App, etc)
     */
    constructor(widgetData, originalElement, entity, platform) {
      this.clickAction = { ...widgetData.clickAction };
      this.replaceSettings = widgetData.replaceSettings;
      this.originalElement = originalElement;
      this.placeholderElement = null;
      this.dataElements = {};
      this.gatherDataElements();
      this.entity = entity;
      this.widgetID = Math.random();
      this.autoplay = false;
      this.isUnblocked = false;
      this.platform = platform;
    }
    /**
     * Dispatch an event on the target element, including the widget's ID and
     * other details.
     * @param {EventTarget} eventTarget
     * @param {string} eventName
     */
    dispatchEvent(eventTarget, eventName) {
      eventTarget.dispatchEvent(
        createCustomEvent(eventName, {
          detail: {
            entity: this.entity,
            replaceSettings: this.replaceSettings,
            widgetID: this.widgetID
          }
        })
      );
    }
    /**
     * Take note of some of the tracking element's attributes (as determined by
     * clickAction.urlDataAttributesToPreserve) and store those in
     * this.dataElement.
     */
    gatherDataElements() {
      if (!this.clickAction.urlDataAttributesToPreserve) {
        return;
      }
      for (const [attrName, attrSettings] of Object.entries(this.clickAction.urlDataAttributesToPreserve)) {
        let value = this.originalElement.getAttribute(attrName);
        if (!value) {
          if (attrSettings.required) {
            this.clickAction.type = "allowFull";
          }
          if (attrName === "data-width") {
            const windowWidth = window.innerWidth;
            const { parentElement } = this.originalElement;
            const parentStyles = parentElement ? window.getComputedStyle(parentElement) : null;
            let parentInnerWidth = null;
            if (parentElement && parentStyles && parentStyles.display !== "inline") {
              parentInnerWidth = parentElement.clientWidth - parseFloat(parentStyles.paddingLeft) - parseFloat(parentStyles.paddingRight);
            }
            if (parentInnerWidth && parentInnerWidth < windowWidth) {
              value = parentInnerWidth.toString();
            } else {
              value = Math.min(attrSettings.default, windowWidth).toString();
            }
          } else {
            value = attrSettings.default;
          }
        }
        this.dataElements[attrName] = value;
      }
    }
    /**
     * Return the URL of the Facebook content, for use when a Facebook Click to
     * Load placeholder has been clicked by the user.
     * @returns {string}
     */
    getTargetURL() {
      this.copySocialDataFields();
      return this.clickAction.targetURL;
    }
    /**
     * Determines which display mode the placeholder element should render in.
     * @returns {displayMode}
     */
    getMode() {
      if (this.replaceSettings.type === "loginButton") {
        return "loginMode";
      }
      if (window?.matchMedia("(prefers-color-scheme: dark)")?.matches) {
        return "darkMode";
      }
      return "lightMode";
    }
    /**
     * Take note of some of the tracking element's style attributes (as
     * determined by clickAction.styleDataAttributes) as a CSS string.
     *
     * @returns {string}
     */
    getStyle() {
      let styleString = "border: none;";
      if (this.clickAction.styleDataAttributes) {
        for (const [attr, valAttr] of Object.entries(this.clickAction.styleDataAttributes)) {
          let valueFound = this.dataElements[valAttr.name];
          if (!valueFound) {
            valueFound = this.dataElements[valAttr.fallbackAttribute];
          }
          let partialStyleString = "";
          if (valueFound) {
            partialStyleString += `${attr}: ${valueFound}`;
          }
          if (!partialStyleString.includes(valAttr.unit)) {
            partialStyleString += valAttr.unit;
          }
          partialStyleString += ";";
          styleString += partialStyleString;
        }
      }
      return styleString;
    }
    /**
     * Store some attributes from the original tracking element, used for both
     * placeholder element styling, and when restoring the original tracking
     * element.
     */
    copySocialDataFields() {
      if (!this.clickAction.urlDataAttributesToPreserve) {
        return;
      }
      if (this.dataElements.app_id_replace && appID != null) {
        this.clickAction.targetURL = this.clickAction.targetURL.replace("app_id_replace", appID);
      }
      for (const key of Object.keys(this.dataElements)) {
        let attrValue = this.dataElements[key];
        if (!attrValue) {
          continue;
        }
        if (key === "data-href" && attrValue.startsWith("//")) {
          attrValue = window.location.protocol + attrValue;
        }
        this.clickAction.targetURL = this.clickAction.targetURL.replace(key, encodeURIComponent(attrValue));
      }
    }
    /**
     * Creates an iFrame for this facebook content.
     *
     * @returns {HTMLIFrameElement}
     */
    createFBIFrame() {
      const frame = document.createElement("iframe");
      frame.setAttribute("src", this.getTargetURL());
      frame.setAttribute("style", this.getStyle());
      return frame;
    }
    /**
     * Tweaks an embedded YouTube video element ready for when it's
     * reloaded.
     *
     * @param {HTMLIFrameElement} videoElement
     * @returns {EventListener?} onError
     *   Function to be called if the video fails to load.
     */
    adjustYouTubeVideoElement(videoElement) {
      let onError = null;
      if (!videoElement.src) {
        return onError;
      }
      const url = new URL(videoElement.src);
      const { hostname: originalHostname } = url;
      if (originalHostname !== "www.youtube-nocookie.com") {
        url.hostname = "www.youtube-nocookie.com";
        onError = (event) => {
          url.hostname = originalHostname;
          videoElement.src = url.href;
          event.stopImmediatePropagation();
        };
      }
      let allowString = videoElement.getAttribute("allow") || "";
      const allowed = new Set(allowString.split(";").map((s) => s.trim()));
      if (this.autoplay) {
        allowed.add("autoplay");
        url.searchParams.set("autoplay", "1");
      } else {
        allowed.delete("autoplay");
        url.searchParams.delete("autoplay");
      }
      allowString = Array.from(allowed).join("; ");
      videoElement.setAttribute("allow", allowString);
      videoElement.src = url.href;
      return onError;
    }
    /**
     * Fades the given element in/out.
     * @param {HTMLElement} element
     *   The element to fade in or out.
     * @param {number} interval
     *   Frequency of opacity updates (ms).
     * @param {boolean} fadeIn
     *   True if the element should fade in instead of out.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade in/out is complete.
     */
    fadeElement(element, interval, fadeIn) {
      return new Promise((resolve) => {
        let opacity = fadeIn ? 0 : 1;
        const originStyle = element.style.cssText;
        const fadeOut = setInterval(function() {
          opacity += fadeIn ? 0.03 : -0.03;
          element.style.cssText = originStyle + `opacity: ${opacity};`;
          if (opacity <= 0 || opacity >= 1) {
            clearInterval(fadeOut);
            resolve();
          }
        }, interval);
      });
    }
    /**
     * Fades the given element out.
     * @param {HTMLElement} element
     *   The element to fade out.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade out is complete.
     */
    fadeOutElement(element) {
      return this.fadeElement(element, 10, false);
    }
    /**
     * Fades the given element in.
     * @param {HTMLElement} element
     *   The element to fade in.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade in is complete.
     */
    fadeInElement(element) {
      return this.fadeElement(element, 10, true);
    }
    /**
     * The function that's called when the user clicks to load some content.
     * Unblocks the content, puts it back in the page, and removes the
     * placeholder.
     * @param {HTMLIFrameElement} originalElement
     *   The original tracking element.
     * @param {HTMLElement} replacementElement
     *   The placeholder element.
     */
    clickFunction(originalElement, replacementElement) {
      let clicked = false;
      const handleClick = (e) => {
        if (e.isTrusted && !clicked) {
          e.stopPropagation();
          this.isUnblocked = true;
          clicked = true;
          let isLogin = false;
          const isSurrogateLogin = false;
          const clickElement = e.srcElement;
          if (this.replaceSettings.type === "loginButton") {
            isLogin = true;
          }
          const action = this.entity === "Youtube" ? "block-ctl-yt" : "block-ctl-fb";
          unblockClickToLoadContent({ entity: this.entity, action, isLogin, isSurrogateLogin }).then((response) => {
            if (response && response.type === "ddg-ctp-user-cancel") {
              return abortSurrogateConfirmation(this.entity);
            }
            const parent = replacementElement.parentNode;
            if (!parent) return;
            if (this.clickAction.type === "allowFull") {
              parent.replaceChild(originalElement, replacementElement);
              this.dispatchEvent(window, "ddg-ctp-load-sdk");
              return;
            }
            const fbContainer = document.createElement("div");
            fbContainer.style.cssText = styles.wrapperDiv;
            const fadeIn = document.createElement("div");
            fadeIn.style.cssText = "display: none; opacity: 0;";
            const loadingImg = document.createElement("img");
            loadingImg.setAttribute("src", loadingImages[this.getMode()]);
            loadingImg.setAttribute("height", "14px");
            loadingImg.style.cssText = styles.loadingImg;
            if (clickElement.nodeName === "BUTTON") {
              clickElement.firstElementChild.insertBefore(loadingImg, clickElement.firstElementChild.firstChild);
            } else {
              let el = clickElement;
              let button = null;
              while (button === null && el !== null) {
                button = el.querySelector("button");
                el = el.parentElement;
              }
              if (button) {
                button.firstElementChild.insertBefore(loadingImg, button.firstElementChild.firstChild);
              }
            }
            fbContainer.appendChild(fadeIn);
            let fbElement;
            let onError = null;
            switch (this.clickAction.type) {
              case "iFrame":
                fbElement = this.createFBIFrame();
                break;
              case "youtube-video":
                onError = this.adjustYouTubeVideoElement(originalElement);
                fbElement = originalElement;
                break;
              default:
                fbElement = originalElement;
                break;
            }
            parent.replaceChild(fbContainer, replacementElement);
            fbContainer.appendChild(replacementElement);
            fadeIn.appendChild(fbElement);
            fbElement.addEventListener(
              "load",
              async () => {
                await this.fadeOutElement(replacementElement);
                fbContainer.replaceWith(fbElement);
                this.dispatchEvent(fbElement, "ddg-ctp-placeholder-clicked");
                await this.fadeInElement(fadeIn);
                fbElement.focus();
              },
              { once: true }
            );
            if (onError) {
              fbElement.addEventListener("error", onError, { once: true });
            }
          });
        }
      };
      if (this.replaceSettings.type === "loginButton" && entityData[this.entity].shouldShowLoginModal) {
        return (e) => {
          if (this.entity === "Facebook, Inc.") {
            notifyFacebookLogin();
          }
          handleUnblockConfirmation(this.platform.name, this.entity, handleClick, e);
        };
      }
      return handleClick;
    }
    /**
     * Based on the current Platform where the Widget is running, it will
     * return if the new layout using Web Components is supported or not.
     * @returns {boolean}
     */
    shouldUseCustomElement() {
      return platformsWithWebComponentsEnabled.includes(this.platform.name);
    }
    /**
     * Based on the current Platform where the Widget is running, it will
     * return if it is one of our mobile apps or not. This should be used to
     * define which layout to use between Mobile and Desktop Platforms variations.
     * @returns {boolean}
     */
    isMobilePlatform() {
      return mobilePlatforms.includes(this.platform.name);
    }
  };
  function replaceTrackingElement(widget, trackingElement, placeholderElement) {
    const elementToReplace = widget.placeholderElement || trackingElement;
    widget.placeholderElement = placeholderElement;
    const originalDisplay = [elementToReplace.style.getPropertyValue("display"), elementToReplace.style.getPropertyPriority("display")];
    elementToReplace.style.setProperty("display", "none", "important");
    elementToReplace.parentElement.insertBefore(placeholderElement, elementToReplace);
    afterPageLoad.then(() => {
      widget.dispatchEvent(trackingElement, "ddg-ctp-tracking-element");
      widget.dispatchEvent(placeholderElement, "ddg-ctp-placeholder-element");
      elementToReplace.remove();
      elementToReplace.style.setProperty("display", ...originalDisplay);
    });
  }
  function createPlaceholderElementAndReplace(widget, trackingElement) {
    if (widget.replaceSettings.type === "blank") {
      replaceTrackingElement(widget, trackingElement, document.createElement("div"));
    }
    if (widget.replaceSettings.type === "loginButton") {
      const icon = widget.replaceSettings.icon;
      if (widget.shouldUseCustomElement()) {
        const facebookLoginButton = new DDGCtlLoginButton({
          devMode,
          label: widget.replaceSettings.buttonTextUnblockLogin,
          hoverText: widget.replaceSettings.popupBodyText,
          logoIcon: facebookLogo,
          originalElement: trackingElement,
          learnMore: {
            // Localized strings for "Learn More" link.
            readAbout: sharedStrings.readAbout,
            learnMore: sharedStrings.learnMore
          },
          onClick: widget.clickFunction.bind(widget)
        }).element;
        facebookLoginButton.classList.add("fb-login-button", "FacebookLogin__button");
        facebookLoginButton.appendChild(makeFontFaceStyleElement());
        replaceTrackingElement(widget, trackingElement, facebookLoginButton);
      } else {
        const { button, container } = makeLoginButton(
          widget.replaceSettings.buttonText,
          widget.getMode(),
          widget.replaceSettings.popupBodyText,
          icon,
          trackingElement
        );
        button.addEventListener("click", widget.clickFunction(trackingElement, container));
        replaceTrackingElement(widget, trackingElement, container);
      }
    }
    if (widget.replaceSettings.type === "dialog") {
      ctl.addDebugFlag();
      ctl.messaging.notify("updateFacebookCTLBreakageFlags", { ctlFacebookPlaceholderShown: true });
      if (widget.shouldUseCustomElement()) {
        const mobileBlockedPlaceholder = new DDGCtlPlaceholderBlockedElement({
          devMode,
          title: widget.replaceSettings.infoTitle,
          // Card title text
          body: widget.replaceSettings.infoText,
          // Card body text
          unblockBtnText: widget.replaceSettings.buttonText,
          // Unblock button text
          useSlimCard: false,
          // Flag for using less padding on card (ie YT CTL on mobile)
          originalElement: trackingElement,
          // The original element this placeholder is replacing.
          learnMore: {
            // Localized strings for "Learn More" link.
            readAbout: sharedStrings.readAbout,
            learnMore: sharedStrings.learnMore
          },
          onButtonClick: widget.clickFunction.bind(widget)
        });
        mobileBlockedPlaceholder.appendChild(makeFontFaceStyleElement());
        replaceTrackingElement(widget, trackingElement, mobileBlockedPlaceholder);
        showExtraUnblockIfShortPlaceholder(null, mobileBlockedPlaceholder);
      } else {
        const icon = widget.replaceSettings.icon;
        const button = makeButton(widget.replaceSettings.buttonText, widget.getMode());
        const textButton = makeTextButton(widget.replaceSettings.buttonText, widget.getMode());
        const { contentBlock, shadowRoot } = createContentBlock(widget, button, textButton, icon);
        button.addEventListener("click", widget.clickFunction(trackingElement, contentBlock));
        textButton.addEventListener("click", widget.clickFunction(trackingElement, contentBlock));
        replaceTrackingElement(widget, trackingElement, contentBlock);
        showExtraUnblockIfShortPlaceholder(shadowRoot, contentBlock);
      }
    }
    if (widget.replaceSettings.type === "youtube-video") {
      ctl.addDebugFlag();
      ctl.messaging.notify("updateYouTubeCTLAddedFlag", { youTubeCTLAddedFlag: true });
      replaceYouTubeCTL(trackingElement, widget);
      ctl.messaging.subscribe("setYoutubePreviewsEnabled", ({ value }) => {
        isYoutubePreviewsEnabled = value;
        replaceYouTubeCTL(trackingElement, widget);
      });
    }
  }
  function replaceYouTubeCTL(trackingElement, widget) {
    if (widget.isUnblocked) {
      return;
    }
    if (isYoutubePreviewsEnabled === true) {
      const oldPlaceholder = widget.placeholderElement;
      const { youTubePreview, shadowRoot } = createYouTubePreview(trackingElement, widget);
      resizeElementToMatch(oldPlaceholder || trackingElement, youTubePreview);
      replaceTrackingElement(widget, trackingElement, youTubePreview);
      showExtraUnblockIfShortPlaceholder(shadowRoot, youTubePreview);
    } else {
      widget.autoplay = false;
      const oldPlaceholder = widget.placeholderElement;
      if (widget.shouldUseCustomElement()) {
        const mobileBlockedPlaceholderElement = new DDGCtlPlaceholderBlockedElement({
          devMode,
          title: widget.replaceSettings.infoTitle,
          // Card title text
          body: widget.replaceSettings.infoText,
          // Card body text
          unblockBtnText: widget.replaceSettings.buttonText,
          // Unblock button text
          useSlimCard: true,
          // Flag for using less padding on card (ie YT CTL on mobile)
          originalElement: trackingElement,
          // The original element this placeholder is replacing.
          learnMore: {
            // Localized strings for "Learn More" link.
            readAbout: sharedStrings.readAbout,
            learnMore: sharedStrings.learnMore
          },
          withToggle: {
            // Toggle config to be displayed in the bottom of the placeholder
            isActive: false,
            // Toggle state
            dataKey: "yt-preview-toggle",
            // data-key attribute for button
            label: widget.replaceSettings.previewToggleText,
            // Text to be presented with toggle
            size: widget.isMobilePlatform() ? "lg" : "md",
            onClick: () => ctl.messaging.notify("setYoutubePreviewsEnabled", { youtubePreviewsEnabled: true })
            // Toggle click callback
          },
          withFeedback: {
            label: sharedStrings.shareFeedback,
            onClick: () => openShareFeedbackPage()
          },
          onButtonClick: widget.clickFunction.bind(widget)
        });
        mobileBlockedPlaceholderElement.appendChild(makeFontFaceStyleElement());
        mobileBlockedPlaceholderElement.id = trackingElement.id;
        resizeElementToMatch(oldPlaceholder || trackingElement, mobileBlockedPlaceholderElement);
        replaceTrackingElement(widget, trackingElement, mobileBlockedPlaceholderElement);
        showExtraUnblockIfShortPlaceholder(null, mobileBlockedPlaceholderElement);
      } else {
        const { blockingDialog, shadowRoot } = createYouTubeBlockingDialog(trackingElement, widget);
        resizeElementToMatch(oldPlaceholder || trackingElement, blockingDialog);
        replaceTrackingElement(widget, trackingElement, blockingDialog);
        showExtraUnblockIfShortPlaceholder(shadowRoot, blockingDialog);
        hideInfoTextIfNarrowPlaceholder(shadowRoot, blockingDialog, 460);
      }
    }
  }
  function showExtraUnblockIfShortPlaceholder(shadowRoot, placeholder) {
    if (!placeholder.parentElement) {
      return;
    }
    const parentStyles = window.getComputedStyle(placeholder.parentElement);
    if (parentStyles.display === "inline") {
      return;
    }
    const { height: placeholderHeight } = placeholder.getBoundingClientRect();
    const { height: parentHeight } = placeholder.parentElement.getBoundingClientRect();
    if (placeholderHeight > 0 && placeholderHeight <= 200 || parentHeight > 0 && parentHeight <= 230) {
      if (shadowRoot) {
        const titleRowTextButton = shadowRoot.querySelector(`#${titleID + "TextButton"}`);
        if (titleRowTextButton) {
          titleRowTextButton.style.display = "block";
        }
      }
      const blockedDiv = shadowRoot?.querySelector(".DuckDuckGoSocialContainer") || placeholder;
      if (blockedDiv) {
        blockedDiv.style.minHeight = "initial";
        blockedDiv.style.maxHeight = parentHeight + "px";
        blockedDiv.style.overflow = "hidden";
      }
    }
  }
  function hideInfoTextIfNarrowPlaceholder(shadowRoot, placeholder, narrowWidth) {
    const { width: placeholderWidth } = placeholder.getBoundingClientRect();
    if (placeholderWidth > 0 && placeholderWidth <= narrowWidth) {
      const buttonContainer = shadowRoot.querySelector(".DuckDuckGoButton.primary")?.parentElement;
      const contentTitle = shadowRoot.getElementById("contentTitle");
      const infoText = shadowRoot.getElementById("infoText");
      const learnMoreLink = shadowRoot.getElementById("learnMoreLink");
      if (!buttonContainer || !contentTitle || !infoText || !learnMoreLink) {
        return;
      }
      infoText.remove();
      learnMoreLink.remove();
      contentTitle.innerText += ". ";
      learnMoreLink.style.removeProperty("font-size");
      contentTitle.appendChild(learnMoreLink);
      buttonContainer.style.removeProperty("margin");
    }
  }
  function unblockClickToLoadContent(message) {
    return ctl.messaging.request("unblockClickToLoadContent", message);
  }
  function handleUnblockConfirmation(platformName, entity, acceptFunction, ...acceptFunctionParams) {
    if (platformsWithNativeModalSupport.includes(platformName)) {
      acceptFunction(...acceptFunctionParams);
    } else {
      makeModal(entity, acceptFunction, ...acceptFunctionParams);
    }
  }
  function notifyFacebookLogin() {
    ctl.addDebugFlag();
    ctl.messaging.notify("updateFacebookCTLBreakageFlags", { ctlFacebookLogin: true });
  }
  async function runLogin(entity) {
    if (entity === "Facebook, Inc.") {
      notifyFacebookLogin();
    }
    const action = entity === "Youtube" ? "block-ctl-yt" : "block-ctl-fb";
    const response = await unblockClickToLoadContent({ entity, action, isLogin: true, isSurrogateLogin: true });
    if (response && response.type === "ddg-ctp-user-cancel") {
      return abortSurrogateConfirmation(this.entity);
    }
    originalWindowDispatchEvent(
      createCustomEvent("ddg-ctp-run-login", {
        detail: {
          entity
        }
      })
    );
  }
  function abortSurrogateConfirmation(entity) {
    originalWindowDispatchEvent(
      createCustomEvent("ddg-ctp-cancel-modal", {
        detail: {
          entity
        }
      })
    );
  }
  function openShareFeedbackPage() {
    ctl.messaging.notify("openShareFeedbackPage");
  }
  function getLearnMoreLink(mode = "lightMode") {
    const linkElement = document.createElement("a");
    linkElement.style.cssText = styles.generalLink + styles[mode].linkFont;
    linkElement.ariaLabel = sharedStrings.readAbout;
    linkElement.href = "https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/";
    linkElement.target = "_blank";
    linkElement.textContent = sharedStrings.learnMore;
    linkElement.id = "learnMoreLink";
    return linkElement;
  }
  function resizeElementToMatch(sourceElement, targetElement) {
    const computedStyle = window.getComputedStyle(sourceElement);
    const stylesToCopy = ["position", "top", "bottom", "left", "right", "transform", "margin"];
    const { height, width } = sourceElement.getBoundingClientRect();
    if (height > 0 && width > 0) {
      targetElement.style.height = height + "px";
      targetElement.style.width = width + "px";
    } else {
      stylesToCopy.push("height", "width");
    }
    for (const key of stylesToCopy) {
      targetElement.style[key] = computedStyle[key];
    }
    if (computedStyle.display !== "inline") {
      if (targetElement.style.maxHeight < computedStyle.height) {
        targetElement.style.maxHeight = "initial";
      }
      if (targetElement.style.maxWidth < computedStyle.width) {
        targetElement.style.maxWidth = "initial";
      }
    }
  }
  function makeFontFaceStyleElement() {
    const fontFaceStyleElement = document.createElement("style");
    fontFaceStyleElement.textContent = styles.fontStyle;
    return fontFaceStyleElement;
  }
  function makeBaseStyleElement(mode = "lightMode") {
    const styleElement = document.createElement("style");
    const wrapperClass = "DuckDuckGoSocialContainer";
    styleElement.textContent = `
        .${wrapperClass} a {
            ${styles[mode].linkFont}
            font-weight: bold;
        }
        .${wrapperClass} a:hover {
            ${styles[mode].linkFont}
            font-weight: bold;
        }
        .DuckDuckGoButton {
            ${styles.button}
        }
        .DuckDuckGoButton > div {
            ${styles.buttonTextContainer}
        }
        .DuckDuckGoButton.primary {
           ${styles[mode].buttonBackground}
        }
        .DuckDuckGoButton.primary > div {
           ${styles[mode].buttonFont}
        }
        .DuckDuckGoButton.primary:hover {
           ${styles[mode].buttonBackgroundHover}
        }
        .DuckDuckGoButton.primary:active {
           ${styles[mode].buttonBackgroundPress}
        }
        .DuckDuckGoButton.secondary {
           ${styles.cancelMode.buttonBackground}
        }
        .DuckDuckGoButton.secondary > div {
            ${styles.cancelMode.buttonFont}
         }
        .DuckDuckGoButton.secondary:hover {
           ${styles.cancelMode.buttonBackgroundHover}
        }
        .DuckDuckGoButton.secondary:active {
           ${styles.cancelMode.buttonBackgroundPress}
        }
    `;
    return { wrapperClass, styleElement };
  }
  function makeTextButton(linkText, mode = "lightMode") {
    const linkElement = document.createElement("a");
    linkElement.style.cssText = styles.headerLink + styles[mode].linkFont;
    linkElement.textContent = linkText;
    return linkElement;
  }
  function makeButton(buttonText, mode = "lightMode") {
    const button = document.createElement("button");
    button.classList.add("DuckDuckGoButton");
    button.classList.add(mode === "cancelMode" ? "secondary" : "primary");
    if (buttonText) {
      const textContainer = document.createElement("div");
      textContainer.textContent = buttonText;
      button.appendChild(textContainer);
    }
    return button;
  }
  function makeToggleButton(mode, isActive = false, classNames = "", dataKey = "") {
    const toggleButton = document.createElement("button");
    toggleButton.className = classNames;
    toggleButton.style.cssText = styles.toggleButton;
    toggleButton.type = "button";
    toggleButton.setAttribute("aria-pressed", isActive ? "true" : "false");
    toggleButton.setAttribute("data-key", dataKey);
    const activeKey = isActive ? "active" : "inactive";
    const toggleBg = document.createElement("div");
    toggleBg.style.cssText = styles.toggleButtonBg + styles[mode].toggleButtonBgState[activeKey];
    const toggleKnob = document.createElement("div");
    toggleKnob.style.cssText = styles.toggleButtonKnob + styles.toggleButtonKnobState[activeKey];
    toggleButton.appendChild(toggleBg);
    toggleButton.appendChild(toggleKnob);
    return toggleButton;
  }
  function makeToggleButtonWithText(text, mode, isActive = false, toggleClassNames = "", textCssStyles = "", dataKey = "") {
    const wrapper = document.createElement("div");
    wrapper.style.cssText = styles.toggleButtonWrapper;
    const toggleButton = makeToggleButton(mode, isActive, toggleClassNames, dataKey);
    const textDiv = document.createElement("div");
    textDiv.style.cssText = styles.contentText + styles.toggleButtonText + styles[mode].toggleButtonText + textCssStyles;
    textDiv.textContent = text;
    wrapper.appendChild(toggleButton);
    wrapper.appendChild(textDiv);
    return wrapper;
  }
  function makeDefaultBlockIcon() {
    const blockedIcon = document.createElement("div");
    const dash = document.createElement("div");
    blockedIcon.appendChild(dash);
    blockedIcon.style.cssText = styles.circle;
    dash.style.cssText = styles.rectangle;
    return blockedIcon;
  }
  function makeShareFeedbackLink() {
    const feedbackLink = document.createElement("a");
    feedbackLink.style.cssText = styles.feedbackLink;
    feedbackLink.target = "_blank";
    feedbackLink.href = "#";
    feedbackLink.text = sharedStrings.shareFeedback;
    feedbackLink.addEventListener("click", function(e) {
      e.preventDefault();
      openShareFeedbackPage();
    });
    return feedbackLink;
  }
  function makeShareFeedbackRow() {
    const feedbackRow = document.createElement("div");
    feedbackRow.style.cssText = styles.feedbackRow;
    const feedbackLink = makeShareFeedbackLink();
    feedbackRow.appendChild(feedbackLink);
    return feedbackRow;
  }
  function makeLoginButton(buttonText, mode, hoverTextBody, icon, originalElement) {
    const container = document.createElement("div");
    container.style.cssText = "position: relative;";
    container.appendChild(makeFontFaceStyleElement());
    const shadowRoot = container.attachShadow({ mode: devMode ? "open" : "closed" });
    container.className = "fb-login-button FacebookLogin__button";
    const { styleElement } = makeBaseStyleElement(mode);
    styleElement.textContent += `
        #DuckDuckGoPrivacyEssentialsHoverableText {
            display: none;
        }
        #DuckDuckGoPrivacyEssentialsHoverable:hover #DuckDuckGoPrivacyEssentialsHoverableText {
            display: block;
        }
    `;
    shadowRoot.appendChild(styleElement);
    const hoverContainer = document.createElement("div");
    hoverContainer.id = "DuckDuckGoPrivacyEssentialsHoverable";
    hoverContainer.style.cssText = styles.hoverContainer;
    shadowRoot.appendChild(hoverContainer);
    const button = makeButton(buttonText, mode);
    if (!icon) {
      button.appendChild(makeDefaultBlockIcon());
    } else {
      const imgElement = document.createElement("img");
      imgElement.style.cssText = styles.loginIcon;
      imgElement.setAttribute("src", icon);
      imgElement.setAttribute("height", "28px");
      button.appendChild(imgElement);
    }
    hoverContainer.appendChild(button);
    const hoverBox = document.createElement("div");
    hoverBox.id = "DuckDuckGoPrivacyEssentialsHoverableText";
    hoverBox.style.cssText = styles.textBubble;
    const arrow = document.createElement("div");
    arrow.style.cssText = styles.textArrow;
    hoverBox.appendChild(arrow);
    const branding = createTitleRow("DuckDuckGo");
    branding.style.cssText += styles.hoverTextTitle;
    hoverBox.appendChild(branding);
    const hoverText = document.createElement("div");
    hoverText.style.cssText = styles.hoverTextBody;
    hoverText.textContent = hoverTextBody + " ";
    hoverText.appendChild(getLearnMoreLink(mode));
    hoverBox.appendChild(hoverText);
    hoverContainer.appendChild(hoverBox);
    const rect = originalElement.getBoundingClientRect();
    if (rect.left < styles.textBubbleLeftShift) {
      const leftShift = -rect.left + 10;
      hoverBox.style.cssText += `left: ${leftShift}px;`;
      const change = (1 - rect.left / styles.textBubbleLeftShift) * (100 - styles.arrowDefaultLocationPercent);
      arrow.style.cssText += `left: ${Math.max(10, styles.arrowDefaultLocationPercent - change)}%;`;
    } else if (rect.left + styles.textBubbleWidth - styles.textBubbleLeftShift > window.innerWidth) {
      const rightShift = rect.left + styles.textBubbleWidth - styles.textBubbleLeftShift;
      const diff = Math.min(rightShift - window.innerWidth, styles.textBubbleLeftShift);
      const rightMargin = 20;
      hoverBox.style.cssText += `left: -${styles.textBubbleLeftShift + diff + rightMargin}px;`;
      const change = diff / styles.textBubbleLeftShift * (100 - styles.arrowDefaultLocationPercent);
      arrow.style.cssText += `left: ${Math.max(10, styles.arrowDefaultLocationPercent + change)}%;`;
    } else {
      hoverBox.style.cssText += `left: -${styles.textBubbleLeftShift}px;`;
      arrow.style.cssText += `left: ${styles.arrowDefaultLocationPercent}%;`;
    }
    return {
      button,
      container
    };
  }
  function makeModal(entity, acceptFunction, ...acceptFunctionParams) {
    const icon = entityData[entity].modalIcon;
    const modalContainer = document.createElement("div");
    modalContainer.setAttribute("data-key", "modal");
    modalContainer.style.cssText = styles.modalContainer;
    modalContainer.appendChild(makeFontFaceStyleElement());
    const closeModal = () => {
      document.body.removeChild(modalContainer);
      abortSurrogateConfirmation(entity);
    };
    const shadowRoot = modalContainer.attachShadow({ mode: devMode ? "open" : "closed" });
    const { styleElement } = makeBaseStyleElement("lightMode");
    shadowRoot.appendChild(styleElement);
    const pageOverlay = document.createElement("div");
    pageOverlay.style.cssText = styles.overlay;
    const modal = document.createElement("div");
    modal.style.cssText = styles.modal;
    const modalTitle = createTitleRow("DuckDuckGo", null, closeModal);
    modal.appendChild(modalTitle);
    const iconElement = document.createElement("img");
    iconElement.style.cssText = styles.icon + styles.modalIcon;
    iconElement.setAttribute("src", icon);
    iconElement.setAttribute("height", "70px");
    const title = document.createElement("div");
    title.style.cssText = styles.modalContentTitle;
    title.textContent = entityData[entity].modalTitle;
    const modalContent = document.createElement("div");
    modalContent.style.cssText = styles.modalContent;
    const message = document.createElement("div");
    message.style.cssText = styles.modalContentText;
    message.textContent = entityData[entity].modalText + " ";
    message.appendChild(getLearnMoreLink());
    modalContent.appendChild(iconElement);
    modalContent.appendChild(title);
    modalContent.appendChild(message);
    const buttonRow = document.createElement("div");
    buttonRow.style.cssText = styles.modalButtonRow;
    const allowButton = makeButton(entityData[entity].modalAcceptText, "lightMode");
    allowButton.style.cssText += styles.modalButton + "margin-bottom: 8px;";
    allowButton.setAttribute("data-key", "allow");
    allowButton.addEventListener("click", function doLogin() {
      acceptFunction(...acceptFunctionParams);
      document.body.removeChild(modalContainer);
    });
    const rejectButton = makeButton(entityData[entity].modalRejectText, "cancelMode");
    rejectButton.setAttribute("data-key", "reject");
    rejectButton.style.cssText += styles.modalButton;
    rejectButton.addEventListener("click", closeModal);
    buttonRow.appendChild(allowButton);
    buttonRow.appendChild(rejectButton);
    modalContent.appendChild(buttonRow);
    modal.appendChild(modalContent);
    shadowRoot.appendChild(pageOverlay);
    shadowRoot.appendChild(modal);
    document.body.insertBefore(modalContainer, document.body.childNodes[0]);
  }
  function createTitleRow(message, textButton, closeBtnFn) {
    const row = document.createElement("div");
    row.style.cssText = styles.titleBox;
    const logoContainer = document.createElement("div");
    logoContainer.style.cssText = styles.logo;
    const logoElement = document.createElement("img");
    logoElement.setAttribute("src", logoImg);
    logoElement.setAttribute("height", "21px");
    logoElement.style.cssText = styles.logoImg;
    logoContainer.appendChild(logoElement);
    row.appendChild(logoContainer);
    const msgElement = document.createElement("div");
    msgElement.id = titleID;
    msgElement.textContent = message;
    msgElement.style.cssText = styles.title;
    row.appendChild(msgElement);
    if (typeof closeBtnFn === "function") {
      const closeButton = document.createElement("button");
      closeButton.style.cssText = styles.closeButton;
      const closeIconImg = document.createElement("img");
      closeIconImg.setAttribute("src", closeIcon);
      closeIconImg.setAttribute("height", "12px");
      closeIconImg.style.cssText = styles.closeIcon;
      closeButton.appendChild(closeIconImg);
      closeButton.addEventListener("click", closeBtnFn);
      row.appendChild(closeButton);
    }
    if (textButton) {
      textButton.id = titleID + "TextButton";
      row.appendChild(textButton);
    }
    return row;
  }
  function createContentBlock(widget, button, textButton, img, bottomRow) {
    const contentBlock = document.createElement("div");
    contentBlock.style.cssText = styles.wrapperDiv;
    contentBlock.appendChild(makeFontFaceStyleElement());
    const shadowRootMode = devMode ? "open" : "closed";
    const shadowRoot = contentBlock.attachShadow({ mode: shadowRootMode });
    const { wrapperClass, styleElement } = makeBaseStyleElement(widget.getMode());
    shadowRoot.appendChild(styleElement);
    const element = document.createElement("div");
    element.style.cssText = styles.block + styles[widget.getMode()].background + styles[widget.getMode()].textFont;
    if (widget.replaceSettings.type === "youtube-video") {
      element.style.cssText += styles.youTubeDialogBlock;
    }
    element.className = wrapperClass;
    shadowRoot.appendChild(element);
    const titleRow = document.createElement("div");
    titleRow.style.cssText = styles.headerRow;
    element.appendChild(titleRow);
    titleRow.appendChild(createTitleRow("DuckDuckGo", textButton));
    const contentRow = document.createElement("div");
    contentRow.style.cssText = styles.content;
    if (img) {
      const imageRow = document.createElement("div");
      imageRow.style.cssText = styles.imgRow;
      const imgElement = document.createElement("img");
      imgElement.style.cssText = styles.icon;
      imgElement.setAttribute("src", img);
      imgElement.setAttribute("height", "70px");
      imageRow.appendChild(imgElement);
      element.appendChild(imageRow);
    }
    const contentTitle = document.createElement("div");
    contentTitle.style.cssText = styles.contentTitle;
    contentTitle.textContent = widget.replaceSettings.infoTitle;
    contentTitle.id = "contentTitle";
    contentRow.appendChild(contentTitle);
    const contentText = document.createElement("div");
    contentText.style.cssText = styles.contentText;
    const contentTextSpan = document.createElement("span");
    contentTextSpan.id = "infoText";
    contentTextSpan.textContent = widget.replaceSettings.infoText + " ";
    contentText.appendChild(contentTextSpan);
    contentText.appendChild(getLearnMoreLink());
    contentRow.appendChild(contentText);
    element.appendChild(contentRow);
    const buttonRow = document.createElement("div");
    buttonRow.style.cssText = styles.buttonRow;
    buttonRow.appendChild(button);
    contentText.appendChild(buttonRow);
    if (bottomRow) {
      contentRow.appendChild(bottomRow);
    }
    if (widget.replaceSettings.type === "youtube-video") {
      const feedbackRow = makeShareFeedbackRow();
      shadowRoot.appendChild(feedbackRow);
    }
    return { contentBlock, shadowRoot };
  }
  function createYouTubeBlockingDialog(trackingElement, widget) {
    const button = makeButton(widget.replaceSettings.buttonText, widget.getMode());
    const textButton = makeTextButton(widget.replaceSettings.buttonText, widget.getMode());
    const bottomRow = document.createElement("div");
    bottomRow.style.cssText = styles.youTubeDialogBottomRow;
    const previewToggle = makeToggleButtonWithText(
      widget.replaceSettings.previewToggleText,
      widget.getMode(),
      false,
      "",
      "",
      "yt-preview-toggle"
    );
    previewToggle.addEventListener(
      "click",
      () => makeModal(widget.entity, () => ctl.messaging.notify("setYoutubePreviewsEnabled", { youtubePreviewsEnabled: true }), widget.entity)
    );
    bottomRow.appendChild(previewToggle);
    const { contentBlock, shadowRoot } = createContentBlock(widget, button, textButton, null, bottomRow);
    contentBlock.id = trackingElement.id;
    contentBlock.style.cssText += styles.wrapperDiv + styles.youTubeWrapperDiv;
    button.addEventListener("click", widget.clickFunction(trackingElement, contentBlock));
    textButton.addEventListener("click", widget.clickFunction(trackingElement, contentBlock));
    return {
      blockingDialog: contentBlock,
      shadowRoot
    };
  }
  function createYouTubePreview(originalElement, widget) {
    const youTubePreview = document.createElement("div");
    youTubePreview.id = originalElement.id;
    youTubePreview.style.cssText = styles.wrapperDiv + styles.placeholderWrapperDiv;
    youTubePreview.appendChild(makeFontFaceStyleElement());
    const shadowRoot = youTubePreview.attachShadow({ mode: devMode ? "open" : "closed" });
    const { wrapperClass, styleElement } = makeBaseStyleElement(widget.getMode());
    shadowRoot.appendChild(styleElement);
    const youTubePreviewDiv = document.createElement("div");
    youTubePreviewDiv.style.cssText = styles.youTubeDialogDiv;
    youTubePreviewDiv.classList.add(wrapperClass);
    shadowRoot.appendChild(youTubePreviewDiv);
    const previewImageWrapper = document.createElement("div");
    previewImageWrapper.style.cssText = styles.youTubePreviewWrapperImg;
    youTubePreviewDiv.appendChild(previewImageWrapper);
    const previewImageElement = document.createElement("img");
    previewImageElement.setAttribute("referrerPolicy", "no-referrer");
    previewImageElement.style.cssText = styles.youTubePreviewImg;
    previewImageWrapper.appendChild(previewImageElement);
    const innerDiv = document.createElement("div");
    innerDiv.style.cssText = styles.youTubePlaceholder;
    const topSection = document.createElement("div");
    topSection.style.cssText = styles.youTubeTopSection;
    innerDiv.appendChild(topSection);
    const titleElement = document.createElement("p");
    titleElement.style.cssText = styles.youTubeTitle;
    topSection.appendChild(titleElement);
    const textButton = makeTextButton(widget.replaceSettings.buttonText, "darkMode");
    textButton.id = titleID + "TextButton";
    textButton.addEventListener("click", widget.clickFunction(originalElement, youTubePreview));
    topSection.appendChild(textButton);
    const playButtonRow = document.createElement("div");
    playButtonRow.style.cssText = styles.youTubePlayButtonRow;
    const playButton = makeButton("", widget.getMode());
    playButton.style.cssText += styles.youTubePlayButton;
    const videoPlayImg = document.createElement("img");
    const videoPlayIcon = widget.replaceSettings.placeholder.videoPlayIcon[widget.getMode()];
    videoPlayImg.setAttribute("src", videoPlayIcon);
    playButton.appendChild(videoPlayImg);
    playButton.addEventListener("click", widget.clickFunction(originalElement, youTubePreview));
    playButtonRow.appendChild(playButton);
    innerDiv.appendChild(playButtonRow);
    const previewToggleRow = document.createElement("div");
    previewToggleRow.style.cssText = styles.youTubePreviewToggleRow;
    const previewToggle = makeToggleButtonWithText(
      widget.replaceSettings.placeholder.previewToggleEnabledText,
      widget.getMode(),
      true,
      "",
      styles.youTubePreviewToggleText,
      "yt-preview-toggle"
    );
    previewToggle.addEventListener("click", () => ctl.messaging.notify("setYoutubePreviewsEnabled", { youtubePreviewsEnabled: false }));
    const previewText = document.createElement("div");
    previewText.style.cssText = styles.contentText + styles.toggleButtonText + styles.youTubePreviewInfoText;
    previewText.insertAdjacentHTML("beforeend", widget.replaceSettings.placeholder.previewInfoText);
    const previewTextLink = previewText.querySelector("a");
    if (previewTextLink) {
      const newPreviewTextLink = getLearnMoreLink(widget.getMode());
      newPreviewTextLink.innerText = previewTextLink.innerText;
      previewTextLink.replaceWith(newPreviewTextLink);
    }
    previewToggleRow.appendChild(previewToggle);
    previewToggleRow.appendChild(previewText);
    innerDiv.appendChild(previewToggleRow);
    youTubePreviewDiv.appendChild(innerDiv);
    const videoURL = originalElement.src || originalElement.getAttribute("data-src");
    ctl.messaging.request("getYouTubeVideoDetails", { videoURL }).then(({ videoURL: videoURLResp, status, title, previewImage }) => {
      if (!status || videoURLResp !== videoURL) {
        return;
      }
      if (status === "success") {
        titleElement.innerText = title;
        titleElement.title = title;
        if (previewImage) {
          previewImageElement.setAttribute("src", previewImage);
        }
        widget.autoplay = true;
      }
    });
    const feedbackRow = makeShareFeedbackRow();
    shadowRoot.appendChild(feedbackRow);
    return { youTubePreview, shadowRoot };
  }
  var _messagingContext;
  var ClickToLoad = class extends ContentFeature {
    constructor() {
      super(...arguments);
      /** @type {MessagingContext} */
      __privateAdd(this, _messagingContext);
    }
    async init(args) {
      if (!this.messaging) {
        throw new Error("Cannot operate click to load without a messaging backend");
      }
      _messagingModuleScope = this.messaging;
      _addDebugFlag = this.addDebugFlag.bind(this);
      const websiteOwner = args?.site?.parentEntity;
      const settings = args?.featureSettings?.clickToLoad || {};
      const locale = args?.locale || "en";
      const localizedConfig = getConfig(locale);
      config = localizedConfig.config;
      sharedStrings = localizedConfig.sharedStrings;
      styles = getStyles(this.assetConfig);
      registerCustomElements();
      for (const entity of Object.keys(config)) {
        if (websiteOwner && entity === websiteOwner || !settings[entity] || settings[entity].state !== "enabled") {
          delete config[entity];
          continue;
        }
        entities.push(entity);
        const shouldShowLoginModal = !!config[entity].informationalModal;
        const currentEntityData = { shouldShowLoginModal };
        if (shouldShowLoginModal) {
          const { informationalModal } = config[entity];
          currentEntityData.modalIcon = informationalModal.icon;
          currentEntityData.modalTitle = informationalModal.messageTitle;
          currentEntityData.modalText = informationalModal.messageBody;
          currentEntityData.modalAcceptText = informationalModal.confirmButtonText;
          currentEntityData.modalRejectText = informationalModal.rejectButtonText;
        }
        entityData[entity] = currentEntityData;
      }
      window.addEventListener("ddg-ctp", (event) => {
        if (!("detail" in event)) return;
        const entity = event.detail?.entity;
        if (!entities.includes(entity)) {
          return;
        }
        if (event.detail?.appID) {
          appID = JSON.stringify(event.detail.appID).replace(/"/g, "");
        }
        if (event.detail?.action === "login") {
          if (entity === "Facebook, Inc.") {
            notifyFacebookLogin();
          }
          if (entityData[entity].shouldShowLoginModal) {
            handleUnblockConfirmation(this.platform.name, entity, runLogin, entity);
          } else {
            runLogin(entity);
          }
        }
      });
      this.messaging.subscribe(
        "displayClickToLoadPlaceholders",
        // TODO: Pass `message.options.ruleAction` through, that way only
        //       content corresponding to the entity for that ruleAction need to
        //       be replaced with a placeholder.
        () => this.replaceClickToLoadElements()
      );
      const clickToLoadState = await this.messaging.request("getClickToLoadState");
      this.onClickToLoadState(clickToLoadState);
      if (document.readyState === "complete") {
        afterPageLoadResolver();
      } else {
        window.addEventListener("load", afterPageLoadResolver, { once: true });
      }
      await afterPageLoad;
      window.addEventListener("ddg-ctp-surrogate-load", () => {
        originalWindowDispatchEvent(createCustomEvent("ddg-ctp-ready"));
      });
      window.setTimeout(() => {
        originalWindowDispatchEvent(createCustomEvent("ddg-ctp-ready"));
      }, 0);
    }
    /**
     * This is only called by the current integration between Android and Extension and is now
     * used to connect only these Platforms responses with the temporary implementation of
     * SendMessageMessagingTransport that wraps this communication.
     * This can be removed once they have their own Messaging integration.
     */
    update(message) {
      if (message?.feature && message?.feature !== "clickToLoad") return;
      const messageType = message?.messageType;
      if (!messageType) return;
      if (!this._clickToLoadMessagingTransport) {
        throw new Error("_clickToLoadMessagingTransport not ready. Cannot operate click to load without a messaging backend");
      }
      return this._clickToLoadMessagingTransport.onResponse(message);
    }
    /**
     * Update Click to Load internal state
     * @param {Object} state Click to Load state response from the Platform
     * @param {boolean} state.devMode Developer or Production environment
     * @param {boolean} state.youtubePreviewsEnabled YouTube Click to Load - YT Previews enabled flag
     */
    onClickToLoadState(state) {
      devMode = state.devMode;
      isYoutubePreviewsEnabled = state.youtubePreviewsEnabled;
      readyToDisplayPlaceholdersResolver();
    }
    /**
     * Replace the blocked CTL elements on the page with placeholders.
     * @param {HTMLElement} [targetElement]
     *   If specified, only this element will be replaced (assuming it matches
     *   one of the expected CSS selectors). If omitted, all matching elements
     *   in the document will be replaced instead.
     */
    async replaceClickToLoadElements(targetElement) {
      await readyToDisplayPlaceholders;
      for (const entity of Object.keys(config)) {
        for (const widgetData of Object.values(config[entity].elementData)) {
          const selector = widgetData.selectors.join();
          let trackingElements = [];
          if (targetElement) {
            if (targetElement.matches(selector)) {
              trackingElements.push(targetElement);
            }
          } else {
            trackingElements = Array.from(document.querySelectorAll(selector));
          }
          await Promise.all(
            trackingElements.map((trackingElement) => {
              if (knownTrackingElements.has(trackingElement)) {
                return Promise.resolve();
              }
              knownTrackingElements.add(trackingElement);
              const widget = new DuckWidget(widgetData, trackingElement, entity, this.platform);
              return createPlaceholderElementAndReplace(widget, trackingElement);
            })
          );
        }
      }
    }
    /**
     * @returns {MessagingContext}
     */
    get messagingContext() {
      if (__privateGet(this, _messagingContext)) return __privateGet(this, _messagingContext);
      __privateSet(this, _messagingContext, this._createMessagingContext());
      return __privateGet(this, _messagingContext);
    }
    // Messaging layer between Click to Load and the Platform
    get messaging() {
      if (this._messaging) return this._messaging;
      if (this.platform.name === "extension") {
        this._clickToLoadMessagingTransport = new SendMessageMessagingTransport();
        const config2 = new TestTransportConfig(this._clickToLoadMessagingTransport);
        this._messaging = new Messaging(this.messagingContext, config2);
        return this._messaging;
      } else if (this.platform.name === "ios" || this.platform.name === "macos") {
        const config2 = new WebkitMessagingConfig({
          secret: "",
          hasModernWebkitAPI: true,
          webkitMessageHandlerNames: ["contentScopeScriptsIsolated"]
        });
        this._messaging = new Messaging(this.messagingContext, config2);
        return this._messaging;
      } else {
        throw new Error("Messaging not supported yet on platform: " + this.name);
      }
    }
  };
  _messagingContext = new WeakMap();

  // ddg:platformFeatures:ddg:platformFeatures
  var ddg_platformFeatures_default = {
    ddg_feature_cookie: CookieFeature,
    ddg_feature_fingerprintingAudio: FingerprintingAudio,
    ddg_feature_fingerprintingBattery: FingerprintingBattery,
    ddg_feature_fingerprintingCanvas: FingerprintingCanvas,
    ddg_feature_googleRejected: GoogleRejected,
    ddg_feature_gpc: GlobalPrivacyControl,
    ddg_feature_fingerprintingHardware: FingerprintingHardware,
    ddg_feature_referrer: Referrer,
    ddg_feature_fingerprintingScreenSize: FingerprintingScreenSize,
    ddg_feature_fingerprintingTemporaryStorage: FingerprintingTemporaryStorage,
    ddg_feature_navigatorInterface: NavigatorInterface,
    ddg_feature_elementHiding: ElementHiding,
    ddg_feature_exceptionHandler: ExceptionHandler,
    ddg_feature_apiManipulation: ApiManipulation,
    ddg_feature_clickToLoad: ClickToLoad
  };

  // src/url-change.js
  var urlChangeListeners = /* @__PURE__ */ new Set();
  function registerForURLChanges(listener) {
    if (urlChangeListeners.size === 0) {
      listenForURLChanges();
    }
    urlChangeListeners.add(listener);
  }
  function handleURLChange() {
    for (const listener of urlChangeListeners) {
      listener();
    }
  }
  function listenForURLChanges() {
    const urlChangedInstance = new ContentFeature("urlChanged", {}, {});
    if ("navigation" in globalThis && "addEventListener" in globalThis.navigation) {
      globalThis.navigation.addEventListener("navigatesuccess", () => {
        handleURLChange();
      });
      return;
    }
    if (isBeingFramed()) {
      return;
    }
    const historyMethodProxy = new DDGProxy(urlChangedInstance, History.prototype, "pushState", {
      apply(target, thisArg, args) {
        const changeResult = DDGReflect.apply(target, thisArg, args);
        handleURLChange();
        return changeResult;
      }
    });
    historyMethodProxy.overload();
    window.addEventListener("popstate", () => {
      handleURLChange();
    });
  }

  // src/content-scope-features.js
  var initArgs = null;
  var updates = [];
  var features = [];
  var alwaysInitFeatures = /* @__PURE__ */ new Set(["cookie"]);
  var performanceMonitor = new PerformanceMonitor();
  var isHTMLDocument = document instanceof HTMLDocument || document instanceof XMLDocument && document.createElement("div") instanceof HTMLDivElement;
  function load(args) {
    const mark = performanceMonitor.mark("load");
    if (!isHTMLDocument) {
      return;
    }
    const importConfig = {
      trackerLookup: $TRACKER_LOOKUP$,
      injectName: "firefox"
    };
    const bundledFeatureNames = typeof importConfig.injectName === "string" ? platformSupport[importConfig.injectName] : [];
    const featuresToLoad = isGloballyDisabled(args) ? platformSpecificFeatures : args.site.enabledFeatures || bundledFeatureNames;
    for (const featureName of bundledFeatureNames) {
      if (featuresToLoad.includes(featureName)) {
        const ContentFeature2 = ddg_platformFeatures_default["ddg_feature_" + featureName];
        const featureInstance2 = new ContentFeature2(featureName, importConfig, args);
        featureInstance2.callLoad();
        features.push({ featureName, featureInstance: featureInstance2 });
      }
    }
    mark.end();
  }
  async function init(args) {
    const mark = performanceMonitor.mark("init");
    initArgs = args;
    if (!isHTMLDocument) {
      return;
    }
    registerMessageSecret(args.messageSecret);
    initStringExemptionLists(args);
    const resolvedFeatures = await Promise.all(features);
    resolvedFeatures.forEach(({ featureInstance: featureInstance2, featureName }) => {
      if (!isFeatureBroken(args, featureName) || alwaysInitExtensionFeatures(args, featureName)) {
        featureInstance2.callInit(args);
        if (featureInstance2.listenForUrlChanges || featureInstance2.urlChanged) {
          registerForURLChanges(() => {
            featureInstance2.recomputeSiteObject();
            featureInstance2?.urlChanged();
          });
        }
      }
    });
    while (updates.length) {
      const update2 = updates.pop();
      await updateFeaturesInner(update2);
    }
    mark.end();
    if (args.debug) {
      performanceMonitor.measureAll();
    }
  }
  function update(args) {
    if (!isHTMLDocument) {
      return;
    }
    if (initArgs === null) {
      updates.push(args);
      return;
    }
    updateFeaturesInner(args);
  }
  function alwaysInitExtensionFeatures(args, featureName) {
    return args.platform.name === "extension" && alwaysInitFeatures.has(featureName);
  }
  async function updateFeaturesInner(args) {
    const resolvedFeatures = await Promise.all(features);
    resolvedFeatures.forEach(({ featureInstance: featureInstance2, featureName }) => {
      if (!isFeatureBroken(initArgs, featureName) && featureInstance2.update) {
        featureInstance2.update(args);
      }
    });
  }

  // entry-points/extension-mv3.js
  var secret = (crypto.getRandomValues(new Uint32Array(1))[0] / 2 ** 32).toString().replace("0.", "");
  load({
    platform: {
      name: "extension"
    },
    site: computeLimitedSiteObject(),
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    bundledConfig: $BUNDLED_CONFIG$
  });
  window.addEventListener(secret, ({ detail: encodedMessage }) => {
    if (!encodedMessage) return;
    const message = JSON.parse(encodedMessage);
    switch (message.type) {
      case "update":
        update(message);
        break;
      case "register":
        if (message.argumentsObject) {
          message.argumentsObject.messageSecret = secret;
          init(message.argumentsObject);
        }
        break;
    }
  });
  window.dispatchEvent(
    new CustomEvent("ddg-secret", {
      detail: secret
    })
  );
})();
