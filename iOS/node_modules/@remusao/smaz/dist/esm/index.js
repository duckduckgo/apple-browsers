import { SmazCompress } from '@remusao/smaz-compress';
import { SmazDecompress } from '@remusao/smaz-decompress';
export class Smaz {
    constructor(codebook, maxSize = 30000) {
        this.codebook = codebook;
        this.compressor = new SmazCompress(codebook, maxSize);
        this.decompressor = new SmazDecompress(codebook);
    }
    compress(str) {
        return this.compressor.compress(str);
    }
    getCompressedSize(str) {
        return this.compressor.getCompressedSize(str);
    }
    decompress(buffer) {
        return this.decompressor.decompress(buffer);
    }
}
const dictionary = ' ;the;e;t;a;of;o;and;i;n;s;e ;r; th; t;in;he;th;h;he ;to;\r\n;l;s ;d; a;an;er;c; o;d ;on; of;re;of ;t ;, ;is;u;at;   ;n ;or;which;f;m;as;it;that;\n;was;en;  ; w;es; an; i;f ;g;p;nd; s;nd ;ed ;w;ed;http://;https://;for;te;ing;y ;The; c;ti;r ;his;st; in;ar;nt;,; to;y;ng; h;with;le;al;to ;b;ou;be;were; b;se;o ;ent;ha;ng ;their;";hi;from; f;in ;de;ion;me;v;.;ve;all;re ;ri;ro;is ;co;f t;are;ea;. ;her; m;er ; p;es ;by;they;di;ra;ic;not;s, ;d t;at ;ce;la;h ;ne;as ;tio;on ;n t;io;we; a ;om;, a;s o;ur;li;ll;ch;had;this;e t;g ;e\r\n; wh;ere; co;e o;a ;us; d;ss;\n\r\n;\r\n\r;="; be; e;s a;ma;one;t t;or ;but;el;so;l ;e s;s,;no;ter; wa;iv;ho;e a; r;hat;s t;ns;ch ;wh;tr;ut;/;have;ly ;ta; ha; on;tha;-; l;ati;en ;pe; re;there;ass;si; fo;wa;ec;our;who;its;z;fo;rs;>;ot;un;<;im;th ;nc;ate;><;ver;ad; we;ly;ee; n;id; cl;ac;il;</;rt; wi;div;e, ; it;whi; ma;ge;x;e c;men;.com'.split(";");
let SMAZ;
function getDefaultSmaz() {
    if (SMAZ === undefined) {
        SMAZ = new Smaz(dictionary);
    }
    return SMAZ;
}
export function decompress(array) {
    return getDefaultSmaz().decompress(array);
}
export function compress(str) {
    return getDefaultSmaz().compress(str);
}
export function getCompressedSize(str) {
    return getDefaultSmaz().getCompressedSize(str);
}
//# sourceMappingURL=index.js.map