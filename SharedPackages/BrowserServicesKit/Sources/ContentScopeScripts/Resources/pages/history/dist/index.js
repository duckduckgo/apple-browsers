"use strict";
(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
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

  // ../node_modules/classnames/index.js
  var require_classnames = __commonJS({
    "../node_modules/classnames/index.js"(exports, module) {
      (function() {
        "use strict";
        var hasOwn = {}.hasOwnProperty;
        function classNames() {
          var classes = "";
          for (var i5 = 0; i5 < arguments.length; i5++) {
            var arg = arguments[i5];
            if (arg) {
              classes = appendClass(classes, parseValue(arg));
            }
          }
          return classes;
        }
        function parseValue(arg) {
          if (typeof arg === "string" || typeof arg === "number") {
            return arg;
          }
          if (typeof arg !== "object") {
            return "";
          }
          if (Array.isArray(arg)) {
            return classNames.apply(null, arg);
          }
          if (arg.toString !== Object.prototype.toString && !arg.toString.toString().includes("[native code]")) {
            return arg.toString();
          }
          var classes = "";
          for (var key in arg) {
            if (hasOwn.call(arg, key) && arg[key]) {
              classes = appendClass(classes, key);
            }
          }
          return classes;
        }
        function appendClass(value, newClass) {
          if (!newClass) {
            return value;
          }
          if (value) {
            return value + " " + newClass;
          }
          return value + newClass;
        }
        if (typeof module !== "undefined" && module.exports) {
          classNames.default = classNames;
          module.exports = classNames;
        } else if (typeof define === "function" && typeof define.amd === "object" && define.amd) {
          define("classnames", [], function() {
            return classNames;
          });
        } else {
          window.classNames = classNames;
        }
      })();
    }
  });

  // ../node_modules/preact/dist/preact.module.js
  var n;
  var l;
  var u;
  var t;
  var i;
  var r;
  var o;
  var e;
  var f;
  var c;
  var s;
  var a;
  var h;
  var p = {};
  var v = [];
  var y = /acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i;
  var w = Array.isArray;
  function d(n3, l5) {
    for (var u4 in l5) n3[u4] = l5[u4];
    return n3;
  }
  function g(n3) {
    n3 && n3.parentNode && n3.parentNode.removeChild(n3);
  }
  function _(l5, u4, t4) {
    var i5, r4, o4, e4 = {};
    for (o4 in u4) "key" == o4 ? i5 = u4[o4] : "ref" == o4 ? r4 = u4[o4] : e4[o4] = u4[o4];
    if (arguments.length > 2 && (e4.children = arguments.length > 3 ? n.call(arguments, 2) : t4), "function" == typeof l5 && null != l5.defaultProps) for (o4 in l5.defaultProps) void 0 === e4[o4] && (e4[o4] = l5.defaultProps[o4]);
    return m(l5, e4, i5, r4, null);
  }
  function m(n3, t4, i5, r4, o4) {
    var e4 = { type: n3, props: t4, key: i5, ref: r4, __k: null, __: null, __b: 0, __e: null, __c: null, constructor: void 0, __v: null == o4 ? ++u : o4, __i: -1, __u: 0 };
    return null == o4 && null != l.vnode && l.vnode(e4), e4;
  }
  function k(n3) {
    return n3.children;
  }
  function x(n3, l5) {
    this.props = n3, this.context = l5;
  }
  function S(n3, l5) {
    if (null == l5) return n3.__ ? S(n3.__, n3.__i + 1) : null;
    for (var u4; l5 < n3.__k.length; l5++) if (null != (u4 = n3.__k[l5]) && null != u4.__e) return u4.__e;
    return "function" == typeof n3.type ? S(n3) : null;
  }
  function C(n3) {
    var l5, u4;
    if (null != (n3 = n3.__) && null != n3.__c) {
      for (n3.__e = n3.__c.base = null, l5 = 0; l5 < n3.__k.length; l5++) if (null != (u4 = n3.__k[l5]) && null != u4.__e) {
        n3.__e = n3.__c.base = u4.__e;
        break;
      }
      return C(n3);
    }
  }
  function M(n3) {
    (!n3.__d && (n3.__d = true) && i.push(n3) && !$.__r++ || r != l.debounceRendering) && ((r = l.debounceRendering) || o)($);
  }
  function $() {
    for (var n3, u4, t4, r4, o4, f4, c4, s4 = 1; i.length; ) i.length > s4 && i.sort(e), n3 = i.shift(), s4 = i.length, n3.__d && (t4 = void 0, o4 = (r4 = (u4 = n3).__v).__e, f4 = [], c4 = [], u4.__P && ((t4 = d({}, r4)).__v = r4.__v + 1, l.vnode && l.vnode(t4), O(u4.__P, t4, r4, u4.__n, u4.__P.namespaceURI, 32 & r4.__u ? [o4] : null, f4, null == o4 ? S(r4) : o4, !!(32 & r4.__u), c4), t4.__v = r4.__v, t4.__.__k[t4.__i] = t4, z(f4, t4, c4), t4.__e != o4 && C(t4)));
    $.__r = 0;
  }
  function I(n3, l5, u4, t4, i5, r4, o4, e4, f4, c4, s4) {
    var a4, h5, y5, w5, d5, g6, _5 = t4 && t4.__k || v, m4 = l5.length;
    for (f4 = P(u4, l5, _5, f4, m4), a4 = 0; a4 < m4; a4++) null != (y5 = u4.__k[a4]) && (h5 = -1 == y5.__i ? p : _5[y5.__i] || p, y5.__i = a4, g6 = O(n3, y5, h5, i5, r4, o4, e4, f4, c4, s4), w5 = y5.__e, y5.ref && h5.ref != y5.ref && (h5.ref && q(h5.ref, null, y5), s4.push(y5.ref, y5.__c || w5, y5)), null == d5 && null != w5 && (d5 = w5), 4 & y5.__u || h5.__k === y5.__k ? f4 = A(y5, f4, n3) : "function" == typeof y5.type && void 0 !== g6 ? f4 = g6 : w5 && (f4 = w5.nextSibling), y5.__u &= -7);
    return u4.__e = d5, f4;
  }
  function P(n3, l5, u4, t4, i5) {
    var r4, o4, e4, f4, c4, s4 = u4.length, a4 = s4, h5 = 0;
    for (n3.__k = new Array(i5), r4 = 0; r4 < i5; r4++) null != (o4 = l5[r4]) && "boolean" != typeof o4 && "function" != typeof o4 ? (f4 = r4 + h5, (o4 = n3.__k[r4] = "string" == typeof o4 || "number" == typeof o4 || "bigint" == typeof o4 || o4.constructor == String ? m(null, o4, null, null, null) : w(o4) ? m(k, { children: o4 }, null, null, null) : null == o4.constructor && o4.__b > 0 ? m(o4.type, o4.props, o4.key, o4.ref ? o4.ref : null, o4.__v) : o4).__ = n3, o4.__b = n3.__b + 1, e4 = null, -1 != (c4 = o4.__i = L(o4, u4, f4, a4)) && (a4--, (e4 = u4[c4]) && (e4.__u |= 2)), null == e4 || null == e4.__v ? (-1 == c4 && (i5 > s4 ? h5-- : i5 < s4 && h5++), "function" != typeof o4.type && (o4.__u |= 4)) : c4 != f4 && (c4 == f4 - 1 ? h5-- : c4 == f4 + 1 ? h5++ : (c4 > f4 ? h5-- : h5++, o4.__u |= 4))) : n3.__k[r4] = null;
    if (a4) for (r4 = 0; r4 < s4; r4++) null != (e4 = u4[r4]) && 0 == (2 & e4.__u) && (e4.__e == t4 && (t4 = S(e4)), B(e4, e4));
    return t4;
  }
  function A(n3, l5, u4) {
    var t4, i5;
    if ("function" == typeof n3.type) {
      for (t4 = n3.__k, i5 = 0; t4 && i5 < t4.length; i5++) t4[i5] && (t4[i5].__ = n3, l5 = A(t4[i5], l5, u4));
      return l5;
    }
    n3.__e != l5 && (l5 && n3.type && !u4.contains(l5) && (l5 = S(n3)), u4.insertBefore(n3.__e, l5 || null), l5 = n3.__e);
    do {
      l5 = l5 && l5.nextSibling;
    } while (null != l5 && 8 == l5.nodeType);
    return l5;
  }
  function H(n3, l5) {
    return l5 = l5 || [], null == n3 || "boolean" == typeof n3 || (w(n3) ? n3.some(function(n4) {
      H(n4, l5);
    }) : l5.push(n3)), l5;
  }
  function L(n3, l5, u4, t4) {
    var i5, r4, o4 = n3.key, e4 = n3.type, f4 = l5[u4];
    if (null === f4 && null == n3.key || f4 && o4 == f4.key && e4 == f4.type && 0 == (2 & f4.__u)) return u4;
    if (t4 > (null != f4 && 0 == (2 & f4.__u) ? 1 : 0)) for (i5 = u4 - 1, r4 = u4 + 1; i5 >= 0 || r4 < l5.length; ) {
      if (i5 >= 0) {
        if ((f4 = l5[i5]) && 0 == (2 & f4.__u) && o4 == f4.key && e4 == f4.type) return i5;
        i5--;
      }
      if (r4 < l5.length) {
        if ((f4 = l5[r4]) && 0 == (2 & f4.__u) && o4 == f4.key && e4 == f4.type) return r4;
        r4++;
      }
    }
    return -1;
  }
  function T(n3, l5, u4) {
    "-" == l5[0] ? n3.setProperty(l5, null == u4 ? "" : u4) : n3[l5] = null == u4 ? "" : "number" != typeof u4 || y.test(l5) ? u4 : u4 + "px";
  }
  function j(n3, l5, u4, t4, i5) {
    var r4, o4;
    n: if ("style" == l5) if ("string" == typeof u4) n3.style.cssText = u4;
    else {
      if ("string" == typeof t4 && (n3.style.cssText = t4 = ""), t4) for (l5 in t4) u4 && l5 in u4 || T(n3.style, l5, "");
      if (u4) for (l5 in u4) t4 && u4[l5] == t4[l5] || T(n3.style, l5, u4[l5]);
    }
    else if ("o" == l5[0] && "n" == l5[1]) r4 = l5 != (l5 = l5.replace(f, "$1")), o4 = l5.toLowerCase(), l5 = o4 in n3 || "onFocusOut" == l5 || "onFocusIn" == l5 ? o4.slice(2) : l5.slice(2), n3.l || (n3.l = {}), n3.l[l5 + r4] = u4, u4 ? t4 ? u4.u = t4.u : (u4.u = c, n3.addEventListener(l5, r4 ? a : s, r4)) : n3.removeEventListener(l5, r4 ? a : s, r4);
    else {
      if ("http://www.w3.org/2000/svg" == i5) l5 = l5.replace(/xlink(H|:h)/, "h").replace(/sName$/, "s");
      else if ("width" != l5 && "height" != l5 && "href" != l5 && "list" != l5 && "form" != l5 && "tabIndex" != l5 && "download" != l5 && "rowSpan" != l5 && "colSpan" != l5 && "role" != l5 && "popover" != l5 && l5 in n3) try {
        n3[l5] = null == u4 ? "" : u4;
        break n;
      } catch (n4) {
      }
      "function" == typeof u4 || (null == u4 || false === u4 && "-" != l5[4] ? n3.removeAttribute(l5) : n3.setAttribute(l5, "popover" == l5 && 1 == u4 ? "" : u4));
    }
  }
  function F(n3) {
    return function(u4) {
      if (this.l) {
        var t4 = this.l[u4.type + n3];
        if (null == u4.t) u4.t = c++;
        else if (u4.t < t4.u) return;
        return t4(l.event ? l.event(u4) : u4);
      }
    };
  }
  function O(n3, u4, t4, i5, r4, o4, e4, f4, c4, s4) {
    var a4, h5, p5, v4, y5, _5, m4, b4, S2, C3, M3, $2, P4, A5, H3, L2, T5, j4 = u4.type;
    if (null != u4.constructor) return null;
    128 & t4.__u && (c4 = !!(32 & t4.__u), o4 = [f4 = u4.__e = t4.__e]), (a4 = l.__b) && a4(u4);
    n: if ("function" == typeof j4) try {
      if (b4 = u4.props, S2 = "prototype" in j4 && j4.prototype.render, C3 = (a4 = j4.contextType) && i5[a4.__c], M3 = a4 ? C3 ? C3.props.value : a4.__ : i5, t4.__c ? m4 = (h5 = u4.__c = t4.__c).__ = h5.__E : (S2 ? u4.__c = h5 = new j4(b4, M3) : (u4.__c = h5 = new x(b4, M3), h5.constructor = j4, h5.render = D), C3 && C3.sub(h5), h5.props = b4, h5.state || (h5.state = {}), h5.context = M3, h5.__n = i5, p5 = h5.__d = true, h5.__h = [], h5._sb = []), S2 && null == h5.__s && (h5.__s = h5.state), S2 && null != j4.getDerivedStateFromProps && (h5.__s == h5.state && (h5.__s = d({}, h5.__s)), d(h5.__s, j4.getDerivedStateFromProps(b4, h5.__s))), v4 = h5.props, y5 = h5.state, h5.__v = u4, p5) S2 && null == j4.getDerivedStateFromProps && null != h5.componentWillMount && h5.componentWillMount(), S2 && null != h5.componentDidMount && h5.__h.push(h5.componentDidMount);
      else {
        if (S2 && null == j4.getDerivedStateFromProps && b4 !== v4 && null != h5.componentWillReceiveProps && h5.componentWillReceiveProps(b4, M3), !h5.__e && null != h5.shouldComponentUpdate && false === h5.shouldComponentUpdate(b4, h5.__s, M3) || u4.__v == t4.__v) {
          for (u4.__v != t4.__v && (h5.props = b4, h5.state = h5.__s, h5.__d = false), u4.__e = t4.__e, u4.__k = t4.__k, u4.__k.some(function(n4) {
            n4 && (n4.__ = u4);
          }), $2 = 0; $2 < h5._sb.length; $2++) h5.__h.push(h5._sb[$2]);
          h5._sb = [], h5.__h.length && e4.push(h5);
          break n;
        }
        null != h5.componentWillUpdate && h5.componentWillUpdate(b4, h5.__s, M3), S2 && null != h5.componentDidUpdate && h5.__h.push(function() {
          h5.componentDidUpdate(v4, y5, _5);
        });
      }
      if (h5.context = M3, h5.props = b4, h5.__P = n3, h5.__e = false, P4 = l.__r, A5 = 0, S2) {
        for (h5.state = h5.__s, h5.__d = false, P4 && P4(u4), a4 = h5.render(h5.props, h5.state, h5.context), H3 = 0; H3 < h5._sb.length; H3++) h5.__h.push(h5._sb[H3]);
        h5._sb = [];
      } else do {
        h5.__d = false, P4 && P4(u4), a4 = h5.render(h5.props, h5.state, h5.context), h5.state = h5.__s;
      } while (h5.__d && ++A5 < 25);
      h5.state = h5.__s, null != h5.getChildContext && (i5 = d(d({}, i5), h5.getChildContext())), S2 && !p5 && null != h5.getSnapshotBeforeUpdate && (_5 = h5.getSnapshotBeforeUpdate(v4, y5)), L2 = a4, null != a4 && a4.type === k && null == a4.key && (L2 = N(a4.props.children)), f4 = I(n3, w(L2) ? L2 : [L2], u4, t4, i5, r4, o4, e4, f4, c4, s4), h5.base = u4.__e, u4.__u &= -161, h5.__h.length && e4.push(h5), m4 && (h5.__E = h5.__ = null);
    } catch (n4) {
      if (u4.__v = null, c4 || null != o4) if (n4.then) {
        for (u4.__u |= c4 ? 160 : 128; f4 && 8 == f4.nodeType && f4.nextSibling; ) f4 = f4.nextSibling;
        o4[o4.indexOf(f4)] = null, u4.__e = f4;
      } else for (T5 = o4.length; T5--; ) g(o4[T5]);
      else u4.__e = t4.__e, u4.__k = t4.__k;
      l.__e(n4, u4, t4);
    }
    else null == o4 && u4.__v == t4.__v ? (u4.__k = t4.__k, u4.__e = t4.__e) : f4 = u4.__e = V(t4.__e, u4, t4, i5, r4, o4, e4, c4, s4);
    return (a4 = l.diffed) && a4(u4), 128 & u4.__u ? void 0 : f4;
  }
  function z(n3, u4, t4) {
    for (var i5 = 0; i5 < t4.length; i5++) q(t4[i5], t4[++i5], t4[++i5]);
    l.__c && l.__c(u4, n3), n3.some(function(u5) {
      try {
        n3 = u5.__h, u5.__h = [], n3.some(function(n4) {
          n4.call(u5);
        });
      } catch (n4) {
        l.__e(n4, u5.__v);
      }
    });
  }
  function N(n3) {
    return "object" != typeof n3 || null == n3 || n3.__b && n3.__b > 0 ? n3 : w(n3) ? n3.map(N) : d({}, n3);
  }
  function V(u4, t4, i5, r4, o4, e4, f4, c4, s4) {
    var a4, h5, v4, y5, d5, _5, m4, b4 = i5.props, k4 = t4.props, x3 = t4.type;
    if ("svg" == x3 ? o4 = "http://www.w3.org/2000/svg" : "math" == x3 ? o4 = "http://www.w3.org/1998/Math/MathML" : o4 || (o4 = "http://www.w3.org/1999/xhtml"), null != e4) {
      for (a4 = 0; a4 < e4.length; a4++) if ((d5 = e4[a4]) && "setAttribute" in d5 == !!x3 && (x3 ? d5.localName == x3 : 3 == d5.nodeType)) {
        u4 = d5, e4[a4] = null;
        break;
      }
    }
    if (null == u4) {
      if (null == x3) return document.createTextNode(k4);
      u4 = document.createElementNS(o4, x3, k4.is && k4), c4 && (l.__m && l.__m(t4, e4), c4 = false), e4 = null;
    }
    if (null == x3) b4 === k4 || c4 && u4.data == k4 || (u4.data = k4);
    else {
      if (e4 = e4 && n.call(u4.childNodes), b4 = i5.props || p, !c4 && null != e4) for (b4 = {}, a4 = 0; a4 < u4.attributes.length; a4++) b4[(d5 = u4.attributes[a4]).name] = d5.value;
      for (a4 in b4) if (d5 = b4[a4], "children" == a4) ;
      else if ("dangerouslySetInnerHTML" == a4) v4 = d5;
      else if (!(a4 in k4)) {
        if ("value" == a4 && "defaultValue" in k4 || "checked" == a4 && "defaultChecked" in k4) continue;
        j(u4, a4, null, d5, o4);
      }
      for (a4 in k4) d5 = k4[a4], "children" == a4 ? y5 = d5 : "dangerouslySetInnerHTML" == a4 ? h5 = d5 : "value" == a4 ? _5 = d5 : "checked" == a4 ? m4 = d5 : c4 && "function" != typeof d5 || b4[a4] === d5 || j(u4, a4, d5, b4[a4], o4);
      if (h5) c4 || v4 && (h5.__html == v4.__html || h5.__html == u4.innerHTML) || (u4.innerHTML = h5.__html), t4.__k = [];
      else if (v4 && (u4.innerHTML = ""), I("template" == t4.type ? u4.content : u4, w(y5) ? y5 : [y5], t4, i5, r4, "foreignObject" == x3 ? "http://www.w3.org/1999/xhtml" : o4, e4, f4, e4 ? e4[0] : i5.__k && S(i5, 0), c4, s4), null != e4) for (a4 = e4.length; a4--; ) g(e4[a4]);
      c4 || (a4 = "value", "progress" == x3 && null == _5 ? u4.removeAttribute("value") : null != _5 && (_5 !== u4[a4] || "progress" == x3 && !_5 || "option" == x3 && _5 != b4[a4]) && j(u4, a4, _5, b4[a4], o4), a4 = "checked", null != m4 && m4 != u4[a4] && j(u4, a4, m4, b4[a4], o4));
    }
    return u4;
  }
  function q(n3, u4, t4) {
    try {
      if ("function" == typeof n3) {
        var i5 = "function" == typeof n3.__u;
        i5 && n3.__u(), i5 && null == u4 || (n3.__u = n3(u4));
      } else n3.current = u4;
    } catch (n4) {
      l.__e(n4, t4);
    }
  }
  function B(n3, u4, t4) {
    var i5, r4;
    if (l.unmount && l.unmount(n3), (i5 = n3.ref) && (i5.current && i5.current != n3.__e || q(i5, null, u4)), null != (i5 = n3.__c)) {
      if (i5.componentWillUnmount) try {
        i5.componentWillUnmount();
      } catch (n4) {
        l.__e(n4, u4);
      }
      i5.base = i5.__P = null;
    }
    if (i5 = n3.__k) for (r4 = 0; r4 < i5.length; r4++) i5[r4] && B(i5[r4], u4, t4 || "function" != typeof n3.type);
    t4 || g(n3.__e), n3.__c = n3.__ = n3.__e = void 0;
  }
  function D(n3, l5, u4) {
    return this.constructor(n3, u4);
  }
  function E(u4, t4, i5) {
    var r4, o4, e4, f4;
    t4 == document && (t4 = document.documentElement), l.__ && l.__(u4, t4), o4 = (r4 = "function" == typeof i5) ? null : i5 && i5.__k || t4.__k, e4 = [], f4 = [], O(t4, u4 = (!r4 && i5 || t4).__k = _(k, null, [u4]), o4 || p, p, t4.namespaceURI, !r4 && i5 ? [i5] : o4 ? null : t4.firstChild ? n.call(t4.childNodes) : null, e4, !r4 && i5 ? i5 : o4 ? o4.__e : t4.firstChild, r4, f4), z(e4, u4, f4);
  }
  function K(n3) {
    function l5(n4) {
      var u4, t4;
      return this.getChildContext || (u4 = /* @__PURE__ */ new Set(), (t4 = {})[l5.__c] = this, this.getChildContext = function() {
        return t4;
      }, this.componentWillUnmount = function() {
        u4 = null;
      }, this.shouldComponentUpdate = function(n5) {
        this.props.value != n5.value && u4.forEach(function(n6) {
          n6.__e = true, M(n6);
        });
      }, this.sub = function(n5) {
        u4.add(n5);
        var l6 = n5.componentWillUnmount;
        n5.componentWillUnmount = function() {
          u4 && u4.delete(n5), l6 && l6.call(n5);
        };
      }), n4.children;
    }
    return l5.__c = "__cC" + h++, l5.__ = n3, l5.Provider = l5.__l = (l5.Consumer = function(n4, l6) {
      return n4.children(l6);
    }).contextType = l5, l5;
  }
  n = v.slice, l = { __e: function(n3, l5, u4, t4) {
    for (var i5, r4, o4; l5 = l5.__; ) if ((i5 = l5.__c) && !i5.__) try {
      if ((r4 = i5.constructor) && null != r4.getDerivedStateFromError && (i5.setState(r4.getDerivedStateFromError(n3)), o4 = i5.__d), null != i5.componentDidCatch && (i5.componentDidCatch(n3, t4 || {}), o4 = i5.__d), o4) return i5.__E = i5;
    } catch (l6) {
      n3 = l6;
    }
    throw n3;
  } }, u = 0, t = function(n3) {
    return null != n3 && null == n3.constructor;
  }, x.prototype.setState = function(n3, l5) {
    var u4;
    u4 = null != this.__s && this.__s != this.state ? this.__s : this.__s = d({}, this.state), "function" == typeof n3 && (n3 = n3(d({}, u4), this.props)), n3 && d(u4, n3), null != n3 && this.__v && (l5 && this._sb.push(l5), M(this));
  }, x.prototype.forceUpdate = function(n3) {
    this.__v && (this.__e = true, n3 && this.__h.push(n3), M(this));
  }, x.prototype.render = k, i = [], o = "function" == typeof Promise ? Promise.prototype.then.bind(Promise.resolve()) : setTimeout, e = function(n3, l5) {
    return n3.__v.__b - l5.__v.__b;
  }, $.__r = 0, f = /(PointerCapture)$|Capture$/i, c = 0, s = F(false), a = F(true), h = 0;

  // ../node_modules/preact/devtools/dist/devtools.module.js
  var i2;
  null != (i2 = "undefined" != typeof globalThis ? globalThis : "undefined" != typeof window ? window : void 0) && i2.__PREACT_DEVTOOLS__ && i2.__PREACT_DEVTOOLS__.attachPreact("10.26.9", l, { Fragment: k, Component: x });

  // ../messaging/lib/windows.js
  var WindowsMessagingTransport = class {
    /**
     * @param {WindowsMessagingConfig} config
     * @param {import('../index.js').MessagingContext} messagingContext
     * @internal
     */
    constructor(config, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config;
      this.globals = {
        window,
        JSONparse: window.JSON.parse,
        JSONstringify: window.JSON.stringify,
        Promise: window.Promise,
        Error: window.Error,
        String: window.String
      };
      for (const [methodName, fn2] of Object.entries(this.config.methods)) {
        if (typeof fn2 !== "function") {
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
        } catch (e4) {
          reject(e4);
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
    constructor(config, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config;
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
      } catch (e4) {
        if (e4 instanceof MissingHandler) {
          throw e4;
        } else {
          console.error("decryption failed", e4);
          console.error(e4);
          return { error: e4 };
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
     * @type {{name: string, length: number}}
     * @internal
     */
    algoObj = {
      name: "AES-GCM",
      length: 256
    };
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
    constructor(config, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config;
    }
    /**
     * @param {NotificationMessage} msg
     */
    notify(msg) {
      try {
        this.config.sendMessageThrows?.(JSON.stringify(msg));
      } catch (e4) {
        console.error(".notify failed", e4);
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
        } catch (e4) {
          unsub();
          reject(new Error("request failed to send: " + e4.message || "unknown error"));
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
    /** @type {(json: string, secret: string) => void} */
    _capturedHandler;
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
    _tryCatch(fn2, context = "none") {
      try {
        return fn2();
      } catch (e4) {
        if (this.debug) {
          console.error("AndroidMessagingConfig error:", context);
          console.error(e4);
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

  // ../injected/src/captured-globals.js
  var Set2 = globalThis.Set;
  var Reflect2 = globalThis.Reflect;
  var customElementsGet = globalThis.customElements?.get.bind(globalThis.customElements);
  var customElementsDefine = globalThis.customElements?.define.bind(globalThis.customElements);
  var URL2 = globalThis.URL;
  var Proxy2 = globalThis.Proxy;
  var functionToString = Function.prototype.toString;
  var TypeError2 = globalThis.TypeError;
  var Symbol2 = globalThis.Symbol;
  var dispatchEvent = globalThis.dispatchEvent?.bind(globalThis);
  var addEventListener = globalThis.addEventListener?.bind(globalThis);
  var removeEventListener = globalThis.removeEventListener?.bind(globalThis);
  var CustomEvent2 = globalThis.CustomEvent;
  var Promise2 = globalThis.Promise;
  var String2 = globalThis.String;
  var Map2 = globalThis.Map;
  var Error2 = globalThis.Error;
  var randomUUID = globalThis.crypto?.randomUUID?.bind(globalThis.crypto);

  // ../injected/src/utils.js
  var globalObj = typeof window === "undefined" ? globalThis : window;
  var Error3 = globalObj.Error;
  var originalWindowDispatchEvent = typeof window === "undefined" ? null : window.dispatchEvent.bind(window);
  function isBeingFramed() {
    if (globalThis.location && "ancestorOrigins" in globalThis.location) {
      return globalThis.location.ancestorOrigins.length > 0;
    }
    return globalThis.top !== globalThis.window;
  }
  var DDGPromise = globalObj.Promise;
  var DDGReflect = globalObj.Reflect;

  // ../messaging/lib/android-adsjs.js
  var AndroidAdsjsMessagingTransport = class {
    /**
     * @param {AndroidAdsjsMessagingConfig} config
     * @param {MessagingContext} messagingContext
     * @internal
     */
    constructor(config, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config;
      this.config.sendInitialPing(messagingContext);
    }
    /**
     * @param {NotificationMessage} msg
     */
    notify(msg) {
      try {
        this.config.sendMessageThrows?.(msg);
      } catch (e4) {
        console.error(".notify failed", e4);
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
          this.config.sendMessageThrows?.(msg);
        } catch (e4) {
          unsub();
          reject(new Error("request failed to send: " + e4.message || "unknown error"));
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
  var AndroidAdsjsMessagingConfig = class {
    /** @type {{
     * postMessage: (message: string) => void,
     * addEventListener: (type: string, listener: (event: MessageEvent) => void) => void,
     * } | null} */
    _capturedHandler;
    /**
     * @param {object} params
     * @param {Record<string, any>} params.target
     * @param {boolean} params.debug
     * @param {string} params.objectName - the object name for addWebMessageListener
     */
    constructor(params) {
      this.target = params.target;
      this.debug = params.debug;
      this.objectName = params.objectName;
      this.listeners = new globalThis.Map();
      this._captureGlobalHandler();
      this._setupEventListener();
    }
    /**
     * The transport can call this to transmit a JSON payload along with a secret
     * to the native Android handler via postMessage.
     *
     * Note: This can throw - it's up to the transport to handle the error.
     *
     * @type {(json: object) => void}
     * @throws
     * @internal
     */
    sendMessageThrows(message) {
      if (!this.objectName) {
        throw new Error("Object name not set for WebMessageListener");
      }
      if (this._capturedHandler && this._capturedHandler.postMessage) {
        this._capturedHandler.postMessage(JSON.stringify(message));
      } else {
        throw new Error("postMessage not available");
      }
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
    _tryCatch(fn2, context = "none") {
      try {
        return fn2();
      } catch (e4) {
        if (this.debug) {
          console.error("AndroidAdsjsMessagingConfig error:", context);
          console.error(e4);
        }
      }
    }
    /**
     * @param {...any} args
     */
    _log(...args) {
      if (this.debug) {
        console.log("AndroidAdsjsMessagingConfig", ...args);
      }
    }
    /**
     * Capture the global handler and remove it from the global object.
     */
    _captureGlobalHandler() {
      const { target, objectName } = this;
      if (Object.prototype.hasOwnProperty.call(target, objectName)) {
        this._capturedHandler = target[objectName];
        delete target[objectName];
      } else {
        this._capturedHandler = null;
        this._log("Android adsjs messaging interface not available", objectName);
      }
    }
    /**
     * Set up event listener for incoming messages from the captured handler.
     */
    _setupEventListener() {
      if (!this._capturedHandler || !this._capturedHandler.addEventListener) {
        this._log("No event listener support available");
        return;
      }
      this._capturedHandler.addEventListener("message", (event) => {
        try {
          const data = (
            /** @type {MessageEvent} */
            event.data
          );
          if (typeof data === "string") {
            const parsedData = JSON.parse(data);
            this._dispatch(parsedData);
          }
        } catch (e4) {
          this._log("Error processing incoming message:", e4);
        }
      });
    }
    /**
     * Send an initial ping message to the platform to establish communication.
     * This is a fire-and-forget notification that signals the JavaScript side is ready.
     * Only sends in top context (not in frames) and if the messaging interface is available.
     *
     * @param {MessagingContext} messagingContext
     * @returns {boolean} true if ping was sent, false if in frame or interface not ready
     */
    sendInitialPing(messagingContext) {
      if (isBeingFramed()) {
        this._log("Skipping initial ping - running in frame context");
        return false;
      }
      try {
        const message = new RequestMessage({
          id: "initialPing",
          context: messagingContext.context,
          featureName: "messaging",
          method: "initialPing"
        });
        this.sendMessageThrows(message);
        this._log("Initial ping sent successfully");
        return true;
      } catch (e4) {
        this._log("Failed to send initial ping:", e4);
        return false;
      }
    }
  };

  // ../messaging/lib/typed-messages.js
  function createTypedMessages(_base, _messaging) {
    const asAny = (
      /** @type {any} */
      _messaging
    );
    return (
      /** @type {BaseClass} */
      asAny
    );
  }

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
    constructor(messagingContext, config) {
      this.messagingContext = messagingContext;
      this.transport = getTransport(config, this.messagingContext);
    }
    /**
     * Send a 'fire-and-forget' message.
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
      try {
        this.transport.notify(message);
      } catch (e4) {
        if (this.messagingContext.env === "development") {
          console.error("[Messaging] Failed to send notification:", e4);
          console.error("[Messaging] Message details:", { name, data });
        }
      }
    }
    /**
     * Send a request and wait for a response
     * @throws {Error}
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
    constructor(config, messagingContext) {
      this.config = config;
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
  function getTransport(config, messagingContext) {
    if (config instanceof WebkitMessagingConfig) {
      return new WebkitMessagingTransport(config, messagingContext);
    }
    if (config instanceof WindowsMessagingConfig) {
      return new WindowsMessagingTransport(config, messagingContext);
    }
    if (config instanceof AndroidMessagingConfig) {
      return new AndroidMessagingTransport(config, messagingContext);
    }
    if (config instanceof AndroidAdsjsMessagingConfig) {
      return new AndroidAdsjsMessagingTransport(config, messagingContext);
    }
    if (config instanceof TestTransportConfig) {
      return new TestTransport(config, messagingContext);
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

  // shared/environment.js
  var Environment = class _Environment {
    /**
     * @param {object} params
     * @param {'app' | 'components'} [params.display] - whether to show the application or component list
     * @param {'production' | 'development'} [params.env] - application environment
     * @param {URLSearchParams} [params.urlParams] - URL params passed into the page
     * @param {ImportMeta['injectName']} [params.injectName] - application platform
     * @param {boolean} [params.willThrow] - whether the application will simulate an error
     * @param {boolean} [params.debugState] - whether to show debugging UI
     * @param {keyof typeof import('./utils').translationsLocales} [params.locale] - for applications strings and numbers formatting
     * @param {number} [params.textLength] - what ratio of text should be used. Set a number higher than 1 to have longer strings for testing
     */
    constructor({
      env = "production",
      urlParams = new URLSearchParams(location.search),
      injectName = "windows",
      willThrow = urlParams.get("willThrow") === "true",
      debugState = urlParams.has("debugState"),
      display = "app",
      locale = "en",
      textLength = 1
    } = {}) {
      this.display = display;
      this.urlParams = urlParams;
      this.injectName = injectName;
      this.willThrow = willThrow;
      this.debugState = debugState;
      this.env = env;
      this.locale = locale;
      this.textLength = textLength;
    }
    /**
     * @param {string|null|undefined} injectName
     * @returns {Environment}
     */
    withInjectName(injectName) {
      if (!injectName) return this;
      if (!isInjectName(injectName)) return this;
      return new _Environment({
        ...this,
        injectName
      });
    }
    /**
     * @param {string|null|undefined} env
     * @returns {Environment}
     */
    withEnv(env) {
      if (!env) return this;
      if (env !== "production" && env !== "development") return this;
      return new _Environment({
        ...this,
        env
      });
    }
    /**
     * @param {string|null|undefined} display
     * @returns {Environment}
     */
    withDisplay(display) {
      if (!display) return this;
      if (display !== "app" && display !== "components") return this;
      return new _Environment({
        ...this,
        display
      });
    }
    /**
     * @param {string|null|undefined} locale
     * @returns {Environment}
     */
    withLocale(locale) {
      if (!locale) return this;
      if (typeof locale !== "string") return this;
      if (locale.length !== 2) return this;
      return new _Environment({
        ...this,
        locale
      });
    }
    /**
     * @param {string|number|null|undefined} length
     * @returns {Environment}
     */
    withTextLength(length) {
      if (!length) return this;
      const num = Number(length);
      if (num >= 1 && num <= 2) {
        return new _Environment({
          ...this,
          textLength: num
        });
      }
      return this;
    }
  };
  function isInjectName(input) {
    const allowed = ["windows", "apple", "integration", "android"];
    return allowed.includes(input);
  }

  // shared/create-special-page-messaging.js
  function createSpecialPageMessaging(opts) {
    const messageContext = new MessagingContext({
      context: "specialPages",
      featureName: opts.pageName,
      env: opts.env
    });
    try {
      if (opts.injectName === "windows") {
        const opts2 = new WindowsMessagingConfig({
          methods: {
            // @ts-expect-error - not in @types/chrome
            postMessage: globalThis.windowsInteropPostMessage,
            // @ts-expect-error - not in @types/chrome
            addEventListener: globalThis.windowsInteropAddEventListener,
            // @ts-expect-error - not in @types/chrome
            removeEventListener: globalThis.windowsInteropRemoveEventListener
          }
        });
        return new Messaging(messageContext, opts2);
      } else if (opts.injectName === "apple") {
        const opts2 = new WebkitMessagingConfig({
          hasModernWebkitAPI: true,
          secret: "",
          webkitMessageHandlerNames: ["specialPages"]
        });
        return new Messaging(messageContext, opts2);
      } else if (opts.injectName === "android") {
        const opts2 = new AndroidMessagingConfig({
          messageSecret: "duckduckgo-android-messaging-secret",
          messageCallback: "messageCallback",
          javascriptInterface: messageContext.context,
          target: globalThis,
          debug: true
        });
        return new Messaging(messageContext, opts2);
      }
    } catch (e4) {
      console.error("could not access handlers for %s, falling back to mock interface", opts.injectName);
    }
    const fallback = opts.mockTransport?.() || new TestTransportConfig({
      /**
       * @param {import('@duckduckgo/messaging').NotificationMessage} msg
       */
      notify(msg) {
        console.log(msg);
      },
      /**
       * @param {import('@duckduckgo/messaging').RequestMessage} msg
       */
      request: (msg) => {
        console.log(msg);
        if (msg.method === "initialSetup") {
          return Promise.resolve({
            locale: "en",
            env: opts.env
          });
        }
        return Promise.resolve(null);
      },
      /**
       * @param {import('@duckduckgo/messaging').SubscriptionEvent} msg
       */
      subscribe(msg) {
        console.log(msg);
        return () => {
          console.log("teardown");
        };
      }
    });
    return new Messaging(messageContext, fallback);
  }

  // ../node_modules/preact/hooks/dist/hooks.module.js
  var t2;
  var r2;
  var u2;
  var i3;
  var o2 = 0;
  var f2 = [];
  var c2 = l;
  var e2 = c2.__b;
  var a2 = c2.__r;
  var v2 = c2.diffed;
  var l2 = c2.__c;
  var m2 = c2.unmount;
  var s2 = c2.__;
  function p2(n3, t4) {
    c2.__h && c2.__h(r2, n3, o2 || t4), o2 = 0;
    var u4 = r2.__H || (r2.__H = { __: [], __h: [] });
    return n3 >= u4.__.length && u4.__.push({}), u4.__[n3];
  }
  function d2(n3) {
    return o2 = 1, h2(D2, n3);
  }
  function h2(n3, u4, i5) {
    var o4 = p2(t2++, 2);
    if (o4.t = n3, !o4.__c && (o4.__ = [i5 ? i5(u4) : D2(void 0, u4), function(n4) {
      var t4 = o4.__N ? o4.__N[0] : o4.__[0], r4 = o4.t(t4, n4);
      t4 !== r4 && (o4.__N = [r4, o4.__[1]], o4.__c.setState({}));
    }], o4.__c = r2, !r2.__f)) {
      var f4 = function(n4, t4, r4) {
        if (!o4.__c.__H) return true;
        var u5 = o4.__c.__H.__.filter(function(n5) {
          return !!n5.__c;
        });
        if (u5.every(function(n5) {
          return !n5.__N;
        })) return !c4 || c4.call(this, n4, t4, r4);
        var i6 = o4.__c.props !== n4;
        return u5.forEach(function(n5) {
          if (n5.__N) {
            var t5 = n5.__[0];
            n5.__ = n5.__N, n5.__N = void 0, t5 !== n5.__[0] && (i6 = true);
          }
        }), c4 && c4.call(this, n4, t4, r4) || i6;
      };
      r2.__f = true;
      var c4 = r2.shouldComponentUpdate, e4 = r2.componentWillUpdate;
      r2.componentWillUpdate = function(n4, t4, r4) {
        if (this.__e) {
          var u5 = c4;
          c4 = void 0, f4(n4, t4, r4), c4 = u5;
        }
        e4 && e4.call(this, n4, t4, r4);
      }, r2.shouldComponentUpdate = f4;
    }
    return o4.__N || o4.__;
  }
  function y2(n3, u4) {
    var i5 = p2(t2++, 3);
    !c2.__s && C2(i5.__H, u4) && (i5.__ = n3, i5.u = u4, r2.__H.__h.push(i5));
  }
  function _2(n3, u4) {
    var i5 = p2(t2++, 4);
    !c2.__s && C2(i5.__H, u4) && (i5.__ = n3, i5.u = u4, r2.__h.push(i5));
  }
  function A2(n3) {
    return o2 = 5, T2(function() {
      return { current: n3 };
    }, []);
  }
  function T2(n3, r4) {
    var u4 = p2(t2++, 7);
    return C2(u4.__H, r4) && (u4.__ = n3(), u4.__H = r4, u4.__h = n3), u4.__;
  }
  function q2(n3, t4) {
    return o2 = 8, T2(function() {
      return n3;
    }, t4);
  }
  function x2(n3) {
    var u4 = r2.context[n3.__c], i5 = p2(t2++, 9);
    return i5.c = n3, u4 ? (null == i5.__ && (i5.__ = true, u4.sub(r2)), u4.props.value) : n3.__;
  }
  function j2() {
    for (var n3; n3 = f2.shift(); ) if (n3.__P && n3.__H) try {
      n3.__H.__h.forEach(z2), n3.__H.__h.forEach(B2), n3.__H.__h = [];
    } catch (t4) {
      n3.__H.__h = [], c2.__e(t4, n3.__v);
    }
  }
  c2.__b = function(n3) {
    r2 = null, e2 && e2(n3);
  }, c2.__ = function(n3, t4) {
    n3 && t4.__k && t4.__k.__m && (n3.__m = t4.__k.__m), s2 && s2(n3, t4);
  }, c2.__r = function(n3) {
    a2 && a2(n3), t2 = 0;
    var i5 = (r2 = n3.__c).__H;
    i5 && (u2 === r2 ? (i5.__h = [], r2.__h = [], i5.__.forEach(function(n4) {
      n4.__N && (n4.__ = n4.__N), n4.u = n4.__N = void 0;
    })) : (i5.__h.forEach(z2), i5.__h.forEach(B2), i5.__h = [], t2 = 0)), u2 = r2;
  }, c2.diffed = function(n3) {
    v2 && v2(n3);
    var t4 = n3.__c;
    t4 && t4.__H && (t4.__H.__h.length && (1 !== f2.push(t4) && i3 === c2.requestAnimationFrame || ((i3 = c2.requestAnimationFrame) || w2)(j2)), t4.__H.__.forEach(function(n4) {
      n4.u && (n4.__H = n4.u), n4.u = void 0;
    })), u2 = r2 = null;
  }, c2.__c = function(n3, t4) {
    t4.some(function(n4) {
      try {
        n4.__h.forEach(z2), n4.__h = n4.__h.filter(function(n5) {
          return !n5.__ || B2(n5);
        });
      } catch (r4) {
        t4.some(function(n5) {
          n5.__h && (n5.__h = []);
        }), t4 = [], c2.__e(r4, n4.__v);
      }
    }), l2 && l2(n3, t4);
  }, c2.unmount = function(n3) {
    m2 && m2(n3);
    var t4, r4 = n3.__c;
    r4 && r4.__H && (r4.__H.__.forEach(function(n4) {
      try {
        z2(n4);
      } catch (n5) {
        t4 = n5;
      }
    }), r4.__H = void 0, t4 && c2.__e(t4, r4.__v));
  };
  var k2 = "function" == typeof requestAnimationFrame;
  function w2(n3) {
    var t4, r4 = function() {
      clearTimeout(u4), k2 && cancelAnimationFrame(t4), setTimeout(n3);
    }, u4 = setTimeout(r4, 35);
    k2 && (t4 = requestAnimationFrame(r4));
  }
  function z2(n3) {
    var t4 = r2, u4 = n3.__c;
    "function" == typeof u4 && (n3.__c = void 0, u4()), r2 = t4;
  }
  function B2(n3) {
    var t4 = r2;
    n3.__c = n3.__(), r2 = t4;
  }
  function C2(n3, t4) {
    return !n3 || n3.length !== t4.length || t4.some(function(t5, r4) {
      return t5 !== n3[r4];
    });
  }
  function D2(n3, t4) {
    return "function" == typeof t4 ? t4(n3) : t4;
  }

  // shared/components/EnvironmentProvider.js
  var EnvironmentContext = K({
    isReducedMotion: false,
    isDarkMode: false,
    debugState: false,
    injectName: (
      /** @type {import('../environment').Environment['injectName']} */
      "windows"
    ),
    willThrow: false,
    /** @type {keyof typeof import('../utils').translationsLocales} */
    locale: "en",
    /** @type {import('../environment').Environment['env']} */
    env: "production"
  });
  var THEME_QUERY = "(prefers-color-scheme: dark)";
  var REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";
  function EnvironmentProvider({
    children,
    debugState,
    env = "production",
    willThrow = false,
    injectName = "windows",
    locale = "en"
  }) {
    const [theme, setTheme] = d2(window.matchMedia(THEME_QUERY).matches ? "dark" : "light");
    const [isReducedMotion, setReducedMotion] = d2(window.matchMedia(REDUCED_MOTION_QUERY).matches);
    y2(() => {
      const mediaQueryList = window.matchMedia(THEME_QUERY);
      const listener = (e4) => setTheme(e4.matches ? "dark" : "light");
      mediaQueryList.addEventListener("change", listener);
      return () => mediaQueryList.removeEventListener("change", listener);
    }, []);
    y2(() => {
      const mediaQueryList = window.matchMedia(REDUCED_MOTION_QUERY);
      const listener = (e4) => setter(e4.matches);
      mediaQueryList.addEventListener("change", listener);
      setter(mediaQueryList.matches);
      function setter(value) {
        document.documentElement.dataset.reducedMotion = String(value);
        setReducedMotion(value);
      }
      window.addEventListener("toggle-reduced-motion", () => {
        setter(true);
      });
      return () => mediaQueryList.removeEventListener("change", listener);
    }, []);
    return /* @__PURE__ */ _(
      EnvironmentContext.Provider,
      {
        value: {
          isReducedMotion,
          debugState,
          isDarkMode: theme === "dark",
          injectName,
          willThrow,
          env,
          locale
        }
      },
      children
    );
  }
  function UpdateEnvironment({ search }) {
    y2(() => {
      const params = new URLSearchParams(search);
      if (params.has("reduced-motion")) {
        setTimeout(() => {
          window.dispatchEvent(new CustomEvent("toggle-reduced-motion"));
        }, 0);
      }
    }, [search]);
    return null;
  }
  function useEnv() {
    return x2(EnvironmentContext);
  }

  // pages/history/app/components/App.jsx
  var import_classnames5 = __toESM(require_classnames(), 1);

  // pages/history/app/components/App.module.css
  var App_default = {
    layout: "App_layout",
    header: "App_header",
    search: "App_search",
    aside: "App_aside",
    main: "App_main",
    customScroller: "App_customScroller",
    paddedError: "App_paddedError",
    paddedErrorRecovery: "App_paddedErrorRecovery"
  };

  // pages/history/app/components/Header.module.css
  var Header_default = {
    root: "Header_root",
    controls: "Header_controls",
    largeButton: "Header_largeButton",
    search: "Header_search",
    form: "Header_form",
    label: "Header_label",
    searchIcon: "Header_searchIcon",
    searchInput: "Header_searchInput"
  };

  // ../node_modules/@preact/signals-core/dist/signals-core.module.js
  var i4 = Symbol.for("preact-signals");
  function t3() {
    if (!(s3 > 1)) {
      var i5, t4 = false;
      while (void 0 !== h3) {
        var r4 = h3;
        h3 = void 0;
        f3++;
        while (void 0 !== r4) {
          var o4 = r4.o;
          r4.o = void 0;
          r4.f &= -3;
          if (!(8 & r4.f) && c3(r4)) try {
            r4.c();
          } catch (r5) {
            if (!t4) {
              i5 = r5;
              t4 = true;
            }
          }
          r4 = o4;
        }
      }
      f3 = 0;
      s3--;
      if (t4) throw i5;
    } else s3--;
  }
  function r3(i5) {
    if (s3 > 0) return i5();
    s3++;
    try {
      return i5();
    } finally {
      t3();
    }
  }
  var o3 = void 0;
  function n2(i5) {
    var t4 = o3;
    o3 = void 0;
    try {
      return i5();
    } finally {
      o3 = t4;
    }
  }
  var h3 = void 0;
  var s3 = 0;
  var f3 = 0;
  var v3 = 0;
  function e3(i5) {
    if (void 0 !== o3) {
      var t4 = i5.n;
      if (void 0 === t4 || t4.t !== o3) {
        t4 = { i: 0, S: i5, p: o3.s, n: void 0, t: o3, e: void 0, x: void 0, r: t4 };
        if (void 0 !== o3.s) o3.s.n = t4;
        o3.s = t4;
        i5.n = t4;
        if (32 & o3.f) i5.S(t4);
        return t4;
      } else if (-1 === t4.i) {
        t4.i = 0;
        if (void 0 !== t4.n) {
          t4.n.p = t4.p;
          if (void 0 !== t4.p) t4.p.n = t4.n;
          t4.p = o3.s;
          t4.n = void 0;
          o3.s.n = t4;
          o3.s = t4;
        }
        return t4;
      }
    }
  }
  function u3(i5, t4) {
    this.v = i5;
    this.i = 0;
    this.n = void 0;
    this.t = void 0;
    this.W = null == t4 ? void 0 : t4.watched;
    this.Z = null == t4 ? void 0 : t4.unwatched;
  }
  u3.prototype.brand = i4;
  u3.prototype.h = function() {
    return true;
  };
  u3.prototype.S = function(i5) {
    var t4 = this, r4 = this.t;
    if (r4 !== i5 && void 0 === i5.e) {
      i5.x = r4;
      this.t = i5;
      if (void 0 !== r4) r4.e = i5;
      else n2(function() {
        var i6;
        null == (i6 = t4.W) || i6.call(t4);
      });
    }
  };
  u3.prototype.U = function(i5) {
    var t4 = this;
    if (void 0 !== this.t) {
      var r4 = i5.e, o4 = i5.x;
      if (void 0 !== r4) {
        r4.x = o4;
        i5.e = void 0;
      }
      if (void 0 !== o4) {
        o4.e = r4;
        i5.x = void 0;
      }
      if (i5 === this.t) {
        this.t = o4;
        if (void 0 === o4) n2(function() {
          var i6;
          null == (i6 = t4.Z) || i6.call(t4);
        });
      }
    }
  };
  u3.prototype.subscribe = function(i5) {
    var t4 = this;
    return E2(function() {
      var r4 = t4.value, n3 = o3;
      o3 = void 0;
      try {
        i5(r4);
      } finally {
        o3 = n3;
      }
    });
  };
  u3.prototype.valueOf = function() {
    return this.value;
  };
  u3.prototype.toString = function() {
    return this.value + "";
  };
  u3.prototype.toJSON = function() {
    return this.value;
  };
  u3.prototype.peek = function() {
    var i5 = o3;
    o3 = void 0;
    try {
      return this.value;
    } finally {
      o3 = i5;
    }
  };
  Object.defineProperty(u3.prototype, "value", { get: function() {
    var i5 = e3(this);
    if (void 0 !== i5) i5.i = this.i;
    return this.v;
  }, set: function(i5) {
    if (i5 !== this.v) {
      if (f3 > 100) throw new Error("Cycle detected");
      this.v = i5;
      this.i++;
      v3++;
      s3++;
      try {
        for (var r4 = this.t; void 0 !== r4; r4 = r4.x) r4.t.N();
      } finally {
        t3();
      }
    }
  } });
  function d3(i5, t4) {
    return new u3(i5, t4);
  }
  function c3(i5) {
    for (var t4 = i5.s; void 0 !== t4; t4 = t4.n) if (t4.S.i !== t4.i || !t4.S.h() || t4.S.i !== t4.i) return true;
    return false;
  }
  function a3(i5) {
    for (var t4 = i5.s; void 0 !== t4; t4 = t4.n) {
      var r4 = t4.S.n;
      if (void 0 !== r4) t4.r = r4;
      t4.S.n = t4;
      t4.i = -1;
      if (void 0 === t4.n) {
        i5.s = t4;
        break;
      }
    }
  }
  function l3(i5) {
    var t4 = i5.s, r4 = void 0;
    while (void 0 !== t4) {
      var o4 = t4.p;
      if (-1 === t4.i) {
        t4.S.U(t4);
        if (void 0 !== o4) o4.n = t4.n;
        if (void 0 !== t4.n) t4.n.p = o4;
      } else r4 = t4;
      t4.S.n = t4.r;
      if (void 0 !== t4.r) t4.r = void 0;
      t4 = o4;
    }
    i5.s = r4;
  }
  function y3(i5, t4) {
    u3.call(this, void 0);
    this.x = i5;
    this.s = void 0;
    this.g = v3 - 1;
    this.f = 4;
    this.W = null == t4 ? void 0 : t4.watched;
    this.Z = null == t4 ? void 0 : t4.unwatched;
  }
  y3.prototype = new u3();
  y3.prototype.h = function() {
    this.f &= -3;
    if (1 & this.f) return false;
    if (32 == (36 & this.f)) return true;
    this.f &= -5;
    if (this.g === v3) return true;
    this.g = v3;
    this.f |= 1;
    if (this.i > 0 && !c3(this)) {
      this.f &= -2;
      return true;
    }
    var i5 = o3;
    try {
      a3(this);
      o3 = this;
      var t4 = this.x();
      if (16 & this.f || this.v !== t4 || 0 === this.i) {
        this.v = t4;
        this.f &= -17;
        this.i++;
      }
    } catch (i6) {
      this.v = i6;
      this.f |= 16;
      this.i++;
    }
    o3 = i5;
    l3(this);
    this.f &= -2;
    return true;
  };
  y3.prototype.S = function(i5) {
    if (void 0 === this.t) {
      this.f |= 36;
      for (var t4 = this.s; void 0 !== t4; t4 = t4.n) t4.S.S(t4);
    }
    u3.prototype.S.call(this, i5);
  };
  y3.prototype.U = function(i5) {
    if (void 0 !== this.t) {
      u3.prototype.U.call(this, i5);
      if (void 0 === this.t) {
        this.f &= -33;
        for (var t4 = this.s; void 0 !== t4; t4 = t4.n) t4.S.U(t4);
      }
    }
  };
  y3.prototype.N = function() {
    if (!(2 & this.f)) {
      this.f |= 6;
      for (var i5 = this.t; void 0 !== i5; i5 = i5.x) i5.t.N();
    }
  };
  Object.defineProperty(y3.prototype, "value", { get: function() {
    if (1 & this.f) throw new Error("Cycle detected");
    var i5 = e3(this);
    this.h();
    if (void 0 !== i5) i5.i = this.i;
    if (16 & this.f) throw this.v;
    return this.v;
  } });
  function w3(i5, t4) {
    return new y3(i5, t4);
  }
  function _3(i5) {
    var r4 = i5.u;
    i5.u = void 0;
    if ("function" == typeof r4) {
      s3++;
      var n3 = o3;
      o3 = void 0;
      try {
        r4();
      } catch (t4) {
        i5.f &= -2;
        i5.f |= 8;
        b(i5);
        throw t4;
      } finally {
        o3 = n3;
        t3();
      }
    }
  }
  function b(i5) {
    for (var t4 = i5.s; void 0 !== t4; t4 = t4.n) t4.S.U(t4);
    i5.x = void 0;
    i5.s = void 0;
    _3(i5);
  }
  function g2(i5) {
    if (o3 !== this) throw new Error("Out-of-order effect");
    l3(this);
    o3 = i5;
    this.f &= -2;
    if (8 & this.f) b(this);
    t3();
  }
  function p3(i5) {
    this.x = i5;
    this.u = void 0;
    this.s = void 0;
    this.o = void 0;
    this.f = 32;
  }
  p3.prototype.c = function() {
    var i5 = this.S();
    try {
      if (8 & this.f) return;
      if (void 0 === this.x) return;
      var t4 = this.x();
      if ("function" == typeof t4) this.u = t4;
    } finally {
      i5();
    }
  };
  p3.prototype.S = function() {
    if (1 & this.f) throw new Error("Cycle detected");
    this.f |= 1;
    this.f &= -9;
    _3(this);
    a3(this);
    s3++;
    var i5 = o3;
    o3 = this;
    return g2.bind(this, i5);
  };
  p3.prototype.N = function() {
    if (!(2 & this.f)) {
      this.f |= 2;
      this.o = h3;
      h3 = this;
    }
  };
  p3.prototype.d = function() {
    this.f |= 8;
    if (!(1 & this.f)) b(this);
  };
  p3.prototype.dispose = function() {
    this.d();
  };
  function E2(i5) {
    var t4 = new p3(i5);
    try {
      t4.c();
    } catch (i6) {
      t4.d();
      throw i6;
    }
    var r4 = t4.d.bind(t4);
    r4[Symbol.dispose] = r4;
    return r4;
  }

  // ../node_modules/@preact/signals/dist/signals.module.js
  var h4;
  var l4;
  var d4;
  var p4 = [];
  var m3 = [];
  E2(function() {
    h4 = this.N;
  })();
  function _4(i5, r4) {
    l[i5] = r4.bind(null, l[i5] || function() {
    });
  }
  function g3(i5) {
    if (d4) d4();
    d4 = i5 && i5.S();
  }
  function b2(i5) {
    var n3 = this, t4 = i5.data, o4 = useSignal(t4);
    o4.value = t4;
    var e4 = T2(function() {
      var i6 = n3, t5 = n3.__v;
      while (t5 = t5.__) if (t5.__c) {
        t5.__c.__$f |= 4;
        break;
      }
      var f4 = w3(function() {
        var i7 = o4.value.value;
        return 0 === i7 ? 0 : true === i7 ? "" : i7 || "";
      }), e5 = w3(function() {
        return !Array.isArray(f4.value) && !t(f4.value);
      }), a5 = E2(function() {
        this.N = T3;
        if (e5.value) {
          var n4 = f4.value;
          if (i6.__v && i6.__v.__e && 3 === i6.__v.__e.nodeType) i6.__v.__e.data = n4;
        }
      }), v5 = n3.__$u.d;
      n3.__$u.d = function() {
        a5();
        v5.call(this);
      };
      return [e5, f4];
    }, []), a4 = e4[0], v4 = e4[1];
    return a4.value ? v4.peek() : v4.value;
  }
  b2.displayName = "_st";
  Object.defineProperties(u3.prototype, { constructor: { configurable: true, value: void 0 }, type: { configurable: true, value: b2 }, props: { configurable: true, get: function() {
    return { data: this };
  } }, __b: { configurable: true, value: 1 } });
  _4("__b", function(i5, n3) {
    if ("string" == typeof n3.type) {
      var r4, t4 = n3.props;
      for (var f4 in t4) if ("children" !== f4) {
        var o4 = t4[f4];
        if (o4 instanceof u3) {
          if (!r4) n3.__np = r4 = {};
          r4[f4] = o4;
          t4[f4] = o4.peek();
        }
      }
    }
    i5(n3);
  });
  _4("__r", function(i5, n3) {
    if (n3.type !== k) {
      g3();
      var r4, f4 = n3.__c;
      if (f4) {
        f4.__$f &= -2;
        if (void 0 === (r4 = f4.__$u)) f4.__$u = r4 = (function(i6) {
          var n4;
          E2(function() {
            n4 = this;
          });
          n4.c = function() {
            f4.__$f |= 1;
            f4.setState({});
          };
          return n4;
        })();
      }
      l4 = f4;
      g3(r4);
    }
    i5(n3);
  });
  _4("__e", function(i5, n3, r4, t4) {
    g3();
    l4 = void 0;
    i5(n3, r4, t4);
  });
  _4("diffed", function(i5, n3) {
    g3();
    l4 = void 0;
    var r4;
    if ("string" == typeof n3.type && (r4 = n3.__e)) {
      var t4 = n3.__np, f4 = n3.props;
      if (t4) {
        var o4 = r4.U;
        if (o4) for (var e4 in o4) {
          var u4 = o4[e4];
          if (void 0 !== u4 && !(e4 in t4)) {
            u4.d();
            o4[e4] = void 0;
          }
        }
        else {
          o4 = {};
          r4.U = o4;
        }
        for (var a4 in t4) {
          var c4 = o4[a4], v4 = t4[a4];
          if (void 0 === c4) {
            c4 = y4(r4, a4, v4, f4);
            o4[a4] = c4;
          } else c4.o(v4, f4);
        }
      }
    }
    i5(n3);
  });
  function y4(i5, n3, r4, t4) {
    var f4 = n3 in i5 && void 0 === i5.ownerSVGElement, o4 = d3(r4);
    return { o: function(i6, n4) {
      o4.value = i6;
      t4 = n4;
    }, d: E2(function() {
      this.N = T3;
      var r5 = o4.value.value;
      if (t4[n3] !== r5) {
        t4[n3] = r5;
        if (f4) i5[n3] = r5;
        else if (r5) i5.setAttribute(n3, r5);
        else i5.removeAttribute(n3);
      }
    }) };
  }
  _4("unmount", function(i5, n3) {
    if ("string" == typeof n3.type) {
      var r4 = n3.__e;
      if (r4) {
        var t4 = r4.U;
        if (t4) {
          r4.U = void 0;
          for (var f4 in t4) {
            var o4 = t4[f4];
            if (o4) o4.d();
          }
        }
      }
    } else {
      var e4 = n3.__c;
      if (e4) {
        var u4 = e4.__$u;
        if (u4) {
          e4.__$u = void 0;
          u4.d();
        }
      }
    }
    i5(n3);
  });
  _4("__h", function(i5, n3, r4, t4) {
    if (t4 < 3 || 9 === t4) n3.__$f |= 2;
    i5(n3, r4, t4);
  });
  x.prototype.shouldComponentUpdate = function(i5, n3) {
    var r4 = this.__$u, t4 = r4 && void 0 !== r4.s;
    for (var f4 in n3) return true;
    if (this.__f || "boolean" == typeof this.u && true === this.u) {
      var o4 = 2 & this.__$f;
      if (!(t4 || o4 || 4 & this.__$f)) return true;
      if (1 & this.__$f) return true;
    } else {
      if (!(t4 || 4 & this.__$f)) return true;
      if (3 & this.__$f) return true;
    }
    for (var e4 in i5) if ("__source" !== e4 && i5[e4] !== this.props[e4]) return true;
    for (var u4 in this.props) if (!(u4 in i5)) return true;
    return false;
  };
  function useSignal(i5, n3) {
    return T2(function() {
      return d3(i5, n3);
    }, []);
  }
  function useComputed(i5, n3) {
    var r4 = A2(i5);
    r4.current = i5;
    l4.__$f |= 4;
    return T2(function() {
      return w3(function() {
        return r4.current();
      }, n3);
    }, []);
  }
  var k3 = "undefined" == typeof requestAnimationFrame ? setTimeout : function(i5) {
    var n3 = function() {
      clearTimeout(r4);
      cancelAnimationFrame(t4);
      i5();
    }, r4 = setTimeout(n3, 35), t4 = requestAnimationFrame(n3);
  };
  var q3 = function(i5) {
    queueMicrotask(function() {
      queueMicrotask(i5);
    });
  };
  function A3() {
    r3(function() {
      var i5;
      while (i5 = p4.shift()) h4.call(i5);
    });
  }
  function w4() {
    if (1 === p4.push(this)) (l.requestAnimationFrame || k3)(A3);
  }
  function F2() {
    r3(function() {
      var i5;
      while (i5 = m3.shift()) h4.call(i5);
    });
  }
  function T3() {
    if (1 === m3.push(this)) (l.requestAnimationFrame || q3)(F2);
  }
  function useSignalEffect(i5) {
    var n3 = A2(i5);
    n3.current = i5;
    y2(function() {
      return E2(function() {
        this.N = w4;
        return n3.current();
      });
    }, []);
  }

  // pages/history/app/global/Providers/QueryProvider.js
  var QueryContext = K(
    /** @type {import('@preact/signals').ReadonlySignal<QueryState>} */
    d3({
      term: (
        /** @type {string|null} */
        null
      ),
      range: (
        /** @type {RangeId|null} */
        null
      ),
      domain: (
        /** @type {string|null} */
        null
      ),
      source: (
        /** @type {Source} */
        "initial"
      )
    })
  );
  var QueryDispatch = K(
    /** @type {(a: Action) => void} */
    ((_5) => {
      throw new Error("missing QueryDispatch");
    })
  );
  function QueryProvider({ children, query = { term: "" } }) {
    const initial = {
      term: "term" in query ? query.term : null,
      range: "range" in query ? query.range : null,
      domain: "domain" in query ? query.domain : null,
      source: (
        /** @type {Source} */
        "initial"
      )
    };
    const queryState = useSignal(initial);
    function dispatch(action) {
      queryState.value = (() => {
        switch (action.kind) {
          case "reset": {
            return { term: "", domain: null, range: null, source: (
              /** @type {const} */
              "auto"
            ) };
          }
          case "search-by-domain": {
            return { term: null, domain: action.value, range: null, source: (
              /** @type {const} */
              "user"
            ) };
          }
          case "search-by-range": {
            return {
              term: null,
              domain: null,
              range: (
                /** @type {RangeId} */
                action.value
              ),
              source: (
                /** @type {const} */
                "user"
              )
            };
          }
          case "search-by-term": {
            return { term: action.value, domain: null, range: null, source: (
              /** @type {const} */
              "user"
            ) };
          }
          default:
            return { term: "", domain: null, range: null, source: (
              /** @type {const} */
              "auto"
            ) };
        }
      })();
    }
    const dispatcher = q2(dispatch, [queryState]);
    return /* @__PURE__ */ _(QueryContext.Provider, { value: queryState }, /* @__PURE__ */ _(QueryDispatch.Provider, { value: dispatcher }, children));
  }
  function useQueryContext() {
    return x2(QueryContext);
  }
  function useQueryDispatch() {
    return x2(QueryDispatch);
  }

  // pages/history/app/icons/Search.js
  function SearchIcon() {
    return /* @__PURE__ */ _("svg", { width: "16", height: "16", viewBox: "0 0 16 16", fill: "none", xmlns: "http://www.w3.org/2000/svg" }, /* @__PURE__ */ _(
      "path",
      {
        d: "M14.8 13.7L10.9 9.8C11.6 8.9 12 7.7 12 6.5C12 3.5 9.5 1 6.5 1C3.5 1 1 3.5 1 6.5C1 9.5 3.5 12 6.5 12C7.7 12 8.9 11.6 9.8 10.9L13.7 14.8C13.8 14.9 14 15 14.2 15C14.4 15 14.6 14.9 14.7 14.8C15.1 14.5 15.1 14 14.8 13.7ZM2.5 6.5C2.5 4.3 4.3 2.5 6.5 2.5C8.7 2.5 10.5 4.3 10.5 6.5C10.5 8.7 8.7 10.5 6.5 10.5C4.3 10.5 2.5 8.7 2.5 6.5Z",
        fill: "currentColor",
        "fill-opacity": "0.6"
      }
    ));
  }

  // shared/translations.js
  function apply(subject, replacements, textLength = 1) {
    if (typeof subject !== "string" || subject.length === 0) return "";
    let out = subject;
    if (replacements) {
      for (let [name, value] of Object.entries(replacements)) {
        if (typeof value !== "string") value = "";
        out = out.replaceAll(`{${name}}`, value);
      }
    }
    if (textLength !== 1 && textLength > 0 && textLength <= 2) {
      const targetLen = Math.ceil(out.length * textLength);
      const target = Math.ceil(textLength);
      const combined = out.repeat(target);
      return combined.slice(0, targetLen);
    }
    return out;
  }

  // shared/components/TranslationsProvider.js
  var TranslationContext = K({
    /** @type {LocalTranslationFn} */
    t: () => {
      throw new Error("must implement");
    }
  });
  function TranslationProvider({ children, translationObject, fallback, textLength = 1 }) {
    function t4(inputKey, replacements) {
      const subject = translationObject?.[inputKey]?.title || fallback?.[inputKey]?.title;
      return apply(subject, replacements, textLength);
    }
    return /* @__PURE__ */ _(TranslationContext.Provider, { value: { t: t4 } }, children);
  }

  // pages/history/public/locales/en/history.json
  var history_default = {
    smartling: {
      string_format: "icu",
      translate_paths: [
        {
          path: "*/title",
          key: "{*}/title",
          instruction: "*/note"
        }
      ]
    },
    empty_title: {
      title: "Nothing to see here!",
      note: "Text shown where there are no remaining history entries"
    },
    empty_text: {
      title: "No browsing history yet.",
      note: "Placeholder text when there's no results to show"
    },
    no_results_title: {
      title: "No results found for {term}",
      note: "The placeholder {term} will be dynamically replaced with the search term entered by the user. For example, if the user searches for 'cats', the title will become 'No results found for cats'."
    },
    no_results_text: {
      title: "Try searching for a different URL or keywords.",
      note: "Placeholder text when a search gave no results."
    },
    delete_all: {
      title: "Delete All",
      note: "Text for a button that deletes all items or entries. An additional confirmation dialog will be presented."
    },
    delete_some: {
      title: "Delete",
      note: "Text for a button that deletes currently selected items"
    },
    delete_none: {
      title: "Nothing to delete",
      note: "Title/tooltip text on a button that does nothing when there is no browsing history to delete. It's additional information shown on hover."
    },
    page_title: {
      title: "History",
      note: "The main page title"
    },
    search: {
      title: "Search",
      note: "The placeholder text in a search input field."
    },
    show_history_all: {
      title: "Show all history",
      note: "Button text for an action that removes all filters and searches, and replaces the list with all history."
    },
    show_history_older: {
      title: "Show older history",
      note: "Button that shows older history entries"
    },
    show_history_for: {
      title: "Show history for {range}",
      note: "The placeholder {range} in the title will be dynamically replaced with specific date ranges such as 'Today', 'Yesterday', or days of the week like 'Monday'. For example, if the range is set to 'Today', the title will become 'Show history for Today'."
    },
    delete_history_all: {
      title: "Delete all history",
      note: "Button text for an action that removes all history entries."
    },
    delete_history_older: {
      title: "Delete older history",
      note: "Button that deletes older history entries."
    },
    delete_history_for: {
      title: "Delete history for {range}",
      note: "The placeholder {range} in the title will be dynamically replaced with specific date ranges such as 'Today', 'Yesterday', or days of the week like 'Monday'. For example, if the range is set to 'Today', the title will become 'Delete history for Today'."
    },
    search_your_history: {
      title: "Search your history",
      note: "Label text for screen readers. It's shown next to the search input field"
    },
    range_all: {
      title: "All",
      note: "Label on a button that shows all history entries"
    },
    range_today: {
      title: "Today",
      note: "Label on a button that shows history entries for today only"
    },
    range_yesterday: {
      title: "Yesterday",
      note: "Label on a button that shows history entries for yesterday only"
    },
    range_monday: {
      title: "Monday",
      note: "Label on a button that shows history entries for monday only"
    },
    range_tuesday: {
      title: "Tuesday",
      note: "Label on a button that shows history entries for tuesday only"
    },
    range_wednesday: {
      title: "Wednesday",
      note: "Label on a button that shows history entries for wednesday only"
    },
    range_thursday: {
      title: "Thursday",
      note: "Label on a button that shows history entries for thursday only"
    },
    range_friday: {
      title: "Friday",
      note: "Label on a button that shows history entries for friday only"
    },
    range_saturday: {
      title: "Saturday",
      note: "Label on a button that shows history entries for saturday only"
    },
    range_sunday: {
      title: "Sunday",
      note: "Label on a button that shows history entries for sunday only"
    },
    range_older: {
      title: "Older",
      note: "Label on a button that shows older history entries."
    }
  };

  // pages/history/app/Settings.js
  var Settings = class _Settings {
    /**
     * @param {object} params
     * @param {{name: 'macos' | 'windows'}} [params.platform]
     * @param {number} [params.typingDebounce=100] how long to debounce typing in the search field - default: 100ms
     * @param {number} [params.urlDebounce=500] how long to debounce reflecting to the URL? - default: 500ms
     */
    constructor({ platform = { name: "macos" }, typingDebounce = 100, urlDebounce = 500 }) {
      this.platform = platform;
      this.typingDebounce = typingDebounce;
      this.urlDebounce = urlDebounce;
    }
    withPlatformName(name) {
      const valid = ["windows", "macos"];
      if (valid.includes(
        /** @type {any} */
        name
      )) {
        return new _Settings({
          ...this,
          platform: { name }
        });
      }
      return this;
    }
    /**
     * @param {null|undefined|number|string} value
     */
    withDebounce(value) {
      if (!value) return this;
      const input = String(value).trim();
      if (input.match(/^\d+$/)) {
        return new _Settings({
          ...this,
          typingDebounce: parseInt(input, 10)
        });
      }
      return this;
    }
    /**
     * @param {null|undefined|number|string} value
     */
    withUrlDebounce(value) {
      if (!value) return this;
      const input = String(value).trim();
      if (input.match(/^\d+$/)) {
        return new _Settings({
          ...this,
          urlDebounce: parseInt(input, 10)
        });
      }
      return this;
    }
  };

  // pages/history/app/types.js
  function useTypedTranslation() {
    return {
      t: x2(TranslationContext).t
    };
  }
  var MessagingContext2 = K(
    /** @type {import("../src/index.js").HistoryPage} */
    {}
  );
  var SettingsContext = K(new Settings({ platform: { name: "macos" } }));
  var useSettings = () => x2(SettingsContext);
  function usePlatformName() {
    return x2(SettingsContext).platform.name;
  }

  // pages/history/app/components/SearchForm.js
  var INPUT_FIELD_NAME = "q";
  function SearchForm({ term, domain }) {
    const { t: t4 } = useTypedTranslation();
    const value = useComputed(() => term.value || domain.value || "");
    const dispatch = useQueryDispatch();
    const platformName = usePlatformName();
    useSearchShortcut(platformName);
    function input(inputEvent) {
      invariant(inputEvent.target instanceof HTMLInputElement);
      invariant(inputEvent.target.form instanceof HTMLFormElement);
      const data = new FormData(inputEvent.target.form);
      const term2 = data.get(INPUT_FIELD_NAME)?.toString();
      invariant(term2 !== void 0);
      dispatch({ kind: "search-by-term", value: term2 });
    }
    function submit(submitEvent) {
      submitEvent.preventDefault();
      invariant(submitEvent.currentTarget instanceof HTMLFormElement);
      const data = new FormData(submitEvent.currentTarget);
      const term2 = data.get(INPUT_FIELD_NAME)?.toString();
      dispatch({ kind: "search-by-term", value: term2 ?? "" });
    }
    return /* @__PURE__ */ _("form", { role: "search", class: Header_default.form, onSubmit: submit }, /* @__PURE__ */ _("label", { class: Header_default.label }, /* @__PURE__ */ _("span", { class: "sr-only" }, t4("search_your_history")), /* @__PURE__ */ _("span", { class: Header_default.searchIcon }, /* @__PURE__ */ _(SearchIcon, null)), /* @__PURE__ */ _(
      "input",
      {
        class: Header_default.searchInput,
        name: INPUT_FIELD_NAME,
        autoCapitalize: "off",
        autoComplete: "off",
        type: "search",
        spellcheck: false,
        placeholder: t4("search"),
        value,
        onInput: input
      }
    )));
  }
  function useSearchShortcut(platformName) {
    useSignalEffect(() => {
      const keydown = (e4) => {
        const isMacOS = platformName === "macos";
        const isFindShortcutMacOS = isMacOS && e4.metaKey && e4.key === "f";
        const isFindShortcutWindows = !isMacOS && e4.ctrlKey && e4.key === "f";
        if (isFindShortcutMacOS || isFindShortcutWindows) {
          e4.preventDefault();
          const searchInput = (
            /** @type {HTMLInputElement|null} */
            document.querySelector(`input[type="search"]`)
          );
          if (searchInput) {
            searchInput.focus();
          }
        }
      };
      document.addEventListener("keydown", keydown);
      return () => {
        document.removeEventListener("keydown", keydown);
      };
    });
  }
  function invariant(condition, message) {
    if (condition) return;
    if (message) throw new Error("Invariant failed: " + message);
    throw new Error("Invariant failed");
  }

  // pages/history/app/icons/Trash.js
  function Trash() {
    return /* @__PURE__ */ _("svg", { width: "16", height: "16", viewBox: "0 0 16 16", fill: "none", xmlns: "http://www.w3.org/2000/svg" }, /* @__PURE__ */ _(
      "path",
      {
        d: "M6.25 5.625C6.25 5.27982 5.97018 5 5.625 5C5.27982 5 5 5.27982 5 5.625V12.375C5 12.7202 5.27982 13 5.625 13C5.97018 13 6.25 12.7202 6.25 12.375V5.625Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ), /* @__PURE__ */ _(
      "path",
      {
        d: "M11 5.625C11 5.27982 10.7202 5 10.375 5C10.0298 5 9.75 5.27982 9.75 5.625V12.375C9.75 12.7202 10.0298 13 10.375 13C10.7202 13 11 12.7202 11 12.375V5.625Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ), /* @__PURE__ */ _(
      "path",
      {
        "fill-rule": "evenodd",
        "clip-rule": "evenodd",
        d: "M11 2V1.875C11 0.839466 10.1605 0 9.125 0H6.875C5.83947 0 5 0.839466 5 1.875V2H1.625C1.27982 2 1 2.27982 1 2.625C1 2.97018 1.27982 3.25 1.625 3.25H2V12.875C2 14.6009 3.39911 16 5.125 16H10.875C12.6009 16 14 14.6009 14 12.875V3.25H14.375C14.7202 3.25 15 2.97018 15 2.625C15 2.27982 14.7202 2 14.375 2H11ZM6.25 2H9.75V1.875C9.75 1.52982 9.47018 1.25 9.125 1.25H6.875C6.52982 1.25 6.25 1.52982 6.25 1.875V2ZM12.75 3.25H3.25V12.875C3.25 13.9105 4.08947 14.75 5.125 14.75H10.875C11.9105 14.75 12.75 13.9105 12.75 12.875V3.25Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ));
  }

  // pages/history/app/utils.js
  var ROW_SIZE = 28;
  var TITLE_SIZE = 32;
  var END_SIZE = 24;
  var TITLE_KIND = ROW_SIZE + TITLE_SIZE;
  var END_KIND = ROW_SIZE + END_SIZE;
  var BOTH_KIND = ROW_SIZE + TITLE_SIZE + END_SIZE;
  function generateHeights(rows) {
    const heights = new Array(rows.length);
    for (let i5 = 0; i5 < rows.length; i5++) {
      const curr = rows[i5];
      const prev = rows[i5 - 1];
      const next = rows[i5 + 1];
      const isStart = curr.dateRelativeDay !== prev?.dateRelativeDay;
      const isEnd = curr.dateRelativeDay !== next?.dateRelativeDay;
      if (isStart && isEnd) {
        heights[i5] = TITLE_SIZE + ROW_SIZE + END_SIZE;
      } else if (isStart) {
        heights[i5] = TITLE_SIZE + ROW_SIZE;
      } else if (isEnd) {
        heights[i5] = ROW_SIZE + END_SIZE;
      } else {
        heights[i5] = ROW_SIZE;
      }
    }
    return heights;
  }
  function generateViewIds(rows) {
    return rows.map((row) => {
      return btoa(row.id).replace(/=/g, "");
    });
  }
  function eventToIntention(event, platformName) {
    if (event instanceof MouseEvent) {
      const isControlClick = platformName === "macos" ? event.metaKey : event.ctrlKey;
      if (isControlClick) {
        return "ctrl+click";
      } else if (event.shiftKey) {
        return "shift+click";
      }
      return "click";
    } else if (event instanceof KeyboardEvent) {
      if (event.key === "Escape") {
        return "escape";
      } else if (event.key === "Delete" || event.key === "Backspace") {
        return "delete";
      } else if (event.key === "ArrowUp" && event.shiftKey) {
        return "shift+up";
      } else if (event.key === "ArrowDown" && event.shiftKey) {
        return "shift+down";
      } else if (event.key === "ArrowUp") {
        return "up";
      } else if (event.key === "ArrowDown") {
        return "down";
      }
    }
    return "unknown";
  }
  function invariant2(condition, message) {
    if (condition) return;
    if (message) throw new Error("Invariant failed: " + message);
    throw new Error("Invariant failed");
  }

  // pages/history/app/constants.js
  var DDG_DEFAULT_ICON_SIZE = 32;
  var OVERSCAN_AMOUNT = 5;
  var BTN_ACTION_ENTRIES_MENU = "entries_menu";
  var BTN_ACTION_DELETE_RANGE = "deleteRange";
  var KNOWN_ACTIONS = (
    /** @type {const} */
    [BTN_ACTION_ENTRIES_MENU, BTN_ACTION_DELETE_RANGE]
  );

  // pages/history/app/history.range.service.js
  var _HistoryRangeService = class _HistoryRangeService {
    index = 0;
    internal = new EventTarget();
    dataReadinessSignal = new EventTarget();
    /**
     * @type {RangeData|null}
     */
    ranges = null;
    /**
     * @param {import("../src/index.js").HistoryPage} history
     */
    constructor(history) {
      this.history = history;
      this.internal.addEventListener(_HistoryRangeService.REFRESH_EVENT, () => {
        this.index++;
        const index = this.index;
        this.fetcher().then((next) => {
          const resolvedPromiseIsStale = this.index !== index;
          if (resolvedPromiseIsStale) return console.log("\u274C rejected stale result");
          this.accept(next);
        });
      });
    }
    /**
     * @param {RangeData} d
     */
    accept(d5) {
      this.ranges = d5;
      this.dataReadinessSignal.dispatchEvent(new Event(_HistoryRangeService.DATA_EVENT));
    }
    fetcher() {
      console.log(`\u{1F9BB} [getRanges]`);
      return this.history.messaging.request("getRanges");
    }
    /**
     * @returns {Promise<RangeData>}
     */
    async getInitial() {
      const rangesPromise = await this.fetcher();
      this.accept(rangesPromise);
      return rangesPromise;
    }
    refresh() {
      this.internal.dispatchEvent(new Event(_HistoryRangeService.REFRESH_EVENT));
    }
    /**
     * @param {(data: RangeData) => void} cb
     */
    onResults(cb) {
      const controller = new AbortController();
      this.dataReadinessSignal.addEventListener(
        _HistoryRangeService.DATA_EVENT,
        () => {
          if (this.ranges === null) throw new Error("unreachable");
          cb(this.ranges);
        },
        { signal: controller.signal }
      );
      return () => controller.abort();
    }
    /**
     * @param {RangeId} range
     */
    async deleteRange(range) {
      console.log("\u{1F4E4} [deleteRange]: ", JSON.stringify({ range }));
      return await this.history.messaging.request("deleteRange", { range });
    }
  };
  __publicField(_HistoryRangeService, "REFRESH_EVENT", "refresh");
  __publicField(_HistoryRangeService, "DATA_EVENT", "data");
  var HistoryRangeService = _HistoryRangeService;

  // pages/new-tab/app/utils.js
  function viewTransition(fn2) {
    if ("startViewTransition" in document && typeof document.startViewTransition === "function") {
      return document.startViewTransition(fn2);
    }
    return fn2();
  }

  // pages/history/app/history.service.js
  var _HistoryService = class _HistoryService {
    /**
     * @return {QueryData}
     */
    static defaultData() {
      return {
        lastQueryParams: null,
        info: {
          query: { term: "" },
          finished: true
        },
        results: []
      };
    }
    /**
     * @type {QueryData}
     */
    data = _HistoryService.defaultData();
    internal = new EventTarget();
    dataReadinessSignal = new EventTarget();
    /** @type {HistoryQuery|null} */
    ongoing = null;
    index = 0;
    /**
     * @param {import("../src/index.js").HistoryPage} history
     */
    constructor(history) {
      this.history = history;
      this.range = new HistoryRangeService(this.history);
      this.internal.addEventListener(_HistoryService.QUERY_EVENT, (evt) => {
        const { detail } = evt;
        if (eq(detail, this.ongoing)) return;
        this.index++;
        const index = this.index;
        this.ongoing = JSON.parse(JSON.stringify(detail));
        this.queryFetcher(detail).then((next) => {
          const old = this.data;
          if (old === null) throw new Error("unreachable - typescript this.query must always be there?");
          const resolvedPromiseIsStale = this.index !== index;
          if (resolvedPromiseIsStale) return console.log("\u274C rejected stale result");
          let valueToPublish;
          if (queryEq(old.info.query, next.info.query) && next.lastQueryParams?.offset > 0) {
            const results = old.results.concat(next.results);
            valueToPublish = { info: next.info, results, lastQueryParams: next.lastQueryParams };
          } else {
            valueToPublish = next;
          }
          this.accept(valueToPublish);
        }).catch((e4) => {
          console.error(e4, detail);
        });
      });
      this.internal.addEventListener(_HistoryService.QUERY_MORE_EVENT, (evt) => {
        if (!this.data) return;
        if (this.data.info.finished) return;
        const { end } = evt.detail;
        const memory = this.data.results;
        if (memory.length - end < OVERSCAN_AMOUNT) {
          const lastquery = this.data.info.query;
          const query = {
            query: lastquery,
            limit: _HistoryService.CHUNK_SIZE,
            offset: this.data.results.length,
            source: "user"
          };
          this.internal.dispatchEvent(new CustomEvent(_HistoryService.QUERY_EVENT, { detail: query }));
        }
      });
    }
    /**
     * To 'accept' data is to store a local reference to it and treat it as 'latest'
     * We also want to broadcast the fact that new data can be read.
     * @param {QueryData} data
     */
    accept(data) {
      this.data = data;
      this.ongoing = null;
      this.dataReadinessSignal.dispatchEvent(new Event("data"));
    }
    /**
     * The single place for the query to be made
     * @param {HistoryQuery} query
     */
    queryFetcher(query) {
      console.log(`\u{1F9BB} [query] ${JSON.stringify(query.query)} offset: ${query.offset}, limit: ${query.limit} source: ${query.source}`);
      return this.history.messaging.request("query", query).then((resp) => {
        return { info: resp.info, results: resp.value, lastQueryParams: query };
      });
    }
    /**
     * @param {HistoryQuery} initQuery
     * @returns {Promise<InitialServiceData>}
     */
    async getInitial(initQuery) {
      const queryPromise = this.queryFetcher(initQuery);
      const rangesPromise = this.range.getInitial();
      const [query, ranges] = await Promise.all([queryPromise, rangesPromise]);
      this.accept(query);
      return { query, ranges };
    }
    /**
     * Allow consumers to be notified when data has changed
     * @param {(data: QueryData) => void} cb
     */
    onResults(cb) {
      const controller = new AbortController();
      this.dataReadinessSignal.addEventListener(
        "data",
        () => {
          if (this.data === null) throw new Error("unreachable");
          cb(this.data);
        },
        { signal: controller.signal }
      );
      return () => controller.abort();
    }
    /**
     * @param {(data: RangeData) => void} cb
     */
    onRanges(cb) {
      return this.range.onResults(cb);
    }
    /**
     * @param {HistoryQuery} query
     */
    trigger(query) {
      this.internal.dispatchEvent(new CustomEvent(_HistoryService.QUERY_EVENT, { detail: query }));
    }
    refreshRanges() {
      this.range.refresh();
    }
    /**
     * @param {number} end - the index of the last seen element
     */
    requestMore(end) {
      this.internal.dispatchEvent(new CustomEvent(_HistoryService.QUERY_MORE_EVENT, { detail: { end } }));
    }
    /**
     * @param {string} url
     * @param {import('../types/history.js').OpenTarget} target
     */
    openUrl(url2, target) {
      this.history.messaging.notify("open", { url: url2, target });
    }
    /**
     * @param {number[]} indexes
     * @return {Promise<ServiceResult>}
     */
    async entriesMenu(indexes) {
      const ids = this._collectIds(indexes);
      console.trace("\u{1F4E4} [entries_menu]: ", JSON.stringify({ ids }));
      const response = await this.history.messaging.request("entries_menu", { ids });
      if (response.action === "none") {
        return { kind: response.action };
      }
      if (response.action === "delete") {
        this._postdelete(indexes);
        return { kind: response.action };
      }
      if (response.action === "domain-search" && ids.length === 1 && indexes.length === 1) {
        const target = this.data?.results[indexes[0]];
        const targetValue = target?.etldPlusOne || target?.domain;
        if (targetValue) {
          return { kind: response.action, value: targetValue };
        } else {
          console.warn("missing target domain from current dataset?");
          return { kind: response.action };
        }
      }
      return { kind: response.action };
    }
    /**
     * @param {number[]} indexes
     * @return {Promise<ServiceResult>}
     */
    async entriesDelete(indexes) {
      const ids = this._collectIds(indexes);
      console.log("\u{1F4E4} [entries_delete]: ", JSON.stringify({ ids }));
      const response = await this.history.messaging.request("entries_delete", { ids });
      if (response.action === "delete") {
        viewTransition(() => {
          this._postdelete(indexes);
        });
      }
      return { kind: response.action };
    }
    /**
     * @param {number[]} indexes
     * @return {string[]}
     */
    _collectIds(indexes) {
      const ids = [];
      for (let i5 = 0; i5 < indexes.length; i5++) {
        const current = this.data?.results[indexes[i5]];
        if (!current) throw new Error("unreachable");
        ids.push(current.id);
      }
      return ids;
    }
    /**
     * @param {(d: QueryData) => QueryData} updater
     */
    update(updater) {
      if (this.data === null) throw new Error("unreachable");
      this.accept(updater(this.data));
    }
    /**
     * @param {number[]} indexes
     */
    _postdelete(indexes) {
      this.update((old) => deleteByIndexes(old, indexes));
    }
    reset() {
      this.update(() => {
        const query = {
          lastQueryParams: null,
          info: {
            query: { term: "" },
            finished: true
          },
          results: []
        };
        return query;
      });
    }
    /**
     * @param {RangeId} range
     * @return {Promise<ServiceResult>}
     */
    async deleteRange(range) {
      const resp = await this.range.deleteRange(range);
      if (resp.action === "delete" && range === "all") {
        this.reset();
      }
      return { kind: resp.action };
    }
    /**
     * @param {string} domain
     * @return {Promise<ServiceResult>}
     */
    async deleteDomain(domain) {
      const resp = await this.history.messaging.request("deleteDomain", { domain });
      if (resp.action === "delete") {
        this.reset();
      }
      return { kind: resp.action };
    }
    /**
     * @param {string} term
     * @return {Promise<ServiceResult>}
     */
    async deleteTerm(term) {
      console.log("\u{1F4E4} [deleteTerm]: ", JSON.stringify({ term }));
      const resp = await this.history.messaging.request("deleteTerm", { term });
      if (resp.action === "delete") {
        this.reset();
      }
      return { kind: resp.action };
    }
  };
  __publicField(_HistoryService, "CHUNK_SIZE", 150);
  __publicField(_HistoryService, "QUERY_EVENT", "query");
  __publicField(_HistoryService, "QUERY_MORE_EVENT", "query-more");
  var HistoryService = _HistoryService;
  function deleteByIndexes(old, indexes) {
    const inverted = indexes.sort((a4, b4) => b4 - a4);
    const removed = [];
    const next = old.results.slice();
    for (let i5 = 0; i5 < inverted.length; i5++) {
      removed.push(next.splice(inverted[i5], 1));
    }
    const nextStats = { ...old, results: next };
    return nextStats;
  }
  function paramsToQuery(params, source) {
    let query;
    const range = toRange(params.get("range"));
    const domain = params.get("domain");
    if (range === "all") {
      query = { term: "" };
    } else if (range) {
      query = { range };
    } else if (domain) {
      query = { domain };
    } else {
      query = { term: params.get("q") || "" };
    }
    return {
      query,
      limit: HistoryService.CHUNK_SIZE,
      offset: 0,
      source
    };
  }
  function toRange(input) {
    if (typeof input !== "string") return null;
    const valid = [
      "all",
      "today",
      "yesterday",
      "monday",
      "tuesday",
      "wednesday",
      "thursday",
      "friday",
      "saturday",
      "sunday",
      "recentlyOpened",
      "older"
    ];
    return valid.includes(input) ? (
      /** @type {import('../types/history.js').RangeId} */
      input
    ) : null;
  }
  function eq(a4, b4) {
    if (!b4) return false;
    if (a4.limit !== b4.limit) return false;
    if (a4.offset !== b4.offset) return false;
    if (a4.source !== b4.source) return false;
    return queryEq(a4.query, b4.query);
  }
  function queryEq(a4, b4) {
    if (!b4) return false;
    const k1 = Object.keys(a4)[0];
    const k22 = Object.keys(b4)[0];
    if (k1 === k22 && a4[k1] === b4[k22]) return true;
    return false;
  }

  // pages/history/app/global/Providers/HistoryServiceProvider.js
  function defaultDispatch(action) {
    console.log("would dispatch", action);
  }
  var HistoryServiceDispatchContext = K(defaultDispatch);
  var ResultsContext = K(
    /** @type {ReadonlySignal<Results>} */
    d3({
      items: [],
      heights: [],
      viewIds: [],
      info: { finished: false, query: { term: "" } }
    })
  );
  var RangesContext = K(
    /** @type {ReadonlySignal<Range[]>} */
    d3([])
  );
  function HistoryServiceProvider({ service, children, initial }) {
    const queryDispatch = useQueryDispatch();
    const ranges = useSignal(initial.ranges.ranges);
    const results = useSignal({
      info: initial.query.info,
      items: initial.query.results,
      heights: generateHeights(initial.query.results),
      viewIds: generateViewIds(initial.query.results)
    });
    useSignalEffect(() => {
      const unsub = service.onResults((data) => {
        results.value = {
          items: data.results,
          info: data.info,
          heights: generateHeights(data.results),
          viewIds: generateViewIds(data.results)
        };
      });
      const unsubRanges = service.onRanges((data) => {
        ranges.value = data.ranges;
      });
      return () => {
        unsub();
        unsubRanges();
      };
    });
    function dispatch(action) {
      switch (action.kind) {
        case "search-commit": {
          const asQuery = paramsToQuery(action.params, action.source);
          service.trigger(asQuery);
          break;
        }
        case "delete-range": {
          const range = toRange(action.value);
          if (range) {
            service.deleteRange(range).then((resp) => {
              if (resp.kind === "delete") {
                queryDispatch({ kind: "reset" });
                service.refreshRanges();
              }
            }).catch(console.error);
          }
          break;
        }
        case "delete-domain": {
          service.deleteDomain(action.domain).then((resp) => {
            if (resp.kind === "delete") {
              queryDispatch({ kind: "reset" });
              service.refreshRanges();
            }
          }).catch(console.error);
          break;
        }
        case "delete-entries-by-index": {
          service.entriesDelete(action.value).then((resp) => {
            if (resp.kind === "delete") {
              service.refreshRanges();
            }
          }).catch(console.error);
          break;
        }
        case "delete-all": {
          service.deleteRange("all").then((x3) => {
            if (x3.kind === "delete") {
              service.refreshRanges();
            }
          }).catch(console.error);
          break;
        }
        case "delete-term": {
          service.deleteTerm(action.term).then((resp) => {
            if (resp.kind === "delete") {
              queryDispatch({ kind: "reset" });
              service.refreshRanges();
            }
          }).catch(console.error);
          break;
        }
        case "open-url": {
          service.openUrl(action.url, action.target);
          break;
        }
        case "show-entries-menu": {
          service.entriesMenu(action.indexes).then((resp) => {
            if (resp.kind === "domain-search" && "value" in resp) {
              queryDispatch({ kind: "search-by-domain", value: resp.value });
            } else if (resp.kind === "delete") {
              service.refreshRanges();
            }
          }).catch(console.error);
          break;
        }
        case "request-more": {
          service.requestMore(action.end);
          break;
        }
      }
    }
    const dispatcher = q2(dispatch, [service]);
    return /* @__PURE__ */ _(HistoryServiceDispatchContext.Provider, { value: dispatcher }, /* @__PURE__ */ _(RangesContext.Provider, { value: ranges }, /* @__PURE__ */ _(ResultsContext.Provider, { value: results }, children)));
  }
  function useHistoryServiceDispatch() {
    return x2(HistoryServiceDispatchContext);
  }
  function useResultsData() {
    return x2(ResultsContext);
  }
  function useRangesData() {
    return x2(RangesContext);
  }

  // pages/history/app/global/hooks/useSelectionState.js
  var defaultState = {
    anchorIndex: (
      /** @type {null|number} */
      null
    ),
    /** @type {{start: null|number; end: null|number}} */
    lastShiftRange: {
      start: null,
      end: null
    },
    focusedIndex: (
      /** @type {null|number} */
      null
    ),
    selected: /* @__PURE__ */ new Set(
      /** @type {number[]} */
      []
    ),
    lastAction: (
      /** @type {Action['kind']|null} */
      null
    )
  };
  function useSelectionStateApi() {
    const state = useSignal(defaultState);
    const selected = useComputed(() => state.value.selected);
    function dispatcher(evt) {
      const next = reducer(state.value, evt);
      next.lastAction = evt.kind;
      state.value = next;
    }
    const dispatch = q2(dispatcher, [state, selected]);
    return { selected, dispatch, state };
  }
  function reducer(prev, evt) {
    switch (evt.kind) {
      case "reset": {
        return {
          ...defaultState
        };
      }
      case "move-selection": {
        const { focusedIndex } = prev;
        invariant2(focusedIndex !== null);
        const delta = evt.direction === "up" ? -1 : 1;
        const max = Math.min(evt.total - 1, focusedIndex + delta);
        const newIndex = Math.max(0, max);
        const newSelected = /* @__PURE__ */ new Set([newIndex]);
        return {
          ...prev,
          anchorIndex: newIndex,
          focusedIndex: newIndex,
          lastShiftRange: { start: null, end: null },
          selected: newSelected
        };
      }
      case "select-index": {
        const newSelected = /* @__PURE__ */ new Set([evt.index]);
        return {
          ...prev,
          anchorIndex: evt.index,
          focusedIndex: evt.index,
          lastShiftRange: { start: null, end: null },
          selected: newSelected
        };
      }
      case "toggle-index": {
        const newSelected = new Set(prev.selected);
        if (newSelected.has(evt.index)) {
          newSelected.delete(evt.index);
        } else {
          newSelected.add(evt.index);
        }
        return {
          ...prev,
          anchorIndex: evt.index,
          lastShiftRange: { start: null, end: null },
          focusedIndex: evt.index,
          selected: newSelected
        };
      }
      case "expand-selected-to-index": {
        const { anchorIndex, lastShiftRange } = prev;
        const newSelected = new Set(prev.selected);
        if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
          for (let i5 = lastShiftRange.start; i5 <= lastShiftRange.end; i5++) {
            newSelected.delete(i5);
          }
        }
        const start = Math.min(anchorIndex ?? 0, evt.index);
        const end = Math.max(anchorIndex ?? 0, evt.index);
        for (let i5 = start; i5 <= end; i5++) {
          newSelected.add(i5);
        }
        return {
          ...prev,
          lastShiftRange: { start, end },
          focusedIndex: evt.index,
          selected: newSelected
        };
      }
      case "inc-or-dec-selected": {
        const { anchorIndex, lastShiftRange } = prev;
        const newSelected = new Set(prev.selected);
        if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
          for (let i5 = lastShiftRange.start; i5 <= lastShiftRange.end; i5++) {
            newSelected.delete(i5);
          }
        }
        const start = Math.min(anchorIndex ?? evt.nextIndex, evt.nextIndex);
        const end = Math.max(anchorIndex ?? evt.nextIndex, evt.nextIndex);
        for (let i5 = start; i5 <= end; i5++) {
          newSelected.add(i5);
        }
        return {
          ...prev,
          focusedIndex: evt.nextIndex,
          lastShiftRange: { start, end },
          anchorIndex: anchorIndex === null ? evt.nextIndex : anchorIndex,
          selected: newSelected
        };
      }
      case "increment-selection": {
        const { focusedIndex, anchorIndex, lastShiftRange } = prev;
        invariant2(focusedIndex !== null);
        const delta = evt.direction === "up" ? -1 : 1;
        const newIndex = Math.max(0, Math.min(evt.total - 1, focusedIndex + delta));
        const newSelected = new Set(prev.selected);
        if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
          for (let i5 = lastShiftRange.start; i5 <= lastShiftRange.end; i5++) {
            newSelected.delete(i5);
          }
        }
        const start = Math.min(anchorIndex ?? newIndex, newIndex);
        const end = Math.max(anchorIndex ?? newIndex, newIndex);
        for (let i5 = start; i5 <= end; i5++) {
          newSelected.add(i5);
        }
        return {
          ...prev,
          focusedIndex: newIndex,
          lastShiftRange: { start, end },
          anchorIndex: anchorIndex === null ? newIndex : anchorIndex,
          selected: newSelected
        };
      }
      default:
        return prev;
    }
  }

  // pages/history/app/global/Providers/SelectionProvider.js
  var SelectionDispatchContext = K(
    /** @type {(a: Action) => void} */
    ((_5) => {
    })
  );
  var SelectionStateContext = K(
    /** @type {ReadonlySignal<SelectionState>} */
    d3({})
  );
  function SelectionProvider({ children }) {
    const { dispatch, state } = useSelectionStateApi();
    return /* @__PURE__ */ _(SelectionStateContext.Provider, { value: state }, /* @__PURE__ */ _(SelectionDispatchContext.Provider, { value: dispatch }, children));
  }
  function useSelectionState() {
    return x2(SelectionStateContext);
  }
  function useSelected() {
    const state = x2(SelectionStateContext);
    return useComputed(() => state.value.selected);
  }
  function useFocussedIndex() {
    const state = x2(SelectionStateContext);
    return useComputed(() => state.value.focusedIndex);
  }
  function useSelectionDispatch() {
    return x2(SelectionDispatchContext);
  }
  function useRowInteractions(mainRef) {
    const platformName = usePlatformName();
    const dispatch = useSelectionDispatch();
    const selected = useSelected();
    const historyDispatch = useHistoryServiceDispatch();
    const results = useResultsData();
    const focusedIndex = useFocussedIndex();
    function handleRowClickIntentions(intention, selection) {
      const { index } = selection;
      switch (intention) {
        case "click":
          dispatch({ kind: "select-index", index, reason: intention });
          return true;
        case "ctrl+click": {
          dispatch({ kind: "toggle-index", index, reason: intention });
          return true;
        }
        case "shift+click": {
          dispatch({ kind: "expand-selected-to-index", index, reason: intention });
          return true;
        }
      }
      return false;
    }
    function clickHandler(event) {
      if (!(event.target instanceof Element)) return;
      if (event.target.closest("button")) return;
      if (event.target.closest("a")) return;
      const itemRow = (
        /** @type {HTMLElement|null} */
        event.target.closest("[data-history-entry][data-index]")
      );
      const intention = eventToIntention(event, platformName);
      const selection = toRowSelection(itemRow);
      if (selection) {
        const handled = handleRowClickIntentions(intention, selection);
        if (handled) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      }
    }
    function handleKeyIntention(intention) {
      const total = results.value.items.length;
      if (focusedIndex.value === null) return false;
      switch (intention) {
        case "shift+down": {
          dispatch({
            kind: "increment-selection",
            direction: "down",
            total
          });
          return true;
        }
        case "shift+up": {
          dispatch({
            kind: "increment-selection",
            direction: "up",
            total
          });
          return true;
        }
        case "up":
          dispatch({ kind: "move-selection", direction: "up", total });
          return true;
        case "down": {
          dispatch({ kind: "move-selection", direction: "down", total });
          return true;
        }
        case "delete": {
          if (selected.value.size === 0) break;
          historyDispatch({ kind: "delete-entries-by-index", value: [...selected.value] });
          break;
        }
      }
      return false;
    }
    function handleGlobalKeyIntentions(intention, event) {
      if (event.target !== document.body) return false;
      switch (intention) {
        case "escape": {
          dispatch({
            kind: "reset",
            reason: "escape key pressed"
          });
          return true;
        }
      }
      return false;
    }
    function keyHandler(event) {
      const intention = eventToIntention(event, platformName);
      if (intention === "unknown") return;
      if (focusedIndex.value === null) return;
      let handled = false;
      if (event.target === document.body || event.target === mainRef.current || mainRef.current?.contains(
        /** @type {any} */
        event.target
      )) {
        handled = handleKeyIntention(intention);
      }
      if (!handled) {
        handled = handleGlobalKeyIntentions(intention, event);
      }
      if (handled) event.preventDefault();
    }
    const onClick = q2(clickHandler, [selected, focusedIndex]);
    const onKeyDown = q2(keyHandler, [selected, focusedIndex]);
    return { onClick, onKeyDown };
  }
  function toRowSelection(elem) {
    if (elem === null) return null;
    const { index, historyEntry } = elem.dataset;
    if (typeof historyEntry !== "string") return null;
    if (typeof index !== "string") return null;
    if (!index.trim().match(/^\d+$/)) return null;
    return { id: historyEntry, index: parseInt(index, 10) };
  }

  // pages/history/app/components/Header.js
  function Header() {
    const search = useQueryContext();
    const term = useComputed(() => search.value.term);
    const range = useComputed(() => search.value.range);
    const domain = useComputed(() => search.value.domain);
    return /* @__PURE__ */ _("div", { class: Header_default.root }, /* @__PURE__ */ _("div", { class: Header_default.controls }, /* @__PURE__ */ _(Controls, { term, range, domain })), /* @__PURE__ */ _("div", { class: Header_default.search }, /* @__PURE__ */ _(SearchForm, { term, domain })));
  }
  function Controls({ term, range, domain }) {
    const { t: t4 } = useTypedTranslation();
    const results = useResultsData();
    const selected = useSelected();
    const dispatch = useHistoryServiceDispatch();
    const ariaDisabled = useComputed(() => results.value.items.length === 0);
    const title = useComputed(() => results.value.items.length === 0 ? t4("delete_none") : "");
    const buttonTxt = useComputed(() => {
      const hasSelections = selected.value.size > 0;
      if (hasSelections) return t4("delete_some");
      return t4("delete_all");
    });
    function onClick() {
      if (ariaDisabled.value === true) return;
      if (selected.value.size > 0) {
        return dispatch({ kind: "delete-entries-by-index", value: [...selected.value] });
      }
      if (range.value !== null) {
        return dispatch({ kind: "delete-range", value: range.value });
      }
      if (term.value !== null && term.value !== "") {
        return dispatch({ kind: "delete-term", term: term.value });
      }
      if (domain.value !== null) {
        return dispatch({ kind: "delete-domain", domain: domain.value });
      }
      if (term.value !== null && term.value !== "") {
        return dispatch({ kind: "delete-term", term: term.value });
      }
      dispatch({ kind: "delete-all" });
    }
    return /* @__PURE__ */ _("button", { class: Header_default.largeButton, onClick, "aria-disabled": ariaDisabled, title, tabindex: 0 }, /* @__PURE__ */ _(Trash, null), /* @__PURE__ */ _("span", null, buttonTxt));
  }

  // ../node_modules/preact/compat/dist/compat.module.js
  function g5(n3, t4) {
    for (var e4 in t4) n3[e4] = t4[e4];
    return n3;
  }
  function E3(n3, t4) {
    for (var e4 in n3) if ("__source" !== e4 && !(e4 in t4)) return true;
    for (var r4 in t4) if ("__source" !== r4 && n3[r4] !== t4[r4]) return true;
    return false;
  }
  function N2(n3, t4) {
    this.props = n3, this.context = t4;
  }
  function M2(n3, e4) {
    function r4(n4) {
      var t4 = this.props.ref, r5 = t4 == n4.ref;
      return !r5 && t4 && (t4.call ? t4(null) : t4.current = null), e4 ? !e4(this.props, n4) || !r5 : E3(this.props, n4);
    }
    function u4(e5) {
      return this.shouldComponentUpdate = r4, _(n3, e5);
    }
    return u4.displayName = "Memo(" + (n3.displayName || n3.name) + ")", u4.prototype.isReactComponent = true, u4.__f = true, u4;
  }
  (N2.prototype = new x()).isPureReactComponent = true, N2.prototype.shouldComponentUpdate = function(n3, t4) {
    return E3(this.props, n3) || E3(this.state, t4);
  };
  var T4 = l.__b;
  l.__b = function(n3) {
    n3.type && n3.type.__f && n3.ref && (n3.props.ref = n3.ref, n3.ref = null), T4 && T4(n3);
  };
  var A4 = "undefined" != typeof Symbol && Symbol.for && Symbol.for("react.forward_ref") || 3911;
  var F4 = l.__e;
  l.__e = function(n3, t4, e4, r4) {
    if (n3.then) {
      for (var u4, o4 = t4; o4 = o4.__; ) if ((u4 = o4.__c) && u4.__c) return null == t4.__e && (t4.__e = e4.__e, t4.__k = e4.__k), u4.__c(n3, t4);
    }
    F4(n3, t4, e4, r4);
  };
  var U = l.unmount;
  function V2(n3, t4, e4) {
    return n3 && (n3.__c && n3.__c.__H && (n3.__c.__H.__.forEach(function(n4) {
      "function" == typeof n4.__c && n4.__c();
    }), n3.__c.__H = null), null != (n3 = g5({}, n3)).__c && (n3.__c.__P === e4 && (n3.__c.__P = t4), n3.__c.__e = true, n3.__c = null), n3.__k = n3.__k && n3.__k.map(function(n4) {
      return V2(n4, t4, e4);
    })), n3;
  }
  function W(n3, t4, e4) {
    return n3 && e4 && (n3.__v = null, n3.__k = n3.__k && n3.__k.map(function(n4) {
      return W(n4, t4, e4);
    }), n3.__c && n3.__c.__P === t4 && (n3.__e && e4.appendChild(n3.__e), n3.__c.__e = true, n3.__c.__P = e4)), n3;
  }
  function P3() {
    this.__u = 0, this.o = null, this.__b = null;
  }
  function j3(n3) {
    var t4 = n3.__.__c;
    return t4 && t4.__a && t4.__a(n3);
  }
  function B3() {
    this.i = null, this.l = null;
  }
  l.unmount = function(n3) {
    var t4 = n3.__c;
    t4 && t4.__R && t4.__R(), t4 && 32 & n3.__u && (n3.type = null), U && U(n3);
  }, (P3.prototype = new x()).__c = function(n3, t4) {
    var e4 = t4.__c, r4 = this;
    null == r4.o && (r4.o = []), r4.o.push(e4);
    var u4 = j3(r4.__v), o4 = false, i5 = function() {
      o4 || (o4 = true, e4.__R = null, u4 ? u4(l5) : l5());
    };
    e4.__R = i5;
    var l5 = function() {
      if (!--r4.__u) {
        if (r4.state.__a) {
          var n4 = r4.state.__a;
          r4.__v.__k[0] = W(n4, n4.__c.__P, n4.__c.__O);
        }
        var t5;
        for (r4.setState({ __a: r4.__b = null }); t5 = r4.o.pop(); ) t5.forceUpdate();
      }
    };
    r4.__u++ || 32 & t4.__u || r4.setState({ __a: r4.__b = r4.__v.__k[0] }), n3.then(i5, i5);
  }, P3.prototype.componentWillUnmount = function() {
    this.o = [];
  }, P3.prototype.render = function(n3, e4) {
    if (this.__b) {
      if (this.__v.__k) {
        var r4 = document.createElement("div"), o4 = this.__v.__k[0].__c;
        this.__v.__k[0] = V2(this.__b, r4, o4.__O = o4.__P);
      }
      this.__b = null;
    }
    var i5 = e4.__a && _(k, null, n3.fallback);
    return i5 && (i5.__u &= -33), [_(k, null, e4.__a ? null : n3.children), i5];
  };
  var H2 = function(n3, t4, e4) {
    if (++e4[1] === e4[0] && n3.l.delete(t4), n3.props.revealOrder && ("t" !== n3.props.revealOrder[0] || !n3.l.size)) for (e4 = n3.i; e4; ) {
      for (; e4.length > 3; ) e4.pop()();
      if (e4[1] < e4[0]) break;
      n3.i = e4 = e4[2];
    }
  };
  (B3.prototype = new x()).__a = function(n3) {
    var t4 = this, e4 = j3(t4.__v), r4 = t4.l.get(n3);
    return r4[0]++, function(u4) {
      var o4 = function() {
        t4.props.revealOrder ? (r4.push(u4), H2(t4, n3, r4)) : u4();
      };
      e4 ? e4(o4) : o4();
    };
  }, B3.prototype.render = function(n3) {
    this.i = null, this.l = /* @__PURE__ */ new Map();
    var t4 = H(n3.children);
    n3.revealOrder && "b" === n3.revealOrder[0] && t4.reverse();
    for (var e4 = t4.length; e4--; ) this.l.set(t4[e4], this.i = [1, 0, this.i]);
    return n3.children;
  }, B3.prototype.componentDidUpdate = B3.prototype.componentDidMount = function() {
    var n3 = this;
    this.l.forEach(function(t4, e4) {
      H2(n3, e4, t4);
    });
  };
  var q4 = "undefined" != typeof Symbol && Symbol.for && Symbol.for("react.element") || 60103;
  var G2 = /^(?:accent|alignment|arabic|baseline|cap|clip(?!PathU)|color|dominant|fill|flood|font|glyph(?!R)|horiz|image(!S)|letter|lighting|marker(?!H|W|U)|overline|paint|pointer|shape|stop|strikethrough|stroke|text(?!L)|transform|underline|unicode|units|v|vector|vert|word|writing|x(?!C))[A-Z]/;
  var J2 = /^on(Ani|Tra|Tou|BeforeInp|Compo)/;
  var K2 = /[A-Z0-9]/g;
  var Q = "undefined" != typeof document;
  var X = function(n3) {
    return ("undefined" != typeof Symbol && "symbol" == typeof Symbol() ? /fil|che|rad/ : /fil|che|ra/).test(n3);
  };
  x.prototype.isReactComponent = {}, ["componentWillMount", "componentWillReceiveProps", "componentWillUpdate"].forEach(function(t4) {
    Object.defineProperty(x.prototype, t4, { configurable: true, get: function() {
      return this["UNSAFE_" + t4];
    }, set: function(n3) {
      Object.defineProperty(this, t4, { configurable: true, writable: true, value: n3 });
    } });
  });
  var en = l.event;
  function rn() {
  }
  function un() {
    return this.cancelBubble;
  }
  function on() {
    return this.defaultPrevented;
  }
  l.event = function(n3) {
    return en && (n3 = en(n3)), n3.persist = rn, n3.isPropagationStopped = un, n3.isDefaultPrevented = on, n3.nativeEvent = n3;
  };
  var ln;
  var cn = { enumerable: false, configurable: true, get: function() {
    return this.class;
  } };
  var fn = l.vnode;
  l.vnode = function(n3) {
    "string" == typeof n3.type && (function(n4) {
      var t4 = n4.props, e4 = n4.type, u4 = {}, o4 = -1 === e4.indexOf("-");
      for (var i5 in t4) {
        var l5 = t4[i5];
        if (!("value" === i5 && "defaultValue" in t4 && null == l5 || Q && "children" === i5 && "noscript" === e4 || "class" === i5 || "className" === i5)) {
          var c4 = i5.toLowerCase();
          "defaultValue" === i5 && "value" in t4 && null == t4.value ? i5 = "value" : "download" === i5 && true === l5 ? l5 = "" : "translate" === c4 && "no" === l5 ? l5 = false : "o" === c4[0] && "n" === c4[1] ? "ondoubleclick" === c4 ? i5 = "ondblclick" : "onchange" !== c4 || "input" !== e4 && "textarea" !== e4 || X(t4.type) ? "onfocus" === c4 ? i5 = "onfocusin" : "onblur" === c4 ? i5 = "onfocusout" : J2.test(i5) && (i5 = c4) : c4 = i5 = "oninput" : o4 && G2.test(i5) ? i5 = i5.replace(K2, "-$&").toLowerCase() : null === l5 && (l5 = void 0), "oninput" === c4 && u4[i5 = c4] && (i5 = "oninputCapture"), u4[i5] = l5;
        }
      }
      "select" == e4 && u4.multiple && Array.isArray(u4.value) && (u4.value = H(t4.children).forEach(function(n5) {
        n5.props.selected = -1 != u4.value.indexOf(n5.props.value);
      })), "select" == e4 && null != u4.defaultValue && (u4.value = H(t4.children).forEach(function(n5) {
        n5.props.selected = u4.multiple ? -1 != u4.defaultValue.indexOf(n5.props.value) : u4.defaultValue == n5.props.value;
      })), t4.class && !t4.className ? (u4.class = t4.class, Object.defineProperty(u4, "className", cn)) : (t4.className && !t4.class || t4.class && t4.className) && (u4.class = u4.className = t4.className), n4.props = u4;
    })(n3), n3.$$typeof = q4, fn && fn(n3);
  };
  var an = l.__r;
  l.__r = function(n3) {
    an && an(n3), ln = n3.__c;
  };
  var sn = l.diffed;
  l.diffed = function(n3) {
    sn && sn(n3);
    var t4 = n3.props, e4 = n3.__e;
    null != e4 && "textarea" === n3.type && "value" in t4 && t4.value !== e4.value && (e4.value = null == t4.value ? "" : t4.value), ln = null;
  };

  // pages/history/app/components/Item.js
  var import_classnames2 = __toESM(require_classnames(), 1);

  // pages/history/app/components/Item.module.css
  var Item_default = {
    item: "Item_item",
    title: "Item_title",
    row: "Item_row",
    hover: "Item_hover",
    favicon: "Item_favicon",
    entryLink: "Item_entryLink",
    domain: "Item_domain",
    time: "Item_time",
    dots: "Item_dots",
    last: "Item_last"
  };

  // pages/history/app/icons/dots.js
  function Dots() {
    return /* @__PURE__ */ _("svg", { width: "16", height: "16", viewBox: "0 0 16 16", fill: "none", xmlns: "http://www.w3.org/2000/svg" }, /* @__PURE__ */ _(
      "path",
      {
        d: "M3.375 8C3.375 8.75939 2.75939 9.375 2 9.375C1.24061 9.375 0.625 8.75939 0.625 8C0.625 7.24061 1.24061 6.625 2 6.625C2.75939 6.625 3.375 7.24061 3.375 8Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ), /* @__PURE__ */ _(
      "path",
      {
        d: "M9.375 8C9.375 8.75939 8.75939 9.375 8 9.375C7.24061 9.375 6.625 8.75939 6.625 8C6.625 7.24061 7.24061 6.625 8 6.625C8.75939 6.625 9.375 7.24061 9.375 8Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ), /* @__PURE__ */ _(
      "path",
      {
        d: "M14 9.375C14.7594 9.375 15.375 8.75939 15.375 8C15.375 7.24061 14.7594 6.625 14 6.625C13.2406 6.625 12.625 7.24061 12.625 8C12.625 8.75939 13.2406 9.375 14 9.375Z",
        fill: "currentColor",
        "fill-opacity": "1"
      }
    ));
  }

  // shared/components/FaviconWithState.js
  var import_classnames = __toESM(require_classnames(), 1);

  // shared/components/FaviconWithState.module.css
  var FaviconWithState_default = {
    favicon: "FaviconWithState_favicon",
    faviconLarge: "FaviconWithState_faviconLarge",
    faviconSmall: "FaviconWithState_faviconSmall",
    faviconText: "FaviconWithState_faviconText"
  };

  // shared/getColorForString.js
  var EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES = [
    "#94B3AF",
    "#727998",
    "#645468",
    "#4D5F7F",
    "#855DB6",
    "#5E5ADB",
    "#678FFF",
    "#6BB4EF",
    "#4A9BAE",
    "#66C4C6",
    "#55D388",
    "#99DB7A",
    "#ECCC7B",
    "#E7A538",
    "#DD6B4C",
    "#D65D62"
  ];
  function getArrayIndex(str, arrayLength) {
    const utf8Encoder = new TextEncoder();
    const bytes = utf8Encoder.encode(str);
    let hash = BigInt(5381);
    for (const byte of bytes) {
      hash = (hash << BigInt(5)) + hash + BigInt(byte);
      hash = BigInt.asIntN(64, hash);
    }
    const index = hash % BigInt(arrayLength);
    return Number(index < 0 ? -index : index);
  }
  var urlToColorCache = /* @__PURE__ */ new Map();
  function urlToColor(url2) {
    if (typeof url2 !== "string") return null;
    if (urlToColorCache.has(url2)) {
      return urlToColorCache.get(url2);
    }
    const index = getArrayIndex(url2, EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES.length);
    const color = EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES[index];
    urlToColorCache.set(url2, color);
    return color;
  }

  // shared/components/FaviconWithState.js
  var states = (
    /** @type {Record<ImgState, ImgState>} */
    {
      loading_favicon_src: "loading_favicon_src",
      did_load_favicon_src: "did_load_favicon_src",
      loading_fallback_img: "loading_fallback_img",
      did_load_fallback_img: "did_load_fallback_img",
      fallback_img_failed: "fallback_img_failed",
      using_fallback_text: "using_fallback_text"
    }
  );
  function FaviconWithState({ defaultSize = 64, fallback, fallbackDark, faviconSrc, faviconMax, etldPlusOne, theme, displayKind }) {
    const size = Math.min(faviconMax, defaultSize);
    const sizeClass = displayKind === "favorite-tile" ? FaviconWithState_default.faviconLarge : FaviconWithState_default.faviconSmall;
    const imgsrc = faviconSrc ? faviconSrc + "?preferredSize=" + size : null;
    const initialState = (() => {
      if (imgsrc) return states.loading_favicon_src;
      if (etldPlusOne) return states.using_fallback_text;
      return states.loading_fallback_img;
    })();
    const [state, setState] = d2(
      /** @type {ImgState} */
      initialState
    );
    switch (state) {
      /**
       * These are the happy paths, where we are loading the favicon source and it does not 404
       */
      case states.loading_favicon_src:
      case states.did_load_favicon_src: {
        if (!imgsrc) {
          console.warn("unreachable - must have imgsrc here");
          return null;
        }
        return /* @__PURE__ */ _(
          "img",
          {
            src: imgsrc,
            class: (0, import_classnames.default)(FaviconWithState_default.favicon, sizeClass),
            alt: "",
            "data-state": state,
            onLoad: () => setState(states.did_load_favicon_src),
            onError: () => {
              if (etldPlusOne) {
                setState(states.using_fallback_text);
              } else {
                setState(states.loading_fallback_img);
              }
            }
          }
        );
      }
      /**
       * A fallback can be applied when the `etldPlusOne` is there. For example,
       * if `etldPlusOne = 'example.com'`, we can display `Ex` and use the domain name
       * to select a background color.
       */
      case states.using_fallback_text: {
        if (!etldPlusOne) {
          console.warn("unreachable - must have etld+1 here");
          return null;
        }
        let style;
        const fallbackColor = urlToColor(etldPlusOne);
        if (fallbackColor) {
          style = { background: fallbackColor };
        }
        const chars = etldPlusOne.slice(0, 2);
        return /* @__PURE__ */ _("div", { class: (0, import_classnames.default)(FaviconWithState_default.favicon, sizeClass, FaviconWithState_default.faviconText), style, "data-state": state }, /* @__PURE__ */ _("span", { "aria-hidden": true }, chars[0]), /* @__PURE__ */ _("span", { "aria-hidden": true }, chars[1]));
      }
      /**
       * If we get here, we couldn't load the favicon source OR the fallback text
       * So, we default to a globe icon
       */
      case states.loading_fallback_img:
      case states.did_load_fallback_img: {
        return /* @__PURE__ */ _(
          "img",
          {
            src: theme === "light" ? fallback : fallbackDark,
            class: (0, import_classnames.default)(FaviconWithState_default.favicon, sizeClass),
            alt: "",
            "data-state": state,
            onLoad: () => setState(states.did_load_fallback_img),
            onError: () => setState(states.fallback_img_failed)
          }
        );
      }
      default:
        return null;
    }
  }

  // pages/history/app/components/Item.js
  var Item = M2(
    /**
     * Renders an individual item with specific styles and layout determined by props.
     *
     * @param {Object} props - An object containing the properties for the item.
     * @param {string} props.id - A unique identifier for the item.
     * @param {string} props.viewId - A unique identifier for the item, safe to use in CSS names
     * @param {string} props.title - The text to be displayed for the item.
     * @param {string} props.url - The text to be displayed for the item.
     * @param {string} props.domain - The text to be displayed for the domain
     * @param {number} props.kind - The kind or type of the item that determines its visual style.
     * @param {string} props.dateTimeOfDay - the time of day, like 11.00am.
     * @param {string} props.dateRelativeDay - the time of day, like 11.00am.
     * @param {string|null} props.etldPlusOne
     * @param {number} props.index - original index
     * @param {boolean} props.selected - whether this item is selected
     * @param {string|null|undefined} props.faviconSrc
     * @param {number} props.faviconMax
     */
    function Item2(props) {
      const { viewId, title, kind, etldPlusOne, faviconSrc, faviconMax, dateTimeOfDay, dateRelativeDay, index, selected } = props;
      const hasFooterGap = kind === END_KIND || kind === BOTH_KIND;
      const hasTitle = kind === TITLE_KIND || kind === BOTH_KIND;
      return /* @__PURE__ */ _(k, null, hasTitle && /* @__PURE__ */ _("div", { class: (0, import_classnames2.default)(Item_default.title), style: { viewTransitionName: `Item-title-${viewId}` } }, dateRelativeDay), /* @__PURE__ */ _(
        "div",
        {
          class: (0, import_classnames2.default)(Item_default.row, Item_default.hover, hasFooterGap && Item_default.last),
          "data-history-entry": props.id,
          "data-index": index,
          "aria-selected": selected,
          style: { viewTransitionName: `Item-item-${viewId}` }
        },
        /* @__PURE__ */ _("div", { class: Item_default.favicon }, /* @__PURE__ */ _(
          FaviconWithState,
          {
            fallback: "./company-icons/other.svg",
            fallbackDark: "./company-icons/other-dark.svg",
            faviconMax,
            faviconSrc,
            etldPlusOne,
            displayKind: "history-favicon",
            theme: "light",
            defaultSize: DDG_DEFAULT_ICON_SIZE
          }
        )),
        /* @__PURE__ */ _("a", { href: props.url, "data-url": props.url, class: Item_default.entryLink, tabindex: 0 }, title),
        /* @__PURE__ */ _("span", { class: Item_default.domain, "data-testid": "Item.domain", title: props.domain }, props.domain),
        /* @__PURE__ */ _("span", { class: Item_default.time }, dateTimeOfDay),
        /* @__PURE__ */ _("button", { class: Item_default.dots, "data-action": BTN_ACTION_ENTRIES_MENU, "data-index": index, value: props.id, tabindex: -1 }, /* @__PURE__ */ _(Dots, null))
      ));
    }
  );

  // pages/history/app/components/VirtualizedList.module.css
  var VirtualizedList_default = {
    container: "VirtualizedList_container",
    listItem: "VirtualizedList_listItem",
    emptyState: "VirtualizedList_emptyState",
    emptyStateOffset: "VirtualizedList_emptyStateOffset",
    icons: "VirtualizedList_icons",
    forground: "VirtualizedList_forground",
    emptyTitle: "VirtualizedList_emptyTitle",
    emptyText: "VirtualizedList_emptyText"
  };

  // pages/history/app/components/VirtualizedList.js
  function VirtualizedList({ items, heights, overscan, scrollingElement, onChange, renderItem }) {
    const { start, end } = useVisibleRows(items, heights, scrollingElement, overscan);
    const subset = items.slice(start, end + 1);
    y2(() => {
      onChange?.(end);
    }, [onChange, end]);
    return /* @__PURE__ */ _(k, null, subset.map((item, rowIndex) => {
      const originalIndex = start + rowIndex;
      const itemTopOffset = heights.slice(0, originalIndex).reduce((acc, item2) => acc + item2, 0);
      return renderItem({
        item,
        index: originalIndex,
        cssClassName: VirtualizedList_default.listItem,
        itemTopOffset,
        style: {
          transform: `translateY(${itemTopOffset}px)`
        }
      });
    }));
  }
  var VisibleItems = M2(VirtualizedList);
  function useVisibleRows(rows, heights, scrollerSelector, overscan = 5) {
    const [{ start, end }, setVisibleRange] = d2({ start: 0, end: 1 });
    const mainScrollerRef = A2(
      /** @type {Element|null} */
      null
    );
    const scrollingSize = A2(
      /** @type {number|null} */
      null
    );
    function updateGlobals() {
      if (!mainScrollerRef.current) return;
      const rec = mainScrollerRef.current.getBoundingClientRect();
      scrollingSize.current = rec.height;
    }
    function setVisibleRowsForOffset() {
      if (!mainScrollerRef.current) return console.warn("cannot access mainScroller ref");
      if (scrollingSize.current === null) return console.warn("need height");
      const scrollY = mainScrollerRef.current?.scrollTop ?? 0;
      const next = calcVisibleRows(heights || [], scrollingSize.current, scrollY);
      const withOverScan = {
        start: Math.max(next.startIndex - overscan, 0),
        end: next.endIndex + overscan
      };
      setVisibleRange((prev) => {
        if (withOverScan.start !== prev.start || withOverScan.end !== prev.end) {
          return { start: withOverScan.start, end: withOverScan.end };
        }
        return prev;
      });
    }
    _2(() => {
      mainScrollerRef.current = document.querySelector(scrollerSelector) || document.documentElement;
      if (!mainScrollerRef.current) console.warn("missing elements");
      updateGlobals();
      setVisibleRowsForOffset();
      const controller = new AbortController();
      mainScrollerRef.current?.addEventListener("scroll", setVisibleRowsForOffset, { signal: controller.signal });
      return () => {
        controller.abort();
      };
    }, [rows, heights, scrollerSelector]);
    y2(() => {
      let lastWindowHeight = window.innerHeight;
      function handler() {
        if (lastWindowHeight === window.innerHeight) return;
        lastWindowHeight = window.innerHeight;
        updateGlobals();
        setVisibleRowsForOffset();
      }
      window.addEventListener("resize", handler);
      return () => {
        return window.removeEventListener("resize", handler);
      };
    }, [heights, rows]);
    return { start, end };
  }
  function calcVisibleRows(heights, space, scrollOffset) {
    let startIndex = 0;
    let endIndex = 0;
    let currentHeight = 0;
    for (let i5 = 0; i5 < heights.length; i5++) {
      if (currentHeight + heights[i5] > scrollOffset) {
        startIndex = i5;
        break;
      }
      currentHeight += heights[i5];
    }
    currentHeight = 0;
    for (let i5 = startIndex; i5 < heights.length; i5++) {
      if (currentHeight + heights[i5] > space) {
        endIndex = i5;
        break;
      }
      currentHeight += heights[i5];
      endIndex = i5;
    }
    return { startIndex, endIndex };
  }

  // pages/history/app/components/Empty.js
  var import_classnames3 = __toESM(require_classnames(), 1);
  function Empty({ title, text }) {
    return /* @__PURE__ */ _("div", { class: (0, import_classnames3.default)(VirtualizedList_default.emptyState, VirtualizedList_default.emptyStateOffset) }, /* @__PURE__ */ _("div", { class: VirtualizedList_default.icons }, /* @__PURE__ */ _("img", { src: "icons/backdrop.svg", width: 128, height: 96, alt: "" }), /* @__PURE__ */ _("img", { src: "icons/clock.svg", width: 60, height: 60, alt: "", class: VirtualizedList_default.forground })), /* @__PURE__ */ _("h2", { class: VirtualizedList_default.emptyTitle }, title), /* @__PURE__ */ _("p", { class: VirtualizedList_default.emptyText }, text));
  }
  function EmptyState() {
    const { t: t4 } = useTypedTranslation();
    const results = useResultsData();
    const query = useQueryContext();
    const hasSearch = useComputed(() => query.value.term !== null && query.value.term.trim().length > 0);
    const text = useComputed(() => {
      const termFromSearchBox = query.value.term;
      if (!("term" in results.value.info.query)) return termFromSearchBox;
      const termFromApiResponse = results.value.info.query.term;
      if (termFromSearchBox === termFromApiResponse) {
        return termFromSearchBox;
      }
      return termFromApiResponse;
    });
    if (hasSearch.value) {
      return /* @__PURE__ */ _(Empty, { title: t4("no_results_title", { term: `"${text.value}"` }), text: t4("no_results_text") });
    }
    return /* @__PURE__ */ _(Empty, { title: t4("empty_title"), text: t4("empty_text") });
  }

  // pages/history/app/components/Results.js
  function ResultsContainer() {
    const results = useResultsData();
    const selected = useSelected();
    const selectionState = useSelectionState();
    const dispatch = useHistoryServiceDispatch();
    y2(() => {
      return selectionState.subscribe(({ lastAction, focusedIndex }) => {
        if (lastAction === "move-selection" || lastAction === "inc-or-dec-selected") {
          const match = document.querySelector(`[aria-selected][data-index="${focusedIndex}"]`);
          match?.scrollIntoView({ block: "nearest", inline: "nearest" });
        }
      });
    }, [selectionState]);
    const onChange = q2((end) => dispatch({ kind: "request-more", end }), [dispatch]);
    return /* @__PURE__ */ _(Results, { results, selected, onChange });
  }
  function Results({ results, selected, onChange }) {
    if (results.value.items.length === 0) {
      return /* @__PURE__ */ _(EmptyState, null);
    }
    const totalHeight = results.value.heights.reduce((acc, item) => acc + item, 0);
    return /* @__PURE__ */ _("ul", { class: VirtualizedList_default.container, style: { height: totalHeight + "px" } }, /* @__PURE__ */ _(
      VisibleItems,
      {
        scrollingElement: "main",
        items: results.value.items,
        heights: results.value.heights,
        overscan: OVERSCAN_AMOUNT,
        onChange,
        renderItem: ({ item, cssClassName, style, index }) => {
          const isSelected = selected.value.has(index);
          const faviconMax = item.favicon?.maxAvailableSize ?? DDG_DEFAULT_ICON_SIZE;
          const favoriteSrc = item.favicon?.src;
          const viewId = results.value.viewIds[index];
          return /* @__PURE__ */ _("li", { key: item.id, "data-id": item.id, class: cssClassName, style, "data-is-selected": isSelected }, /* @__PURE__ */ _(
            Item,
            {
              id: item.id,
              viewId,
              kind: results.value.heights[index],
              url: item.url,
              domain: item.domain,
              title: item.title,
              dateTimeOfDay: item.dateTimeOfDay,
              dateRelativeDay: item.dateRelativeDay,
              index,
              selected: isSelected,
              etldPlusOne: item.etldPlusOne ?? null,
              faviconSrc: favoriteSrc,
              faviconMax
            }
          ));
        }
      }
    ));
  }

  // pages/history/app/components/Sidebar.js
  var import_classnames4 = __toESM(require_classnames(), 1);

  // pages/history/app/components/Sidebar.module.css
  var Sidebar_default = {
    stack: "Sidebar_stack",
    pageTitle: "Sidebar_pageTitle",
    nav: "Sidebar_nav",
    item: "Sidebar_item",
    delete: "Sidebar_delete",
    active: "Sidebar_active",
    link: "Sidebar_link",
    icon: "Sidebar_icon"
  };

  // pages/new-tab/app/types.js
  function useTypedTranslationWith(_context) {
    return {
      /** @type {any} */
      t: x2(TranslationContext).t
    };
  }
  var MessagingContext3 = K(
    /** @type {import("../src/index.js").NewTabPage} */
    {}
  );
  var TelemetryContext = K(
    /** @type {import("./telemetry/telemetry.js").Telemetry} */
    {
      measureFromPageLoad: () => {
      }
    }
  );
  var InitialSetupContext = K(
    /** @type {InitialSetupResponse} */
    {}
  );

  // pages/history/app/components/Sidebar.js
  var iconMap = {
    all: "icons/all.svg",
    today: "icons/today.svg",
    yesterday: "icons/yesterday.svg",
    monday: "icons/day.svg",
    tuesday: "icons/day.svg",
    wednesday: "icons/day.svg",
    thursday: "icons/day.svg",
    friday: "icons/day.svg",
    saturday: "icons/day.svg",
    sunday: "icons/day.svg",
    older: "icons/older.svg"
  };
  var titleMap = {
    all: (t4) => t4("range_all"),
    today: (t4) => t4("range_today"),
    yesterday: (t4) => t4("range_yesterday"),
    monday: (t4) => t4("range_monday"),
    tuesday: (t4) => t4("range_tuesday"),
    wednesday: (t4) => t4("range_wednesday"),
    thursday: (t4) => t4("range_thursday"),
    friday: (t4) => t4("range_friday"),
    saturday: (t4) => t4("range_saturday"),
    sunday: (t4) => t4("range_sunday"),
    older: (t4) => t4("range_older")
  };
  function Sidebar({ ranges }) {
    const { t: t4 } = useTypedTranslation();
    const search = useQueryContext();
    const current = useComputed(() => search.value.range);
    const dispatch = useQueryDispatch();
    const historyServiceDispatch = useHistoryServiceDispatch();
    function onClick(range) {
      if (range === "all") {
        dispatch({ kind: "search-by-term", value: "" });
      } else if (range) {
        dispatch({ kind: "search-by-range", value: range });
      }
    }
    function onDelete(range) {
      historyServiceDispatch({ kind: "delete-range", value: range });
    }
    return /* @__PURE__ */ _("div", { class: Sidebar_default.stack }, /* @__PURE__ */ _("h1", { class: Sidebar_default.pageTitle }, t4("page_title")), /* @__PURE__ */ _("nav", { class: (0, import_classnames4.default)(Sidebar_default.nav, App_default.customScroller) }, ranges.value.map((range) => {
      return /* @__PURE__ */ _(Item3, { key: range.id, onClick, onDelete, current, range: range.id, count: range.count });
    })));
  }
  function Item3({ current, range, onClick, onDelete, count }) {
    const { t: t4 } = useTypedTranslation();
    const { buttonLabel, linkLabel } = labels(range, t4);
    const classNames = useComputed(() => {
      if (range === "all" && current.value === null) {
        return (0, import_classnames4.default)(Sidebar_default.item, Sidebar_default.active);
      }
      return (0, import_classnames4.default)(Sidebar_default.item, current.value === range && Sidebar_default.active);
    });
    return /* @__PURE__ */ _("div", { class: classNames, key: range }, /* @__PURE__ */ _(
      "button",
      {
        "aria-label": linkLabel,
        class: Sidebar_default.link,
        tabIndex: 0,
        onClick: (e4) => {
          e4.preventDefault();
          onClick(range);
        }
      },
      /* @__PURE__ */ _("span", { className: Sidebar_default.icon }, /* @__PURE__ */ _("img", { src: iconMap[range] })),
      titleMap[range](t4)
    ), /* @__PURE__ */ _(DeleteAllButton, { onClick: onDelete, ariaLabel: buttonLabel, range, count }));
  }
  function DeleteAllButton({ range, onClick, ariaLabel, count }) {
    const { t: t4 } = useTypedTranslationWith(
      /** @type {json} */
      {}
    );
    const ariaDisabled = count === 0 ? "true" : "false";
    const buttonTitle = count === 0 ? t4("delete_none") : "";
    return /* @__PURE__ */ _(
      "button",
      {
        class: Sidebar_default.delete,
        onClick: (e4) => {
          if (e4.currentTarget.getAttribute("aria-disabled") === "true") {
            return;
          }
          onClick(range);
        },
        "aria-label": ariaLabel,
        tabindex: 0,
        value: range,
        title: buttonTitle,
        "aria-disabled": ariaDisabled
      },
      /* @__PURE__ */ _(Trash, null)
    );
  }
  function labels(range, t4) {
    switch (range) {
      case "all":
        return { linkLabel: t4("show_history_all"), buttonLabel: t4("delete_history_all") };
      case "today":
      case "yesterday":
      case "monday":
      case "tuesday":
      case "wednesday":
      case "thursday":
      case "friday":
      case "saturday":
      case "sunday":
        return { linkLabel: t4("show_history_for", { range }), buttonLabel: t4("delete_history_for", { range }) };
      case "older":
        return { linkLabel: t4("show_history_older"), buttonLabel: t4("delete_history_older") };
    }
  }

  // pages/history/app/global/hooks/useContextMenuForEntries.js
  function useContextMenuForEntries() {
    const selected = useSelected();
    const dispatch = useHistoryServiceDispatch();
    y2(() => {
      function contextMenu(event) {
        const target = (
          /** @type {HTMLElement|null} */
          event.target
        );
        if (!(target instanceof HTMLElement)) return;
        const elem = target.closest("[data-history-entry]");
        if (!elem || !(elem instanceof HTMLElement)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        const isSelected = elem.getAttribute("aria-selected") === "true";
        if (isSelected) {
          dispatch({ kind: "show-entries-menu", indexes: [...selected.value] });
        } else {
          dispatch({ kind: "show-entries-menu", indexes: [Number(elem.dataset.index)] });
        }
      }
      document.addEventListener("contextmenu", contextMenu);
      return () => {
        document.removeEventListener("contextmenu", contextMenu);
      };
    }, []);
  }

  // shared/handlers.js
  function eventToTarget(event, platformName) {
    const isControlClick = platformName === "macos" ? event.metaKey : event.ctrlKey;
    if (isControlClick || "button" in event && event.button === 1) {
      return "new-tab";
    } else if (event.shiftKey) {
      return "new-window";
    }
    return "same-tab";
  }

  // pages/history/app/global/hooks/useAuxClickHandler.js
  function useAuxClickHandler() {
    const platformName = usePlatformName();
    const dispatch = useHistoryServiceDispatch();
    y2(() => {
      const handleAuxClick = (event) => {
        const row = (
          /** @type {HTMLDivElement|null} */
          event.target.closest("[aria-selected]")
        );
        const anchor = (
          /** @type {HTMLAnchorElement|null} */
          row?.querySelector("a[href][data-url]")
        );
        const url2 = anchor?.dataset.url;
        if (anchor && url2 && event.button === 1) {
          event.preventDefault();
          event.stopImmediatePropagation();
          const target = eventToTarget(event, platformName);
          dispatch({ kind: "open-url", url: url2, target });
        }
      };
      document.addEventListener("auxclick", handleAuxClick);
      return () => {
        document.removeEventListener("auxclick", handleAuxClick);
      };
    }, [platformName, dispatch]);
  }

  // pages/history/app/global/hooks/useButtonClickHandler.js
  function useButtonClickHandler() {
    const historyServiceDispatch = useHistoryServiceDispatch();
    const selected = useSelected();
    y2(() => {
      function clickHandler(event) {
        if (!(event.target instanceof Element)) return;
        const btn = (
          /** @type {HTMLButtonElement|null} */
          event.target.closest("button[data-action]")
        );
        if (btn === null) return;
        if (btn?.getAttribute("aria-disabled") === "true") return;
        const action = toKnownAction(btn);
        if (action === null) return;
        event.stopImmediatePropagation();
        event.preventDefault();
        switch (action) {
          case BTN_ACTION_ENTRIES_MENU: {
            const index = parseInt(btn.dataset.index ?? "-1", 10);
            const withinSelection = selected.value.has(index);
            if (withinSelection) {
              historyServiceDispatch({
                kind: "show-entries-menu",
                indexes: [...selected.value]
              });
            } else {
              historyServiceDispatch({
                kind: "show-entries-menu",
                indexes: [Number(btn.dataset.index)]
              });
            }
            return;
          }
          default:
            return null;
        }
      }
      document.addEventListener("click", clickHandler);
      return () => {
        document.removeEventListener("click", clickHandler);
      };
    }, []);
  }
  function toKnownAction(elem) {
    if (!elem) return null;
    const action = elem.dataset.action;
    if (!action) return null;
    if (KNOWN_ACTIONS.includes(
      /** @type {any} */
      action
    )) return (
      /** @type {KNOWN_ACTIONS[number]} */
      action
    );
    return null;
  }

  // pages/history/app/global/hooks/useLinkClickHandler.js
  function useLinkClickHandler() {
    const platformName = usePlatformName();
    const dispatch = useHistoryServiceDispatch();
    y2(() => {
      function dblClickHandler(event) {
        const url2 = closestUrl(event);
        if (url2) {
          event.preventDefault();
          event.stopImmediatePropagation();
          const target = eventToTarget(event, platformName);
          dispatch({ kind: "open-url", url: url2, target });
        }
      }
      function keydownHandler(event) {
        if (event.key !== "Enter" && event.key !== " ") return;
        const url2 = closestUrl(event);
        if (url2) {
          event.preventDefault();
          event.stopImmediatePropagation();
          const target = eventToTarget(event, platformName);
          dispatch({ kind: "open-url", url: url2, target });
        }
      }
      document.addEventListener("keydown", keydownHandler);
      document.addEventListener("dblclick", dblClickHandler);
      return () => {
        document.removeEventListener("dblclick", dblClickHandler);
        document.removeEventListener("keydown", keydownHandler);
      };
    }, [platformName, dispatch]);
  }
  function closestUrl(event) {
    if (!(event.target instanceof Element)) return null;
    const row = (
      /** @type {HTMLDivElement|null} */
      event.target.closest("[aria-selected]")
    );
    const anchor = (
      /** @type {HTMLAnchorElement|null} */
      row?.querySelector("a[href][data-url]")
    );
    const url2 = anchor?.dataset.url;
    return url2 || null;
  }

  // pages/history/app/global/hooks/useResetSelectionsOnQueryChange.js
  function useResetSelectionsOnQueryChange() {
    const dispatch = useSelectionDispatch();
    const query = useQueryContext();
    const results = useResultsData();
    const length = useComputed(() => results.value.items.length);
    useSignalEffect(() => {
      let prevLength = 0;
      const unsubs = [
        // when anything about the query changes, reset selections
        query.subscribe(() => {
          dispatch({ kind: "reset", reason: "query changed" });
        }),
        // when the size of data is smaller than before, reset
        length.subscribe((newLength) => {
          if (newLength < prevLength) {
            dispatch({
              kind: "reset",
              reason: `items length shrank from ${prevLength} to ${newLength}`
            });
          }
          prevLength = newLength;
        })
      ];
      return () => {
        for (const unsub of unsubs) {
          unsub();
        }
      };
    });
  }

  // pages/history/app/global/hooks/useSearchCommitForRange.js
  function useSearchCommitForRange() {
    const dispatch = useHistoryServiceDispatch();
    const query = useQueryContext();
    y2(() => {
      let timer;
      let counter = 0;
      const sub = query.subscribe((nextQuery) => {
        const { range } = nextQuery;
        if (counter === 0) {
          counter += 1;
          return;
        }
        const url2 = new URL(window.location.href);
        url2.searchParams.delete("q");
        url2.searchParams.delete("range");
        if (range !== null) {
          url2.searchParams.set("range", range);
          window.history.replaceState(null, "", url2.toString());
          dispatch({ kind: "search-commit", params: new URLSearchParams(url2.searchParams), source: "user" });
        }
      });
      return () => {
        sub();
        clearTimeout(timer);
      };
    }, [query, dispatch]);
  }

  // pages/history/app/global/hooks/useURLReflection.js
  function useURLReflection() {
    const settings = useSettings();
    const query = useQueryContext();
    useSignalEffect(() => {
      let timer;
      let count = 0;
      const unsubscribe = query.subscribe((nextValue) => {
        if (count === 0) return count += 1;
        clearTimeout(timer);
        if (nextValue.term !== null) {
          const term = nextValue.term;
          timer = setTimeout(() => {
            const url2 = new URL(window.location.href);
            url2.searchParams.set("q", term);
            url2.searchParams.delete("range");
            url2.searchParams.delete("domain");
            if (term.trim() === "") {
              url2.searchParams.delete("q");
            }
            window.history.replaceState(null, "", url2.toString());
          }, settings.urlDebounce);
        }
        if (nextValue.domain !== null) {
          const url2 = new URL(window.location.href);
          url2.searchParams.set("domain", nextValue.domain);
          url2.searchParams.delete("q");
          url2.searchParams.delete("range");
          window.history.replaceState(null, "", url2.toString());
        }
        return null;
      });
      return () => {
        unsubscribe();
        clearTimeout(timer);
      };
    });
  }

  // pages/history/app/global/hooks/useSearchCommit.js
  function useSearchCommit() {
    const dispatch = useHistoryServiceDispatch();
    const settings = useSettings();
    const query = useQueryContext();
    useSignalEffect(() => {
      let timer;
      let count = 0;
      const unsubscribe = query.subscribe((next) => {
        if (count === 0) return count += 1;
        clearTimeout(timer);
        if (next.term !== null) {
          const term = next.term;
          const source = next.source;
          timer = setTimeout(() => {
            const params = new URLSearchParams();
            params.set("q", term);
            dispatch({ kind: "search-commit", params, source });
          }, settings.typingDebounce);
        }
        if (next.domain !== null) {
          const params = new URLSearchParams();
          params.set("domain", next.domain);
          dispatch({ kind: "search-commit", params, source: next.source });
        }
        return null;
      });
      return () => {
        unsubscribe();
        clearTimeout(timer);
      };
    });
  }

  // pages/history/app/global/hooks/useLayoutMode.js
  function useLayoutMode() {
    const mode = useSignal(
      /** @type {'reduced' | 'normal'} */
      window.matchMedia("(max-width: 799px)").matches ? "reduced" : "normal"
    );
    _2(() => {
      const mediaQuery = window.matchMedia("(max-width: 799px)");
      const handleChange = () => {
        mode.value = mediaQuery.matches ? "reduced" : "normal";
      };
      handleChange();
      mediaQuery.addEventListener("change", handleChange);
      return () => {
        mediaQuery.removeEventListener("change", handleChange);
      };
    }, []);
    return mode;
  }

  // pages/history/app/global/hooks/useClickAnywhereElse.jsx
  function useClickAnywhereElse() {
    const dispatch = useSelectionDispatch();
    return q2(
      (e4) => {
        if (e4.target?.closest?.("button,a") === null) {
          dispatch({ kind: "reset", reason: "click occurred outside of rows" });
        }
      },
      [dispatch]
    );
  }

  // pages/history/app/components/App.jsx
  function App() {
    const platformName = usePlatformName();
    const mainRef = A2(
      /** @type {HTMLElement|null} */
      null
    );
    const { isDarkMode } = useEnv();
    const ranges = useRangesData();
    const query = useQueryContext();
    const mode = useLayoutMode();
    useResetSelectionsOnQueryChange();
    useLinkClickHandler();
    useButtonClickHandler();
    useContextMenuForEntries();
    useAuxClickHandler();
    useURLReflection();
    useSearchCommit();
    useSearchCommitForRange();
    const clickAnywhere = useClickAnywhereElse();
    const { onClick, onKeyDown } = useRowInteractions(mainRef);
    y2(() => {
      const unsubscribe = query.subscribe(() => {
        mainRef.current?.scrollTo(0, 0);
      });
      document.addEventListener("keydown", onKeyDown);
      return () => {
        document.removeEventListener("keydown", onKeyDown);
        unsubscribe();
      };
    }, [onKeyDown, query]);
    return /* @__PURE__ */ _(
      "div",
      {
        class: App_default.layout,
        "data-theme": isDarkMode ? "dark" : "light",
        "data-platform": platformName,
        "data-layout-mode": mode,
        onClick: clickAnywhere
      },
      /* @__PURE__ */ _("aside", { class: App_default.aside }, /* @__PURE__ */ _(Sidebar, { ranges })),
      /* @__PURE__ */ _("header", { class: App_default.header }, /* @__PURE__ */ _(Header, null)),
      /* @__PURE__ */ _("main", { class: (0, import_classnames5.default)(App_default.main, App_default.customScroller), ref: mainRef, onClick }, /* @__PURE__ */ _(ResultsContainer, null))
    );
  }
  function AppLevelErrorBoundaryFallback({ children }) {
    return /* @__PURE__ */ _("div", { class: App_default.paddedError }, /* @__PURE__ */ _("p", null, children), /* @__PURE__ */ _("div", { class: App_default.paddedErrorRecovery }, "You can try to", " ", /* @__PURE__ */ _(
      "button",
      {
        onClick: () => {
          const current = new URL(window.location.href);
          current.search = "";
          current.pathname = "";
          location.href = current.toString();
        }
      },
      "Reload this page"
    )));
  }

  // pages/history/app/components/Components.module.css
  var Components_default = {
    main: "Components_main"
  };

  // pages/history/app/components/Components.jsx
  function Components() {
    return /* @__PURE__ */ _("main", { class: Components_default.main }, "Component list here!");
  }

  // shared/call-with-retry.js
  async function callWithRetry(fn2, params = {}) {
    const { maxAttempts = 10, intervalMs = 300 } = params;
    let attempt = 1;
    while (attempt <= maxAttempts) {
      try {
        return { value: await fn2(), attempt };
      } catch (error) {
        if (attempt === maxAttempts) {
          return { error: `Max attempts reached: ${error}` };
        }
        await new Promise((resolve) => setTimeout(resolve, intervalMs));
        attempt++;
      }
    }
    return { error: "Unreachable: value not retrieved" };
  }

  // shared/components/ErrorBoundary.js
  var ErrorBoundary = class extends x {
    constructor(props) {
      super(props);
      this.state = { hasError: false };
    }
    static getDerivedStateFromError() {
      return { hasError: true };
    }
    componentDidCatch(error, info) {
      console.error(error);
      console.log(info);
      let message = error.message;
      if (typeof message !== "string") message = "unknown";
      const composed = this.props.context ? [this.props.context, message].join(" ") : message;
      this.props.didCatch({ error, message: composed, info });
    }
    render() {
      if (this.state.hasError) {
        return this.props.fallback;
      }
      return this.props.children;
    }
  };

  // shared/components/InlineErrorBoundary.js
  var INLINE_ERROR = "A problem occurred with this feature. DuckDuckGo was notified";
  function InlineErrorBoundary({ children, format, context, fallback, messaging: messaging2 }) {
    const didCatch = (message) => {
      const formatted = format?.(message) || message;
      messaging2.reportPageException({ message: formatted });
    };
    const fallbackElement = fallback?.(INLINE_ERROR) || /* @__PURE__ */ _("p", null, INLINE_ERROR);
    return /* @__PURE__ */ _(ErrorBoundary, { context, didCatch: ({ message }) => didCatch(message), fallback: fallbackElement }, children);
  }

  // pages/history/app/index.js
  async function init(root2, messaging2, baseEnvironment2) {
    const result = await callWithRetry(() => messaging2.initialSetup());
    if ("error" in result) {
      throw new Error(result.error);
    }
    const init2 = result.value;
    const environment = baseEnvironment2.withEnv(init2.env).withLocale(init2.locale).withLocale(baseEnvironment2.urlParams.get("locale")).withTextLength(baseEnvironment2.urlParams.get("textLength")).withDisplay(baseEnvironment2.urlParams.get("display"));
    const settings = new Settings({}).withPlatformName(baseEnvironment2.injectName).withPlatformName(init2.platform?.name).withPlatformName(baseEnvironment2.urlParams.get("platform")).withDebounce(baseEnvironment2.urlParams.get("debounce")).withUrlDebounce(baseEnvironment2.urlParams.get("urlDebounce"));
    if (!window.__playwright_01) {
      console.log("initialSetup", init2);
      console.log("environment", environment);
      console.log("settings", settings);
    }
    const didCatchInit = (message) => {
      messaging2.reportInitException({ message });
    };
    applyDefaultStyles(init2.customizer?.defaultStyles);
    const strings = await getStrings(environment);
    const service = new HistoryService(messaging2);
    const query = paramsToQuery(environment.urlParams, "initial");
    const initial = await fetchInitial(query, service, didCatchInit);
    if (environment.display === "app") {
      E(
        /* @__PURE__ */ _(
          InlineErrorBoundary,
          {
            messaging: messaging2,
            context: "History view application",
            fallback: (message) => {
              return /* @__PURE__ */ _(AppLevelErrorBoundaryFallback, null, message);
            }
          },
          /* @__PURE__ */ _(
            EnvironmentProvider,
            {
              debugState: environment.debugState,
              injectName: environment.injectName,
              willThrow: environment.willThrow
            },
            /* @__PURE__ */ _(UpdateEnvironment, { search: window.location.search }),
            /* @__PURE__ */ _(TranslationProvider, { translationObject: strings, fallback: history_default, textLength: environment.textLength }, /* @__PURE__ */ _(MessagingContext2.Provider, { value: messaging2 }, /* @__PURE__ */ _(SettingsContext.Provider, { value: settings }, /* @__PURE__ */ _(QueryProvider, { query: query.query }, /* @__PURE__ */ _(HistoryServiceProvider, { service, initial }, /* @__PURE__ */ _(SelectionProvider, null, /* @__PURE__ */ _(App, null)))))))
          )
        ),
        root2
      );
    } else if (environment.display === "components") {
      E(
        /* @__PURE__ */ _(EnvironmentProvider, { debugState: false, injectName: environment.injectName }, /* @__PURE__ */ _(TranslationProvider, { translationObject: strings, fallback: history_default, textLength: environment.textLength }, /* @__PURE__ */ _(Components, null))),
        root2
      );
    }
  }
  function applyDefaultStyles(defaultStyles) {
    if (defaultStyles?.lightBackgroundColor) {
      document.body.style.setProperty("--default-light-background-color", defaultStyles.lightBackgroundColor);
    }
    if (defaultStyles?.darkBackgroundColor) {
      document.body.style.setProperty("--default-dark-background-color", defaultStyles.darkBackgroundColor);
    }
  }
  async function fetchInitial(query, service, didCatch) {
    try {
      return await service.getInitial(query);
    } catch (e4) {
      console.error(e4);
      didCatch(e4.message || String(e4));
      return {
        ranges: {
          ranges: [{ id: "all", count: 0 }]
        },
        query: {
          info: { query: { term: "" }, finished: true },
          results: [],
          lastQueryParams: null
        }
      };
    }
  }
  async function getStrings(environment) {
    return environment.locale === "en" ? history_default : await fetch(`./locales/${environment.locale}/history.json`).then((x3) => x3.json()).catch((e4) => {
      console.error("Could not load locale", environment.locale, e4);
      return history_default;
    });
  }

  // pages/history/app/mocks/mock-transport.js
  var url = new URL(window.location.href);

  // pages/history/src/index.js
  var HistoryPage = class {
    /**
     * @param {import("@duckduckgo/messaging").Messaging} messaging
     */
    constructor(messaging2) {
      this.messaging = createTypedMessages(this, messaging2);
    }
    /**
     * Sends an initial message to the native layer. This is the opportunity for the native layer
     * to provide the initial state of the application or any configuration, for example:
     *
     * ```json
     * {
     *   "env": "development",
     *   "locale": "en"
     * }
     * ```
     *
     * @returns {Promise<import('../types/history.js').InitialSetupResponse>}
     */
    initialSetup() {
      return this.messaging.request("initialSetup");
    }
    /**
     * This will be sent if the application has loaded, but a client-side error
     * has occurred that cannot be recovered from
     * @param {{message: string}} params
     */
    reportPageException(params) {
      this.messaging.notify("reportPageException", params);
    }
    /**
     * This will be sent if the application fails to load.
     * @param {{message: string}} params
     */
    reportInitException(params) {
      this.messaging.notify("reportInitException", params);
    }
  };
  var baseEnvironment = new Environment().withInjectName("apple").withEnv("production");
  var messaging = createSpecialPageMessaging({
    injectName: baseEnvironment.injectName,
    env: baseEnvironment.env,
    pageName: (
      /** @type {string} */
      "history"
    ),
    mockTransport: () => {
      if (baseEnvironment.injectName !== "integration") return null;
      let mock = null;
      return mock;
    }
  });
  var historyPage = new HistoryPage(messaging);
  var root = document.querySelector("#app");
  if (!root) {
    document.documentElement.dataset.fatalError = "true";
    E("Fatal: #app missing", document.body);
    throw new Error("Missing #app");
  }
  init(root, historyPage, baseEnvironment).catch((e4) => {
    console.error(e4);
    const msg = typeof e4?.message === "string" ? e4.message : "unknown init error";
    historyPage.reportInitException({ message: msg });
    document.documentElement.dataset.fatalError = "true";
    const element = /* @__PURE__ */ _(k, null, /* @__PURE__ */ _("div", { style: "padding: 1rem;" }, /* @__PURE__ */ _("p", null, /* @__PURE__ */ _("strong", null, "A fatal error occurred:")), /* @__PURE__ */ _("br", null), /* @__PURE__ */ _("pre", { style: { whiteSpace: "prewrap", overflow: "auto" } }, /* @__PURE__ */ _("code", null, JSON.stringify({ message: e4.message }, null, 2)))));
    E(element, document.body);
  });
})();
/*! Bundled license information:

classnames/index.js:
  (*!
  	Copyright (c) 2018 Jed Watson.
  	Licensed under the MIT License (MIT), see
  	http://jedwatson.github.io/classnames
  *)
*/
