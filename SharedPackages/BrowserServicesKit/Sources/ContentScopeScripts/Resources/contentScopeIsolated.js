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
  var __require = /* @__PURE__ */ ((x2) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x2, {
    get: (a2, b2) => (typeof require !== "undefined" ? require : a2)[b2]
  }) : x2)(function(x2) {
    if (typeof require !== "undefined") return require.apply(this, arguments);
    throw Error('Dynamic require of "' + x2 + '" is not supported');
  });
  var __esm = (fn, res) => function __init() {
    return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
  };
  var __commonJS = (cb, mod) => function __require2() {
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

  // <define:import.meta.trackerLookup>
  var define_import_meta_trackerLookup_default;
  var init_define_import_meta_trackerLookup = __esm({
    "<define:import.meta.trackerLookup>"() {
      define_import_meta_trackerLookup_default = { org: { cdn77: { rsc: { "1558334541": 1 } }, adsrvr: 1, ampproject: 1, "browser-update": 1, flowplayer: 1, "privacy-center": 1, webvisor: 1, framasoft: 1, "do-not-tracker": 1, trackersimulator: 1 }, io: { "1dmp": 1, "1rx": 1, "4dex": 1, adnami: 1, aidata: 1, arcspire: 1, bidr: 1, branch: 1, center: 1, cloudimg: 1, concert: 1, connectad: 1, cordial: 1, dcmn: 1, extole: 1, getblue: 1, hbrd: 1, instana: 1, karte: 1, leadsmonitor: 1, litix: 1, lytics: 1, marchex: 1, mediago: 1, mrf: 1, narrative: 1, ntv: 1, optad360: 1, oracleinfinity: 1, oribi: 1, "p-n": 1, personalizer: 1, pghub: 1, piano: 1, powr: 1, pzz: 1, searchspring: 1, segment: 1, siteimproveanalytics: 1, sspinc: 1, t13: 1, webgains: 1, wovn: 1, yellowblue: 1, zprk: 1, axept: 1, akstat: 1, clarium: 1, hotjar: 1 }, com: { "2020mustang": 1, "33across": 1, "360yield": 1, "3lift": 1, "4dsply": 1, "4strokemedia": 1, "8353e36c2a": 1, "a-mx": 1, a2z: 1, aamsitecertifier: 1, absorbingband: 1, abstractedauthority: 1, abtasty: 1, acexedge: 1, acidpigs: 1, acsbapp: 1, acuityplatform: 1, "ad-score": 1, "ad-stir": 1, adalyser: 1, adapf: 1, adara: 1, adblade: 1, addthis: 1, addtoany: 1, adelixir: 1, adentifi: 1, adextrem: 1, adgrx: 1, adhese: 1, adition: 1, adkernel: 1, adlightning: 1, adlooxtracking: 1, admanmedia: 1, admedo: 1, adnium: 1, "adnxs-simple": 1, adnxs: 1, adobedtm: 1, adotmob: 1, adpone: 1, adpushup: 1, adroll: 1, adrta: 1, "ads-twitter": 1, "ads3-adnow": 1, adsafeprotected: 1, adstanding: 1, adswizz: 1, adtdp: 1, adtechus: 1, adtelligent: 1, adthrive: 1, adtlgc: 1, adtng: 1, adultfriendfinder: 1, advangelists: 1, adventive: 1, adventori: 1, advertising: 1, aegpresents: 1, affinity: 1, affirm: 1, agilone: 1, agkn: 1, aimbase: 1, albacross: 1, alcmpn: 1, alexametrics: 1, alicdn: 1, alikeaddition: 1, aliveachiever: 1, aliyuncs: 1, alluringbucket: 1, aloofvest: 1, "amazon-adsystem": 1, amazon: 1, ambiguousafternoon: 1, amplitude: 1, "analytics-egain": 1, aniview: 1, annoyedairport: 1, annoyingclover: 1, anyclip: 1, anymind360: 1, "app-us1": 1, appboycdn: 1, appdynamics: 1, appsflyer: 1, aralego: 1, aspiringattempt: 1, aswpsdkus: 1, atemda: 1, att: 1, attentivemobile: 1, attractionbanana: 1, audioeye: 1, audrte: 1, automaticside: 1, avanser: 1, avmws: 1, aweber: 1, aweprt: 1, azure: 1, b0e8: 1, badgevolcano: 1, bagbeam: 1, ballsbanana: 1, bandborder: 1, batch: 1, bawdybalance: 1, bc0a: 1, bdstatic: 1, bedsberry: 1, beginnerpancake: 1, benchmarkemail: 1, betweendigital: 1, bfmio: 1, bidtheatre: 1, billowybelief: 1, bimbolive: 1, bing: 1, bizographics: 1, bizrate: 1, bkrtx: 1, blismedia: 1, blogherads: 1, bluecava: 1, bluekai: 1, blushingbread: 1, boatwizard: 1, boilingcredit: 1, boldchat: 1, booking: 1, borderfree: 1, bounceexchange: 1, brainlyads: 1, "brand-display": 1, brandmetrics: 1, brealtime: 1, brightfunnel: 1, brightspotcdn: 1, btloader: 1, btstatic: 1, bttrack: 1, btttag: 1, bumlam: 1, butterbulb: 1, buttonladybug: 1, buzzfeed: 1, buzzoola: 1, byside: 1, c3tag: 1, cabnnr: 1, calculatorstatement: 1, callrail: 1, calltracks: 1, capablecup: 1, "captcha-delivery": 1, carpentercomparison: 1, cartstack: 1, carvecakes: 1, casalemedia: 1, cattlecommittee: 1, cdninstagram: 1, cdnwidget: 1, channeladvisor: 1, chargecracker: 1, chartbeat: 1, chatango: 1, chaturbate: 1, cheqzone: 1, cherriescare: 1, chickensstation: 1, childlikecrowd: 1, childlikeform: 1, chocolateplatform: 1, cintnetworks: 1, circlelevel: 1, "ck-ie": 1, clcktrax: 1, cleanhaircut: 1, clearbit: 1, clearbitjs: 1, clickagy: 1, clickcease: 1, clickcertain: 1, clicktripz: 1, clientgear: 1, cloudflare: 1, cloudflareinsights: 1, cloudflarestream: 1, cobaltgroup: 1, cobrowser: 1, cognitivlabs: 1, colossusssp: 1, combativecar: 1, comm100: 1, googleapis: { commondatastorage: 1, imasdk: 1, storage: 1, fonts: 1, maps: 1, www: 1 }, "company-target": 1, condenastdigital: 1, confusedcart: 1, connatix: 1, contextweb: 1, conversionruler: 1, convertkit: 1, convertlanguage: 1, cootlogix: 1, coveo: 1, cpmstar: 1, cquotient: 1, crabbychin: 1, cratecamera: 1, crazyegg: 1, "creative-serving": 1, creativecdn: 1, criteo: 1, crowdedmass: 1, crowdriff: 1, crownpeak: 1, crsspxl: 1, ctnsnet: 1, cudasvc: 1, cuddlethehyena: 1, cumbersomecarpenter: 1, curalate: 1, curvedhoney: 1, cushiondrum: 1, cutechin: 1, cxense: 1, d28dc30335: 1, dailymotion: 1, damdoor: 1, dampdock: 1, dapperfloor: 1, "datadoghq-browser-agent": 1, decisivebase: 1, deepintent: 1, defybrick: 1, delivra: 1, demandbase: 1, detectdiscovery: 1, devilishdinner: 1, dimelochat: 1, disagreeabledrop: 1, discreetfield: 1, disqus: 1, dmpxs: 1, dockdigestion: 1, dotomi: 1, doubleverify: 1, drainpaste: 1, dramaticdirection: 1, driftt: 1, dtscdn: 1, dtscout: 1, dwin1: 1, dynamics: 1, dynamicyield: 1, dynatrace: 1, ebaystatic: 1, ecal: 1, eccmp: 1, elfsight: 1, elitrack: 1, eloqua: 1, en25: 1, encouragingthread: 1, enormousearth: 1, ensighten: 1, enviousshape: 1, eqads: 1, "ero-advertising": 1, esputnik: 1, evergage: 1, evgnet: 1, exdynsrv: 1, exelator: 1, exoclick: 1, exosrv: 1, expansioneggnog: 1, expedia: 1, expertrec: 1, exponea: 1, exponential: 1, extole: 1, ezodn: 1, ezoic: 1, ezoiccdn: 1, facebook: 1, "facil-iti": 1, fadewaves: 1, fallaciousfifth: 1, farmergoldfish: 1, "fastly-insights": 1, fearlessfaucet: 1, fiftyt: 1, financefear: 1, fitanalytics: 1, five9: 1, fixedfold: 1, fksnk: 1, flashtalking: 1, flipp: 1, flowerstreatment: 1, floweryflavor: 1, flutteringfireman: 1, "flux-cdn": 1, foresee: 1, fortunatemark: 1, fouanalytics: 1, fox: 1, fqtag: 1, frailfruit: 1, freezingbuilding: 1, fronttoad: 1, fullstory: 1, functionalfeather: 1, fuzzybasketball: 1, gammamaximum: 1, gbqofs: 1, geetest: 1, geistm: 1, geniusmonkey: 1, "geoip-js": 1, getbread: 1, getcandid: 1, getclicky: 1, getdrip: 1, getelevar: 1, getrockerbox: 1, getshogun: 1, getsitecontrol: 1, giraffepiano: 1, glassdoor: 1, gloriousbeef: 1, godpvqnszo: 1, "google-analytics": 1, google: 1, googleadservices: 1, googlehosted: 1, googleoptimize: 1, googlesyndication: 1, googletagmanager: 1, googletagservices: 1, gorgeousedge: 1, govx: 1, grainmass: 1, greasysquare: 1, greylabeldelivery: 1, groovehq: 1, growsumo: 1, gstatic: 1, "guarantee-cdn": 1, guiltlessbasketball: 1, gumgum: 1, haltingbadge: 1, hammerhearing: 1, handsomelyhealth: 1, harborcaption: 1, hawksearch: 1, amazonaws: { "us-east-2": { s3: { "hb-obv2": 1 } } }, heapanalytics: 1, hellobar: 1, hhbypdoecp: 1, hiconversion: 1, highwebmedia: 1, histats: 1, hlserve: 1, hocgeese: 1, hollowafterthought: 1, honorableland: 1, hotjar: 1, hp: 1, "hs-banner": 1, htlbid: 1, htplayground: 1, hubspot: 1, "ib-ibi": 1, "id5-sync": 1, igodigital: 1, iheart: 1, iljmp: 1, illiweb: 1, impactcdn: 1, "impactradius-event": 1, impressionmonster: 1, improvedcontactform: 1, improvedigital: 1, imrworldwide: 1, indexww: 1, infolinks: 1, infusionsoft: 1, inmobi: 1, inq: 1, "inside-graph": 1, instagram: 1, intentiq: 1, intergient: 1, investingchannel: 1, invocacdn: 1, iperceptions: 1, iplsc: 1, ipredictive: 1, iteratehq: 1, ivitrack: 1, j93557g: 1, jaavnacsdw: 1, jimstatic: 1, journity: 1, js7k: 1, jscache: 1, juiceadv: 1, juicyads: 1, justanswer: 1, justpremium: 1, jwpcdn: 1, kakao: 1, kampyle: 1, kargo: 1, kissmetrics: 1, klarnaservices: 1, klaviyo: 1, knottyswing: 1, krushmedia: 1, ktkjmp: 1, kxcdn: 1, laboredlocket: 1, ladesk: 1, ladsp: 1, laughablelizards: 1, leadsrx: 1, lendingtree: 1, levexis: 1, liadm: 1, licdn: 1, lightboxcdn: 1, lijit: 1, linkedin: 1, linksynergy: 1, "list-manage": 1, listrakbi: 1, livechatinc: 1, livejasmin: 1, localytics: 1, loggly: 1, loop11: 1, looseloaf: 1, lovelydrum: 1, lunchroomlock: 1, lwonclbench: 1, macromill: 1, maddeningpowder: 1, mailchimp: 1, mailchimpapp: 1, mailerlite: 1, "maillist-manage": 1, marinsm: 1, marketiq: 1, marketo: 1, marphezis: 1, marriedbelief: 1, materialparcel: 1, matheranalytics: 1, mathtag: 1, maxmind: 1, mczbf: 1, measlymiddle: 1, medallia: 1, meddleplant: 1, media6degrees: 1, mediacategory: 1, mediavine: 1, mediawallahscript: 1, medtargetsystem: 1, megpxs: 1, memberful: 1, memorizematch: 1, mentorsticks: 1, metaffiliation: 1, metricode: 1, metricswpsh: 1, mfadsrvr: 1, mgid: 1, micpn: 1, microadinc: 1, "minutemedia-prebid": 1, minutemediaservices: 1, mixpo: 1, mkt932: 1, mktoresp: 1, mktoweb: 1, ml314: 1, moatads: 1, mobtrakk: 1, monsido: 1, mookie1: 1, motionflowers: 1, mountain: 1, mouseflow: 1, mpeasylink: 1, mql5: 1, mrtnsvr: 1, murdoog: 1, mxpnl: 1, mybestpro: 1, myregistry: 1, nappyattack: 1, navistechnologies: 1, neodatagroup: 1, nervoussummer: 1, netmng: 1, newrelic: 1, newscgp: 1, nextdoor: 1, ninthdecimal: 1, nitropay: 1, noibu: 1, nondescriptnote: 1, nosto: 1, npttech: 1, ntvpwpush: 1, nuance: 1, nutritiousbean: 1, nxsttv: 1, omappapi: 1, omnisnippet1: 1, omnisrc: 1, omnitagjs: 1, ondemand: 1, oneall: 1, onesignal: 1, "onetag-sys": 1, "oo-syringe": 1, ooyala: 1, opecloud: 1, opentext: 1, opera: 1, opmnstr: 1, "opti-digital": 1, optimicdn: 1, optimizely: 1, optinmonster: 1, optmnstr: 1, optmstr: 1, optnmnstr: 1, optnmstr: 1, osano: 1, "otm-r": 1, outbrain: 1, overconfidentfood: 1, ownlocal: 1, pailpatch: 1, panickypancake: 1, panoramicplane: 1, parastorage: 1, pardot: 1, parsely: 1, partplanes: 1, patreon: 1, paypal: 1, pbstck: 1, pcmag: 1, peerius: 1, perfdrive: 1, perfectmarket: 1, permutive: 1, picreel: 1, pinterest: 1, pippio: 1, piwikpro: 1, pixlee: 1, placidperson: 1, pleasantpump: 1, plotrabbit: 1, pluckypocket: 1, pocketfaucet: 1, possibleboats: 1, postaffiliatepro: 1, postrelease: 1, potatoinvention: 1, powerfulcopper: 1, predictplate: 1, prepareplanes: 1, pricespider: 1, priceypies: 1, pricklydebt: 1, profusesupport: 1, proofpoint: 1, protoawe: 1, providesupport: 1, pswec: 1, psychedelicarithmetic: 1, psyma: 1, ptengine: 1, publir: 1, pubmatic: 1, pubmine: 1, pubnation: 1, qualaroo: 1, qualtrics: 1, quantcast: 1, quantserve: 1, quantummetric: 1, quietknowledge: 1, quizzicalpartner: 1, quizzicalzephyr: 1, quora: 1, r42tag: 1, radiateprose: 1, railwayreason: 1, rakuten: 1, rambunctiousflock: 1, rangeplayground: 1, "rating-widget": 1, realsrv: 1, rebelswing: 1, reconditerake: 1, reconditerespect: 1, recruitics: 1, reddit: 1, redditstatic: 1, rehabilitatereason: 1, repeatsweater: 1, reson8: 1, resonantrock: 1, resonate: 1, responsiveads: 1, restrainstorm: 1, restructureinvention: 1, retargetly: 1, revcontent: 1, rezync: 1, rfihub: 1, rhetoricalloss: 1, richaudience: 1, righteouscrayon: 1, rightfulfall: 1, riotgames: 1, riskified: 1, rkdms: 1, rlcdn: 1, rmtag: 1, rogersmedia: 1, rokt: 1, route: 1, rtbsystem: 1, rubiconproject: 1, ruralrobin: 1, "s-onetag": 1, saambaa: 1, sablesong: 1, "sail-horizon": 1, salesforceliveagent: 1, samestretch: 1, sascdn: 1, satisfycork: 1, savoryorange: 1, scarabresearch: 1, scaredsnakes: 1, scaredsong: 1, scaredstomach: 1, scarfsmash: 1, scene7: 1, scholarlyiq: 1, scintillatingsilver: 1, scorecardresearch: 1, screechingstove: 1, screenpopper: 1, scribblestring: 1, sddan: 1, seatsmoke: 1, securedvisit: 1, seedtag: 1, sefsdvc: 1, segment: 1, sekindo: 1, selectivesummer: 1, selfishsnake: 1, servebom: 1, servedbyadbutler: 1, servenobid: 1, serverbid: 1, "serving-sys": 1, shakegoldfish: 1, shamerain: 1, shapecomb: 1, shappify: 1, shareaholic: 1, sharethis: 1, sharethrough: 1, shopifyapps: 1, shopperapproved: 1, shrillspoon: 1, sibautomation: 1, sicksmash: 1, signifyd: 1, singroot: 1, site: 1, siteimprove: 1, siteimproveanalytics: 1, sitescout: 1, sixauthority: 1, skillfuldrop: 1, skimresources: 1, skisofa: 1, "sli-spark": 1, slickstream: 1, slopesoap: 1, smadex: 1, smartadserver: 1, smashquartz: 1, smashsurprise: 1, smg: 1, smilewanted: 1, smoggysnakes: 1, snapchat: 1, snapkit: 1, snigelweb: 1, socdm: 1, sojern: 1, songsterritory: 1, sonobi: 1, soundstocking: 1, spectacularstamp: 1, speedcurve: 1, sphereup: 1, spiceworks: 1, spookyexchange: 1, spookyskate: 1, spookysleet: 1, sportradarserving: 1, sportslocalmedia: 1, spotxchange: 1, springserve: 1, srvmath: 1, "ssl-images-amazon": 1, stackadapt: 1, stakingsmile: 1, statcounter: 1, steadfastseat: 1, steadfastsound: 1, steadfastsystem: 1, steelhousemedia: 1, steepsquirrel: 1, stereotypedsugar: 1, stickyadstv: 1, stiffgame: 1, stingycrush: 1, straightnest: 1, stripchat: 1, strivesquirrel: 1, strokesystem: 1, stupendoussleet: 1, stupendoussnow: 1, stupidscene: 1, sulkycook: 1, sumo: 1, sumologic: 1, sundaysky: 1, superficialeyes: 1, superficialsquare: 1, surveymonkey: 1, survicate: 1, svonm: 1, swankysquare: 1, symantec: 1, taboola: 1, tailtarget: 1, talkable: 1, tamgrt: 1, tangycover: 1, taobao: 1, tapad: 1, tapioni: 1, taptapnetworks: 1, taskanalytics: 1, tealiumiq: 1, "techlab-cdn": 1, technoratimedia: 1, techtarget: 1, tediousticket: 1, teenytinyshirt: 1, tendertest: 1, "the-ozone-project": 1, theadex: 1, themoneytizer: 1, theplatform: 1, thestar: 1, thinkitten: 1, threetruck: 1, thrtle: 1, tidaltv: 1, tidiochat: 1, tiktok: 1, tinypass: 1, tiqcdn: 1, tiresomethunder: 1, trackjs: 1, traffichaus: 1, trafficjunky: 1, trafmag: 1, travelaudience: 1, treasuredata: 1, tremorhub: 1, trendemon: 1, tribalfusion: 1, trovit: 1, trueleadid: 1, truoptik: 1, truste: 1, trustpilot: 1, trvdp: 1, tsyndicate: 1, tubemogul: 1, turn: 1, tvpixel: 1, tvsquared: 1, tweakwise: 1, twitter: 1, tynt: 1, typicalteeth: 1, u5e: 1, ubembed: 1, uidapi: 1, ultraoranges: 1, unbecominglamp: 1, unbxdapi: 1, undertone: 1, uninterestedquarter: 1, unpkg: 1, unrulymedia: 1, unwieldyhealth: 1, unwieldyplastic: 1, upsellit: 1, urbanairship: 1, usabilla: 1, usbrowserspeed: 1, usemessages: 1, userreport: 1, uservoice: 1, valuecommerce: 1, vengefulgrass: 1, vidazoo: 1, videoplayerhub: 1, vidoomy: 1, viglink: 1, visualwebsiteoptimizer: 1, vivaclix: 1, vk: 1, vlitag: 1, voicefive: 1, volatilevessel: 1, voraciousgrip: 1, voxmedia: 1, vrtcal: 1, w3counter: 1, walkme: 1, warmafterthought: 1, warmquiver: 1, webcontentassessor: 1, webengage: 1, webeyez: 1, webtraxs: 1, "webtrends-optimize": 1, webtrends: 1, wgplayer: 1, woosmap: 1, worldoftulo: 1, wpadmngr: 1, wpshsdk: 1, wpushsdk: 1, wsod: 1, "wt-safetag": 1, wysistat: 1, xg4ken: 1, xiti: 1, xlirdr: 1, xlivrdr: 1, "xnxx-cdn": 1, "y-track": 1, yahoo: 1, yandex: 1, yieldmo: 1, yieldoptimizer: 1, yimg: 1, yotpo: 1, yottaa: 1, "youtube-nocookie": 1, youtube: 1, zemanta: 1, zendesk: 1, zeotap: 1, zestycrime: 1, zonos: 1, zoominfo: 1, zopim: 1, createsend1: 1, veoxa: 1, parchedsofa: 1, sooqr: 1, adtraction: 1, addthisedge: 1, adsymptotic: 1, bootstrapcdn: 1, bugsnag: 1, dmxleo: 1, dtssrv: 1, fontawesome: 1, "hs-scripts": 1, jwpltx: 1, nereserv: 1, onaudience: 1, outbrainimg: 1, quantcount: 1, rtactivate: 1, shopifysvc: 1, stripe: 1, twimg: 1, vimeo: 1, vimeocdn: 1, wp: 1, "2znp09oa": 1, "4jnzhl0d0": 1, "6ldu6qa": 1, "82o9v830": 1, abilityscale: 1, aboardamusement: 1, aboardlevel: 1, abovechat: 1, abruptroad: 1, absentairport: 1, absorbingcorn: 1, absorbingprison: 1, abstractedamount: 1, absurdapple: 1, abundantcoin: 1, acceptableauthority: 1, accurateanimal: 1, accuratecoal: 1, achieverknee: 1, acidicstraw: 1, acridangle: 1, acridtwist: 1, actoramusement: 1, actuallysheep: 1, actuallysnake: 1, actuallything: 1, adamantsnail: 1, addictedattention: 1, adorableanger: 1, adorableattention: 1, adventurousamount: 1, afraidlanguage: 1, aftermathbrother: 1, agilebreeze: 1, agreeablearch: 1, agreeabletouch: 1, aheadday: 1, aheadgrow: 1, aheadmachine: 1, ak0gsh40: 1, alertarithmetic: 1, aliasanvil: 1, alleythecat: 1, aloofmetal: 1, alpineactor: 1, ambientdusk: 1, ambientlagoon: 1, ambiguousanger: 1, ambiguousdinosaurs: 1, ambiguousincome: 1, ambrosialsummit: 1, amethystzenith: 1, amuckafternoon: 1, amusedbucket: 1, analogwonder: 1, analyzecorona: 1, ancientact: 1, annoyingacoustics: 1, anxiousapples: 1, aquaticowl: 1, ar1nvz5: 1, archswimming: 1, aromamirror: 1, arrivegrowth: 1, artthevoid: 1, aspiringapples: 1, aspiringtoy: 1, astonishingfood: 1, astralhustle: 1, astrallullaby: 1, attendchase: 1, attractivecap: 1, audioarctic: 1, automaticturkey: 1, availablerest: 1, avalonalbum: 1, averageactivity: 1, awarealley: 1, awesomeagreement: 1, awzbijw: 1, axiomaticalley: 1, axiomaticanger: 1, azuremystique: 1, backupcat: 1, badgeboat: 1, badgerabbit: 1, baitbaseball: 1, balloonbelieve: 1, bananabarrel: 1, barbarousbase: 1, basilfish: 1, basketballbelieve: 1, baskettexture: 1, bawdybeast: 1, beamvolcano: 1, beancontrol: 1, bearmoonlodge: 1, beetleend: 1, begintrain: 1, berserkhydrant: 1, bespokesandals: 1, bestboundary: 1, bewilderedbattle: 1, bewilderedblade: 1, bhcumsc: 1, bikepaws: 1, bikesboard: 1, billowybead: 1, binspiredtees: 1, birthdaybelief: 1, blackbrake: 1, bleachbubble: 1, bleachscarecrow: 1, bleedlight: 1, blesspizzas: 1, blissfulcrescendo: 1, blissfullagoon: 1, blueeyedblow: 1, blushingbeast: 1, boatsvest: 1, boilingbeetle: 1, boostbehavior: 1, boredcrown: 1, bouncyproperty: 1, boundarybusiness: 1, boundlessargument: 1, boundlessbrake: 1, boundlessveil: 1, brainybasin: 1, brainynut: 1, branchborder: 1, brandsfive: 1, brandybison: 1, bravebone: 1, bravecalculator: 1, breadbalance: 1, breakableinsurance: 1, breakfastboat: 1, breezygrove: 1, brianwould: 1, brighttoe: 1, briskstorm: 1, broadborder: 1, broadboundary: 1, broadcastbed: 1, broaddoor: 1, brotherslocket: 1, bruisebaseball: 1, brunchforher: 1, buildingknife: 1, bulbbait: 1, burgersalt: 1, burlywhistle: 1, burnbubble: 1, bushesbag: 1, bustlingbath: 1, bustlingbook: 1, butterburst: 1, cakesdrum: 1, calculatingcircle: 1, calculatingtoothbrush: 1, callousbrake: 1, calmcactus: 1, calypsocapsule: 1, cannonchange: 1, capablecows: 1, capriciouscorn: 1, captivatingcanyon: 1, captivatingillusion: 1, captivatingpanorama: 1, captivatingperformance: 1, carefuldolls: 1, caringcast: 1, caringzinc: 1, carloforward: 1, carscannon: 1, cartkitten: 1, catalogcake: 1, catschickens: 1, causecherry: 1, cautiouscamera: 1, cautiouscherries: 1, cautiouscrate: 1, cautiouscredit: 1, cavecurtain: 1, ceciliavenus: 1, celestialeuphony: 1, celestialquasar: 1, celestialspectra: 1, chaireggnog: 1, chairscrack: 1, chairsdonkey: 1, chalkoil: 1, changeablecats: 1, channelcamp: 1, charmingplate: 1, charscroll: 1, cheerycraze: 1, chessbranch: 1, chesscolor: 1, chesscrowd: 1, childlikeexample: 1, chilledliquid: 1, chingovernment: 1, chinsnakes: 1, chipperisle: 1, chivalrouscord: 1, chubbycreature: 1, chunkycactus: 1, cicdserver: 1, cinemabonus: 1, clammychicken: 1, cloisteredcord: 1, cloisteredcurve: 1, closedcows: 1, closefriction: 1, cloudhustles: 1, cloudjumbo: 1, clovercabbage: 1, clumsycar: 1, coatfood: 1, cobaltoverture: 1, coffeesidehustle: 1, coldbalance: 1, coldcreatives: 1, colorfulafterthought: 1, colossalclouds: 1, colossalcoat: 1, colossalcry: 1, combativedetail: 1, combbit: 1, combcattle: 1, combcompetition: 1, cometquote: 1, comfortablecheese: 1, comfygoodness: 1, companyparcel: 1, comparereaction: 1, compiledoctor: 1, concernedchange: 1, concernedchickens: 1, condemnedcomb: 1, conditionchange: 1, conditioncrush: 1, confesschairs: 1, configchain: 1, connectashelf: 1, consciouschairs: 1, consciouscheese: 1, consciousdirt: 1, consumerzero: 1, controlcola: 1, controlhall: 1, convertbatch: 1, cooingcoal: 1, coordinatedbedroom: 1, coordinatedcoat: 1, copycarpenter: 1, copyrightaccesscontrols: 1, coralreverie: 1, corgibeachday: 1, cosmicsculptor: 1, cosmosjackson: 1, courageousbaby: 1, coverapparatus: 1, coverlayer: 1, cozydusk: 1, cozyhillside: 1, cozytryst: 1, crackedsafe: 1, crafthenry: 1, crashchance: 1, craterbox: 1, creatorcherry: 1, creatorpassenger: 1, creaturecabbage: 1, crimsonmeadow: 1, critictruck: 1, crookedcreature: 1, cruisetourist: 1, cryptvalue: 1, crystalboulevard: 1, crystalstatus: 1, cubchannel: 1, cubepins: 1, cuddlycake: 1, cuddlylunchroom: 1, culturedcamera: 1, culturedfeather: 1, cumbersomecar: 1, cumbersomecloud: 1, curiouschalk: 1, curioussuccess: 1, curlycannon: 1, currentcollar: 1, curtaincows: 1, curvycord: 1, curvycry: 1, cushionpig: 1, cutcurrent: 1, cyclopsdial: 1, dailydivision: 1, damagedadvice: 1, damageddistance: 1, dancemistake: 1, dandydune: 1, dandyglow: 1, dapperdiscussion: 1, datastoried: 1, daughterstone: 1, daymodern: 1, dazzlingbook: 1, deafeningdock: 1, deafeningdowntown: 1, debonairdust: 1, debonairtree: 1, debugentity: 1, decidedrum: 1, decisivedrawer: 1, decisiveducks: 1, decoycreation: 1, deerbeginner: 1, defeatedbadge: 1, defensevest: 1, degreechariot: 1, delegatediscussion: 1, delicatecascade: 1, deliciousducks: 1, deltafault: 1, deluxecrate: 1, dependenttrip: 1, desirebucket: 1, desiredirt: 1, detailedgovernment: 1, detailedkitten: 1, detectdinner: 1, detourgame: 1, deviceseal: 1, deviceworkshop: 1, dewdroplagoon: 1, difficultfog: 1, digestiondrawer: 1, dinnerquartz: 1, diplomahawaii: 1, direfuldesk: 1, discreetquarter: 1, distributionneck: 1, distributionpocket: 1, distributiontomatoes: 1, disturbedquiet: 1, divehope: 1, dk4ywix: 1, dogsonclouds: 1, dollardelta: 1, doubledefend: 1, doubtdrawer: 1, dq95d35: 1, dreamycanyon: 1, driftpizza: 1, drollwharf: 1, drydrum: 1, dustydime: 1, dustyhammer: 1, eagereden: 1, eagerflame: 1, eagerknight: 1, earthyfarm: 1, eatablesquare: 1, echochief: 1, echoinghaven: 1, effervescentcoral: 1, effervescentvista: 1, effulgentnook: 1, effulgenttempest: 1, ejyymghi: 1, elasticchange: 1, elderlybean: 1, elderlytown: 1, elephantqueue: 1, elusivebreeze: 1, elusivecascade: 1, elysiantraverse: 1, embellishedmeadow: 1, embermosaic: 1, emberwhisper: 1, eminentbubble: 1, eminentend: 1, emptyescort: 1, enchantedskyline: 1, enchantingdiscovery: 1, enchantingenchantment: 1, enchantingmystique: 1, enchantingtundra: 1, enchantingvalley: 1, encourageshock: 1, endlesstrust: 1, endurablebulb: 1, energeticexample: 1, energeticladybug: 1, engineergrape: 1, engineertrick: 1, enigmaticblossom: 1, enigmaticcanyon: 1, enigmaticvoyage: 1, enormousfoot: 1, enterdrama: 1, entertainskin: 1, enthusiastictemper: 1, enviousthread: 1, equablekettle: 1, etherealbamboo: 1, ethereallagoon: 1, etherealpinnacle: 1, etherealquasar: 1, etherealripple: 1, evanescentedge: 1, evasivejar: 1, eventexistence: 1, exampleshake: 1, excitingtub: 1, exclusivebrass: 1, executeknowledge: 1, exhibitsneeze: 1, exquisiteartisanship: 1, extractobservation: 1, extralocker: 1, extramonies: 1, exuberantedge: 1, facilitatebreakfast: 1, fadechildren: 1, fadedsnow: 1, fairfeeling: 1, fairiesbranch: 1, fairytaleflame: 1, falseframe: 1, familiarrod: 1, fancyactivity: 1, fancydune: 1, fancygrove: 1, fangfeeling: 1, fantastictone: 1, farethief: 1, farshake: 1, farsnails: 1, fastenfather: 1, fasterfineart: 1, fasterjson: 1, fatcoil: 1, faucetfoot: 1, faultycanvas: 1, fearfulfish: 1, fearfulmint: 1, fearlesstramp: 1, featherstage: 1, feeblestamp: 1, feignedfaucet: 1, fernwaycloud: 1, fertilefeeling: 1, fewjuice: 1, fewkittens: 1, finalizeforce: 1, finestpiece: 1, finitecube: 1, firecatfilms: 1, fireworkcamp: 1, firstendpoint: 1, firstfrogs: 1, firsttexture: 1, fitmessage: 1, fivesidedsquare: 1, flakyfeast: 1, flameuncle: 1, flimsycircle: 1, flimsythought: 1, flippedfunnel: 1, floodprincipal: 1, flourishingcollaboration: 1, flourishingendeavor: 1, flourishinginnovation: 1, flourishingpartnership: 1, flowersornament: 1, flowerycreature: 1, floweryfact: 1, floweryoperation: 1, foambench: 1, followborder: 1, forecasttiger: 1, foretellfifth: 1, forevergears: 1, forgetfulflowers: 1, forgetfulsnail: 1, fractalcoast: 1, framebanana: 1, franticroof: 1, frantictrail: 1, frazzleart: 1, freakyglass: 1, frequentflesh: 1, friendlycrayon: 1, friendlyfold: 1, friendwool: 1, frightenedpotato: 1, frogator: 1, frogtray: 1, frugalfiestas: 1, fumblingform: 1, functionalcrown: 1, funoverbored: 1, funoverflow: 1, furnstudio: 1, furryfork: 1, furryhorses: 1, futuristicapparatus: 1, futuristicfairies: 1, futuristicfifth: 1, futuristicframe: 1, fuzzyaudio: 1, fuzzyerror: 1, gardenovens: 1, gaudyairplane: 1, geekactive: 1, generalprose: 1, generateoffice: 1, giantsvessel: 1, giddycoat: 1, gitcrumbs: 1, givevacation: 1, gladglen: 1, gladysway: 1, glamhawk: 1, gleamingcow: 1, gleaminghaven: 1, glisteningguide: 1, glisteningsign: 1, glitteringbrook: 1, glowingmeadow: 1, gluedpixel: 1, goldfishgrowth: 1, gondolagnome: 1, goodbark: 1, gracefulmilk: 1, grandfatherguitar: 1, gravitygive: 1, gravitykick: 1, grayoranges: 1, grayreceipt: 1, greyinstrument: 1, gripcorn: 1, groovyornament: 1, grouchybrothers: 1, grouchypush: 1, grumpydime: 1, grumpydrawer: 1, guardeddirection: 1, guardedschool: 1, guessdetail: 1, guidecent: 1, guildalpha: 1, gulliblegrip: 1, gustocooking: 1, gustygrandmother: 1, habitualhumor: 1, halcyoncanyon: 1, halcyonsculpture: 1, hallowedinvention: 1, haltingdivision: 1, haltinggold: 1, handleteeth: 1, handnorth: 1, handsomehose: 1, handsomeindustry: 1, handsomelythumb: 1, handsomeyam: 1, handyfield: 1, handyfireman: 1, handyincrease: 1, haplesshydrant: 1, haplessland: 1, happysponge: 1, harborcub: 1, harmonicbamboo: 1, harmonywing: 1, hatefulrequest: 1, headydegree: 1, headyhook: 1, healflowers: 1, hearinglizards: 1, heartbreakingmind: 1, hearthorn: 1, heavydetail: 1, heavyplayground: 1, helpcollar: 1, helpflame: 1, hfc195b: 1, highfalutinbox: 1, highfalutinhoney: 1, hilariouszinc: 1, historicalbeam: 1, homelycrown: 1, honeybulb: 1, honeywhipped: 1, honorablehydrant: 1, horsenectar: 1, hospitablehall: 1, hospitablehat: 1, howdyinbox: 1, humdrumhobbies: 1, humdrumtouch: 1, hurtgrape: 1, hypnoticwound: 1, hystericalcloth: 1, hystericalfinger: 1, idolscene: 1, idyllicjazz: 1, illinvention: 1, illustriousoatmeal: 1, immensehoney: 1, imminentshake: 1, importantmeat: 1, importedincrease: 1, importedinsect: 1, importlocate: 1, impossibleexpansion: 1, impossiblemove: 1, impulsejewel: 1, impulselumber: 1, incomehippo: 1, incompetentjoke: 1, inconclusiveaction: 1, infamousstream: 1, innocentlamp: 1, innocentwax: 1, inputicicle: 1, inquisitiveice: 1, inquisitiveinvention: 1, intelligentscissors: 1, intentlens: 1, interestdust: 1, internalcondition: 1, internalsink: 1, iotapool: 1, irritatingfog: 1, itemslice: 1, ivykiosk: 1, jadeitite: 1, jaderooster: 1, jailbulb: 1, joblessdrum: 1, jollylens: 1, joyfulkeen: 1, joyoussurprise: 1, jubilantaura: 1, jubilantcanyon: 1, jubilantcascade: 1, jubilantglimmer: 1, jubilanttempest: 1, jubilantwhisper: 1, justicejudo: 1, kaputquill: 1, keenquill: 1, kindhush: 1, kitesquirrel: 1, knitstamp: 1, laboredlight: 1, lameletters: 1, lamplow: 1, largebrass: 1, lasttaco: 1, leaplunchroom: 1, leftliquid: 1, lemonpackage: 1, lemonsandjoy: 1, liftedknowledge: 1, lightenafterthought: 1, lighttalon: 1, livelumber: 1, livelylaugh: 1, livelyreward: 1, livingsleet: 1, lizardslaugh: 1, loadsurprise: 1, lonelyflavor: 1, longingtrees: 1, lorenzourban: 1, losslace: 1, loudlunch: 1, loveseashore: 1, lp3tdqle: 1, ludicrousarch: 1, lumberamount: 1, luminousboulevard: 1, luminouscatalyst: 1, luminoussculptor: 1, lumpygnome: 1, lumpylumber: 1, lustroushaven: 1, lyricshook: 1, madebyintent: 1, magicaljoin: 1, magnetairport: 1, majesticmountainrange: 1, majesticwaterscape: 1, majesticwilderness: 1, maliciousmusic: 1, managedpush: 1, mantrafox: 1, marblediscussion: 1, markahouse: 1, markedmeasure: 1, marketspiders: 1, marriedmailbox: 1, marriedvalue: 1, massivemark: 1, materialisticmoon: 1, materialmilk: 1, materialplayground: 1, meadowlullaby: 1, meatydime: 1, mediatescarf: 1, mediumshort: 1, mellowhush: 1, mellowmailbox: 1, melodiouschorus: 1, melodiouscomposition: 1, meltmilk: 1, memopilot: 1, memorizeneck: 1, meremark: 1, merequartz: 1, merryopal: 1, merryvault: 1, messagenovice: 1, messyoranges: 1, mightyspiders: 1, mimosamajor: 1, mindfulgem: 1, minorcattle: 1, minusmental: 1, minuteburst: 1, miscreantmoon: 1, mistyhorizon: 1, mittencattle: 1, mixedreading: 1, modularmental: 1, monacobeatles: 1, moorshoes: 1, motionlessbag: 1, motionlessbelief: 1, motionlessmeeting: 1, movemeal: 1, muddledaftermath: 1, muddledmemory: 1, mundanenail: 1, mundanepollution: 1, mushywaste: 1, muteknife: 1, mutemailbox: 1, mysticalagoon: 1, naivestatement: 1, nappyneck: 1, neatshade: 1, nebulacrescent: 1, nebulajubilee: 1, nebulousamusement: 1, nebulousgarden: 1, nebulousquasar: 1, nebulousripple: 1, needlessnorth: 1, needyneedle: 1, neighborlywatch: 1, niftygraphs: 1, niftyhospital: 1, niftyjelly: 1, nightwound: 1, nimbleplot: 1, nocturnalloom: 1, nocturnalmystique: 1, noiselessplough: 1, nonchalantnerve: 1, nondescriptcrowd: 1, nondescriptstocking: 1, nostalgicknot: 1, nostalgicneed: 1, notifyglass: 1, nudgeduck: 1, nullnorth: 1, numberlessring: 1, numerousnest: 1, nuttyorganization: 1, oafishchance: 1, oafishobservation: 1, obscenesidewalk: 1, observantice: 1, oldfashionedoffer: 1, omgthink: 1, omniscientfeeling: 1, onlywoofs: 1, opalquill: 1, operationchicken: 1, operationnail: 1, oppositeoperation: 1, optimallimit: 1, opulentsylvan: 1, orientedargument: 1, orionember: 1, ourblogthing: 1, outgoinggiraffe: 1, outsidevibe: 1, outstandingincome: 1, outstandingsnails: 1, overkick: 1, overratedchalk: 1, oxygenfuse: 1, pailcrime: 1, painstakingpickle: 1, paintpear: 1, paleleaf: 1, pamelarandom: 1, panickycurtain: 1, parallelbulb: 1, pardonpopular: 1, parentpicture: 1, parsimoniouspolice: 1, passivepolo: 1, pastoralroad: 1, pawsnug: 1, peacefullimit: 1, pedromister: 1, pedropanther: 1, perceivequarter: 1, perkyjade: 1, petiteumbrella: 1, philippinch: 1, photographpan: 1, piespower: 1, piquantgrove: 1, piquantmeadow: 1, piquantpigs: 1, piquantprice: 1, piquantvortex: 1, pixeledhub: 1, pizzasnut: 1, placeframe: 1, placidactivity: 1, planebasin: 1, plantdigestion: 1, playfulriver: 1, plotparent: 1, pluckyzone: 1, poeticpackage: 1, pointdigestion: 1, pointlesshour: 1, pointlesspocket: 1, pointlessprofit: 1, pointlessrifle: 1, polarismagnet: 1, polishedcrescent: 1, polishedfolly: 1, politeplanes: 1, politicalflip: 1, politicalporter: 1, popplantation: 1, possiblepencil: 1, powderjourney: 1, powerfulblends: 1, preciousplanes: 1, prefixpatriot: 1, presetrabbits: 1, previousplayground: 1, previouspotato: 1, pricklypollution: 1, pristinegale: 1, probablepartner: 1, processplantation: 1, producepickle: 1, productsurfer: 1, profitrumour: 1, promiseair: 1, proofconvert: 1, propertypotato: 1, protestcopy: 1, psychedelicchess: 1, publicsofa: 1, puffyloss: 1, puffypaste: 1, puffypull: 1, puffypurpose: 1, pulsatingmeadow: 1, pumpedpancake: 1, pumpedpurpose: 1, punyplant: 1, puppytooth: 1, purposepipe: 1, quacksquirrel: 1, quaintcan: 1, quaintlake: 1, quantumlagoon: 1, quantumshine: 1, queenskart: 1, quillkick: 1, quirkybliss: 1, quirkysugar: 1, quixoticnebula: 1, rabbitbreath: 1, rabbitrifle: 1, radiantcanopy: 1, radiantlullaby: 1, railwaygiraffe: 1, raintwig: 1, rainyhand: 1, rainyrule: 1, rangecake: 1, raresummer: 1, reactjspdf: 1, readingguilt: 1, readymoon: 1, readysnails: 1, realizedoor: 1, realizerecess: 1, rebelclover: 1, rebelhen: 1, rebelsubway: 1, receiptcent: 1, receptiveink: 1, receptivereaction: 1, recessrain: 1, reconditeprison: 1, reflectivestatement: 1, refundradar: 1, regularplants: 1, regulatesleet: 1, relationrest: 1, reloadphoto: 1, rememberdiscussion: 1, rentinfinity: 1, replaceroute: 1, resonantbrush: 1, respectrain: 1, resplendentecho: 1, retrievemint: 1, rhetoricalactivity: 1, rhetoricalveil: 1, rhymezebra: 1, rhythmrule: 1, richstring: 1, rigidrobin: 1, rigidveil: 1, rigorlab: 1, ringplant: 1, ringsrecord: 1, ritzykey: 1, ritzyrepresentative: 1, ritzyveil: 1, rockpebbles: 1, rollconnection: 1, roofrelation: 1, roseincome: 1, rottenray: 1, rusticprice: 1, ruthlessdegree: 1, ruthlessmilk: 1, sableloss: 1, sablesmile: 1, sadloaf: 1, saffronrefuge: 1, sagargift: 1, saltsacademy: 1, samesticks: 1, samplesamba: 1, scarcecard: 1, scarceshock: 1, scarcesign: 1, scarcestructure: 1, scarcesurprise: 1, scaredcomfort: 1, scaredsidewalk: 1, scaredslip: 1, scaredsnake: 1, scaredswing: 1, scarefowl: 1, scatteredheat: 1, scatteredquiver: 1, scatteredstream: 1, scenicapparel: 1, scientificshirt: 1, scintillatingscissors: 1, scissorsstatement: 1, scrapesleep: 1, scratchsofa: 1, screechingfurniture: 1, screechingstocking: 1, scribbleson: 1, scrollservice: 1, scrubswim: 1, seashoresociety: 1, secondhandfall: 1, secretivesheep: 1, secretspiders: 1, secretturtle: 1, seedscissors: 1, seemlysuggestion: 1, selfishsea: 1, sendingspire: 1, sensorsmile: 1, separatesort: 1, seraphichorizon: 1, seraphicjubilee: 1, serendipityecho: 1, serenecascade: 1, serenepebble: 1, serenesurf: 1, serioussuit: 1, serpentshampoo: 1, settleshoes: 1, shadeship: 1, shaggytank: 1, shakyseat: 1, shakysurprise: 1, shakytaste: 1, shallowblade: 1, sharkskids: 1, sheargovernor: 1, shesubscriptions: 1, shinypond: 1, shirtsidewalk: 1, shiveringspot: 1, shiverscissors: 1, shockinggrass: 1, shockingship: 1, shredquiz: 1, shydinosaurs: 1, sierrakermit: 1, signaturepod: 1, siliconslow: 1, sillyscrew: 1, simplesidewalk: 1, simulateswing: 1, sincerebuffalo: 1, sincerepelican: 1, sinceresubstance: 1, sinkbooks: 1, sixscissors: 1, sizzlingsmoke: 1, slaysweater: 1, slimyscarf: 1, slinksuggestion: 1, smallershops: 1, smashshoe: 1, smilewound: 1, smilingcattle: 1, smilingswim: 1, smilingwaves: 1, smoggysongs: 1, smoggystation: 1, snacktoken: 1, snakemineral: 1, snakeslang: 1, sneakwind: 1, sneakystew: 1, snoresmile: 1, snowmentor: 1, soggysponge: 1, soggyzoo: 1, solarislabyrinth: 1, somberscarecrow: 1, sombersea: 1, sombersquirrel: 1, sombersticks: 1, sombersurprise: 1, soothingglade: 1, sophisticatedstove: 1, sordidsmile: 1, soresidewalk: 1, soresneeze: 1, sorethunder: 1, soretrain: 1, sortsail: 1, sortsummer: 1, sowlettuce: 1, spadelocket: 1, sparkgoal: 1, sparklingshelf: 1, specialscissors: 1, spellmist: 1, spellsalsa: 1, spiffymachine: 1, spirebaboon: 1, spookystitch: 1, spoonsilk: 1, spotlessstamp: 1, spottednoise: 1, springolive: 1, springsister: 1, springsnails: 1, sproutingbag: 1, sprydelta: 1, sprysummit: 1, spuriousair: 1, spuriousbase: 1, spurioussquirrel: 1, spuriousstranger: 1, spysubstance: 1, squalidscrew: 1, squeakzinc: 1, squealingturn: 1, stakingbasket: 1, stakingshock: 1, staleshow: 1, stalesummer: 1, starkscale: 1, startingcars: 1, statshunt: 1, statuesqueship: 1, stayaction: 1, steadycopper: 1, stealsteel: 1, steepscale: 1, steepsister: 1, stepcattle: 1, stepplane: 1, stepwisevideo: 1, stereoproxy: 1, stewspiders: 1, stiffstem: 1, stimulatingsneeze: 1, stingsquirrel: 1, stingyshoe: 1, stingyspoon: 1, stockingsleet: 1, stockingsneeze: 1, stomachscience: 1, stonechin: 1, stopstomach: 1, stormyachiever: 1, stormyfold: 1, strangeclocks: 1, strangersponge: 1, strangesink: 1, streetsort: 1, stretchsister: 1, stretchsneeze: 1, stretchsquirrel: 1, stripedbat: 1, strivesidewalk: 1, sturdysnail: 1, subletyoke: 1, sublimequartz: 1, subsequentswim: 1, substantialcarpenter: 1, substantialgrade: 1, succeedscene: 1, successfulscent: 1, suddensoda: 1, sugarfriction: 1, suggestionbridge: 1, summerobject: 1, sunshinegates: 1, superchichair: 1, superficialspring: 1, superviseshoes: 1, supportwaves: 1, suspectmark: 1, swellstocking: 1, swelteringsleep: 1, swingslip: 1, swordgoose: 1, syllablesight: 1, synonymousrule: 1, synonymoussticks: 1, synthesizescarecrow: 1, tackytrains: 1, tacojournal: 1, talltouch: 1, tangibleteam: 1, tangyamount: 1, tastelesstrees: 1, tastelesstrucks: 1, tastesnake: 1, tawdryson: 1, tearfulglass: 1, techconverter: 1, tediousbear: 1, tedioustooth: 1, teenytinycellar: 1, teenytinytongue: 1, telephoneapparatus: 1, tempertrick: 1, tempttalk: 1, temptteam: 1, terriblethumb: 1, terrifictooth: 1, testadmiral: 1, texturetrick: 1, therapeuticcars: 1, thickticket: 1, thicktrucks: 1, thingsafterthought: 1, thingstaste: 1, thinkitwice: 1, thirdrespect: 1, thirstytwig: 1, thomastorch: 1, thoughtlessknot: 1, thrivingmarketplace: 1, ticketaunt: 1, ticklesign: 1, tidymitten: 1, tightpowder: 1, tinyswans: 1, tinytendency: 1, tiredthroat: 1, toolcapital: 1, toomanyalts: 1, torpidtongue: 1, trackcaddie: 1, tradetooth: 1, trafficviews: 1, tranquilamulet: 1, tranquilarchipelago: 1, tranquilcan: 1, tranquilcanyon: 1, tranquilplume: 1, tranquilside: 1, tranquilveil: 1, tranquilveranda: 1, trappush: 1, treadbun: 1, tremendousearthquake: 1, tremendousplastic: 1, tremendoustime: 1, tritebadge: 1, tritethunder: 1, tritetongue: 1, troubledtail: 1, troubleshade: 1, truckstomatoes: 1, truculentrate: 1, tumbleicicle: 1, tuneupcoffee: 1, twistloss: 1, twistsweater: 1, typicalairplane: 1, ubiquitoussea: 1, ubiquitousyard: 1, ultravalid: 1, unablehope: 1, unaccountablecreator: 1, unaccountablepie: 1, unarmedindustry: 1, unbecominghall: 1, uncoveredexpert: 1, understoodocean: 1, unequalbrake: 1, unequaltrail: 1, unknowncontrol: 1, unknowncrate: 1, unknowntray: 1, untidyquestion: 1, untidyrice: 1, unusedstone: 1, unusualtitle: 1, unwieldyimpulse: 1, uppitytime: 1, uselesslumber: 1, validmemo: 1, vanfireworks: 1, vanishmemory: 1, velvetnova: 1, velvetquasar: 1, venomousvessel: 1, venusgloria: 1, verdantanswer: 1, verdantlabyrinth: 1, verdantloom: 1, verdantsculpture: 1, verseballs: 1, vibrantcelebration: 1, vibrantgale: 1, vibranthaven: 1, vibrantpact: 1, vibrantsundown: 1, vibranttalisman: 1, vibrantvale: 1, victoriousrequest: 1, virtualvincent: 1, vividcanopy: 1, vividfrost: 1, vividmeadow: 1, vividplume: 1, voicelessvein: 1, voidgoo: 1, volatileprofit: 1, waitingnumber: 1, wantingwindow: 1, warnwing: 1, washbanana: 1, wateryvan: 1, waterywave: 1, waterywrist: 1, wearbasin: 1, websitesdude: 1, wellgroomedapparel: 1, wellgroomedhydrant: 1, wellmadefrog: 1, westpalmweb: 1, whimsicalcanyon: 1, whimsicalgrove: 1, whineattempt: 1, whirlwealth: 1, whiskyqueue: 1, whisperingcascade: 1, whisperingcrib: 1, whisperingquasar: 1, whisperingsummit: 1, whispermeeting: 1, wildcommittee: 1, wirecomic: 1, wiredforcoffee: 1, wirypaste: 1, wistfulwaste: 1, wittypopcorn: 1, wittyshack: 1, workoperation: 1, worldlever: 1, worriednumber: 1, worriedwine: 1, wretchedfloor: 1, wrongpotato: 1, wrongwound: 1, wtaccesscontrol: 1, xovq5nemr: 1, yieldingwoman: 1, zbwp6ghm: 1, zephyrcatalyst: 1, zephyrlabyrinth: 1, zestyhorizon: 1, zestyrover: 1, zestywire: 1, zipperxray: 1, zonewedgeshaft: 1 }, net: { "2mdn": 1, "2o7": 1, "3gl": 1, "a-mo": 1, acint: 1, adform: 1, adhigh: 1, admixer: 1, adobedc: 1, adspeed: 1, adverticum: 1, apicit: 1, appier: 1, akamaized: { "assets-momentum": 1 }, aticdn: 1, edgekey: { au: 1, ca: 1, ch: 1, cn: 1, "com-v1": 1, es: 1, ihg: 1, in: 1, io: 1, it: 1, jp: 1, net: 1, org: 1, com: { scene7: 1 }, "uk-v1": 1, uk: 1 }, azure: 1, azurefd: 1, bannerflow: 1, "bf-tools": 1, bidswitch: 1, bitsngo: 1, blueconic: 1, boldapps: 1, buysellads: 1, cachefly: 1, cedexis: 1, certona: 1, "confiant-integrations": 1, contentsquare: 1, criteo: 1, crwdcntrl: 1, cloudfront: { d1af033869koo7: 1, d1cr9zxt7u0sgu: 1, d1s87id6169zda: 1, d1vg5xiq7qffdj: 1, d1y068gyog18cq: 1, d214hhm15p4t1d: 1, d21gpk1vhmjuf5: 1, d2zah9y47r7bi2: 1, d38b8me95wjkbc: 1, d38xvr37kwwhcm: 1, d3fv2pqyjay52z: 1, d3i4yxtzktqr9n: 1, d3odp2r1osuwn0: 1, d5yoctgpv4cpx: 1, d6tizftlrpuof: 1, dbukjj6eu5tsf: 1, dn0qt3r0xannq: 1, dsh7ky7308k4b: 1, d2g3ekl4mwm40k: 1 }, demdex: 1, dotmetrics: 1, doubleclick: 1, durationmedia: 1, "e-planning": 1, edgecastcdn: 1, emsecure: 1, episerver: 1, esm1: 1, eulerian: 1, everestjs: 1, everesttech: 1, eyeota: 1, ezoic: 1, fastly: { global: { shared: { f2: 1 }, sni: { j: 1 } }, map: { "prisa-us-eu": 1, scribd: 1 }, ssl: { global: { "qognvtzku-x": 1 } } }, facebook: 1, fastclick: 1, fonts: 1, azureedge: { "fp-cdn": 1, sdtagging: 1 }, fuseplatform: 1, fwmrm: 1, "go-mpulse": 1, hadronid: 1, "hs-analytics": 1, hsleadflows: 1, "im-apps": 1, impervadns: 1, iocnt: 1, iprom: 1, jsdelivr: 1, "kanade-ad": 1, krxd: 1, "line-scdn": 1, listhub: 1, livecom: 1, livedoor: 1, liveperson: 1, lkqd: 1, llnwd: 1, lpsnmedia: 1, magnetmail: 1, marketo: 1, maxymiser: 1, media: 1, microad: 1, mobon: 1, monetate: 1, mxptint: 1, myfonts: 1, myvisualiq: 1, naver: 1, "nr-data": 1, ojrq: 1, omtrdc: 1, onecount: 1, openx: 1, openxcdn: 1, opta: 1, owneriq: 1, pages02: 1, pages03: 1, pages04: 1, pages05: 1, pages06: 1, pages08: 1, pingdom: 1, pmdstatic: 1, popads: 1, popcash: 1, primecaster: 1, "pro-market": 1, akamaihd: { "pxlclnmdecom-a": 1 }, rfihub: 1, sancdn: 1, "sc-static": 1, semasio: 1, sensic: 1, sexad: 1, smaato: 1, spreadshirts: 1, storygize: 1, tfaforms: 1, trackcmp: 1, trackedlink: 1, tradetracker: 1, "truste-svc": 1, uuidksinc: 1, viafoura: 1, visilabs: 1, visx: 1, w55c: 1, wdsvc: 1, witglobal: 1, yandex: 1, yastatic: 1, yieldlab: 1, zencdn: 1, zucks: 1, opencmp: 1, azurewebsites: { "app-fnsp-matomo-analytics-prod": 1 }, "ad-delivery": 1, chartbeat: 1, msecnd: 1, cloudfunctions: { "us-central1-adaptive-growth": 1 }, eviltracker: 1 }, co: { "6sc": 1, ayads: 1, getlasso: 1, idio: 1, increasingly: 1, jads: 1, nanorep: 1, nc0: 1, pcdn: 1, prmutv: 1, resetdigital: 1, t: 1, tctm: 1, zip: 1 }, gt: { ad: 1 }, ru: { adfox: 1, adriver: 1, digitaltarget: 1, mail: 1, mindbox: 1, rambler: 1, rutarget: 1, sape: 1, smi2: 1, "tns-counter": 1, top100: 1, ulogin: 1, yandex: 1, yadro: 1 }, jp: { adingo: 1, admatrix: 1, auone: 1, co: { dmm: 1, "i-mobile": 1, rakuten: 1, yahoo: 1 }, fout: 1, genieesspv: 1, "gmossp-sp": 1, gsspat: 1, gssprt: 1, ne: { hatena: 1 }, i2i: 1, "impact-ad": 1, microad: 1, nakanohito: 1, r10s: 1, "reemo-ad": 1, rtoaster: 1, shinobi: 1, "team-rec": 1, uncn: 1, yimg: 1, yjtag: 1 }, pl: { adocean: 1, gemius: 1, nsaudience: 1, onet: 1, salesmanago: 1, wp: 1 }, pro: { adpartner: 1, piwik: 1, usocial: 1 }, de: { adscale: 1, "auswaertiges-amt": 1, fiduciagad: 1, ioam: 1, itzbund: 1, vgwort: 1, werk21system: 1 }, re: { adsco: 1 }, info: { adxbid: 1, bitrix: 1, navistechnologies: 1, usergram: 1, webantenna: 1 }, tv: { affec: 1, attn: 1, iris: 1, ispot: 1, samba: 1, teads: 1, twitch: 1, videohub: 1 }, dev: { amazon: 1 }, us: { amung: 1, samplicio: 1, slgnt: 1, trkn: 1, owlsr: 1 }, media: { andbeyond: 1, nextday: 1, townsquare: 1, underdog: 1 }, link: { app: 1 }, cloud: { avct: 1, egain: 1, matomo: 1 }, delivery: { ay: 1, monu: 1 }, ly: { bit: 1 }, br: { com: { btg360: 1, clearsale: 1, jsuol: 1, shopconvert: 1, shoptarget: 1, soclminer: 1 }, org: { ivcbrasil: 1 } }, ch: { ch: 1, "da-services": 1, google: 1 }, me: { channel: 1, contentexchange: 1, grow: 1, line: 1, loopme: 1, t: 1 }, ms: { clarity: 1 }, my: { cnt: 1 }, se: { codigo: 1 }, to: { cpx: 1, tawk: 1 }, chat: { crisp: 1, gorgias: 1 }, fr: { "d-bi": 1, "open-system": 1, weborama: 1 }, uk: { co: { dailymail: 1, hsbc: 1 } }, gov: { dhs: 1 }, ai: { "e-volution": 1, hybrid: 1, m2: 1, nrich: 1, wknd: 1 }, be: { geoedge: 1 }, au: { com: { google: 1, news: 1, nine: 1, zipmoney: 1, telstra: 1 } }, stream: { ibclick: 1 }, cz: { imedia: 1, seznam: 1, trackad: 1 }, app: { infusionsoft: 1, permutive: 1, shop: 1 }, tech: { ingage: 1, primis: 1 }, eu: { kameleoon: 1, medallia: 1, media01: 1, ocdn: 1, rqtrk: 1, slgnt: 1 }, fi: { kesko: 1, simpli: 1 }, live: { lura: 1 }, services: { marketingautomation: 1 }, sg: { mediacorp: 1 }, bi: { newsroom: 1 }, fm: { pdst: 1 }, ad: { pixel: 1 }, xyz: { playground: 1 }, it: { plug: 1, repstatic: 1 }, cc: { popin: 1 }, network: { pub: 1 }, nl: { rijksoverheid: 1 }, fyi: { sda: 1 }, es: { socy: 1 }, im: { spot: 1 }, market: { spotim: 1 }, am: { tru: 1 }, no: { uio: 1, medietall: 1 }, at: { waust: 1 }, pe: { shop: 1 }, ca: { bc: { gov: 1 } }, gg: { clean: 1 }, example: { "ad-company": 1 }, site: { "ad-company": 1, "third-party": { bad: 1, broken: 1 } }, pw: { "5mcwl": 1, fvl1f: 1, h78xb: 1, i9w8p: 1, k54nw: 1, tdzvm: 1, tzwaw: 1, vq1qi: 1, zlp6s: 1 }, pub: { admiral: 1 } };
    }
  });

  // ../node_modules/xregexp/src/xregexp.js
  var require_xregexp = __commonJS({
    "../node_modules/xregexp/src/xregexp.js"(exports, module) {
      "use strict";
      init_define_import_meta_trackerLookup();
      /*!
       * XRegExp 3.2.0
       * <xregexp.com>
       * Steven Levithan (c) 2007-2017 MIT License
       */
      var REGEX_DATA = "xregexp";
      var features2 = {
        astral: false,
        natives: false
      };
      var nativ = {
        exec: RegExp.prototype.exec,
        test: RegExp.prototype.test,
        match: String.prototype.match,
        replace: String.prototype.replace,
        split: String.prototype.split
      };
      var fixed = {};
      var regexCache = {};
      var patternCache = {};
      var tokens = [];
      var defaultScope = "default";
      var classScope = "class";
      var nativeTokens = {
        // Any native multicharacter token in default scope, or any single character
        "default": /\\(?:0(?:[0-3][0-7]{0,2}|[4-7][0-7]?)?|[1-9]\d*|x[\dA-Fa-f]{2}|u(?:[\dA-Fa-f]{4}|{[\dA-Fa-f]+})|c[A-Za-z]|[\s\S])|\(\?(?:[:=!]|<[=!])|[?*+]\?|{\d+(?:,\d*)?}\??|[\s\S]/,
        // Any native multicharacter token in character class scope, or any single character
        "class": /\\(?:[0-3][0-7]{0,2}|[4-7][0-7]?|x[\dA-Fa-f]{2}|u(?:[\dA-Fa-f]{4}|{[\dA-Fa-f]+})|c[A-Za-z]|[\s\S])|[\s\S]/
      };
      var replacementToken = /\$(?:{([\w$]+)}|(\d\d?|[\s\S]))/g;
      var correctExecNpcg = nativ.exec.call(/()??/, "")[1] === void 0;
      var hasFlagsProp = /x/.flags !== void 0;
      var toString2 = {}.toString;
      function hasNativeFlag(flag) {
        var isSupported = true;
        try {
          new RegExp("", flag);
        } catch (exception) {
          isSupported = false;
        }
        return isSupported;
      }
      var hasNativeU = hasNativeFlag("u");
      var hasNativeY = hasNativeFlag("y");
      var registeredFlags = {
        g: true,
        i: true,
        m: true,
        u: hasNativeU,
        y: hasNativeY
      };
      function augment(regex, captureNames, xSource, xFlags, isInternalOnly) {
        var p;
        regex[REGEX_DATA] = {
          captureNames
        };
        if (isInternalOnly) {
          return regex;
        }
        if (regex.__proto__) {
          regex.__proto__ = XRegExp.prototype;
        } else {
          for (p in XRegExp.prototype) {
            regex[p] = XRegExp.prototype[p];
          }
        }
        regex[REGEX_DATA].source = xSource;
        regex[REGEX_DATA].flags = xFlags ? xFlags.split("").sort().join("") : xFlags;
        return regex;
      }
      function clipDuplicates(str) {
        return nativ.replace.call(str, /([\s\S])(?=[\s\S]*\1)/g, "");
      }
      function copyRegex(regex, options) {
        if (!XRegExp.isRegExp(regex)) {
          throw new TypeError("Type RegExp expected");
        }
        var xData = regex[REGEX_DATA] || {};
        var flags = getNativeFlags(regex);
        var flagsToAdd = "";
        var flagsToRemove = "";
        var xregexpSource = null;
        var xregexpFlags = null;
        options = options || {};
        if (options.removeG) {
          flagsToRemove += "g";
        }
        if (options.removeY) {
          flagsToRemove += "y";
        }
        if (flagsToRemove) {
          flags = nativ.replace.call(flags, new RegExp("[" + flagsToRemove + "]+", "g"), "");
        }
        if (options.addG) {
          flagsToAdd += "g";
        }
        if (options.addY) {
          flagsToAdd += "y";
        }
        if (flagsToAdd) {
          flags = clipDuplicates(flags + flagsToAdd);
        }
        if (!options.isInternalOnly) {
          if (xData.source !== void 0) {
            xregexpSource = xData.source;
          }
          if (xData.flags != null) {
            xregexpFlags = flagsToAdd ? clipDuplicates(xData.flags + flagsToAdd) : xData.flags;
          }
        }
        regex = augment(
          new RegExp(options.source || regex.source, flags),
          hasNamedCapture(regex) ? xData.captureNames.slice(0) : null,
          xregexpSource,
          xregexpFlags,
          options.isInternalOnly
        );
        return regex;
      }
      function dec(hex2) {
        return parseInt(hex2, 16);
      }
      function getContextualTokenSeparator(match, scope, flags) {
        if (
          // No need to separate tokens if at the beginning or end of a group
          match.input.charAt(match.index - 1) === "(" || match.input.charAt(match.index + match[0].length) === ")" || // Avoid separating tokens when the following token is a quantifier
          isPatternNext(match.input, match.index + match[0].length, flags, "[?*+]|{\\d+(?:,\\d*)?}")
        ) {
          return "";
        }
        return "(?:)";
      }
      function getNativeFlags(regex) {
        return hasFlagsProp ? regex.flags : (
          // Explicitly using `RegExp.prototype.toString` (rather than e.g. `String` or concatenation
          // with an empty string) allows this to continue working predictably when
          // `XRegExp.proptotype.toString` is overridden
          nativ.exec.call(/\/([a-z]*)$/i, RegExp.prototype.toString.call(regex))[1]
        );
      }
      function hasNamedCapture(regex) {
        return !!(regex[REGEX_DATA] && regex[REGEX_DATA].captureNames);
      }
      function hex(dec2) {
        return parseInt(dec2, 10).toString(16);
      }
      function indexOf(array, value) {
        var len = array.length;
        var i;
        for (i = 0; i < len; ++i) {
          if (array[i] === value) {
            return i;
          }
        }
        return -1;
      }
      function isPatternNext(pattern, pos, flags, needlePattern) {
        var inlineCommentPattern = "\\(\\?#[^)]*\\)";
        var lineCommentPattern = "#[^#\\n]*";
        var patternsToIgnore = flags.indexOf("x") > -1 ? (
          // Ignore any leading whitespace, line comments, and inline comments
          ["\\s", lineCommentPattern, inlineCommentPattern]
        ) : (
          // Ignore any leading inline comments
          [inlineCommentPattern]
        );
        return nativ.test.call(
          new RegExp("^(?:" + patternsToIgnore.join("|") + ")*(?:" + needlePattern + ")"),
          pattern.slice(pos)
        );
      }
      function isType(value, type) {
        return toString2.call(value) === "[object " + type + "]";
      }
      function pad4(str) {
        while (str.length < 4) {
          str = "0" + str;
        }
        return str;
      }
      function prepareFlags(pattern, flags) {
        var i;
        if (clipDuplicates(flags) !== flags) {
          throw new SyntaxError("Invalid duplicate regex flag " + flags);
        }
        pattern = nativ.replace.call(pattern, /^\(\?([\w$]+)\)/, function($0, $1) {
          if (nativ.test.call(/[gy]/, $1)) {
            throw new SyntaxError("Cannot use flag g or y in mode modifier " + $0);
          }
          flags = clipDuplicates(flags + $1);
          return "";
        });
        for (i = 0; i < flags.length; ++i) {
          if (!registeredFlags[flags.charAt(i)]) {
            throw new SyntaxError("Unknown regex flag " + flags.charAt(i));
          }
        }
        return {
          pattern,
          flags
        };
      }
      function prepareOptions(value) {
        var options = {};
        if (isType(value, "String")) {
          XRegExp.forEach(value, /[^\s,]+/, function(match) {
            options[match] = true;
          });
          return options;
        }
        return value;
      }
      function registerFlag(flag) {
        if (!/^[\w$]$/.test(flag)) {
          throw new Error("Flag must be a single character A-Za-z0-9_$");
        }
        registeredFlags[flag] = true;
      }
      function runTokens(pattern, flags, pos, scope, context) {
        var i = tokens.length;
        var leadChar = pattern.charAt(pos);
        var result = null;
        var match;
        var t;
        while (i--) {
          t = tokens[i];
          if (t.leadChar && t.leadChar !== leadChar || t.scope !== scope && t.scope !== "all" || t.flag && flags.indexOf(t.flag) === -1) {
            continue;
          }
          match = XRegExp.exec(pattern, t.regex, pos, "sticky");
          if (match) {
            result = {
              matchLength: match[0].length,
              output: t.handler.call(context, match, scope, flags),
              reparse: t.reparse
            };
            break;
          }
        }
        return result;
      }
      function setAstral(on) {
        features2.astral = on;
      }
      function setNatives(on) {
        RegExp.prototype.exec = (on ? fixed : nativ).exec;
        RegExp.prototype.test = (on ? fixed : nativ).test;
        String.prototype.match = (on ? fixed : nativ).match;
        String.prototype.replace = (on ? fixed : nativ).replace;
        String.prototype.split = (on ? fixed : nativ).split;
        features2.natives = on;
      }
      function toObject(value) {
        if (value == null) {
          throw new TypeError("Cannot convert null or undefined to object");
        }
        return value;
      }
      function XRegExp(pattern, flags) {
        if (XRegExp.isRegExp(pattern)) {
          if (flags !== void 0) {
            throw new TypeError("Cannot supply flags when copying a RegExp");
          }
          return copyRegex(pattern);
        }
        pattern = pattern === void 0 ? "" : String(pattern);
        flags = flags === void 0 ? "" : String(flags);
        if (XRegExp.isInstalled("astral") && flags.indexOf("A") === -1) {
          flags += "A";
        }
        if (!patternCache[pattern]) {
          patternCache[pattern] = {};
        }
        if (!patternCache[pattern][flags]) {
          var context = {
            hasNamedCapture: false,
            captureNames: []
          };
          var scope = defaultScope;
          var output = "";
          var pos = 0;
          var result;
          var applied = prepareFlags(pattern, flags);
          var appliedPattern = applied.pattern;
          var appliedFlags = applied.flags;
          while (pos < appliedPattern.length) {
            do {
              result = runTokens(appliedPattern, appliedFlags, pos, scope, context);
              if (result && result.reparse) {
                appliedPattern = appliedPattern.slice(0, pos) + result.output + appliedPattern.slice(pos + result.matchLength);
              }
            } while (result && result.reparse);
            if (result) {
              output += result.output;
              pos += result.matchLength || 1;
            } else {
              var token = XRegExp.exec(appliedPattern, nativeTokens[scope], pos, "sticky")[0];
              output += token;
              pos += token.length;
              if (token === "[" && scope === defaultScope) {
                scope = classScope;
              } else if (token === "]" && scope === classScope) {
                scope = defaultScope;
              }
            }
          }
          patternCache[pattern][flags] = {
            // Use basic cleanup to collapse repeated empty groups like `(?:)(?:)` to `(?:)`. Empty
            // groups are sometimes inserted during regex transpilation in order to keep tokens
            // separated. However, more than one empty group in a row is never needed.
            pattern: nativ.replace.call(output, /(?:\(\?:\))+/g, "(?:)"),
            // Strip all but native flags
            flags: nativ.replace.call(appliedFlags, /[^gimuy]+/g, ""),
            // `context.captureNames` has an item for each capturing group, even if unnamed
            captures: context.hasNamedCapture ? context.captureNames : null
          };
        }
        var generated = patternCache[pattern][flags];
        return augment(
          new RegExp(generated.pattern, generated.flags),
          generated.captures,
          pattern,
          flags
        );
      }
      XRegExp.prototype = new RegExp();
      XRegExp.version = "3.2.0";
      XRegExp._clipDuplicates = clipDuplicates;
      XRegExp._hasNativeFlag = hasNativeFlag;
      XRegExp._dec = dec;
      XRegExp._hex = hex;
      XRegExp._pad4 = pad4;
      XRegExp.addToken = function(regex, handler, options) {
        options = options || {};
        var optionalFlags = options.optionalFlags;
        var i;
        if (options.flag) {
          registerFlag(options.flag);
        }
        if (optionalFlags) {
          optionalFlags = nativ.split.call(optionalFlags, "");
          for (i = 0; i < optionalFlags.length; ++i) {
            registerFlag(optionalFlags[i]);
          }
        }
        tokens.push({
          regex: copyRegex(regex, {
            addG: true,
            addY: hasNativeY,
            isInternalOnly: true
          }),
          handler,
          scope: options.scope || defaultScope,
          flag: options.flag,
          reparse: options.reparse,
          leadChar: options.leadChar
        });
        XRegExp.cache.flush("patterns");
      };
      XRegExp.cache = function(pattern, flags) {
        if (!regexCache[pattern]) {
          regexCache[pattern] = {};
        }
        return regexCache[pattern][flags] || (regexCache[pattern][flags] = XRegExp(pattern, flags));
      };
      XRegExp.cache.flush = function(cacheName) {
        if (cacheName === "patterns") {
          patternCache = {};
        } else {
          regexCache = {};
        }
      };
      XRegExp.escape = function(str) {
        return nativ.replace.call(toObject(str), /[-\[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
      };
      XRegExp.exec = function(str, regex, pos, sticky) {
        var cacheKey = "g";
        var addY = false;
        var fakeY = false;
        var match;
        var r2;
        addY = hasNativeY && !!(sticky || regex.sticky && sticky !== false);
        if (addY) {
          cacheKey += "y";
        } else if (sticky) {
          fakeY = true;
          cacheKey += "FakeY";
        }
        regex[REGEX_DATA] = regex[REGEX_DATA] || {};
        r2 = regex[REGEX_DATA][cacheKey] || (regex[REGEX_DATA][cacheKey] = copyRegex(regex, {
          addG: true,
          addY,
          source: fakeY ? regex.source + "|()" : void 0,
          removeY: sticky === false,
          isInternalOnly: true
        }));
        pos = pos || 0;
        r2.lastIndex = pos;
        match = fixed.exec.call(r2, str);
        if (fakeY && match && match.pop() === "") {
          match = null;
        }
        if (regex.global) {
          regex.lastIndex = match ? r2.lastIndex : 0;
        }
        return match;
      };
      XRegExp.forEach = function(str, regex, callback) {
        var pos = 0;
        var i = -1;
        var match;
        while (match = XRegExp.exec(str, regex, pos)) {
          callback(match, ++i, str, regex);
          pos = match.index + (match[0].length || 1);
        }
      };
      XRegExp.globalize = function(regex) {
        return copyRegex(regex, { addG: true });
      };
      XRegExp.install = function(options) {
        options = prepareOptions(options);
        if (!features2.astral && options.astral) {
          setAstral(true);
        }
        if (!features2.natives && options.natives) {
          setNatives(true);
        }
      };
      XRegExp.isInstalled = function(feature) {
        return !!features2[feature];
      };
      XRegExp.isRegExp = function(value) {
        return toString2.call(value) === "[object RegExp]";
      };
      XRegExp.match = function(str, regex, scope) {
        var global = regex.global && scope !== "one" || scope === "all";
        var cacheKey = (global ? "g" : "") + (regex.sticky ? "y" : "") || "noGY";
        var result;
        var r2;
        regex[REGEX_DATA] = regex[REGEX_DATA] || {};
        r2 = regex[REGEX_DATA][cacheKey] || (regex[REGEX_DATA][cacheKey] = copyRegex(regex, {
          addG: !!global,
          removeG: scope === "one",
          isInternalOnly: true
        }));
        result = nativ.match.call(toObject(str), r2);
        if (regex.global) {
          regex.lastIndex = scope === "one" && result ? (
            // Can't use `r2.lastIndex` since `r2` is nonglobal in this case
            result.index + result[0].length
          ) : 0;
        }
        return global ? result || [] : result && result[0];
      };
      XRegExp.matchChain = function(str, chain) {
        return (function recurseChain(values, level) {
          var item = chain[level].regex ? chain[level] : { regex: chain[level] };
          var matches = [];
          function addMatch(match) {
            if (item.backref) {
              if (!(match.hasOwnProperty(item.backref) || +item.backref < match.length)) {
                throw new ReferenceError("Backreference to undefined group: " + item.backref);
              }
              matches.push(match[item.backref] || "");
            } else {
              matches.push(match[0]);
            }
          }
          for (var i = 0; i < values.length; ++i) {
            XRegExp.forEach(values[i], item.regex, addMatch);
          }
          return level === chain.length - 1 || !matches.length ? matches : recurseChain(matches, level + 1);
        })([str], 0);
      };
      XRegExp.replace = function(str, search, replacement, scope) {
        var isRegex = XRegExp.isRegExp(search);
        var global = search.global && scope !== "one" || scope === "all";
        var cacheKey = (global ? "g" : "") + (search.sticky ? "y" : "") || "noGY";
        var s2 = search;
        var result;
        if (isRegex) {
          search[REGEX_DATA] = search[REGEX_DATA] || {};
          s2 = search[REGEX_DATA][cacheKey] || (search[REGEX_DATA][cacheKey] = copyRegex(search, {
            addG: !!global,
            removeG: scope === "one",
            isInternalOnly: true
          }));
        } else if (global) {
          s2 = new RegExp(XRegExp.escape(String(search)), "g");
        }
        result = fixed.replace.call(toObject(str), s2, replacement);
        if (isRegex && search.global) {
          search.lastIndex = 0;
        }
        return result;
      };
      XRegExp.replaceEach = function(str, replacements) {
        var i;
        var r;
        for (i = 0; i < replacements.length; ++i) {
          r = replacements[i];
          str = XRegExp.replace(str, r[0], r[1], r[2]);
        }
        return str;
      };
      XRegExp.split = function(str, separator, limit) {
        return fixed.split.call(toObject(str), separator, limit);
      };
      XRegExp.test = function(str, regex, pos, sticky) {
        return !!XRegExp.exec(str, regex, pos, sticky);
      };
      XRegExp.uninstall = function(options) {
        options = prepareOptions(options);
        if (features2.astral && options.astral) {
          setAstral(false);
        }
        if (features2.natives && options.natives) {
          setNatives(false);
        }
      };
      XRegExp.union = function(patterns, flags, options) {
        options = options || {};
        var conjunction = options.conjunction || "or";
        var numCaptures = 0;
        var numPriorCaptures;
        var captureNames;
        function rewrite(match, paren, backref) {
          var name = captureNames[numCaptures - numPriorCaptures];
          if (paren) {
            ++numCaptures;
            if (name) {
              return "(?<" + name + ">";
            }
          } else if (backref) {
            return "\\" + (+backref + numPriorCaptures);
          }
          return match;
        }
        if (!(isType(patterns, "Array") && patterns.length)) {
          throw new TypeError("Must provide a nonempty array of patterns to merge");
        }
        var parts = /(\()(?!\?)|\\([1-9]\d*)|\\[\s\S]|\[(?:[^\\\]]|\\[\s\S])*\]/g;
        var output = [];
        var pattern;
        for (var i = 0; i < patterns.length; ++i) {
          pattern = patterns[i];
          if (XRegExp.isRegExp(pattern)) {
            numPriorCaptures = numCaptures;
            captureNames = pattern[REGEX_DATA] && pattern[REGEX_DATA].captureNames || [];
            output.push(nativ.replace.call(XRegExp(pattern.source).source, parts, rewrite));
          } else {
            output.push(XRegExp.escape(pattern));
          }
        }
        var separator = conjunction === "none" ? "" : "|";
        return XRegExp(output.join(separator), flags);
      };
      fixed.exec = function(str) {
        var origLastIndex = this.lastIndex;
        var match = nativ.exec.apply(this, arguments);
        var name;
        var r2;
        var i;
        if (match) {
          if (!correctExecNpcg && match.length > 1 && indexOf(match, "") > -1) {
            r2 = copyRegex(this, {
              removeG: true,
              isInternalOnly: true
            });
            nativ.replace.call(String(str).slice(match.index), r2, function() {
              var len = arguments.length;
              var i2;
              for (i2 = 1; i2 < len - 2; ++i2) {
                if (arguments[i2] === void 0) {
                  match[i2] = void 0;
                }
              }
            });
          }
          if (this[REGEX_DATA] && this[REGEX_DATA].captureNames) {
            for (i = 1; i < match.length; ++i) {
              name = this[REGEX_DATA].captureNames[i - 1];
              if (name) {
                match[name] = match[i];
              }
            }
          }
          if (this.global && !match[0].length && this.lastIndex > match.index) {
            this.lastIndex = match.index;
          }
        }
        if (!this.global) {
          this.lastIndex = origLastIndex;
        }
        return match;
      };
      fixed.test = function(str) {
        return !!fixed.exec.call(this, str);
      };
      fixed.match = function(regex) {
        var result;
        if (!XRegExp.isRegExp(regex)) {
          regex = new RegExp(regex);
        } else if (regex.global) {
          result = nativ.match.apply(this, arguments);
          regex.lastIndex = 0;
          return result;
        }
        return fixed.exec.call(regex, toObject(this));
      };
      fixed.replace = function(search, replacement) {
        var isRegex = XRegExp.isRegExp(search);
        var origLastIndex;
        var captureNames;
        var result;
        if (isRegex) {
          if (search[REGEX_DATA]) {
            captureNames = search[REGEX_DATA].captureNames;
          }
          origLastIndex = search.lastIndex;
        } else {
          search += "";
        }
        if (isType(replacement, "Function")) {
          result = nativ.replace.call(String(this), search, function() {
            var args = arguments;
            var i;
            if (captureNames) {
              args[0] = new String(args[0]);
              for (i = 0; i < captureNames.length; ++i) {
                if (captureNames[i]) {
                  args[0][captureNames[i]] = args[i + 1];
                }
              }
            }
            if (isRegex && search.global) {
              search.lastIndex = args[args.length - 2] + args[0].length;
            }
            return replacement.apply(void 0, args);
          });
        } else {
          result = nativ.replace.call(this == null ? this : String(this), search, function() {
            var args = arguments;
            return nativ.replace.call(String(replacement), replacementToken, function($0, $1, $2) {
              var n;
              if ($1) {
                n = +$1;
                if (n <= args.length - 3) {
                  return args[n] || "";
                }
                n = captureNames ? indexOf(captureNames, $1) : -1;
                if (n < 0) {
                  throw new SyntaxError("Backreference to undefined group " + $0);
                }
                return args[n + 1] || "";
              }
              if ($2 === "$") {
                return "$";
              }
              if ($2 === "&" || +$2 === 0) {
                return args[0];
              }
              if ($2 === "`") {
                return args[args.length - 1].slice(0, args[args.length - 2]);
              }
              if ($2 === "'") {
                return args[args.length - 1].slice(args[args.length - 2] + args[0].length);
              }
              $2 = +$2;
              if (!isNaN($2)) {
                if ($2 > args.length - 3) {
                  throw new SyntaxError("Backreference to undefined group " + $0);
                }
                return args[$2] || "";
              }
              throw new SyntaxError("Invalid token " + $0);
            });
          });
        }
        if (isRegex) {
          if (search.global) {
            search.lastIndex = 0;
          } else {
            search.lastIndex = origLastIndex;
          }
        }
        return result;
      };
      fixed.split = function(separator, limit) {
        if (!XRegExp.isRegExp(separator)) {
          return nativ.split.apply(this, arguments);
        }
        var str = String(this);
        var output = [];
        var origLastIndex = separator.lastIndex;
        var lastLastIndex = 0;
        var lastLength;
        limit = (limit === void 0 ? -1 : limit) >>> 0;
        XRegExp.forEach(str, separator, function(match) {
          if (match.index + match[0].length > lastLastIndex) {
            output.push(str.slice(lastLastIndex, match.index));
            if (match.length > 1 && match.index < str.length) {
              Array.prototype.push.apply(output, match.slice(1));
            }
            lastLength = match[0].length;
            lastLastIndex = match.index + lastLength;
          }
        });
        if (lastLastIndex === str.length) {
          if (!nativ.test.call(separator, "") || lastLength) {
            output.push("");
          }
        } else {
          output.push(str.slice(lastLastIndex));
        }
        separator.lastIndex = origLastIndex;
        return output.length > limit ? output.slice(0, limit) : output;
      };
      XRegExp.addToken(
        /\\([ABCE-RTUVXYZaeg-mopqyz]|c(?![A-Za-z])|u(?![\dA-Fa-f]{4}|{[\dA-Fa-f]+})|x(?![\dA-Fa-f]{2}))/,
        function(match, scope) {
          if (match[1] === "B" && scope === defaultScope) {
            return match[0];
          }
          throw new SyntaxError("Invalid escape " + match[0]);
        },
        {
          scope: "all",
          leadChar: "\\"
        }
      );
      XRegExp.addToken(
        /\\u{([\dA-Fa-f]+)}/,
        function(match, scope, flags) {
          var code = dec(match[1]);
          if (code > 1114111) {
            throw new SyntaxError("Invalid Unicode code point " + match[0]);
          }
          if (code <= 65535) {
            return "\\u" + pad4(hex(code));
          }
          if (hasNativeU && flags.indexOf("u") > -1) {
            return match[0];
          }
          throw new SyntaxError("Cannot use Unicode code point above \\u{FFFF} without flag u");
        },
        {
          scope: "all",
          leadChar: "\\"
        }
      );
      XRegExp.addToken(
        /\[(\^?)\]/,
        function(match) {
          return match[1] ? "[\\s\\S]" : "\\b\\B";
        },
        { leadChar: "[" }
      );
      XRegExp.addToken(
        /\(\?#[^)]*\)/,
        getContextualTokenSeparator,
        { leadChar: "(" }
      );
      XRegExp.addToken(
        /\s+|#[^\n]*\n?/,
        getContextualTokenSeparator,
        { flag: "x" }
      );
      XRegExp.addToken(
        /\./,
        function() {
          return "[\\s\\S]";
        },
        {
          flag: "s",
          leadChar: "."
        }
      );
      XRegExp.addToken(
        /\\k<([\w$]+)>/,
        function(match) {
          var index = isNaN(match[1]) ? indexOf(this.captureNames, match[1]) + 1 : +match[1];
          var endIndex = match.index + match[0].length;
          if (!index || index > this.captureNames.length) {
            throw new SyntaxError("Backreference to undefined group " + match[0]);
          }
          return "\\" + index + (endIndex === match.input.length || isNaN(match.input.charAt(endIndex)) ? "" : "(?:)");
        },
        { leadChar: "\\" }
      );
      XRegExp.addToken(
        /\\(\d+)/,
        function(match, scope) {
          if (!(scope === defaultScope && /^[1-9]/.test(match[1]) && +match[1] <= this.captureNames.length) && match[1] !== "0") {
            throw new SyntaxError("Cannot use octal escape or backreference to undefined group " + match[0]);
          }
          return match[0];
        },
        {
          scope: "all",
          leadChar: "\\"
        }
      );
      XRegExp.addToken(
        /\(\?P?<([\w$]+)>/,
        function(match) {
          if (!isNaN(match[1])) {
            throw new SyntaxError("Cannot use integer as capture name " + match[0]);
          }
          if (match[1] === "length" || match[1] === "__proto__") {
            throw new SyntaxError("Cannot use reserved word as capture name " + match[0]);
          }
          if (indexOf(this.captureNames, match[1]) > -1) {
            throw new SyntaxError("Cannot use same name for multiple groups " + match[0]);
          }
          this.captureNames.push(match[1]);
          this.hasNamedCapture = true;
          return "(";
        },
        { leadChar: "(" }
      );
      XRegExp.addToken(
        /\((?!\?)/,
        function(match, scope, flags) {
          if (flags.indexOf("n") > -1) {
            return "(?:";
          }
          this.captureNames.push(null);
          return "(";
        },
        {
          optionalFlags: "n",
          leadChar: "("
        }
      );
      module.exports = XRegExp;
    }
  });

  // ../node_modules/parse-address/address.js
  var require_address = __commonJS({
    "../node_modules/parse-address/address.js"(exports) {
      "use strict";
      init_define_import_meta_trackerLookup();
      //! Copyright (c) 2014-2015, hassansin
      //!
      //!Perl Ref: http://cpansearch.perl.org/src/TIMB/Geo-StreetAddress-US-1.04/US.pm
      (function() {
        var root;
        root = this;
        var XRegExp;
        if (typeof __require !== "undefined") {
          XRegExp = require_xregexp();
        } else
          XRegExp = root.XRegExp;
        var parser = {};
        var Addr_Match = {};
        var Directional = {
          north: "N",
          northeast: "NE",
          east: "E",
          southeast: "SE",
          south: "S",
          southwest: "SW",
          west: "W",
          northwest: "NW"
        };
        var Street_Type = {
          allee: "aly",
          alley: "aly",
          ally: "aly",
          anex: "anx",
          annex: "anx",
          annx: "anx",
          arcade: "arc",
          av: "ave",
          aven: "ave",
          avenu: "ave",
          avenue: "ave",
          avn: "ave",
          avnue: "ave",
          bayoo: "byu",
          bayou: "byu",
          beach: "bch",
          bend: "bnd",
          bluf: "blf",
          bluff: "blf",
          bluffs: "blfs",
          bot: "btm",
          bottm: "btm",
          bottom: "btm",
          boul: "blvd",
          boulevard: "blvd",
          boulv: "blvd",
          branch: "br",
          brdge: "brg",
          bridge: "brg",
          brnch: "br",
          brook: "brk",
          brooks: "brks",
          burg: "bg",
          burgs: "bgs",
          bypa: "byp",
          bypas: "byp",
          bypass: "byp",
          byps: "byp",
          camp: "cp",
          canyn: "cyn",
          canyon: "cyn",
          cape: "cpe",
          causeway: "cswy",
          causway: "cswy",
          causwa: "cswy",
          cen: "ctr",
          cent: "ctr",
          center: "ctr",
          centers: "ctrs",
          centr: "ctr",
          centre: "ctr",
          circ: "cir",
          circl: "cir",
          circle: "cir",
          circles: "cirs",
          ck: "crk",
          cliff: "clf",
          cliffs: "clfs",
          club: "clb",
          cmp: "cp",
          cnter: "ctr",
          cntr: "ctr",
          cnyn: "cyn",
          common: "cmn",
          commons: "cmns",
          corner: "cor",
          corners: "cors",
          course: "crse",
          court: "ct",
          courts: "cts",
          cove: "cv",
          coves: "cvs",
          cr: "crk",
          crcl: "cir",
          crcle: "cir",
          crecent: "cres",
          creek: "crk",
          crescent: "cres",
          cresent: "cres",
          crest: "crst",
          crossing: "xing",
          crossroad: "xrd",
          crossroads: "xrds",
          crscnt: "cres",
          crsent: "cres",
          crsnt: "cres",
          crssing: "xing",
          crssng: "xing",
          crt: "ct",
          curve: "curv",
          dale: "dl",
          dam: "dm",
          div: "dv",
          divide: "dv",
          driv: "dr",
          drive: "dr",
          drives: "drs",
          drv: "dr",
          dvd: "dv",
          estate: "est",
          estates: "ests",
          exp: "expy",
          expr: "expy",
          express: "expy",
          expressway: "expy",
          expw: "expy",
          extension: "ext",
          extensions: "exts",
          extn: "ext",
          extnsn: "ext",
          fall: "fall",
          falls: "fls",
          ferry: "fry",
          field: "fld",
          fields: "flds",
          flat: "flt",
          flats: "flts",
          ford: "frd",
          fords: "frds",
          forest: "frst",
          forests: "frst",
          forg: "frg",
          forge: "frg",
          forges: "frgs",
          fork: "frk",
          forks: "frks",
          fort: "ft",
          freeway: "fwy",
          freewy: "fwy",
          frry: "fry",
          frt: "ft",
          frway: "fwy",
          frwy: "fwy",
          garden: "gdn",
          gardens: "gdns",
          gardn: "gdn",
          gateway: "gtwy",
          gatewy: "gtwy",
          gatway: "gtwy",
          glen: "gln",
          glens: "glns",
          grden: "gdn",
          grdn: "gdn",
          grdns: "gdns",
          green: "grn",
          greens: "grns",
          grov: "grv",
          grove: "grv",
          groves: "grvs",
          gtway: "gtwy",
          harb: "hbr",
          harbor: "hbr",
          harbors: "hbrs",
          harbr: "hbr",
          haven: "hvn",
          havn: "hvn",
          height: "hts",
          heights: "hts",
          hgts: "hts",
          highway: "hwy",
          highwy: "hwy",
          hill: "hl",
          hills: "hls",
          hiway: "hwy",
          hiwy: "hwy",
          hllw: "holw",
          hollow: "holw",
          hollows: "holw",
          holws: "holw",
          hrbor: "hbr",
          ht: "hts",
          hway: "hwy",
          inlet: "inlt",
          island: "is",
          islands: "iss",
          isles: "isle",
          islnd: "is",
          islnds: "iss",
          jction: "jct",
          jctn: "jct",
          jctns: "jcts",
          junction: "jct",
          junctions: "jcts",
          junctn: "jct",
          juncton: "jct",
          key: "ky",
          keys: "kys",
          knol: "knl",
          knoll: "knl",
          knolls: "knls",
          la: "ln",
          lake: "lk",
          lakes: "lks",
          land: "land",
          landing: "lndg",
          lane: "ln",
          lanes: "ln",
          ldge: "ldg",
          light: "lgt",
          lights: "lgts",
          lndng: "lndg",
          loaf: "lf",
          lock: "lck",
          locks: "lcks",
          lodg: "ldg",
          lodge: "ldg",
          loops: "loop",
          mall: "mall",
          manor: "mnr",
          manors: "mnrs",
          meadow: "mdw",
          meadows: "mdws",
          medows: "mdws",
          mews: "mews",
          mill: "ml",
          mills: "mls",
          mission: "msn",
          missn: "msn",
          mnt: "mt",
          mntain: "mtn",
          mntn: "mtn",
          mntns: "mtns",
          motorway: "mtwy",
          mount: "mt",
          mountain: "mtn",
          mountains: "mtns",
          mountin: "mtn",
          mssn: "msn",
          mtin: "mtn",
          neck: "nck",
          orchard: "orch",
          orchrd: "orch",
          overpass: "opas",
          ovl: "oval",
          parks: "park",
          parkway: "pkwy",
          parkways: "pkwy",
          parkwy: "pkwy",
          pass: "pass",
          passage: "psge",
          paths: "path",
          pikes: "pike",
          pine: "pne",
          pines: "pnes",
          pk: "park",
          pkway: "pkwy",
          pkwys: "pkwy",
          pky: "pkwy",
          place: "pl",
          plain: "pln",
          plaines: "plns",
          plains: "plns",
          plaza: "plz",
          plza: "plz",
          point: "pt",
          points: "pts",
          port: "prt",
          ports: "prts",
          prairie: "pr",
          prarie: "pr",
          prk: "park",
          prr: "pr",
          rad: "radl",
          radial: "radl",
          radiel: "radl",
          ranch: "rnch",
          ranches: "rnch",
          rapid: "rpd",
          rapids: "rpds",
          rdge: "rdg",
          rest: "rst",
          ridge: "rdg",
          ridges: "rdgs",
          river: "riv",
          rivr: "riv",
          rnchs: "rnch",
          road: "rd",
          roads: "rds",
          route: "rte",
          rvr: "riv",
          row: "row",
          rue: "rue",
          run: "run",
          shoal: "shl",
          shoals: "shls",
          shoar: "shr",
          shoars: "shrs",
          shore: "shr",
          shores: "shrs",
          skyway: "skwy",
          spng: "spg",
          spngs: "spgs",
          spring: "spg",
          springs: "spgs",
          sprng: "spg",
          sprngs: "spgs",
          spurs: "spur",
          sqr: "sq",
          sqre: "sq",
          sqrs: "sqs",
          squ: "sq",
          square: "sq",
          squares: "sqs",
          station: "sta",
          statn: "sta",
          stn: "sta",
          str: "st",
          strav: "stra",
          strave: "stra",
          straven: "stra",
          stravenue: "stra",
          stravn: "stra",
          stream: "strm",
          street: "st",
          streets: "sts",
          streme: "strm",
          strt: "st",
          strvn: "stra",
          strvnue: "stra",
          sumit: "smt",
          sumitt: "smt",
          summit: "smt",
          terr: "ter",
          terrace: "ter",
          throughway: "trwy",
          tpk: "tpke",
          tr: "trl",
          trace: "trce",
          traces: "trce",
          track: "trak",
          tracks: "trak",
          trafficway: "trfy",
          trail: "trl",
          trails: "trl",
          trk: "trak",
          trks: "trak",
          trls: "trl",
          trnpk: "tpke",
          trpk: "tpke",
          tunel: "tunl",
          tunls: "tunl",
          tunnel: "tunl",
          tunnels: "tunl",
          tunnl: "tunl",
          turnpike: "tpke",
          turnpk: "tpke",
          underpass: "upas",
          union: "un",
          unions: "uns",
          valley: "vly",
          valleys: "vlys",
          vally: "vly",
          vdct: "via",
          viadct: "via",
          viaduct: "via",
          view: "vw",
          views: "vws",
          vill: "vlg",
          villag: "vlg",
          village: "vlg",
          villages: "vlgs",
          ville: "vl",
          villg: "vlg",
          villiage: "vlg",
          vist: "vis",
          vista: "vis",
          vlly: "vly",
          vst: "vis",
          vsta: "vis",
          wall: "wall",
          walks: "walk",
          well: "wl",
          wells: "wls",
          wy: "way"
        };
        var State_Code = {
          "alabama": "AL",
          "alaska": "AK",
          "american samoa": "AS",
          "arizona": "AZ",
          "arkansas": "AR",
          "california": "CA",
          "colorado": "CO",
          "connecticut": "CT",
          "delaware": "DE",
          "district of columbia": "DC",
          "federated states of micronesia": "FM",
          "florida": "FL",
          "georgia": "GA",
          "guam": "GU",
          "hawaii": "HI",
          "idaho": "ID",
          "illinois": "IL",
          "indiana": "IN",
          "iowa": "IA",
          "kansas": "KS",
          "kentucky": "KY",
          "louisiana": "LA",
          "maine": "ME",
          "marshall islands": "MH",
          "maryland": "MD",
          "massachusetts": "MA",
          "michigan": "MI",
          "minnesota": "MN",
          "mississippi": "MS",
          "missouri": "MO",
          "montana": "MT",
          "nebraska": "NE",
          "nevada": "NV",
          "new hampshire": "NH",
          "new jersey": "NJ",
          "new mexico": "NM",
          "new york": "NY",
          "north carolina": "NC",
          "north dakota": "ND",
          "northern mariana islands": "MP",
          "ohio": "OH",
          "oklahoma": "OK",
          "oregon": "OR",
          "palau": "PW",
          "pennsylvania": "PA",
          "puerto rico": "PR",
          "rhode island": "RI",
          "south carolina": "SC",
          "south dakota": "SD",
          "tennessee": "TN",
          "texas": "TX",
          "utah": "UT",
          "vermont": "VT",
          "virgin islands": "VI",
          "virginia": "VA",
          "washington": "WA",
          "west virginia": "WV",
          "wisconsin": "WI",
          "wyoming": "WY"
        };
        var Direction_Code;
        var initialized = false;
        var Normalize_Map = {
          prefix: Directional,
          prefix1: Directional,
          prefix2: Directional,
          suffix: Directional,
          suffix1: Directional,
          suffix2: Directional,
          type: Street_Type,
          type1: Street_Type,
          type2: Street_Type,
          state: State_Code
        };
        function capitalize2(s) {
          return s && s[0].toUpperCase() + s.slice(1);
        }
        function keys(o) {
          return Object.keys(o);
        }
        function values(o) {
          var v2 = [];
          keys(o).forEach(function(k) {
            v2.push(o[k]);
          });
          return v2;
        }
        function each(o, fn) {
          keys(o).forEach(function(k) {
            fn(o[k], k);
          });
        }
        function invert(o) {
          var o1 = {};
          keys(o).forEach(function(k) {
            o1[o[k]] = k;
          });
          return o1;
        }
        function flatten(o) {
          return keys(o).concat(values(o));
        }
        function lazyInit() {
          if (initialized) {
            return;
          }
          initialized = true;
          Direction_Code = invert(Directional);
          Addr_Match = {
            type: flatten(Street_Type).sort().filter(function(v2, i, arr) {
              return arr.indexOf(v2) === i;
            }).join("|"),
            fraction: "\\d+\\/\\d+",
            state: "\\b(?:" + keys(State_Code).concat(values(State_Code)).map(XRegExp.escape).join("|") + ")\\b",
            direct: values(Directional).sort(function(a2, b2) {
              return a2.length < b2.length;
            }).reduce(function(prev, curr) {
              return prev.concat([XRegExp.escape(curr.replace(/\w/g, "$&.")), curr]);
            }, keys(Directional)).join("|"),
            dircode: keys(Direction_Code).join("|"),
            zip: "(?<zip>\\d{5})[- ]?(?<plus4>\\d{4})?",
            corner: "(?:\\band\\b|\\bat\\b|&|\\@)"
          };
          Addr_Match.number = "(?<number>(\\d+-?\\d*)|([N|S|E|W]\\d{1,3}[N|S|E|W]\\d{1,6}))(?=\\D)";
          Addr_Match.street = "                                       \n      (?:                                                       \n        (?:(?<street_0>" + Addr_Match.direct + ")\\W+               \n           (?<type_0>" + Addr_Match.type + ")\\b                    \n        )                                                       \n        |                                                       \n        (?:(?<prefix_0>" + Addr_Match.direct + ")\\W+)?             \n        (?:                                                     \n          (?<street_1>[^,]*\\d)                                 \n          (?:[^\\w,]*(?<suffix_1>" + Addr_Match.direct + ")\\b)     \n          |                                                     \n          (?<street_2>[^,]+)                                    \n          (?:[^\\w,]+(?<type_2>" + Addr_Match.type + ")\\b)         \n          (?:[^\\w,]+(?<suffix_2>" + Addr_Match.direct + ")\\b)?    \n          |                                                     \n          (?<street_3>[^,]+?)                                   \n          (?:[^\\w,]+(?<type_3>" + Addr_Match.type + ")\\b)?        \n          (?:[^\\w,]+(?<suffix_3>" + Addr_Match.direct + ")\\b)?    \n        )                                                       \n      )";
          Addr_Match.po_box = "p\\W*(?:[om]|ost\\ ?office)\\W*b(?:ox)?";
          Addr_Match.sec_unit_type_numbered = "             \n      (?<sec_unit_type_1>su?i?te                      \n        |" + Addr_Match.po_box + "                        \n        |(?:ap|dep)(?:ar)?t(?:me?nt)?                 \n        |ro*m                                         \n        |flo*r?                                       \n        |uni?t                                        \n        |bu?i?ldi?n?g                                 \n        |ha?nga?r                                     \n        |lo?t                                         \n        |pier                                         \n        |slip                                         \n        |spa?ce?                                      \n        |stop                                         \n        |tra?i?le?r                                   \n        |box)(?![a-z]                                 \n      )                                               \n      ";
          Addr_Match.sec_unit_type_unnumbered = "           \n      (?<sec_unit_type_2>ba?se?me?n?t                 \n        |fro?nt                                       \n        |lo?bby                                       \n        |lowe?r                                       \n        |off?i?ce?                                    \n        |pe?n?t?ho?u?s?e?                             \n        |rear                                         \n        |side                                         \n        |uppe?r                                       \n      )\\b";
          Addr_Match.sec_unit = "                               \n      (?:                               #fix3             \n        (?:                             #fix1             \n          (?:                                             \n            (?:" + Addr_Match.sec_unit_type_numbered + "\\W*) \n            |(?<sec_unit_type_3>\\#)\\W*                  \n          )                                               \n          (?<sec_unit_num_1>[\\w-]+)                      \n        )                                                 \n        |                                                 \n        " + Addr_Match.sec_unit_type_unnumbered + "           \n      )";
          Addr_Match.city_and_state = "                       \n      (?:                                               \n        (?<city>[^\\d,]+?)\\W+                          \n        (?<state>" + Addr_Match.state + ")                  \n      )                                                 \n      ";
          Addr_Match.place = "                                \n      (?:" + Addr_Match.city_and_state + "\\W*)?            \n      (?:" + Addr_Match.zip + ")?                           \n      ";
          Addr_Match.address = XRegExp("                      \n      ^                                                 \n      [^\\w\\#]*                                        \n      (" + Addr_Match.number + ")\\W*                       \n      (?:" + Addr_Match.fraction + "\\W*)?                  \n         " + Addr_Match.street + "\\W+                      \n      (?:" + Addr_Match.sec_unit + ")?\\W*          #fix2   \n         " + Addr_Match.place + "                           \n      \\W*$", "ix");
          var sep = "(?:\\W+|$)";
          Addr_Match.informal_address = XRegExp("                   \n      ^                                                       \n      \\s*                                                    \n      (?:" + Addr_Match.sec_unit + sep + ")?                        \n      (?:" + Addr_Match.number + ")?\\W*                          \n      (?:" + Addr_Match.fraction + "\\W*)?                        \n         " + Addr_Match.street + sep + "                            \n      (?:" + Addr_Match.sec_unit.replace(/_\d/g, "$&1") + sep + ")?  \n      (?:" + Addr_Match.place + ")?                               \n      ", "ix");
          Addr_Match.po_address = XRegExp("                         \n      ^                                                       \n      \\s*                                                    \n      (?:" + Addr_Match.sec_unit.replace(/_\d/g, "$&1") + sep + ")?  \n      (?:" + Addr_Match.place + ")?                               \n      ", "ix");
          Addr_Match.intersection = XRegExp("                     \n      ^\\W*                                                 \n      " + Addr_Match.street.replace(/_\d/g, "1$&") + "\\W*?      \n      \\s+" + Addr_Match.corner + "\\s+                         \n      " + Addr_Match.street.replace(/_\d/g, "2$&") + "\\W+     \n      " + Addr_Match.place + "\\W*$", "ix");
        }
        parser.normalize_address = function(parts) {
          lazyInit();
          if (!parts)
            return null;
          var parsed = {};
          Object.keys(parts).forEach(function(k) {
            if (["input", "index"].indexOf(k) !== -1 || isFinite(k))
              return;
            var key = isFinite(k.split("_").pop()) ? k.split("_").slice(0, -1).join("_") : k;
            if (parts[k])
              parsed[key] = parts[k].trim().replace(/^\s+|\s+$|[^\w\s\-#&]/g, "");
          });
          each(Normalize_Map, function(map, key) {
            if (parsed[key] && map[parsed[key].toLowerCase()]) {
              parsed[key] = map[parsed[key].toLowerCase()];
            }
          });
          ["type", "type1", "type2"].forEach(function(key) {
            if (key in parsed)
              parsed[key] = parsed[key].charAt(0).toUpperCase() + parsed[key].slice(1).toLowerCase();
          });
          if (parsed.city) {
            parsed.city = XRegExp.replace(
              parsed.city,
              XRegExp("^(?<dircode>" + Addr_Match.dircode + ")\\s+(?=\\S)", "ix"),
              function(match) {
                return capitalize2(Direction_Code[match.dircode.toUpperCase()]) + " ";
              }
            );
          }
          return parsed;
        };
        parser.parseAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.address);
          return parser.normalize_address(parts);
        };
        parser.parseInformalAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.informal_address);
          return parser.normalize_address(parts);
        };
        parser.parsePoAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.po_address);
          return parser.normalize_address(parts);
        };
        parser.parseLocation = function(address) {
          lazyInit();
          if (XRegExp(Addr_Match.corner, "xi").test(address)) {
            return parser.parseIntersection(address);
          }
          if (XRegExp("^" + Addr_Match.po_box, "xi").test(address)) {
            return parser.parsePoAddress(address);
          }
          return parser.parseAddress(address) || parser.parseInformalAddress(address);
        };
        parser.parseIntersection = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.intersection);
          parts = parser.normalize_address(parts);
          if (parts) {
            parts.type2 = parts.type2 || "";
            parts.type1 = parts.type1 || "";
            if (parts.type2 && !parts.type1 || parts.type1 === parts.type2) {
              var type = parts.type2;
              type = XRegExp.replace(type, /s\W*$/, "");
              if (XRegExp("^" + Addr_Match.type + "$", "ix").test(type)) {
                parts.type1 = parts.type2 = type;
              }
            }
          }
          return parts;
        };
        if (typeof define !== "undefined" && define.amd) {
          define([], function() {
            return parser;
          });
        } else if (typeof exports !== "undefined") {
          exports.parseIntersection = parser.parseIntersection;
          exports.parseLocation = parser.parseLocation;
          exports.parseInformalAddress = parser.parseInformalAddress;
          exports.parseAddress = parser.parseAddress;
        } else {
          root.addressParser = root.addressParser || parser;
        }
      })();
    }
  });

  // entry-points/apple.js
  init_define_import_meta_trackerLookup();

  // src/content-scope-features.js
  init_define_import_meta_trackerLookup();

  // src/utils.js
  init_define_import_meta_trackerLookup();

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
  init_define_import_meta_trackerLookup();
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
  var isAppleSiliconCache = null;
  var OriginalCustomEvent = typeof CustomEvent === "undefined" ? null : CustomEvent;
  var originalWindowDispatchEvent = typeof window === "undefined" ? null : window.dispatchEvent.bind(window);
  function registerMessageSecret(secret) {
    messageSecret = secret;
  }
  function getGlobal() {
    return globalObj;
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
  function isFeatureBroken(args, feature) {
    const isFeatureEnabled = args.site.enabledFeatures?.includes(feature) ?? false;
    if (isPlatformSpecificFeature(feature)) {
      return !isFeatureEnabled;
    }
    return args.site.isBroken || args.site.allowlisted || !isFeatureEnabled;
  }
  function camelcase(dashCaseText) {
    return dashCaseText.replace(/-(.)/g, (_2, letter) => {
      return letter.toUpperCase();
    });
  }
  function isAppleSilicon() {
    if (isAppleSiliconCache !== null) {
      return isAppleSiliconCache;
    }
    const canvas = document.createElement("canvas");
    const gl = canvas.getContext("webgl");
    const compressedTextureValue = gl?.getSupportedExtensions()?.indexOf("WEBGL_compressed_texture_etc");
    isAppleSiliconCache = typeof compressedTextureValue === "number" && compressedTextureValue !== -1;
    return isAppleSiliconCache;
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
          const selectedSetting = processAttrByCriteria(configSetting);
          if (selectedSetting === void 0) {
            return defaultValue;
          }
          return processAttr(selectedSetting, defaultValue);
        }
        if (!configSetting.type) {
          return defaultValue;
        }
        if (configSetting.type === "function") {
          if (configSetting.functionName && functionMap[configSetting.functionName]) {
            return functionMap[configSetting.functionName];
          }
          if (configSetting.functionValue) {
            const functionValue = configSetting.functionValue;
            return () => processAttr(functionValue, void 0);
          }
        }
        if (configSetting.type === "undefined") {
          return void 0;
        }
        if (configSetting.async) {
          return DDGPromise.resolve(configSetting.value);
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
  function getPlatformVersion(preferences) {
    if (preferences.versionNumber) {
      return preferences.versionNumber;
    }
    if (preferences.versionString) {
      return preferences.versionString;
    }
    return void 0;
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
  function isMaxSupportedVersion(maxSupportedVersion, currentVersion) {
    if (typeof currentVersion === "string" && typeof maxSupportedVersion === "string") {
      if (satisfiesMinVersion(currentVersion, maxSupportedVersion)) {
        return true;
      }
    } else if (typeof currentVersion === "number" && typeof maxSupportedVersion === "number") {
      if (maxSupportedVersion >= currentVersion) {
        return true;
      }
    }
    return false;
  }
  function processConfig(data2, userList, preferences, platformSpecificFeatures2 = []) {
    const topLevelHostname = getTabHostname();
    const site = computeLimitedSiteObject();
    const allowlisted = userList.filter((domain) => domain === topLevelHostname).length > 0;
    const output = { ...preferences };
    if (output.platform) {
      const version = getPlatformVersion(preferences);
      if (version) {
        output.platform.version = version;
      }
    }
    const enabledFeatures = computeEnabledFeatures(data2, topLevelHostname, preferences.platform?.version, platformSpecificFeatures2);
    const isBroken = isUnprotectedDomain(topLevelHostname, data2.unprotectedTemporary);
    output.site = Object.assign(site, {
      isBroken,
      allowlisted,
      enabledFeatures
    });
    output.featureSettings = parseFeatureSettings(data2, enabledFeatures);
    output.bundledConfig = data2;
    return output;
  }
  function computeEnabledFeatures(data2, topLevelHostname, platformVersion, platformSpecificFeatures2 = []) {
    const remoteFeatureNames = Object.keys(data2.features);
    const platformSpecificFeaturesNotInRemoteConfig = platformSpecificFeatures2.filter(
      (featureName) => !remoteFeatureNames.includes(featureName)
    );
    const enabledFeatures = remoteFeatureNames.filter((featureName) => {
      const feature = data2.features[featureName];
      if (feature.minSupportedVersion && platformVersion) {
        if (!isSupportedVersion(feature.minSupportedVersion, platformVersion)) {
          return false;
        }
      }
      return feature.state === "enabled" && !isUnprotectedDomain(topLevelHostname, feature.exceptions);
    }).concat(platformSpecificFeaturesNotInRemoteConfig);
    return enabledFeatures;
  }
  function parseFeatureSettings(data2, enabledFeatures) {
    const featureSettings = {};
    const remoteFeatureNames = Object.keys(data2.features);
    remoteFeatureNames.forEach((featureName) => {
      if (!enabledFeatures.includes(featureName)) {
        return;
      }
      featureSettings[featureName] = data2.features[featureName].settings;
    });
    return featureSettings;
  }
  function isGloballyDisabled(args) {
    return args.site.allowlisted || args.site.isBroken;
  }
  var platformSpecificFeatures = ["navigatorInterface", "windowsPermissionUsage", "messageBridge", "favicon"];
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
  init_define_import_meta_trackerLookup();
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
      "webTelemetry",
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
    "android-adsjs": [
      "apiManipulation",
      "webCompat",
      "fingerprintingHardware",
      "fingerprintingScreenSize",
      "fingerprintingTemporaryStorage",
      "fingerprintingAudio",
      "fingerprintingBattery",
      "gpc",
      "breakageReporting"
    ],
    windows: [
      "cookie",
      ...baseFeatures,
      "webTelemetry",
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
  init_define_import_meta_trackerLookup();
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

  // ddg:platformFeatures:ddg:platformFeatures
  init_define_import_meta_trackerLookup();

  // src/features/duck-player.js
  init_define_import_meta_trackerLookup();

  // src/content-feature.js
  init_define_import_meta_trackerLookup();

  // src/wrapper-utils.js
  init_define_import_meta_trackerLookup();
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

  // ../messaging/index.js
  init_define_import_meta_trackerLookup();

  // ../messaging/lib/windows.js
  init_define_import_meta_trackerLookup();
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
      const data2 = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
      const notification = WindowsNotification.fromNotification(msg, data2);
      this.config.methods.postMessage(notification);
    }
    /**
     * @param {import('../index.js').RequestMessage} msg
     * @param {{signal?: AbortSignal}} opts
     * @return {Promise<any>}
     */
    request(msg, opts = {}) {
      const data2 = this.globals.JSONparse(this.globals.JSONstringify(msg.params || {}));
      const outgoing = WindowsRequestMessage.fromRequest(msg, data2);
      this.config.methods.postMessage(outgoing);
      const comparator = (eventData) => {
        return eventData.featureName === msg.featureName && eventData.context === msg.context && eventData.id === msg.id;
      };
      function isMessageResponse(data3) {
        if ("result" in data3) return true;
        if ("error" in data3) return true;
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
    static fromNotification(notification, data2) {
      const output = {
        Data: data2,
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
    static fromRequest(msg, data2) {
      const output = {
        Data: data2,
        Feature: msg.context,
        SubFeatureName: msg.featureName,
        Name: msg.method,
        Id: msg.id
      };
      return output;
    }
  };

  // ../messaging/lib/webkit.js
  init_define_import_meta_trackerLookup();

  // ../messaging/schema.js
  init_define_import_meta_trackerLookup();
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
  function isResponseFor(request, data2) {
    if ("result" in data2) {
      return data2.featureName === request.featureName && data2.context === request.context && data2.id === request.id;
    }
    if ("error" in data2) {
      if ("message" in data2.error) {
        return true;
      }
    }
    return false;
  }
  function isSubscriptionEventFor(sub, data2) {
    if ("subscriptionName" in data2) {
      return data2.featureName === sub.featureName && data2.context === sub.context && data2.subscriptionName === sub.subscriptionName;
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
    wkSend(handler, data2 = {}) {
      if (!(handler in this.globals.window.webkit.messageHandlers)) {
        throw new MissingHandler(`Missing webkit handler: '${handler}'`, handler);
      }
      if (!this.config.hasModernWebkitAPI) {
        const outgoing = {
          ...data2,
          messageHandling: {
            ...data2.messageHandling,
            secret: this.config.secret
          }
        };
        if (!(handler in this.globals.capturedWebkitHandlers)) {
          throw new MissingHandler(`cannot continue, method ${handler} not captured on macos < 11`, handler);
        } else {
          return this.globals.capturedWebkitHandlers[handler](outgoing);
        }
      }
      return this.globals.window.webkit.messageHandlers[handler].postMessage?.(data2);
    }
    /**
     * Sends message to the webkit layer and waits for the specified response
     * @param {String} handler
     * @param {import('../index.js').RequestMessage} data
     * @returns {Promise<*>}
     * @internal
     */
    async wkSendAndWait(handler, data2) {
      if (this.config.hasModernWebkitAPI) {
        const response = await this.wkSend(handler, data2);
        return this.globals.JSONparse(response || "{}");
      }
      try {
        const randMethodName = this.createRandMethodName();
        const key = await this.createRandKey();
        const iv = this.createRandIv();
        const { ciphertext, tag } = await new this.globals.Promise((resolve) => {
          this.generateRandomMethod(randMethodName, resolve);
          data2.messageHandling = new SecureMessagingParams({
            methodName: randMethodName,
            secret: this.config.secret,
            key: this.globals.Arrayfrom(key),
            iv: this.globals.Arrayfrom(iv)
          });
          this.wkSend(handler, data2);
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
      const data2 = await this.wkSendAndWait(msg.context, msg);
      if (isResponseFor(msg, data2)) {
        if (data2.result) {
          return data2.result || {};
        }
        if (data2.error) {
          throw new Error(data2.error.message);
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
        value: (data2) => {
          if (data2 && isSubscriptionEventFor(msg, data2)) {
            callback(data2.params);
          } else {
            console.warn("Received a message that did not match the subscription", data2);
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
  init_define_import_meta_trackerLookup();
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
        function handler(data2) {
          if (isResponseFor(msg, data2)) {
            if (data2.result) {
              resolve(data2.result || {});
              return unsub();
            }
            if (data2.error) {
              reject(new Error(data2.error.message));
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
      const unsub = this.config.subscribe(msg.subscriptionName, (data2) => {
        if (isSubscriptionEventFor(msg, data2)) {
          callback(data2.params || {});
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

  // ../messaging/lib/android-adsjs.js
  init_define_import_meta_trackerLookup();
  var AndroidAdsjsMessagingTransport = class {
    /**
     * @param {AndroidAdsjsMessagingConfig} config
     * @param {MessagingContext} messagingContext
     * @internal
     */
    constructor(config2, messagingContext) {
      this.messagingContext = messagingContext;
      this.config = config2;
      this.config.sendInitialPing(messagingContext);
    }
    /**
     * @param {NotificationMessage} msg
     */
    notify(msg) {
      try {
        this.config.sendMessageThrows?.(msg);
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
          this.config.sendMessageThrows?.(msg);
        } catch (e) {
          unsub();
          reject(new Error("request failed to send: " + e.message || "unknown error"));
        }
        function handler(data2) {
          if (isResponseFor(msg, data2)) {
            if (data2.result) {
              resolve(data2.result || {});
              return unsub();
            }
            if (data2.error) {
              reject(new Error(data2.error.message));
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
      const unsub = this.config.subscribe(msg.subscriptionName, (data2) => {
        if (isSubscriptionEventFor(msg, data2)) {
          callback(data2.params || {});
        }
      });
      return () => {
        unsub();
      };
    }
  };
  var AndroidAdsjsMessagingConfig = class {
    /**
     * @param {object} params
     * @param {Record<string, any>} params.target
     * @param {boolean} params.debug
     * @param {string} params.objectName - the object name for addWebMessageListener
     */
    constructor(params) {
      /** @type {{
       * postMessage: (message: string) => void,
       * addEventListener: (type: string, listener: (event: MessageEvent) => void) => void,
       * } | null} */
      __publicField(this, "_capturedHandler");
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
    _tryCatch(fn, context = "none") {
      try {
        return fn();
      } catch (e) {
        if (this.debug) {
          console.error("AndroidAdsjsMessagingConfig error:", context);
          console.error(e);
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
          const data2 = (
            /** @type {MessageEvent} */
            event.data
          );
          if (typeof data2 === "string") {
            const parsedData = JSON.parse(data2);
            this._dispatch(parsedData);
          }
        } catch (e) {
          this._log("Error processing incoming message:", e);
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
      } catch (e) {
        this._log("Failed to send initial ping:", e);
        return false;
      }
    }
  };

  // ../messaging/lib/typed-messages.js
  init_define_import_meta_trackerLookup();

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
    notify(name, data2 = {}) {
      const message = new NotificationMessage({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        method: name,
        params: data2
      });
      try {
        this.transport.notify(message);
      } catch (e) {
        if (this.messagingContext.env === "development") {
          console.error("[Messaging] Failed to send notification:", e);
          console.error("[Messaging] Message details:", { name, data: data2 });
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
    request(name, data2 = {}) {
      const id = globalThis?.crypto?.randomUUID?.() || name + ".response";
      const message = new RequestMessage({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        method: name,
        params: data2,
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
    if (config2 instanceof AndroidAdsjsMessagingConfig) {
      return new AndroidAdsjsMessagingTransport(config2, messagingContext);
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
  function isTrackerOrigin(trackerLookup, originHostname = getGlobal().document.location.hostname) {
    const parts = originHostname.split(".").reverse();
    let node = trackerLookup;
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

  // src/config-feature.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/index.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/immutabilityHelpers.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/typeguards.js
  init_define_import_meta_trackerLookup();
  function isJSONArray(value) {
    return Array.isArray(value);
  }
  function isJSONObject(value) {
    return value !== null && typeof value === "object" && (value.constructor === void 0 || // for example Object.create(null)
    value.constructor.name === "Object");
  }

  // ../node_modules/immutable-json-patch/lib/esm/utils.js
  init_define_import_meta_trackerLookup();
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
    }
    if (isJSONObject(value)) {
      const copy2 = {
        ...value
      };
      Object.getOwnPropertySymbols(value).forEach((symbol) => {
        copy2[symbol] = value[symbol];
      });
      return copy2;
    }
    return value;
  }
  function applyProp(object, key, value) {
    if (object[key] === value) {
      return object;
    }
    const updatedObject = shallowClone(object);
    updatedObject[key] = value;
    return updatedObject;
  }
  function getIn(object, path) {
    let value = object;
    let i = 0;
    while (i < path.length) {
      if (isJSONObject(value)) {
        value = value[path[i]];
      } else if (isJSONArray(value)) {
        value = value[Number.parseInt(path[i])];
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
    }
    if (createPath) {
      const newObject = IS_INTEGER_REGEX.test(key) ? [] : {};
      newObject[key] = updatedValue;
      return newObject;
    }
    throw new Error("Path does not exist");
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
      }
      const updatedObject = shallowClone(object);
      if (isJSONArray(updatedObject)) {
        updatedObject.splice(Number.parseInt(key2), 1);
      }
      if (isJSONObject(updatedObject)) {
        delete updatedObject[key2];
      }
      return updatedObject;
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
        throw new TypeError(`Array expected at path ${JSON.stringify(parentPath)}`);
      }
      const updatedItems = shallowClone(items);
      updatedItems.splice(Number.parseInt(index), 0, value);
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

  // ../node_modules/immutable-json-patch/lib/esm/immutableJSONPatch.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/jsonPointer.js
  init_define_import_meta_trackerLookup();
  function parseJSONPointer(pointer) {
    const path = pointer.split("/");
    path.shift();
    return path.map((p) => p.replace(/~1/g, "/").replace(/~0/g, "~"));
  }
  function compileJSONPointer(path) {
    return path.map(compileJSONPointerProp).join("");
  }
  function compileJSONPointerProp(pathProp) {
    return `/${String(pathProp).replace(/~/g, "~0").replace(/\//g, "~1")}`;
  }

  // ../node_modules/immutable-json-patch/lib/esm/immutableJSONPatch.js
  function immutableJSONPatch(document2, operations, options) {
    let updatedDocument = document2;
    for (let i = 0; i < operations.length; i++) {
      validateJSONPatchOperation(operations[i]);
      let operation = operations[i];
      if (options?.before) {
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
        throw new Error(`Unknown JSONPatch operation ${JSON.stringify(operation)}`);
      }
      if (options?.after) {
        const result = options.after(updatedDocument, operation, previousDocument);
        if (result !== void 0) {
          updatedDocument = result;
        }
      }
    }
    return updatedDocument;
  }
  function replace(document2, path, value) {
    return existsIn(document2, path) ? setIn(document2, path, value) : document2;
  }
  function remove(document2, path) {
    return deleteIn(document2, path);
  }
  function add(document2, path, value) {
    if (isArrayItem(document2, path)) {
      return insertAt(document2, path, value);
    }
    return setIn(document2, path, value);
  }
  function copy(document2, path, from) {
    const value = getIn(document2, from);
    if (isArrayItem(document2, path)) {
      return insertAt(document2, path, value);
    }
    return setIn(document2, path, value);
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
      throw new Error(`Unknown JSONPatch op ${JSON.stringify(operation.op)}`);
    }
    if (typeof operation.path !== "string") {
      throw new Error(`Required property "path" missing or not a string in operation ${JSON.stringify(operation)}`);
    }
    if (operation.op === "copy" || operation.op === "move") {
      if (typeof operation.from !== "string") {
        throw new Error(`Required property "from" missing or not a string in operation ${JSON.stringify(operation)}`);
      }
    }
  }
  function parsePath(document2, pointer) {
    return resolvePathIndex(document2, parseJSONPointer(pointer));
  }
  function parseFrom(fromPointer) {
    return parseJSONPointer(fromPointer);
  }

  // ../node_modules/urlpattern-polyfill/index.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/urlpattern-polyfill/dist/urlpattern.js
  init_define_import_meta_trackerLookup();
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
     * Getter for injectName, will be overridden by subclasses (namely ContentFeature)
     * @returns {string | undefined}
     */
    get injectName() {
      return void 0;
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
        let condition2 = rule.condition;
        if (condition2 === void 0 && "domain" in rule) {
          condition2 = this._domainToConditonBlocks(rule.domain);
        }
        return this._matchConditionalBlockOrArray(condition2);
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
     * @property {object} [maxSupportedVersion]
     * @property {object} [experiment]
     * @property {string} [experiment.experimentName]
     * @property {string} [experiment.cohort]
     * @property {object} [context]
     * @property {boolean} [context.frame] - true if the condition applies to frames
     * @property {boolean} [context.top] - true if the condition applies to the top frame
     * @property {string} [injectName] - the inject name to match against (e.g., "apple-isolated")
     * @property {boolean} [internal] - true if the condition applies to internal builds
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
        context: this._matchContextConditional,
        urlPattern: this._matchUrlPatternConditional,
        experiment: this._matchExperimentConditional,
        minSupportedVersion: this._matchMinSupportedVersion,
        maxSupportedVersion: this._matchMaxSupportedVersion,
        injectName: this._matchInjectNameConditional,
        internal: this._matchInternalConditional
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
     * Takes a condition block and returns true if the current context matches the context.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchContextConditional(conditionBlock) {
      if (!conditionBlock.context) return false;
      const isFrame = window.self !== window.top;
      if (conditionBlock.context.frame && isFrame) {
        return true;
      }
      if (conditionBlock.context.top && !isFrame) {
        return true;
      }
      return false;
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
     * Takes a condition block and returns true if the current inject name matches the injectName.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchInjectNameConditional(conditionBlock) {
      if (!conditionBlock.injectName) return false;
      const currentInjectName = this.injectName;
      if (!currentInjectName) return false;
      return conditionBlock.injectName === currentInjectName;
    }
    /**
     * Takes a condition block and returns true if the internal state matches the condition.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchInternalConditional(conditionBlock) {
      if (conditionBlock.internal === void 0) return false;
      const isInternal = __privateGet(this, _args)?.platform?.internal;
      if (isInternal === void 0) return false;
      return Boolean(conditionBlock.internal) === Boolean(isInternal);
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
     * Takes a condition block and returns true if the platform version satisfies the `maxSupportedFeature`
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchMaxSupportedVersion(conditionBlock) {
      if (!conditionBlock.maxSupportedVersion) return false;
      return isMaxSupportedVersion(conditionBlock.maxSupportedVersion, __privateGet(this, _args)?.platform?.version);
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
     * @param {'enabled' | 'disabled'} [defaultState]
     * @param {string} [featureName]
     * @returns {boolean}
     */
    getFeatureSettingEnabled(featureKeyName, defaultState, featureName) {
      const result = this.getFeatureSetting(featureKeyName, featureName) || defaultState;
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
      /**
       * Set this to true if you wish to get update calls (legacy).
       * @type {boolean}
       */
      __publicField(this, "listenForUpdateChanges", false);
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

  // src/features/duckplayer/overlay-messages.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/constants.js
  init_define_import_meta_trackerLookup();
  var MSG_NAME_INITIAL_SETUP = "initialSetup";
  var MSG_NAME_SET_VALUES = "setUserValues";
  var MSG_NAME_READ_VALUES = "getUserValues";
  var MSG_NAME_READ_VALUES_SERP = "readUserValues";
  var MSG_NAME_OPEN_PLAYER = "openDuckPlayer";
  var MSG_NAME_OPEN_INFO = "openInfo";
  var MSG_NAME_PUSH_DATA = "onUserValuesChanged";
  var MSG_NAME_PIXEL = "sendDuckPlayerPixel";
  var MSG_NAME_PROXY_INCOMING = "ddg-serp-yt";
  var MSG_NAME_PROXY_RESPONSE = "ddg-serp-yt-response";

  // src/features/duckplayer/overlay-messages.js
  var DuckPlayerOverlayMessages = class {
    /**
     * @param {Messaging} messaging
     * @param {import('./environment.js').Environment} environment
     * @internal
     */
    constructor(messaging, environment) {
      this.messaging = messaging;
      this.environment = environment;
    }
    /**
     * @returns {Promise<import("../duck-player.js").OverlaysInitialSettings>}
     */
    initialSetup() {
      if (this.environment.isIntegrationMode()) {
        return Promise.resolve({
          userValues: {
            overlayInteracted: false,
            privatePlayerMode: { alwaysAsk: {} }
          },
          ui: {}
        });
      }
      return this.messaging.request(MSG_NAME_INITIAL_SETUP);
    }
    /**
     * Inform the native layer that an interaction occurred
     * @param {import("../duck-player.js").UserValues} userValues
     * @returns {Promise<import("../duck-player.js").UserValues>}
     */
    setUserValues(userValues) {
      return this.messaging.request(MSG_NAME_SET_VALUES, userValues);
    }
    /**
     * @returns {Promise<import("../duck-player.js").UserValues>}
     */
    getUserValues() {
      return this.messaging.request(MSG_NAME_READ_VALUES, {});
    }
    /**
     * @param {Pixel} pixel
     */
    sendPixel(pixel) {
      this.messaging.notify(MSG_NAME_PIXEL, {
        pixelName: pixel.name(),
        params: pixel.params()
      });
    }
    /**
     * This is sent when the user wants to open Duck Player.
     * See {@link OpenInDuckPlayerMsg} for params
     * @param {OpenInDuckPlayerMsg} params
     */
    openDuckPlayer(params) {
      return this.messaging.notify(MSG_NAME_OPEN_PLAYER, params);
    }
    /**
     * This is sent when the user wants to open Duck Player.
     */
    openInfo() {
      return this.messaging.notify(MSG_NAME_OPEN_INFO);
    }
    /**
     * Get notification when preferences/state changed
     * @param {(userValues: import("../duck-player.js").UserValues) => void} cb
     */
    onUserValuesChanged(cb) {
      return this.messaging.subscribe("onUserValuesChanged", cb);
    }
    /**
     * Get notification when ui settings changed
     * @param {(userValues: import("../duck-player.js").UISettings) => void} cb
     */
    onUIValuesChanged(cb) {
      return this.messaging.subscribe("onUIValuesChanged", cb);
    }
    /**
     * This allows our SERP to interact with Duck Player settings.
     */
    serpProxy() {
      function respond(kind, data2) {
        window.dispatchEvent(
          new CustomEvent(MSG_NAME_PROXY_RESPONSE, {
            detail: { kind, data: data2 },
            composed: true,
            bubbles: true
          })
        );
      }
      this.onUserValuesChanged((values) => {
        respond(MSG_NAME_PUSH_DATA, values);
      });
      window.addEventListener(MSG_NAME_PROXY_INCOMING, (evt) => {
        try {
          assertCustomEvent(evt);
          if (evt.detail.kind === MSG_NAME_SET_VALUES) {
            return this.setUserValues(evt.detail.data).then((updated) => respond(MSG_NAME_PUSH_DATA, updated)).catch(console.error);
          }
          if (evt.detail.kind === MSG_NAME_READ_VALUES_SERP) {
            return this.getUserValues().then((updated) => respond(MSG_NAME_PUSH_DATA, updated)).catch(console.error);
          }
          if (evt.detail.kind === MSG_NAME_OPEN_INFO) {
            return this.openInfo();
          }
          console.warn("unhandled event", evt);
        } catch (e) {
          console.warn("cannot handle this message", e);
        }
      });
    }
  };
  function assertCustomEvent(event) {
    if (!("detail" in event)) throw new Error("none-custom event");
    if (typeof event.detail.kind !== "string") throw new Error("custom event requires detail.kind to be a string");
  }
  var Pixel = class {
    /**
     * A list of known pixels
     * @param {{name: "overlay"}
     *   | {name: "play.use", remember: "0" | "1"}
     *   | {name: "play.use.thumbnail"}
     *   | {name: "play.do_not_use", remember: "0" | "1"}
     *   | {name: "play.do_not_use.dismiss"}} input
     */
    constructor(input) {
      this.input = input;
    }
    name() {
      return this.input.name;
    }
    params() {
      switch (this.input.name) {
        case "overlay":
          return {};
        case "play.use.thumbnail":
          return {};
        case "play.use":
        case "play.do_not_use": {
          return { remember: this.input.remember };
        }
        case "play.do_not_use.dismiss":
          return {};
        default:
          throw new Error("unreachable");
      }
    }
  };
  var OpenInDuckPlayerMsg = class {
    /**
     * @param {object} params
     * @param {string} params.href
     */
    constructor(params) {
      this.href = params.href;
    }
  };

  // src/features/duckplayer/overlays.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/util.js
  init_define_import_meta_trackerLookup();
  function appendImageAsBackground(parent, targetSelector, imageUrl) {
    const canceled = false;
    fetch(imageUrl, { method: "HEAD" }).then((x2) => {
      const status = String(x2.status);
      if (canceled) return console.warn("not adding image, cancelled");
      if (status.startsWith("2")) {
        if (!canceled) {
          append();
        } else {
          console.warn("ignoring cancelled load");
        }
      } else {
        markError();
      }
    }).catch(() => {
      console.error("e from fetch");
    });
    function markError() {
      parent.dataset.thumbLoaded = String(false);
      parent.dataset.error = String(true);
    }
    function append() {
      const targetElement = parent.querySelector(targetSelector);
      if (!(targetElement instanceof HTMLElement)) {
        return console.warn("could not find child with selector", targetSelector, "from", parent);
      }
      parent.dataset.thumbLoaded = String(true);
      parent.dataset.thumbSrc = imageUrl;
      const img = new Image();
      img.src = imageUrl;
      img.onload = function() {
        if (canceled) return console.warn("not adding image, cancelled");
        targetElement.style.backgroundImage = `url(${imageUrl})`;
        targetElement.style.backgroundSize = "cover";
      };
      img.onerror = function() {
        if (canceled) return console.warn("not calling markError, cancelled");
        markError();
        const targetElement2 = parent.querySelector(targetSelector);
        if (!(targetElement2 instanceof HTMLElement)) return;
        targetElement2.style.backgroundImage = "";
      };
    }
  }
  var SideEffects = class {
    /**
     * @param {object} params
     * @param {boolean} [params.debug]
     */
    constructor({ debug: debug2 = false } = {}) {
      /** @type {{fn: () => void, name: string}[]} */
      __publicField(this, "_cleanups", []);
      this.debug = debug2;
    }
    /**
     * Wrap a side-effecting operation for easier debugging
     * and teardown/release of resources
     * @param {string} name
     * @param {() => () => void} fn
     */
    add(name, fn) {
      try {
        if (this.debug) {
          console.log("\u2622\uFE0F", name);
        }
        const cleanup = fn();
        if (typeof cleanup === "function") {
          this._cleanups.push({ name, fn: cleanup });
        }
      } catch (e) {
        console.error("%s threw an error", name, e);
      }
    }
    /**
     * Remove elements, event listeners etc
     * @param {string} [name]
     */
    destroy(name) {
      const cleanups = name ? this._cleanups.filter((c) => c.name === name) : this._cleanups;
      for (const cleanup of cleanups) {
        if (typeof cleanup.fn === "function") {
          try {
            if (this.debug) {
              console.log("\u{1F5D1}\uFE0F", cleanup.name);
            }
            cleanup.fn();
          } catch (e) {
            console.error(`cleanup ${cleanup.name} threw`, e);
          }
        } else {
          throw new Error("invalid cleanup");
        }
      }
      if (name) {
        this._cleanups = this._cleanups.filter((c) => c.name !== name);
      } else {
        this._cleanups = [];
      }
    }
  };
  var _VideoParams = class _VideoParams {
    /**
     * @param {string} id - the YouTube video ID
     * @param {string|null|undefined} time - an optional time
     */
    constructor(id, time) {
      this.id = id;
      this.time = time;
    }
    /**
     * @returns {string}
     */
    toPrivatePlayerUrl() {
      const duckUrl = new URL(`duck://player/${this.id}`);
      if (this.time) {
        duckUrl.searchParams.set("t", this.time);
      }
      return duckUrl.href;
    }
    /**
     * Get the large thumbnail URL for the current video id
     *
     * @returns {string}
     */
    toLargeThumbnailUrl() {
      const url = new URL(`/vi/${this.id}/maxresdefault.jpg`, "https://i.ytimg.com");
      return url.href;
    }
    /**
     * Create a VideoParams instance from a href, only if it's on the watch page
     *
     * @param {string} href
     * @returns {VideoParams|null}
     */
    static forWatchPage(href) {
      let url;
      try {
        url = new URL(href);
      } catch (e) {
        return null;
      }
      if (!url.pathname.startsWith("/watch")) {
        return null;
      }
      return _VideoParams.fromHref(url.href);
    }
    /**
     * Convert a relative pathname into VideoParams
     *
     * @param pathname
     * @returns {VideoParams|null}
     */
    static fromPathname(pathname) {
      let url;
      try {
        url = new URL(pathname, window.location.origin);
      } catch (e) {
        return null;
      }
      return _VideoParams.fromHref(url.href);
    }
    /**
     * Convert a href into valid video params. Those can then be converted into a private player
     * link when needed
     *
     * @param href
     * @returns {VideoParams|null}
     */
    static fromHref(href) {
      let url;
      try {
        url = new URL(href);
      } catch (e) {
        return null;
      }
      let id = null;
      const vParam = url.searchParams.get("v");
      const tParam = url.searchParams.get("t");
      let time = null;
      if (vParam && _VideoParams.validVideoId.test(vParam)) {
        id = vParam;
      } else {
        return null;
      }
      if (tParam && _VideoParams.validTimestamp.test(tParam)) {
        time = tParam;
      }
      return new _VideoParams(id, time);
    }
  };
  __publicField(_VideoParams, "validVideoId", /^[a-zA-Z0-9-_]+$/);
  __publicField(_VideoParams, "validTimestamp", /^[0-9hms]+$/);
  var VideoParams = _VideoParams;
  var DomState = class {
    constructor() {
      __publicField(this, "loaded", false);
      __publicField(this, "loadedCallbacks", []);
      window.addEventListener("DOMContentLoaded", () => {
        this.loaded = true;
        this.loadedCallbacks.forEach((cb) => cb());
      });
    }
    onLoaded(loadedCallback) {
      if (this.loaded) return loadedCallback();
      this.loadedCallbacks.push(loadedCallback);
    }
  };
  var Logger = class {
    /**
     * @param {object} options
     * @param {string} options.id - Prefix added to log output
     * @param {() => boolean} options.shouldLog - Tells logger whether to output to console
     */
    constructor({ id, shouldLog }) {
      /** @type {string} */
      __publicField(this, "id");
      /** @type {() => boolean} */
      __publicField(this, "shouldLog");
      if (!id || !shouldLog) {
        throw new Error("Missing props in Logger");
      }
      this.shouldLog = shouldLog;
      this.id = id;
    }
    error(...args) {
      this.output(console.error, args);
    }
    info(...args) {
      this.output(console.info, args);
    }
    log(...args) {
      this.output(console.log, args);
    }
    warn(...args) {
      this.output(console.warn, args);
    }
    output(handler, args) {
      if (this.shouldLog()) {
        handler(`${this.id.padEnd(20, " ")} |`, ...args);
      }
    }
  };

  // src/features/duckplayer/thumbnails.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/icon-overlay.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/assets/styles.css
  var styles_default = '/* -- THUMBNAIL OVERLAY -- */\n.ddg-overlay {\n    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";\n    position: absolute;\n    margin-top: 5px;\n    margin-left: 5px;\n    z-index: 1000;\n    height: 32px;\n\n    background: rgba(0, 0, 0, 0.6);\n    box-shadow: 0px 1px 2px rgba(0, 0, 0, 0.25), 0px 4px 8px rgba(0, 0, 0, 0.1), inset 0px 0px 0px 1px rgba(0, 0, 0, 0.18);\n    backdrop-filter: blur(2px);\n    -webkit-backdrop-filter: blur(2px);\n    border-radius: 6px;\n\n    transition: 0.15s linear background;\n}\n\n.ddg-overlay a.ddg-play-privately {\n    color: white;\n    text-decoration: none;\n    font-style: normal;\n    font-weight: 600;\n    font-size: 12px;\n}\n\n.ddg-overlay .ddg-dax,\n.ddg-overlay .ddg-play-icon {\n    display: inline-block;\n\n}\n\n.ddg-overlay .ddg-dax {\n    float: left;\n    padding: 4px 4px;\n    width: 24px;\n    height: 24px;\n}\n\n.ddg-overlay .ddg-play-text-container {\n    width: 0px;\n    overflow: hidden;\n    float: left;\n    opacity: 0;\n    transition: all 0.15s linear;\n}\n\n.ddg-overlay .ddg-play-text {\n    line-height: 14px;\n    margin-top: 10px;\n    width: 200px;\n}\n\n.ddg-overlay .ddg-play-icon {\n    float: right;\n    width: 24px;\n    height: 20px;\n    padding: 6px 4px;\n}\n\n.ddg-overlay:not([data-size="fixed small"]):hover .ddg-play-text-container {\n    width: 80px;\n    opacity: 1;\n}\n\n.ddg-overlay[data-size^="video-player"].hidden {\n    display: none;\n}\n\n.ddg-overlay[data-size="video-player"] {\n    bottom: 145px;\n    right: 20px;\n    opacity: 1;\n    transition: opacity .2s;\n}\n\n.html5-video-player.playing-mode.ytp-autohide .ddg-overlay[data-size="video-player"] {\n    opacity: 0;\n}\n\n.html5-video-player.ad-showing .ddg-overlay[data-size="video-player"] {\n    display: none;\n}\n\n.html5-video-player.ytp-hide-controls .ddg-overlay[data-size="video-player"] {\n    display: none;\n}\n\n.ddg-overlay[data-size="video-player-with-title"] {\n    top: 40px;\n    left: 10px;\n}\n\n.ddg-overlay[data-size="video-player-with-paid-content"] {\n    top: 65px;\n    left: 11px;\n}\n\n.ddg-overlay[data-size="title"] {\n    position: relative;\n    margin: 0;\n    float: right;\n}\n\n.ddg-overlay[data-size="title"] .ddg-play-text-container {\n    width: 90px;\n}\n\n.ddg-overlay[data-size^="fixed"] {\n    position: absolute;\n    top: 0;\n    left: 0;\n    display: none;\n    z-index: 10;\n}\n\n#preview .ddg-overlay {\n    transition: transform 160ms ease-out 200ms;\n    /*TODO: scale needs to equal 1/--ytd-video-preview-initial-scale*/\n    transform: scale(1.15) translate(5px, 4px);\n}\n\n#preview ytd-video-preview[active] .ddg-overlay {\n    transform:scale(1) translate(0px, 0px);\n}\n';

  // src/features/duckplayer/assets/dax.svg
  var dax_default = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none"><path fill="#DE5833" fill-rule="evenodd" d="M16 32c8.837 0 16-7.163 16-16S24.837 0 16 0 0 7.163 0 16s7.163 16 16 16Z" clip-rule="evenodd"/><path fill="#DDD" fill-rule="evenodd" d="M18.25 27.938c0-.125.03-.154-.367-.946-1.056-2.115-2.117-5.096-1.634-7.019.088-.349-.995-12.936-1.76-13.341-.85-.453-1.898-1.172-2.855-1.332-.486-.078-1.123-.041-1.62.026-.089.012-.093.17-.008.2.327.11.724.302.958.593.044.055-.016.142-.086.144-.22.008-.62.1-1.148.549-.061.052-.01.148.068.133 1.134-.225 2.292-.114 2.975.506.044.04.021.113-.037.128-5.923 1.61-4.75 6.763-3.174 13.086 1.405 5.633 1.934 7.448 2.1 8.001a.18.18 0 0 0 .106.117c2.039.812 6.482.848 6.482-.533v-.313Z" clip-rule="evenodd"/><path fill="#fff" fill-rule="evenodd" d="M30.688 16c0 8.112-6.576 14.688-14.688 14.688-8.112 0-14.688-6.576-14.688-14.688C1.313 7.888 7.888 1.312 16 1.312c8.112 0 14.688 6.576 14.688 14.688ZM12.572 28.996a140.697 140.697 0 0 1-2.66-9.48L9.8 19.06v-.003C8.442 13.516 7.334 8.993 13.405 7.57c.055-.013.083-.08.046-.123-.697-.826-2.001-1.097-3.651-.528-.068.024-.127-.045-.085-.102.324-.446.956-.79 1.268-.94.065-.03.06-.125-.008-.146a6.968 6.968 0 0 0-.942-.225c-.093-.015-.101-.174-.008-.186 2.339-.315 4.781.387 6.007 1.931a.081.081 0 0 0 .046.029c4.488.964 4.81 8.058 4.293 8.382-.102.063-.429.027-.86-.021-1.746-.196-5.204-.583-2.35 4.736.028.053-.01.122-.068.132-1.604.25.438 5.258 1.953 8.58C25 27.71 29.437 22.374 29.437 16c0-7.421-6.016-13.438-13.437-13.438C8.579 2.563 2.562 8.58 2.562 16c0 6.237 4.25 11.481 10.01 12.996Z" clip-rule="evenodd"/><path fill="#3CA82B" d="M21.07 22.675c-.341-.159-1.655.783-2.527 1.507-.183-.258-.526-.446-1.301-.31-.678.117-1.053.28-1.22.563-1.07-.406-2.872-1.033-3.307-.428-.476.662.119 3.79.75 4.197.33.212 1.908-.802 2.732-1.502.133.188.347.295.787.284.665-.015 1.744-.17 1.912-.48a.341.341 0 0 0 .026-.066c.847.316 2.338.651 2.67.601.869-.13-.12-4.18-.522-4.366Z"/><path fill="#4CBA3C" d="M18.622 24.274a1.3 1.3 0 0 1 .09.2c.12.338.317 1.412.169 1.678-.15.265-1.115.393-1.711.403-.596.01-.73-.207-.851-.545-.097-.27-.144-.905-.143-1.269-.024-.539.173-.729 1.083-.876.674-.11 1.03.018 1.237.235.957-.714 2.553-1.722 2.709-1.538.777.918.875 3.105.707 3.985-.055.287-2.627-.285-2.627-.595 0-1.288-.334-1.642-.663-1.678ZM12.99 23.872c.21-.333 1.918.081 2.856.498 0 0-.193.873.114 1.901.09.301-2.157 1.64-2.45 1.41-.339-.267-.963-3.108-.52-3.809Z"/><path fill="#FC3" fill-rule="evenodd" d="M13.817 17.101c.138-.6.782-1.733 3.08-1.705 1.163-.005 2.606 0 3.563-.11a12.813 12.813 0 0 0 3.181-.773c.995-.38 1.348-.295 1.472-.068.136.25-.024.68-.372 1.077-.664.758-1.857 1.345-3.966 1.52-2.108.174-3.505-.392-4.106.529-.26.397-.06 1.333 1.98 1.628 2.755.397 5.018-.48 5.297.05.28.53-1.33 1.607-4.09 1.63-2.76.022-4.484-.967-5.095-1.458-.775-.624-1.123-1.533-.944-2.32Z" clip-rule="evenodd"/><g fill="#14307E" opacity=".8"><path d="M17.332 10.532c.154-.252.495-.447 1.054-.447.558 0 .821.222 1.003.47.037.05-.02.11-.076.085a29.677 29.677 0 0 1-.043-.018c-.204-.09-.455-.199-.884-.205-.46-.006-.75.109-.932.208-.062.033-.159-.034-.122-.093ZM11.043 10.854c.542-.226.968-.197 1.27-.126.063.015.107-.053.057-.094-.234-.189-.758-.423-1.44-.168-.61.227-.897.699-.899 1.009 0 .073.15.08.19.017.104-.167.28-.411.822-.638Z"/><path fill-rule="evenodd" d="M18.86 13.98a.867.867 0 0 1-.868-.865.867.867 0 0 1 1.737 0 .867.867 0 0 1-.869.865Zm.612-1.152a.225.225 0 0 0-.45 0 .225.225 0 0 0 .45 0ZM13.106 13.713a1.01 1.01 0 0 1-1.012 1.01 1.011 1.011 0 0 1-1.013-1.01c0-.557.454-1.009 1.013-1.009.558 0 1.012.452 1.012 1.01Zm-.299-.334a.262.262 0 0 0-.524 0 .262.262 0 0 0 .524 0Z" clip-rule="evenodd"/></g></svg>';

  // src/features/duckplayer/text.js
  init_define_import_meta_trackerLookup();

  // src/dom-utils.js
  init_define_import_meta_trackerLookup();
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
  function trustedUnsafe(string) {
    return html([string]);
  }
  function createPolicy() {
    if (globalThis.trustedTypes) {
      return globalThis.trustedTypes?.createPolicy?.("ddg-default", { createHTML: (s) => s });
    }
    return {
      createHTML: (s) => s
    };
  }

  // src/features/duckplayer/text.js
  var text = {
    playText: {
      title: "Duck Player"
    },
    videoOverlayTitle: {
      title: "Tired of targeted YouTube ads and recommendations?"
    },
    videoOverlayTitle2: {
      title: "Turn on Duck Player to watch without targeted ads"
    },
    videoOverlayTitle3: {
      title: "Drowning in ads on YouTube? {newline} Turn on Duck Player."
    },
    videoOverlaySubtitle: {
      title: "provides a clean viewing experience without personalized ads and prevents viewing activity from influencing your YouTube recommendations."
    },
    videoOverlaySubtitle2: {
      title: "What you watch in DuckDuckGo won\u2019t influence your recommendations on YouTube."
    },
    videoButtonOpen: {
      title: "Watch in Duck Player"
    },
    videoButtonOpen2: {
      title: "Turn On Duck Player"
    },
    videoButtonOptOut: {
      title: "Watch Here"
    },
    videoButtonOptOut2: {
      title: "No Thanks"
    },
    rememberLabel: {
      title: "Remember my choice"
    }
  };
  var i18n = {
    /**
     * @param {keyof text} name
     */
    t(name) {
      if (!text.hasOwnProperty(name)) {
        console.error(`missing key ${name}`);
        return "missing";
      }
      const match = text[name];
      if (!match.title) {
        return "missing";
      }
      return match.title;
    }
  };
  var overlayCopyVariants = {
    default: {
      title: i18n.t("videoOverlayTitle2"),
      subtitle: i18n.t("videoOverlaySubtitle2"),
      buttonOptOut: i18n.t("videoButtonOptOut2"),
      buttonOpen: i18n.t("videoButtonOpen2"),
      rememberLabel: i18n.t("rememberLabel")
    }
  };
  var mobileStrings = (lookup) => {
    return {
      title: lookup.videoOverlayTitle2,
      subtitle: lookup.videoOverlaySubtitle2,
      buttonOptOut: lookup.videoButtonOptOut2,
      buttonOpen: lookup.videoButtonOpen2,
      rememberLabel: lookup.rememberLabel
    };
  };

  // src/features/duckplayer/icon-overlay.js
  var IconOverlay = class {
    constructor() {
      __publicField(this, "sideEffects", new SideEffects());
      __publicField(this, "policy", createPolicy());
      /** @type {HTMLElement | null} */
      __publicField(this, "element", null);
      /**
       * Special class used for the overlay hover. For hovering, we use a
       * single element and move it around to the hovered video element.
       */
      __publicField(this, "HOVER_CLASS", "ddg-overlay-hover");
      __publicField(this, "OVERLAY_CLASS", "ddg-overlay");
      __publicField(this, "CSS_OVERLAY_MARGIN_TOP", 5);
      __publicField(this, "CSS_OVERLAY_HEIGHT", 32);
      /** @type {HTMLElement | null} */
      __publicField(this, "currentVideoElement", null);
      __publicField(this, "hoverOverlayVisible", false);
    }
    /**
     * Creates an Icon Overlay.
     * @param {string} size - currently kind-of unused
     * @param {string} href - what, if any, href to set the link to by default.
     * @param {string} [extraClass] - whether to add any extra classes, such as hover
     * @returns {HTMLElement}
     */
    create(size, href, extraClass) {
      const overlayElement = document.createElement("div");
      overlayElement.setAttribute("class", "ddg-overlay" + (extraClass ? " " + extraClass : ""));
      overlayElement.setAttribute("data-size", size);
      const svgIcon = trustedUnsafe(dax_default);
      const safeString = html` <a class="ddg-play-privately" href="#">
            <div class="ddg-dax">${svgIcon}</div>
            <div class="ddg-play-text-container">
                <div class="ddg-play-text">${i18n.t("playText")}</div>
            </div>
        </a>`.toString();
      overlayElement.innerHTML = this.policy.createHTML(safeString);
      overlayElement.querySelector("a.ddg-play-privately")?.setAttribute("href", href);
      return overlayElement;
    }
    /**
     * Util to return the hover overlay
     * @returns {HTMLElement | null}
     */
    getHoverOverlay() {
      return document.querySelector("." + this.HOVER_CLASS);
    }
    /**
     * Moves the hover overlay to a specified videoElement
     * @param {HTMLElement} videoElement - which element to move it to
     */
    moveHoverOverlayToVideoElement(videoElement) {
      const overlay = this.getHoverOverlay();
      if (overlay === null || this.videoScrolledOutOfViewInPlaylist(videoElement)) {
        return;
      }
      const videoElementOffset = this.getElementOffset(videoElement);
      overlay.setAttribute(
        "style",
        "top: " + videoElementOffset.top + "px;left: " + videoElementOffset.left + "px;display:block;"
      );
      overlay.setAttribute("data-size", "fixed " + this.getThumbnailSize(videoElement));
      const href = videoElement.getAttribute("href");
      if (href) {
        const privateUrl = VideoParams.fromPathname(href)?.toPrivatePlayerUrl();
        if (overlay && privateUrl) {
          overlay.querySelector("a")?.setAttribute("href", privateUrl);
        }
      }
      this.hoverOverlayVisible = true;
      this.currentVideoElement = videoElement;
    }
    /**
     * Returns true if the videoElement is scrolled out of view in a playlist. (In these cases
     * we don't want to show the overlay.)
     * @param {HTMLElement} videoElement
     * @returns {boolean}
     */
    videoScrolledOutOfViewInPlaylist(videoElement) {
      const inPlaylist = videoElement.closest("#items.playlist-items");
      if (inPlaylist) {
        const video = videoElement.getBoundingClientRect();
        const playlist = inPlaylist.getBoundingClientRect();
        const videoOutsideTop = video.top + this.CSS_OVERLAY_MARGIN_TOP < playlist.top;
        const videoOutsideBottom = video.top + this.CSS_OVERLAY_HEIGHT + this.CSS_OVERLAY_MARGIN_TOP > playlist.bottom;
        if (videoOutsideTop || videoOutsideBottom) {
          return true;
        }
      }
      return false;
    }
    /**
     * Return the offset of an HTML Element
     * @param {HTMLElement} el
     * @returns {Object}
     */
    getElementOffset(el) {
      const box = el.getBoundingClientRect();
      const docElem = document.documentElement;
      return {
        top: box.top + window.pageYOffset - docElem.clientTop,
        left: box.left + window.pageXOffset - docElem.clientLeft
      };
    }
    /**
     * Hides the hover overlay element, but only if mouse pointer is outside of the hover overlay element
     */
    hideHoverOverlay(event, force) {
      const overlay = this.getHoverOverlay();
      const toElement = event.toElement;
      if (overlay) {
        if (toElement === overlay || overlay.contains(toElement) || force) {
          return;
        }
        this.hideOverlay(overlay);
        this.hoverOverlayVisible = false;
      }
    }
    /**
     * Util for hiding an overlay
     * @param {HTMLElement} overlay
     */
    hideOverlay(overlay) {
      overlay.setAttribute("style", "display:none;");
    }
    /**
     * Appends the Hover Overlay to the page. This is the one that is shown on hover of any video thumbnail.
     * More performant / clean than adding an overlay to each and every video thumbnail. Also it prevents triggering
     * the video hover preview on the homepage if the user hovers the overlay, because user is no longer hovering
     * inside a video thumbnail when hovering the overlay. Nice.
     * @param {(href: string) => void} onClick
     */
    appendHoverOverlay(onClick) {
      this.sideEffects.add("Adding the re-usable overlay to the page ", () => {
        const cleanUpCSS = this.loadCSS();
        const element = this.create("fixed", "", this.HOVER_CLASS);
        document.body.appendChild(element);
        this.addClickHandler(element, onClick);
        return () => {
          element.remove();
          cleanUpCSS();
        };
      });
    }
    loadCSS() {
      const id = "__ddg__icon";
      const style = document.head.querySelector(`#${id}`);
      if (!style) {
        const style2 = document.createElement("style");
        style2.id = id;
        style2.textContent = styles_default;
        document.head.appendChild(style2);
      }
      return () => {
        const style2 = document.head.querySelector(`#${id}`);
        if (style2) {
          document.head.removeChild(style2);
        }
      };
    }
    /**
     * @param {HTMLElement} container
     * @param {string} href
     * @param {(href: string) => void} onClick
     */
    appendSmallVideoOverlay(container, href, onClick) {
      this.sideEffects.add("Adding a small overlay for the video player", () => {
        const cleanUpCSS = this.loadCSS();
        const element = this.create("video-player", href, "hidden");
        this.addClickHandler(element, onClick);
        container.appendChild(element);
        element.classList.remove("hidden");
        return () => {
          element?.remove();
          cleanUpCSS();
        };
      });
    }
    getThumbnailSize(videoElement) {
      const imagesByArea = {};
      Array.from(videoElement.querySelectorAll("img")).forEach((image) => {
        imagesByArea[image.offsetWidth * image.offsetHeight] = image;
      });
      const largestImage = Math.max.apply(this, Object.keys(imagesByArea).map(Number));
      const getSizeType = (width, height) => {
        if (width < 123 + 10) {
          return "small";
        } else if (width < 300 && height < 175) {
          return "medium";
        } else {
          return "large";
        }
      };
      return getSizeType(imagesByArea[largestImage].offsetWidth, imagesByArea[largestImage].offsetHeight);
    }
    /**
     * Handle when dax is clicked - prevent propagation
     * so no further listeners see this
     *
     * @param {HTMLElement} element - the wrapping div
     * @param {(href: string) => void} callback - the function to execute following a click
     */
    addClickHandler(element, callback) {
      element.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        const link = (
          /** @type {HTMLElement} */
          event.target.closest("a")
        );
        const href = link?.getAttribute("href");
        if (href) {
          callback(href);
        }
      });
    }
    destroy() {
      this.sideEffects.destroy();
    }
  };

  // src/features/duckplayer/environment.js
  init_define_import_meta_trackerLookup();

  // ../build/locales/duckplayer-locales.js
  init_define_import_meta_trackerLookup();
  var duckplayer_locales_default = `{"bg":{"overlays.json":{"videoOverlayTitle2":"\u0412\u043A\u043B\u044E\u0447\u0435\u0442\u0435 Duck Player, \u0437\u0430 \u0434\u0430 \u0433\u043B\u0435\u0434\u0430\u0442\u0435 \u0431\u0435\u0437 \u043D\u0430\u0441\u043E\u0447\u0435\u043D\u0438 \u0440\u0435\u043A\u043B\u0430\u043C\u0438","videoButtonOpen2":"\u0412\u043A\u043B\u044E\u0447\u0432\u0430\u043D\u0435 \u043D\u0430 Duck Player","videoButtonOptOut2":"\u041D\u0435, \u0431\u043B\u0430\u0433\u043E\u0434\u0430\u0440\u044F","rememberLabel":"\u0417\u0430\u043F\u043E\u043C\u043D\u0438 \u043C\u043E\u044F \u0438\u0437\u0431\u043E\u0440"}},"cs":{"overlays.json":{"videoOverlayTitle2":"Zapn\u011Bte si Duck Player a\xA0sledujte videa bez c\xEDlen\xFDch reklam","videoButtonOpen2":"Zapni si Duck Player","videoButtonOptOut2":"Ne, d\u011Bkuji","rememberLabel":"Zapamatovat mou volbu"}},"da":{"overlays.json":{"videoOverlayTitle2":"Sl\xE5 Duck Player til for at se indhold uden m\xE5lrettede reklamer","videoButtonOpen2":"Sl\xE5 Duck Player til","videoButtonOptOut2":"Nej tak.","rememberLabel":"Husk mit valg"}},"de":{"overlays.json":{"videoOverlayTitle2":"Aktiviere den Duck Player, um ohne gezielte Werbung zu schauen","videoButtonOpen2":"Duck Player aktivieren","videoButtonOptOut2":"Nein, danke","rememberLabel":"Meine Auswahl merken"}},"el":{"overlays.json":{"videoOverlayTitle2":"\u0395\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03B9\u03AE\u03C3\u03C4\u03B5 \u03C4\u03BF Duck Player \u03B3\u03B9\u03B1 \u03C0\u03B1\u03C1\u03B1\u03BA\u03BF\u03BB\u03BF\u03CD\u03B8\u03B7\u03C3\u03B7 \u03C7\u03C9\u03C1\u03AF\u03C2 \u03C3\u03C4\u03BF\u03C7\u03B5\u03C5\u03BC\u03AD\u03BD\u03B5\u03C2 \u03B4\u03B9\u03B1\u03C6\u03B7\u03BC\u03AF\u03C3\u03B5\u03B9\u03C2","videoButtonOpen2":"\u0395\u03BD\u03B5\u03C1\u03B3\u03BF\u03C0\u03BF\u03AF\u03B7\u03C3\u03B7 \u03C4\u03BF\u03C5 Duck Player","videoButtonOptOut2":"\u038C\u03C7\u03B9, \u03B5\u03C5\u03C7\u03B1\u03C1\u03B9\u03C3\u03C4\u03CE","rememberLabel":"\u0398\u03C5\u03BC\u03B7\u03B8\u03B5\u03AF\u03C4\u03B5 \u03C4\u03B7\u03BD \u03B5\u03C0\u03B9\u03BB\u03BF\u03B3\u03AE \u03BC\u03BF\u03C5"}},"en":{"native.json":{"unknownErrorHeading2":"Duck Player can\u2019t load this video","unknownErrorMessage2a":"This video can\u2019t be viewed outside of YouTube.","unknownErrorMessage2b":"You can still watch this video on YouTube, but without the added privacy of Duck Player.","ageRestrictedErrorHeading2":"Sorry, this video is age-restricted","ageRestrictedErrorMessage2a":"To watch age-restricted videos, you need to sign in to YouTube to verify your age.","ageRestrictedErrorMessage2b":"You can still watch this video, but you\u2019ll have to sign in and watch it on YouTube without the added privacy of Duck Player.","noEmbedErrorHeading2":"Sorry, this video can only be played on YouTube","noEmbedErrorMessage2a":"The creator of this video has chosen not to allow it to be viewed on other sites.","noEmbedErrorMessage2b":"You can still watch it on YouTube, but without the added privacy of Duck Player.","blockedVideoErrorHeading":"YouTube won\u2019t let Duck Player load this video","blockedVideoErrorMessage1":"YouTube doesn\u2019t allow this video to be viewed outside of YouTube.","blockedVideoErrorMessage2":"You can still watch this video on YouTube, but without the added privacy of Duck Player.","signInRequiredErrorHeading2":"Sorry, YouTube thinks you\u2019re a bot","signInRequiredErrorMessage1":"YouTube is blocking this video from loading. If you\u2019re using a VPN, try turning it off and reloading this page.","signInRequiredErrorMessage2":"If this doesn\u2019t work, you can still watch this video on YouTube, but without the added privacy of Duck Player.","signInRequiredErrorMessage2a":"This can happen if you\u2019re using a VPN. Try turning the VPN off or switching server locations and reloading this page.","signInRequiredErrorMessage2b":"If that doesn\u2019t work, you\u2019ll have to sign in and watch this video on YouTube without the added privacy of Duck Player."},"overlays.json":{"videoOverlayTitle2":"Turn on Duck Player to watch without targeted ads","videoButtonOpen2":"Turn On Duck Player","videoButtonOptOut2":"No Thanks","rememberLabel":"Remember my choice"}},"es":{"overlays.json":{"videoOverlayTitle2":"Activa Duck Player para ver sin anuncios personalizados","videoButtonOpen2":"Activar Duck Player","videoButtonOptOut2":"No, gracias","rememberLabel":"Recordar mi elecci\xF3n"}},"et":{"overlays.json":{"videoOverlayTitle2":"Sihitud reklaamideta vaatamiseks l\xFClita sisse Duck Player","videoButtonOpen2":"L\xFClita Duck Player sisse","videoButtonOptOut2":"Ei ait\xE4h","rememberLabel":"J\xE4ta mu valik meelde"}},"fi":{"overlays.json":{"videoOverlayTitle2":"Jos haluat katsoa ilman kohdennettuja mainoksia, ota Duck Player k\xE4ytt\xF6\xF6n","videoButtonOpen2":"Ota Duck Player k\xE4ytt\xF6\xF6n","videoButtonOptOut2":"Ei kiitos","rememberLabel":"Muista valintani"}},"fr":{"overlays.json":{"videoOverlayTitle2":"Activez Duck Player pour une vid\xE9o sans publicit\xE9s cibl\xE9es","videoButtonOpen2":"Activez Duck Player","videoButtonOptOut2":"Non merci","rememberLabel":"M\xE9moriser mon choix"}},"hr":{"overlays.json":{"videoOverlayTitle2":"Uklju\u010Di Duck Player za gledanje bez ciljanih oglasa","videoButtonOpen2":"Uklju\u010Di Duck Player","videoButtonOptOut2":"Ne, hvala","rememberLabel":"Zapamti moj izbor"}},"hu":{"overlays.json":{"videoOverlayTitle2":"Kapcsold be a Duck Playert, hogy c\xE9lzott hirdet\xE9sek n\xE9lk\xFCl vide\xF3zhass","videoButtonOpen2":"Duck Player bekapcsol\xE1sa","videoButtonOptOut2":"Nem, k\xF6sz\xF6n\xF6m","rememberLabel":"V\xE1lasztott be\xE1ll\xEDt\xE1s megjegyz\xE9se"}},"it":{"overlays.json":{"videoOverlayTitle2":"Attiva Duck Player per guardare senza annunci personalizzati","videoButtonOpen2":"Attiva Duck Player","videoButtonOptOut2":"No, grazie","rememberLabel":"Ricorda la mia scelta"}},"lt":{"overlays.json":{"videoOverlayTitle2":"\u012Ejunkite \u201EDuck Player\u201C, kad gal\u0117tum\u0117te \u017Ei\u016Br\u0117ti be tikslini\u0173 reklam\u0173","videoButtonOpen2":"\u012Ejunkite \u201EDuck Player\u201C","videoButtonOptOut2":"Ne, d\u0117koju","rememberLabel":"\u012Esiminti mano pasirinkim\u0105"}},"lv":{"overlays.json":{"videoOverlayTitle2":"Iesl\u0113dz Duck Player, lai skat\u012Btos bez m\u0113r\u0137\u0113t\u0101m rekl\u0101m\u0101m","videoButtonOpen2":"Iesl\u0113gt Duck Player","videoButtonOptOut2":"N\u0113, paldies","rememberLabel":"Atcer\u0113ties manu izv\u0113li"}},"nb":{"overlays.json":{"videoOverlayTitle2":"Sl\xE5 p\xE5 Duck Player for \xE5 se p\xE5 uten m\xE5lrettede annonser","videoButtonOpen2":"Sl\xE5 p\xE5 Duck Player","videoButtonOptOut2":"Nei takk","rememberLabel":"Husk valget mitt"}},"nl":{"overlays.json":{"videoOverlayTitle2":"Zet Duck Player aan om te kijken zonder gerichte advertenties","videoButtonOpen2":"Duck Player aanzetten","videoButtonOptOut2":"Nee, bedankt","rememberLabel":"Mijn keuze onthouden"}},"pl":{"overlays.json":{"videoOverlayTitle2":"W\u0142\u0105cz Duck Player, aby ogl\u0105da\u0107 bez reklam ukierunkowanych","videoButtonOpen2":"W\u0142\u0105cz Duck Player","videoButtonOptOut2":"Nie, dzi\u0119kuj\u0119","rememberLabel":"Zapami\u0119taj m\xF3j wyb\xF3r"}},"pt":{"overlays.json":{"videoOverlayTitle2":"Ativa o Duck Player para ver sem an\xFAncios personalizados","videoButtonOpen2":"Ligar o Duck Player","videoButtonOptOut2":"N\xE3o, obrigado","rememberLabel":"Memorizar a minha op\xE7\xE3o"}},"ro":{"overlays.json":{"videoOverlayTitle2":"Activeaz\u0103 Duck Player pentru a viziona f\u0103r\u0103 reclame direc\u021Bionate","videoButtonOpen2":"Activeaz\u0103 Duck Player","videoButtonOptOut2":"Nu, mul\u021Bumesc","rememberLabel":"Re\u021Bine alegerea mea"}},"ru":{"overlays.json":{"videoOverlayTitle2":"Duck Player\xA0\u2014 \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440 \u0431\u0435\u0437 \u0446\u0435\u043B\u0435\u0432\u043E\u0439 \u0440\u0435\u043A\u043B\u0430\u043C\u044B","videoButtonOpen2":"\u0412\u043A\u043B\u044E\u0447\u0438\u0442\u044C Duck Player","videoButtonOptOut2":"\u041D\u0435\u0442, \u0441\u043F\u0430\u0441\u0438\u0431\u043E","rememberLabel":"\u0417\u0430\u043F\u043E\u043C\u043D\u0438\u0442\u044C \u0432\u044B\u0431\u043E\u0440"}},"sk":{"overlays.json":{"videoOverlayTitle2":"Zapnite Duck Player a pozerajte bez cielen\xFDch rekl\xE1m","videoButtonOpen2":"Zapn\xFA\u0165 prehr\xE1va\u010D Duck Player","videoButtonOptOut2":"Nie, \u010Fakujem","rememberLabel":"Zapam\xE4ta\u0165 si moju vo\u013Ebu"}},"sl":{"overlays.json":{"videoOverlayTitle2":"Vklopite predvajalnik Duck Player za gledanje brez ciljanih oglasov","videoButtonOpen2":"Vklopi predvajalnik Duck Player","videoButtonOptOut2":"Ne, hvala","rememberLabel":"Zapomni si mojo izbiro"}},"sv":{"overlays.json":{"videoOverlayTitle2":"Aktivera Duck Player f\xF6r att titta utan riktade annonser","videoButtonOpen2":"Aktivera Duck Player","videoButtonOptOut2":"Nej tack","rememberLabel":"Kom ih\xE5g mitt val"}},"tr":{"overlays.json":{"videoOverlayTitle2":"Hedeflenmi\u015F reklamlar olmadan izlemek i\xE7in Duck Player'\u0131 a\xE7\u0131n","videoButtonOpen2":"Duck Player'\u0131 A\xE7","videoButtonOptOut2":"Hay\u0131r Te\u015Fekk\xFCrler","rememberLabel":"Se\xE7imimi hat\u0131rla"}}}`;

  // src/features/duckplayer/environment.js
  var Environment = class {
    /**
     * @param {object} params
     * @param {{name: string}} params.platform
     * @param {boolean|null|undefined} [params.debug]
     * @param {ImportMeta['injectName']} params.injectName
     * @param {string} params.locale
     */
    constructor(params) {
      __publicField(this, "allowedProxyOrigins", ["duckduckgo.com"]);
      __publicField(this, "_strings", JSON.parse(duckplayer_locales_default));
      this.debug = Boolean(params.debug);
      this.injectName = params.injectName;
      this.platform = params.platform;
      this.locale = params.locale;
    }
    /**
     * @param {"overlays.json" | "native.json"} named
     * @returns {Record<string, string>}
     */
    strings(named) {
      const matched = this._strings[this.locale];
      if (matched) return matched[named];
      return this._strings.en[named];
    }
    /**
     * This is the URL of the page that the user is currently on
     * It's abstracted so that we can mock it in tests
     * @return {string}
     */
    getPlayerPageHref() {
      if (this.debug) {
        const url = new URL(window.location.href);
        if (url.hostname === "www.youtube.com") return window.location.href;
        if (url.searchParams.has("v")) {
          const base = new URL("/watch", "https://youtube.com");
          base.searchParams.set("v", url.searchParams.get("v") || "");
          return base.toString();
        }
        return "https://youtube.com/watch?v=123";
      }
      return window.location.href;
    }
    getLargeThumbnailSrc(videoId) {
      const url = new URL(`/vi/${videoId}/maxresdefault.jpg`, "https://i.ytimg.com");
      return url.href;
    }
    setHref(href) {
      window.location.href = href;
    }
    hasOneTimeOverride() {
      try {
        if (window.location.hash !== "#ddg-play") return false;
        if (typeof document.referrer !== "string") return false;
        if (document.referrer.length === 0) return false;
        const { hostname } = new URL(document.referrer);
        const isAllowed = this.allowedProxyOrigins.includes(hostname);
        return isAllowed;
      } catch (e) {
        console.error(e);
      }
      return false;
    }
    isIntegrationMode() {
      return this.debug === true && this.injectName === "integration";
    }
    isTestMode() {
      return this.debug === true;
    }
    get opensVideoOverlayLinksViaMessage() {
      return this.platform.name !== "windows";
    }
    /**
     * @return {boolean}
     */
    get isMobile() {
      return this.platform.name === "ios" || this.platform.name === "android";
    }
    /**
     * @return {boolean}
     */
    get isDesktop() {
      return !this.isMobile;
    }
    /**
     * @return {'desktop' | 'mobile'}
     */
    get layout() {
      if (this.platform.name === "ios" || this.platform.name === "android") {
        return "mobile";
      }
      return "desktop";
    }
  };

  // src/features/duckplayer/thumbnails.js
  var Thumbnails = class {
    /**
     * @param {ThumbnailParams} params
     */
    constructor(params) {
      __publicField(this, "sideEffects", new SideEffects());
      this.settings = params.settings;
      this.messages = params.messages;
      this.environment = params.environment;
    }
    /**
     * Perform side effects
     */
    init() {
      this.sideEffects.add("showing overlays on hover", () => {
        const { selectors } = this.settings;
        const parentNode = document.documentElement || document.body;
        const icon = new IconOverlay();
        icon.appendHoverOverlay((href) => {
          if (this.environment.opensVideoOverlayLinksViaMessage) {
            this.messages.sendPixel(new Pixel({ name: "play.use.thumbnail" }));
          }
          this.messages.openDuckPlayer(new OpenInDuckPlayerMsg({ href }));
        });
        let clicked = false;
        const clickHandler = (e) => {
          const overlay = icon.getHoverOverlay();
          if (overlay?.contains(e.target)) {
          } else if (overlay) {
            clicked = true;
            icon.hideOverlay(overlay);
            icon.hoverOverlayVisible = false;
            setTimeout(() => {
              clicked = false;
            }, 0);
          }
        };
        parentNode.addEventListener("click", clickHandler, true);
        const removeOverlay = () => {
          const overlay = icon.getHoverOverlay();
          if (overlay) {
            icon.hideOverlay(overlay);
            icon.hoverOverlayVisible = false;
          }
        };
        const appendOverlay = (element) => {
          if (element && element.isConnected) {
            icon.moveHoverOverlayToVideoElement(element);
          }
        };
        const mouseOverHandler = (e) => {
          if (clicked) return;
          const hoverElement = findElementFromEvent(selectors.thumbLink, selectors.hoverExcluded, e);
          const validLink = isValidLink(hoverElement, selectors.excludedRegions);
          if (!hoverElement || !validLink) {
            return removeOverlay();
          }
          if (hoverElement.querySelector("a[href]")) {
            return removeOverlay();
          }
          if (!hoverElement.querySelector("img")) {
            return removeOverlay();
          }
          if (e.target === hoverElement || hoverElement?.contains(e.target)) {
            return appendOverlay(hoverElement);
          }
          const matched = selectors.allowedEventTargets.find((css) => e.target.matches(css));
          if (matched) {
            appendOverlay(hoverElement);
          }
        };
        parentNode.addEventListener("mouseover", mouseOverHandler, true);
        return () => {
          parentNode.removeEventListener("mouseover", mouseOverHandler, true);
          parentNode.removeEventListener("click", clickHandler, true);
          icon.destroy();
        };
      });
    }
    destroy() {
      this.sideEffects.destroy();
    }
  };
  var ClickInterception = class {
    /**
     * @param {ThumbnailParams} params
     */
    constructor(params) {
      __publicField(this, "sideEffects", new SideEffects());
      this.settings = params.settings;
      this.messages = params.messages;
      this.environment = params.environment;
    }
    /**
     * Perform side effects
     */
    init() {
      this.sideEffects.add("intercepting clicks", () => {
        const { selectors } = this.settings;
        const parentNode = document.documentElement || document.body;
        const clickHandler = (e) => {
          const elementInStack = findElementFromEvent(selectors.thumbLink, selectors.clickExcluded, e);
          const validLink = isValidLink(elementInStack, selectors.excludedRegions);
          const block = (href) => {
            e.preventDefault();
            e.stopImmediatePropagation();
            this.messages.openDuckPlayer({ href });
          };
          if (!validLink) {
            return;
          }
          if (e.target === elementInStack || elementInStack?.contains(e.target)) {
            return block(validLink);
          }
          const matched = selectors.allowedEventTargets.find((css) => e.target.matches(css));
          if (matched) {
            block(validLink);
          }
        };
        parentNode.addEventListener("click", clickHandler, true);
        return () => {
          parentNode.removeEventListener("click", clickHandler, true);
        };
      });
    }
    destroy() {
      this.sideEffects.destroy();
    }
  };
  function findElementFromEvent(selector, excludedSelectors, e) {
    let matched = null;
    const fastPath = excludedSelectors.length === 0;
    for (const element of document.elementsFromPoint(e.clientX, e.clientY)) {
      if (excludedSelectors.some((ex) => element.matches(ex))) {
        return null;
      }
      if (element.matches(selector)) {
        matched = /** @type {HTMLElement} */
        element;
        if (fastPath) return matched;
      }
    }
    return matched;
  }
  function isValidLink(element, excludedRegions) {
    if (!element) return null;
    const existsInExcludedParent = excludedRegions.some((selector) => {
      for (const parent of document.querySelectorAll(selector)) {
        if (parent.contains(element)) return true;
      }
      return false;
    });
    if (existsInExcludedParent) return null;
    if (!("href" in element)) return null;
    return VideoParams.fromHref(element.href)?.toPrivatePlayerUrl();
  }

  // src/features/duckplayer/video-overlay.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/components/ddg-video-overlay.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/assets/video-overlay.css
  var video_overlay_default = '/* -- VIDEO PLAYER OVERLAY */\n:host {\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    z-index: 10000;\n}\n:host * {\n    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";\n}\n.ddg-video-player-overlay {\n    font-size: 13px;\n    font-weight: 400;\n    line-height: 16px;\n    text-align: center;\n\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    z-index: 10000;\n}\n\n.ddg-eyeball svg {\n    width: 60px;\n    height: 60px;\n}\n\n.ddg-vpo-bg {\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    text-align: center;\n    background: black;\n}\n\n.ddg-vpo-bg:after {\n    content: " ";\n    position: absolute;\n    display: block;\n    width: 100%;\n    height: 100%;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    background: rgba(0,0,0,1); /* this gets overriden if the background image can be found */\n    color: white;\n    text-align: center;\n}\n\n.ddg-video-player-overlay[data-thumb-loaded="true"] .ddg-vpo-bg:after {\n    background: rgba(0,0,0,0.75);\n}\n\n.ddg-vpo-content {\n    position: relative;\n    top: 50%;\n    transform: translate(-50%, -50%);\n    left: 50%;\n    max-width: 90%;\n}\n\n.ddg-vpo-eyeball {\n    margin-bottom: 18px;\n}\n\n.ddg-vpo-title {\n    font-size: 22px;\n    font-weight: 400;\n    line-height: 26px;\n    margin-top: 25px;\n}\n\n.ddg-vpo-text {\n    margin-top: 16px;\n    width: 496px;\n    margin-left: auto;\n    margin-right: auto;\n}\n\n.ddg-vpo-text b {\n    font-weight: 600;\n}\n\n.ddg-vpo-buttons {\n    margin-top: 25px;\n}\n.ddg-vpo-buttons > * {\n    display: inline-block;\n    margin: 0;\n    padding: 0;\n}\n\n.ddg-vpo-button {\n    color: white;\n    padding: 9px 16px;\n    font-size: 13px;\n    border-radius: 8px;\n    font-weight: 600;\n    display: inline-block;\n    text-decoration: none;\n}\n\n.ddg-vpo-button + .ddg-vpo-button {\n    margin-left: 10px;\n}\n\n.ddg-vpo-cancel {\n    background: #585b58;\n    border: 0.5px solid rgba(40, 145, 255, 0.05);\n    box-shadow: 0px 0px 0px 0.5px rgba(0, 0, 0, 0.1), 0px 0px 1px rgba(0, 0, 0, 0.05), 0px 1px 1px rgba(0, 0, 0, 0.2), inset 0px 0.5px 0px rgba(255, 255, 255, 0.2), inset 0px 1px 0px rgba(255, 255, 255, 0.05);\n}\n\n.ddg-vpo-open {\n    background: #3969EF;\n    border: 0.5px solid rgba(40, 145, 255, 0.05);\n    box-shadow: 0px 0px 0px 0.5px rgba(0, 0, 0, 0.1), 0px 0px 1px rgba(0, 0, 0, 0.05), 0px 1px 1px rgba(0, 0, 0, 0.2), inset 0px 0.5px 0px rgba(255, 255, 255, 0.2), inset 0px 1px 0px rgba(255, 255, 255, 0.05);\n}\n\n.ddg-vpo-open:hover {\n    background: #1d51e2;\n}\n.ddg-vpo-cancel:hover {\n    cursor: pointer;\n    background: #2f2f2f;\n}\n\n.ddg-vpo-remember {\n}\n.ddg-vpo-remember label {\n    display: flex;\n    align-items: center;\n    justify-content: center;\n    margin-top: 25px;\n    cursor: pointer;\n}\n.ddg-vpo-remember input {\n    margin-right: 6px;\n}\n';

  // src/features/duckplayer/components/ddg-video-overlay.js
  var DDGVideoOverlay = class extends HTMLElement {
    /**
     * @param {object} options
     * @param {import("../environment.js").Environment} options.environment
     * @param {import("../util").VideoParams} options.params
     * @param {import("../../duck-player.js").UISettings} options.ui
     * @param {VideoOverlay} options.manager
     */
    constructor({ environment, params, ui, manager }) {
      super();
      __publicField(this, "policy", createPolicy());
      if (!(manager instanceof VideoOverlay)) throw new Error("invalid arguments");
      this.environment = environment;
      this.ui = ui;
      this.params = params;
      this.manager = manager;
      const shadow = this.attachShadow({ mode: this.environment.isTestMode() ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = video_overlay_default;
      const overlay = this.createOverlay();
      shadow.appendChild(overlay);
      shadow.appendChild(style);
    }
    /**
     * @returns {HTMLDivElement}
     */
    createOverlay() {
      const overlayCopy = overlayCopyVariants.default;
      const overlayElement = document.createElement("div");
      overlayElement.classList.add("ddg-video-player-overlay");
      const svgIcon = trustedUnsafe(dax_default);
      const safeString = html`
            <div class="ddg-vpo-bg"></div>
            <div class="ddg-vpo-content">
                <div class="ddg-eyeball">${svgIcon}</div>
                <div class="ddg-vpo-title">${overlayCopy.title}</div>
                <div class="ddg-vpo-text">${overlayCopy.subtitle}</div>
                <div class="ddg-vpo-buttons">
                    <button class="ddg-vpo-button ddg-vpo-cancel" type="button">${overlayCopy.buttonOptOut}</button>
                    <a class="ddg-vpo-button ddg-vpo-open" href="#">${overlayCopy.buttonOpen}</a>
                </div>
                <div class="ddg-vpo-remember">
                    <label for="remember"> <input id="remember" type="checkbox" name="ddg-remember" /> ${overlayCopy.rememberLabel} </label>
                </div>
            </div>
        `.toString();
      overlayElement.innerHTML = this.policy.createHTML(safeString);
      const href = this.params.toPrivatePlayerUrl();
      overlayElement.querySelector(".ddg-vpo-open")?.setAttribute("href", href);
      this.appendThumbnail(overlayElement, this.params.id);
      this.setupButtonsInsideOverlay(overlayElement, this.params);
      return overlayElement;
    }
    /**
     * @param {HTMLElement} overlayElement
     * @param {string} videoId
     */
    appendThumbnail(overlayElement, videoId) {
      const imageUrl = this.environment.getLargeThumbnailSrc(videoId);
      appendImageAsBackground(overlayElement, ".ddg-vpo-bg", imageUrl);
    }
    /**
     * @param {HTMLElement} containerElement
     * @param {import("../util").VideoParams} params
     */
    setupButtonsInsideOverlay(containerElement, params) {
      const cancelElement = containerElement.querySelector(".ddg-vpo-cancel");
      const watchInPlayer = containerElement.querySelector(".ddg-vpo-open");
      if (!cancelElement) return console.warn("Could not access .ddg-vpo-cancel");
      if (!watchInPlayer) return console.warn("Could not access .ddg-vpo-open");
      const optOutHandler = (e) => {
        if (e.isTrusted) {
          const remember = containerElement.querySelector('input[name="ddg-remember"]');
          if (!(remember instanceof HTMLInputElement)) throw new Error("cannot find our input");
          this.manager.userOptOut(remember.checked, params);
        }
      };
      const watchInPlayerHandler = (e) => {
        if (e.isTrusted) {
          e.preventDefault();
          const remember = containerElement.querySelector('input[name="ddg-remember"]');
          if (!(remember instanceof HTMLInputElement)) throw new Error("cannot find our input");
          this.manager.userOptIn(remember.checked, params);
        }
      };
      cancelElement.addEventListener("click", optOutHandler);
      watchInPlayer.addEventListener("click", watchInPlayerHandler);
    }
  };
  __publicField(DDGVideoOverlay, "CUSTOM_TAG_NAME", "ddg-video-overlay");

  // src/features/duckplayer/components/ddg-video-overlay-mobile.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/assets/mobile-video-overlay.css
  var mobile_video_overlay_default = '/* -- VIDEO PLAYER OVERLAY */\n:host {\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    z-index: 10000;\n    --title-size: 16px;\n    --title-line-height: 20px;\n    --title-gap: 16px;\n    --button-gap: 6px;\n    --logo-size: 32px;\n    --logo-gap: 8px;\n    --gutter: 16px;\n\n}\n/* iphone 15 */\n@media screen and (min-width: 390px) {\n    :host {\n        --title-size: 20px;\n        --title-line-height: 25px;\n        --button-gap: 16px;\n        --logo-size: 40px;\n        --logo-gap: 12px;\n        --title-gap: 16px;\n    }\n}\n/* iphone 15 Pro Max */\n@media screen and (min-width: 430px) {\n    :host {\n        --title-size: 22px;\n        --title-gap: 24px;\n        --button-gap: 20px;\n        --logo-gap: 16px;\n    }\n}\n/* small landscape */\n@media screen and (min-width: 568px) {\n}\n/* large landscape */\n@media screen and (min-width: 844px) {\n    :host {\n        --title-gap: 30px;\n        --button-gap: 24px;\n        --logo-size: 48px;\n    }\n}\n\n\n:host * {\n    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";\n}\n\n:root *, :root *:after, :root *:before {\n    box-sizing: border-box;\n}\n\n.ddg-video-player-overlay {\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    z-index: 10000;\n    padding-left: var(--gutter);\n    padding-right: var(--gutter);\n\n    @media screen and (min-width: 568px) {\n        padding: 0;\n    }\n}\n\n.bg {\n    position: absolute;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    color: white;\n    background: rgba(0, 0, 0, 0.6);\n    text-align: center;\n}\n\n.bg:before {\n    content: " ";\n    position: absolute;\n    display: block;\n    width: 100%;\n    height: 100%;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    background:\n            linear-gradient(180deg, rgba(0, 0, 0, 1) 0%, rgba(0, 0, 0, 0.5) 40%, rgba(0, 0, 0, 0) 60%),\n            radial-gradient(circle at bottom, rgba(131, 58, 180, 0.8), rgba(253, 29, 29, 0.6), rgba(252, 176, 69, 0.4));\n}\n\n.bg:after {\n    content: " ";\n    position: absolute;\n    display: block;\n    width: 100%;\n    height: 100%;\n    top: 0;\n    left: 0;\n    right: 0;\n    bottom: 0;\n    background: rgba(0,0,0,0.7);\n    text-align: center;\n}\n\n.content {\n    height: 100%;\n    width: 100%;\n    margin: 0 auto;\n    overflow: hidden;\n    display: grid;\n    color: rgba(255, 255, 255, 0.96);\n    position: relative;\n    grid-column-gap: var(--logo-gap);\n    grid-template-columns: var(--logo-size) auto calc(12px + 16px);\n    grid-template-rows:\n            auto\n            var(--title-gap)\n            auto\n            var(--button-gap)\n            auto;\n    align-content: center;\n    justify-content: center;\n\n    @media screen and (min-width: 568px) {\n        grid-template-columns: var(--logo-size) auto auto;\n    }\n}\n\n.logo {\n    align-self: start;\n    grid-column: 1/2;\n    grid-row: 1/2;\n}\n\n.logo svg {\n    width: 100%;\n    height: 100%;\n}\n\n.arrow {\n    position: absolute;\n    top: 48px;\n    left: -18px;\n    color: white;\n    z-index: 0;\n}\n\n.title {\n    font-size: var(--title-size);\n    line-height: var(--title-line-height);\n    font-weight: 600;\n    grid-column: 2/3;\n    grid-row: 1/2;\n\n    @media screen and (min-width: 568px) {\n        grid-column: 2/4;\n        max-width: 428px;\n    }\n}\n\n.text {\n    display: none;\n}\n\n.info {\n    grid-column: 3/4;\n    grid-row: 1/2;\n    align-self: start;\n    padding-top: 3px;\n    justify-self: end;\n\n    @media screen and (min-width: 568px) {\n        grid-column: unset;\n        grid-row: unset;\n        position: absolute;\n        top: 12px;\n        right: 12px;\n    }\n    @media screen and (min-width: 844px) {\n        top: 24px;\n        right: 24px;\n    }\n}\n\n.buttons {\n    gap: 8px;\n    display: flex;\n    grid-column: 1/4;\n    grid-row: 3/4;\n\n    @media screen and (min-width: 568px) {\n        grid-column: 2/3;\n    }\n}\n\n.remember {\n    height: 40px;\n    border-radius: 8px;\n    display: flex;\n    gap: 16px;\n    align-items: center;\n    justify-content: space-between;\n    padding-left: 8px;\n    padding-right: 8px;\n    grid-column: 1/4;\n    grid-row: 5/6;\n\n    @media screen and (min-width: 568px) {\n        grid-column: 2/3;\n    }\n}\n\n.button {\n    margin: 0;\n    -webkit-appearance: none;\n    background: none;\n    box-shadow: none;\n    border: none;\n    display: flex;\n    align-items: center;\n    justify-content: center;\n    color: rgba(255, 255, 255, 1);\n    text-decoration: none;\n    line-height: 16px;\n    padding: 0 12px;\n    font-size: 15px;\n    font-weight: 600;\n    border-radius: 8px;\n}\n\n.button--info {\n    display: block;\n    padding: 0;\n    margin: 0;\n    width: 16px;\n    height: 16px;\n    @media screen and (min-width: 568px) {\n        width: 24px;\n        height: 24px;\n    }\n    @media screen and (min-width: 844px) {\n        width: 24px;\n        height: 24px;\n    }\n}\n.button--info svg {\n    display: block;\n    width: 100%;\n    height: 100%;\n}\n\n.button--info svg path {\n    fill: rgba(255, 255, 255, 0.84);\n}\n\n.cancel {\n    background: rgba(255, 255, 255, 0.3);\n    min-height: 40px;\n}\n\n.open {\n    background: #3969EF;\n    flex: 1;\n    text-align: center;\n    min-height: 40px;\n\n    @media screen and (min-width: 568px) {\n        flex: inherit;\n        padding-left: 24px;\n        padding-right: 24px;\n    }\n}\n\n.open:hover {\n}\n.cancel:hover {\n}\n\n.remember-label {\n    display: flex;\n    align-items: center;\n    flex: 1;\n}\n\n.remember-text {\n    display: block;\n    font-size: 13px;\n    font-weight: 400;\n}\n.remember-checkbox {\n    margin-left: auto;\n    display: flex;\n}\n\n.switch {\n    margin: 0;\n    padding: 0;\n    width: 52px;\n    height: 32px;\n    border: 0;\n    box-shadow: none;\n    background: rgba(136, 136, 136, 0.5);\n    border-radius: 32px;\n    position: relative;\n    transition: all .3s;\n}\n\n.switch:active .thumb {\n    scale: 1.15;\n}\n\n.thumb {\n    width: 20px;\n    height: 20px;\n    border-radius: 100%;\n    background: white;\n    position: absolute;\n    top: 4px;\n    left: 4px;\n    pointer-events: none;\n    transition: .2s left ease-in-out;\n}\n\n.switch[aria-checked="true"] {\n    background: rgba(57, 105, 239, 1)\n}\n\n.ios-switch {\n    width: 42px;\n    height: 24px;\n}\n\n.ios-switch .thumb {\n    top: 2px;\n    left: 2px;\n    width: 20px;\n    height: 20px;\n    box-shadow: 0 1px 4px 0 rgba(0, 0, 0, 0.25)\n}\n\n.ios-switch:active .thumb {\n    scale: 1;\n}\n\n.ios-switch[aria-checked="true"] .thumb {\n    left: calc(100% - 22px)\n}\n\n.android {}\n';

  // src/features/duckplayer/assets/info.svg
  var info_default = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="25" viewBox="0 0 24 25" fill="none">\n    <path d="M12.7248 5.96753C11.6093 5.96753 10.9312 6.86431 10.9312 7.69548C10.9312 8.70163 11.6968 9.02972 12.3748 9.02972C13.6216 9.02972 14.1465 8.08919 14.1465 7.32364C14.1465 6.36124 13.381 5.96753 12.7248 5.96753Z" fill="white" fill-opacity="0.84"/>\n    <path d="M13.3696 10.3183L10.6297 10.7613C10.5458 11.4244 10.4252 12.0951 10.3026 12.7763C10.0661 14.0912 9.82251 15.4455 9.82251 16.8607C9.82251 18.2659 10.6629 19.0328 11.9918 19.0328C13.5096 19.0328 13.7693 18.0801 13.8282 17.2171C12.57 17.3996 12.2936 16.8317 12.4992 15.495C12.7049 14.1584 13.3696 10.3183 13.3696 10.3183Z" fill="white" fill-opacity="0.84"/>\n    <path fill-rule="evenodd" clip-rule="evenodd" d="M12 0.5C5.37258 0.5 0 5.87258 0 12.5C0 19.1274 5.37258 24.5 12 24.5C18.6274 24.5 24 19.1274 24 12.5C24 5.87258 18.6274 0.5 12 0.5ZM2.25 12.5C2.25 7.11522 6.61522 2.75 12 2.75C17.3848 2.75 21.75 7.11522 21.75 12.5C21.75 17.8848 17.3848 22.25 12 22.25C6.61522 22.25 2.25 17.8848 2.25 12.5Z" fill="white" fill-opacity="0.84"/>\n</svg>\n';

  // src/features/duckplayer/components/ddg-video-overlay-mobile.js
  var _DDGVideoOverlayMobile = class _DDGVideoOverlayMobile extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "policy", createPolicy());
      /** @type {boolean} */
      __publicField(this, "testMode", false);
      /** @type {Text | null} */
      __publicField(this, "text", null);
    }
    connectedCallback() {
      this.createMarkupAndStyles();
    }
    createMarkupAndStyles() {
      const shadow = this.attachShadow({ mode: this.testMode ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = mobile_video_overlay_default;
      const overlayElement = document.createElement("div");
      const content = this.mobileHtml();
      overlayElement.innerHTML = this.policy.createHTML(content);
      shadow.append(style, overlayElement);
      this.setupEventHandlers(overlayElement);
    }
    /**
     * @returns {string}
     */
    mobileHtml() {
      if (!this.text) {
        console.warn("missing `text`. Please assign before rendering");
        return "";
      }
      const svgIcon = trustedUnsafe(dax_default);
      const infoIcon = trustedUnsafe(info_default);
      return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="content ios">
                    <div class="logo">${svgIcon}</div>
                    <div class="title">${this.text.title}</div>
                    <div class="info">
                        <button class="button button--info" type="button" aria-label="Open Information Modal">${infoIcon}</button>
                    </div>
                    <div class="text">${this.text.subtitle}</div>
                    <div class="buttons">
                        <button class="button cancel ddg-vpo-cancel" type="button">${this.text.buttonOptOut}</button>
                        <a class="button open ddg-vpo-open" href="#">${this.text.buttonOpen}</a>
                    </div>
                    <div class="remember">
                        <div class="remember-label">
                            <span class="remember-text"> ${this.text.rememberLabel} </span>
                            <span class="remember-checkbox">
                                <input id="remember" type="checkbox" name="ddg-remember" hidden />
                                <button role="switch" aria-checked="false" class="switch ios-switch">
                                    <span class="thumb"></span>
                                </button>
                            </span>
                        </div>
                    </div>
                </div>
            </div>
        `.toString();
    }
    /**
     * @param {HTMLElement} containerElement
     */
    setupEventHandlers(containerElement) {
      const switchElem = containerElement.querySelector("[role=switch]");
      const infoButton = containerElement.querySelector(".button--info");
      const remember = containerElement.querySelector('input[name="ddg-remember"]');
      const cancelElement = containerElement.querySelector(".ddg-vpo-cancel");
      const watchInPlayer = containerElement.querySelector(".ddg-vpo-open");
      if (!infoButton || !cancelElement || !watchInPlayer || !switchElem || !(remember instanceof HTMLInputElement)) {
        return console.warn("missing elements");
      }
      infoButton.addEventListener("click", () => {
        this.dispatchEvent(new Event(_DDGVideoOverlayMobile.OPEN_INFO));
      });
      switchElem.addEventListener("pointerdown", () => {
        const current = switchElem.getAttribute("aria-checked");
        if (current === "false") {
          switchElem.setAttribute("aria-checked", "true");
          remember.checked = true;
        } else {
          switchElem.setAttribute("aria-checked", "false");
          remember.checked = false;
        }
      });
      cancelElement.addEventListener("click", (e) => {
        if (!e.isTrusted) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        this.dispatchEvent(new CustomEvent(_DDGVideoOverlayMobile.OPT_OUT, { detail: { remember: remember.checked } }));
      });
      watchInPlayer.addEventListener("click", (e) => {
        if (!e.isTrusted) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        this.dispatchEvent(new CustomEvent(_DDGVideoOverlayMobile.OPT_IN, { detail: { remember: remember.checked } }));
      });
    }
  };
  __publicField(_DDGVideoOverlayMobile, "CUSTOM_TAG_NAME", "ddg-video-overlay-mobile");
  __publicField(_DDGVideoOverlayMobile, "OPEN_INFO", "open-info");
  __publicField(_DDGVideoOverlayMobile, "OPT_IN", "opt-in");
  __publicField(_DDGVideoOverlayMobile, "OPT_OUT", "opt-out");
  var DDGVideoOverlayMobile = _DDGVideoOverlayMobile;

  // src/features/duckplayer/components/ddg-video-thumbnail-overlay-mobile.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/assets/mobile-video-thumbnail-overlay.css
  var mobile_video_thumbnail_overlay_default = `/* -- VIDEO PLAYER OVERLAY */
:host {
    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    right: 0;
    z-index: 10000;
    --title-size: 16px;
    --title-line-height: 20px;
    --title-gap: 16px;
    --button-gap: 6px;
    --logo-size: 32px;
    --logo-gap: 8px;
    --gutter: 16px;
}
/* iphone 15 */
@media screen and (min-width: 390px) {
    :host {
        --title-size: 20px;
        --title-line-height: 25px;
        --button-gap: 16px;
        --logo-size: 40px;
        --logo-gap: 12px;
        --title-gap: 16px;
    }
}
/* iphone 15 Pro Max */
@media screen and (min-width: 430px) {
    :host {
        --title-size: 22px;
        --title-gap: 24px;
        --button-gap: 20px;
        --logo-gap: 16px;
    }
}
/* small landscape */
@media screen and (min-width: 568px) {
}
/* large landscape */
@media screen and (min-width: 844px) {
    :host {
        --title-gap: 30px;
        --button-gap: 24px;
        --logo-size: 48px;
    }
}


:host * {
    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
}

:root *, :root *:after, :root *:before {
    box-sizing: border-box;
}

.ddg-video-player-overlay {
    width: 100%;
    height: 100%;
    padding-left: var(--gutter);
    padding-right: var(--gutter);

    @media screen and (min-width: 568px) {
        padding: 0;
    }
}

.bg {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    color: white;
    background: rgba(0, 0, 0, 0.6);
    background-position: center;
    text-align: center;
}

.logo {
    content: " ";
    position: absolute;
    display: block;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: transparent;
    background-image: url('data:image/svg+xml,<svg width="90" height="64" viewBox="0 0 90 64" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" clip-rule="evenodd" d="M88.119 9.88293C87.0841 6.01134 84.0348 2.96133 80.1625 1.92639C73.1438 0.0461578 44.9996 0.0461578 44.9996 0.0461578C44.9996 0.0461578 16.8562 0.0461578 9.83751 1.92639C5.96518 2.96133 2.91592 6.01134 1.88097 9.88293C0 16.9023 0 31.5456 0 31.5456C0 31.5456 0 46.1896 1.88097 53.2083C2.91592 57.0799 5.96518 60.1306 9.83751 61.1648C16.8562 63.0458 44.9996 63.0458 44.9996 63.0458C44.9996 63.0458 73.1438 63.0458 80.1625 61.1648C84.0348 60.1306 87.0841 57.0799 88.119 53.2083C90 46.1896 90 31.5456 90 31.5456C90 31.5456 90 16.9023 88.119 9.88293Z" fill="%23FF0000"/><path fill-rule="evenodd" clip-rule="evenodd" d="M36.8184 45.3313L60.2688 31.792L36.8184 18.2512V45.3313Z" fill="%23FFFFFE"/></svg>');
    background-size: 90px 64px;
    background-position: center center;
    background-repeat: no-repeat;
}
`;

  // src/features/duckplayer/components/ddg-video-thumbnail-overlay-mobile.js
  var DDGVideoThumbnailOverlay = class extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "policy", createPolicy());
      /** @type {boolean} */
      __publicField(this, "testMode", false);
    }
    connectedCallback() {
      this.createMarkupAndStyles();
    }
    createMarkupAndStyles() {
      const shadow = this.attachShadow({ mode: this.testMode ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = mobile_video_thumbnail_overlay_default;
      const container = document.createElement("div");
      const content = this.mobileHtml();
      container.innerHTML = this.policy.createHTML(content);
      shadow.append(style, container);
      this.container = container;
    }
    /**
     * @returns {string}
     */
    mobileHtml() {
      return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="logo"></div>
            </div>
        `.toString();
    }
  };
  __publicField(DDGVideoThumbnailOverlay, "CUSTOM_TAG_NAME", "ddg-video-thumbnail-overlay-mobile");

  // src/features/duckplayer/components/ddg-video-drawer-mobile.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer/assets/mobile-video-drawer.css
  var mobile_video_drawer_default = '/* -- VIDEO PLAYER OVERLAY */\n:host {\n    position: absolute;\n    bottom: 0;\n    right: 0;\n    left: 0;\n    top: 0;\n    z-index: 10010;\n    --title-size: 16px;\n    --title-line-height: 20px;\n    --title-gap: 16px;\n    --button-gap: 6px;\n    --logo-size: 32px;\n    --logo-gap: 8px;\n    --gutter: 16px;\n}\n/* iphone 15 */\n@media screen and (min-width: 390px) {\n    :host {\n        --title-size: 20px;\n        --title-line-height: 25px;\n        --button-gap: 16px;\n        --logo-size: 40px;\n        --logo-gap: 12px;\n        --title-gap: 16px;\n    }\n}\n/* iphone 15 Pro Max */\n@media screen and (min-width: 430px) {\n    :host {\n        --title-size: 22px;\n        --title-gap: 24px;\n        --button-gap: 20px;\n        --logo-gap: 16px;\n    }\n}\n/* small landscape */\n@media screen and (min-width: 568px) {\n}\n/* large landscape */\n@media screen and (min-width: 844px) {\n    :host {\n        --title-gap: 30px;\n        --button-gap: 24px;\n        --logo-size: 48px;\n    }\n}\n\n\n:host * {\n    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";\n}\n\n:root *, :root *:after, :root *:before {\n    box-sizing: border-box;\n}\n\n.ddg-mobile-drawer-overlay {\n    --overlay-background: rgba(0, 0, 0, 0.6);\n    --drawer-background: #fafafa;\n    --drawer-color: rgba(0, 0, 0, 0.84);\n    --button-background: rgba(0, 0, 0, 0.06);\n    --button-color: rgba(0, 0, 0, 0.84);\n    --button-accent-background: #3969ef;\n    --button-accent-color: #fff;\n    --switch-off-background: #888;\n    --switch-on-background: #3969ef;\n    --switch-thumb-background: #fff;\n    --info-color: #000;\n\n    --drawer-padding-block: 24px;\n    --drawer-padding-inline: 16px;\n    --drawer-buffer: 48px;\n\n    height: 100%;\n    position: absolute;\n    width: 100%;\n}\n\n@media (prefers-color-scheme: dark) {\n    .ddg-mobile-drawer-overlay {\n        --drawer-background: #333;\n        --drawer-color: rgba(255, 255, 255, 0.84);\n        --button-background: rgba(255, 255, 255, 0.18);\n        --button-color: #fff;\n        --button-accent-background: #7295f6;\n        --button-accent-color: rgba(0, 0, 0, 0.84);\n        --switch-off-background: #888;\n        --switch-on-background: #7295f6;\n        --switch-thumb-background: #fff;\n        --info-color: rgba(255, 255, 255, 0.84);\n    }\n}\n\n.ddg-mobile-drawer-background {\n    background: var(--overlay-background);\n    bottom: 0;\n    left: 0;\n    opacity: 0;\n    position: fixed;\n    right: 0;\n    top: 0;\n}\n\n.ddg-mobile-drawer {\n    background: var(--drawer-background);\n    border-top-left-radius: 10px;\n    border-top-right-radius: 10px;\n    bottom: -100vh;\n    box-shadow: 0px -4px 12px 0px rgba(0, 0, 0, 0.10), 0px -20px 40px 0px rgba(0, 0, 0, 0.08);\n    box-sizing: border-box;\n    color: var(--drawer-color);\n    display: flex;\n    flex-direction: column;\n    gap: 12px;\n    left: 0;\n    position: fixed;\n    width: 100%;\n\n    /* Apply safe-area padding as fallback in case media query below gets removed in the future */\n    padding-top: var(--drawer-padding-block);\n    padding-right: calc(var(--drawer-padding-inline) + env(safe-area-inset-right));\n    padding-bottom: calc(var(--drawer-padding-block) + var(--drawer-buffer));\n    padding-left: calc(var(--drawer-padding-inline) + env(safe-area-inset-left));\n}\n\n/* Apply a blanket 18% inline padding on viewports wider than 700px */\n@media screen and (min-width: 700px) {\n    .ddg-mobile-drawer {\n        padding-left: 18%;\n        padding-right: 18%;\n    }\n}\n\n/* ANIMATIONS */\n\n.animateIn .ddg-mobile-drawer-background {\n    animation: fade-in 300ms ease-out 100ms 1 both;\n}\n\n.animateOut .ddg-mobile-drawer-background {\n    animation: fade-out 300ms ease-out 10ms 1 both;\n}\n\n.animateIn .ddg-mobile-drawer {\n    animation: slide-in 300ms cubic-bezier(0.34, 1.3, 0.64, 1) 100ms 1 both;\n}\n\n.animateOut .ddg-mobile-drawer {\n    animation: slide-out 300ms cubic-bezier(0.36, 0, 0.66, -0.3) 100ms 1 both;\n}\n\n@media (prefers-reduced-motion) {\n    .animateIn *,\n    .animateOut * {\n        animation-duration: 0s !important;\n    }\n}\n\n@keyframes fade-in {\n    0% {\n        opacity: 0;\n    }\n\n    100% {\n        opacity: 1;\n    }\n}\n\n@keyframes fade-out {\n    0% {\n        opacity: 1;\n    }\n\n    100% {\n        opacity: 0;\n    }\n}\n\n@keyframes slide-in {\n    0% {\n        bottom: -100vh;\n    }\n\n    100% {\n        bottom: calc(-1 * var(--drawer-buffer));\n    }\n}\n\n@keyframes slide-out {\n    0% {\n        bottom: calc(-1 * var(--drawer-buffer));\n    }\n\n    100% {\n        bottom: -100vh;\n    }\n}\n\n.heading {\n    align-items: center;\n    display: flex;\n    gap: 12px;\n    margin-bottom: 4px;\n}\n\n.logo {\n    flex: 0 0 32px;\n    height: 32px;\n    width: 32px;\n}\n\n.title {\n    flex: 1 1 auto;\n    font-size: 19px;\n    font-weight: 700;\n    line-height: calc(24 / 19);\n}\n\n.info {\n    align-self: start;\n    flex: 0 0 16px;\n    height: 32px;\n    position: relative;\n    width: 16px;\n}\n\n/* BUTTONS */\n\n.buttons {\n    gap: 8px;\n    display: flex;\n}\n\n.button {\n    flex: 1 1 50%;\n    margin: 0;\n    appearance: none;\n    background: none;\n    box-shadow: none;\n    border: none;\n    display: flex;\n    align-items: center;\n    justify-content: center;\n    background: var(--button-background);\n    color: var(--button-color);\n    text-decoration: none;\n    line-height: 20px;\n    padding: 12px 16px;\n    font-size: 15px;\n    font-weight: 600;\n    border-radius: 8px;\n}\n\n.info-button {\n    appearance: none;\n    background: none;\n    border: 0;\n    height: 40px;\n    margin: 0;\n    padding: 12px;\n    position: absolute;\n    right: calc(-1 * var(--drawer-padding-inline));\n    top: calc(-1 * var(--drawer-padding-block));\n    width: 40px;\n}\n\n.info-button svg {\n    display: block;\n    width: 16px;\n    height: 16px;\n}\n\n.info-button svg path {\n    fill: var(--info-color);\n}\n\n.open {\n    background: var(--button-accent-background);\n    color: var(--button-accent-color);\n    text-align: center;\n    width: 100%;\n\n    @media screen and (min-width: 568px) {\n        flex: inherit;\n        padding-left: 24px;\n        padding-right: 24px;\n    }\n}\n\n/* REMEMBER ME */\n\n.remember {\n    height: 40px;\n    display: flex;\n    gap: 16px;\n    align-items: center;\n    justify-content: space-between;\n    padding: 0 8px;\n}\n\n.remember-label {\n    display: flex;\n    align-items: center;\n    flex: 1;\n}\n\n.remember-text {\n    display: block;\n    font-size: 14px;\n    font-weight: 700;\n    line-height: calc(18 / 14);\n}\n.remember-checkbox {\n    margin-left: auto;\n    display: flex;\n}\n\n/* SWITCH */\n\n.switch {\n    margin: 0;\n    padding: 0;\n    width: 52px;\n    height: 32px;\n    border: 0;\n    box-shadow: none;\n    background: var(--switch-off-background);\n    border-radius: 32px;\n    position: relative;\n    transition: all .3s;\n}\n\n.switch:active .thumb {\n    scale: 1.15;\n}\n\n.thumb {\n    width: 24px;\n    height: 24px;\n    border-radius: 100%;\n    background: var(--switch-thumb-background);\n    position: absolute;\n    top: 4px;\n    left: 4px;\n    pointer-events: none;\n    transition: .2s left ease-in-out;\n}\n\n.switch[aria-checked="true"] .thumb {\n    left: calc(100% - 32px + 4px);\n}\n.switch[aria-checked="true"] {\n    background: var(--switch-on-background);\n}\n\n.ios-switch {\n    width: 51px;\n    height: 31px;\n}\n\n.ios-switch .thumb {\n    top: 2px;\n    left: 2px;\n    width: 27px;\n    height: 27px;\n    box-shadow: 0 1px 4px 0 rgba(0, 0, 0, 0.25);\n}\n\n.ios-switch:active .thumb {\n    scale: 1;\n}\n\n.ios-switch[aria-checked="true"] .thumb {\n    left: calc(100% - 32px + 3px);\n}\n';

  // src/features/duckplayer/assets/info-solid.svg
  var info_solid_default = '<svg fill="none" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">\n  <g clip-path="url(#Info-Solid-16_svg__a)">\n    <path fill="#000" fill-rule="evenodd" d="M16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0M8.483 3.645c-.743 0-1.196.598-1.196 1.152 0 .67.51.89.963.89.831 0 1.181-.628 1.181-1.138 0-.642-.51-.904-.948-.904m.43 2.9-1.827.296c-.055.442-.136.89-.218 1.343-.157.877-.32 1.78-.32 2.723 0 .937.56 1.448 1.447 1.448 1.011 0 1.185-.635 1.224-1.21-.839.121-1.023-.257-.886-1.148s.58-3.451.58-3.451Z" clip-rule="evenodd"/>\n  </g>\n  <defs>\n    <clipPath id="Info-Solid-16_svg__a">\n      <path fill="#fff" d="M0 0h16v16H0z"/>\n    </clipPath>\n  </defs>\n</svg>\n';

  // src/features/duckplayer/components/ddg-video-drawer-mobile.js
  var _DDGVideoDrawerMobile = class _DDGVideoDrawerMobile extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "policy", createPolicy());
      /** @type {boolean} */
      __publicField(this, "testMode", false);
      /** @type {Text | null} */
      __publicField(this, "text", null);
      /** @type {HTMLElement | null} */
      __publicField(this, "container");
      /** @type {HTMLElement | null} */
      __publicField(this, "drawer");
      /** @type {HTMLElement | null} */
      __publicField(this, "overlay");
      /** @type {'idle'|'animating'} */
      __publicField(this, "animationState", "idle");
    }
    connectedCallback() {
      this.createMarkupAndStyles();
    }
    createMarkupAndStyles() {
      const shadow = this.attachShadow({ mode: this.testMode ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = mobile_video_drawer_default;
      const overlayElement = document.createElement("div");
      const content = this.mobileHtml();
      overlayElement.innerHTML = this.policy.createHTML(content);
      shadow.append(style, overlayElement);
      this.setupEventHandlers(overlayElement);
      this.animateOverlay("in");
    }
    /**
     * @returns {string}
     */
    mobileHtml() {
      if (!this.text) {
        console.warn("missing `text`. Please assign before rendering");
        return "";
      }
      const svgIcon = trustedUnsafe(dax_default);
      const infoIcon = trustedUnsafe(info_solid_default);
      return html`
            <div class="ddg-mobile-drawer-overlay">
                <div class="ddg-mobile-drawer-background"></div>
                <div class="ddg-mobile-drawer">
                    <div class="heading">
                        <div class="logo">${svgIcon}</div>
                        <div class="title">${this.text.title}</div>
                        <div class="info">
                            <button class="info-button" type="button" aria-label="Open Information Modal">${infoIcon}</button>
                        </div>
                    </div>
                    <div class="buttons">
                        <button class="button cancel ddg-vpo-cancel" type="button">${this.text.buttonOptOut}</button>
                        <a class="button open ddg-vpo-open" href="#">${this.text.buttonOpen}</a>
                    </div>
                    <div class="remember">
                        <div class="remember-label">
                            <span class="remember-text"> ${this.text.rememberLabel} </span>
                            <span class="remember-checkbox">
                                <input id="remember" type="checkbox" name="ddg-remember" hidden />
                                <button role="switch" aria-checked="false" class="switch ios-switch">
                                    <span class="thumb"></span>
                                </button>
                            </span>
                        </div>
                    </div>
                </div>
            </div>
        `.toString();
    }
    /**
     *
     * @param {'in'|'out'} direction
     */
    animateOverlay(direction) {
      if (!this.overlay) return;
      this.animationState = "animating";
      switch (direction) {
        case "in":
          this.overlay.classList.remove("animateOut");
          this.overlay.classList.add("animateIn");
          break;
        case "out":
          this.overlay.classList.remove("animateIn");
          this.overlay.classList.add("animateOut");
          break;
      }
    }
    /**
     * @param {() => void} callback
     */
    onAnimationEnd(callback) {
      if (this.animationState !== "animating") callback();
      this.overlay?.addEventListener(
        "animationend",
        () => {
          callback();
        },
        { once: true }
      );
    }
    /**
     * @param {HTMLElement} [container]
     * @returns
     */
    setupEventHandlers(container) {
      if (!container) {
        console.warn("Error setting up drawer component");
        return;
      }
      const switchElem = container.querySelector("[role=switch]");
      const infoButton = container.querySelector(".info-button");
      const remember = container.querySelector('input[name="ddg-remember"]');
      const cancelElement = container.querySelector(".ddg-vpo-cancel");
      const watchInPlayer = container.querySelector(".ddg-vpo-open");
      const background = container.querySelector(".ddg-mobile-drawer-background");
      const overlay = container.querySelector(".ddg-mobile-drawer-overlay");
      const drawer = container.querySelector(".ddg-mobile-drawer");
      if (!cancelElement || !watchInPlayer || !switchElem || !infoButton || !background || !overlay || !drawer || !(remember instanceof HTMLInputElement)) {
        return console.warn("missing elements");
      }
      this.container = container;
      this.overlay = /** @type {HTMLElement} */
      overlay;
      this.drawer = /** @type {HTMLElement} */
      drawer;
      infoButton.addEventListener("click", () => {
        this.dispatchEvent(new Event(_DDGVideoDrawerMobile.OPEN_INFO));
      });
      switchElem.addEventListener("pointerdown", () => {
        const current = switchElem.getAttribute("aria-checked");
        if (current === "false") {
          switchElem.setAttribute("aria-checked", "true");
          remember.checked = true;
        } else {
          switchElem.setAttribute("aria-checked", "false");
          remember.checked = false;
        }
      });
      cancelElement.addEventListener("click", (e) => {
        if (!e.isTrusted) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        this.animateOverlay("out");
        this.dispatchEvent(new CustomEvent(_DDGVideoDrawerMobile.OPT_OUT, { detail: { remember: remember.checked } }));
      });
      background.addEventListener("click", (e) => {
        if (!e.isTrusted || e.target !== background) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        this.animateOverlay("out");
        const mouseEvent = (
          /** @type {MouseEvent} */
          e
        );
        let eventName = _DDGVideoDrawerMobile.DISMISS;
        for (const element of document.elementsFromPoint(mouseEvent.clientX, mouseEvent.clientY)) {
          if (element.tagName === DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME.toUpperCase()) {
            eventName = _DDGVideoDrawerMobile.THUMBNAIL_CLICK;
            break;
          }
        }
        this.dispatchEvent(new CustomEvent(eventName));
      });
      watchInPlayer.addEventListener("click", (e) => {
        if (!e.isTrusted) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        this.dispatchEvent(new CustomEvent(_DDGVideoDrawerMobile.OPT_IN, { detail: { remember: remember.checked } }));
      });
      overlay.addEventListener("animationend", () => {
        this.animationState = "idle";
      });
    }
  };
  __publicField(_DDGVideoDrawerMobile, "CUSTOM_TAG_NAME", "ddg-video-drawer-mobile");
  __publicField(_DDGVideoDrawerMobile, "OPEN_INFO", "open-info");
  __publicField(_DDGVideoDrawerMobile, "OPT_IN", "opt-in");
  __publicField(_DDGVideoDrawerMobile, "OPT_OUT", "opt-out");
  __publicField(_DDGVideoDrawerMobile, "DISMISS", "dismiss");
  __publicField(_DDGVideoDrawerMobile, "THUMBNAIL_CLICK", "thumbnail-click");
  __publicField(_DDGVideoDrawerMobile, "DID_EXIT", "did-exit");
  var DDGVideoDrawerMobile = _DDGVideoDrawerMobile;

  // src/features/duckplayer/video-overlay.js
  var VideoOverlay = class {
    /**
     * @param {object} options
     * @param {import("../duck-player.js").UserValues} options.userValues
     * @param {import("../duck-player.js").OverlaysFeatureSettings} options.settings
     * @param {import("./environment.js").Environment} options.environment
     * @param {import("./overlay-messages.js").DuckPlayerOverlayMessages} options.messages
     * @param {import("../duck-player.js").UISettings} options.ui
     */
    constructor({ userValues, settings, environment, messages, ui }) {
      __publicField(this, "sideEffects", new SideEffects());
      /** @type {string | null} */
      __publicField(this, "lastVideoId", null);
      /** @type {boolean} */
      __publicField(this, "didAllowFirstVideo", false);
      this.userValues = userValues;
      this.settings = settings;
      this.environment = environment;
      this.messages = messages;
      this.ui = ui;
    }
    /**
     * @param {'page-load' | 'preferences-changed' | 'href-changed'} trigger
     */
    init(trigger) {
      if (trigger === "page-load") {
        this.handleFirstPageLoad();
      } else if (trigger === "preferences-changed") {
        this.watchForVideoBeingAdded({ via: "user notification", ignoreCache: true });
      } else if (trigger === "href-changed") {
        this.watchForVideoBeingAdded({ via: "href changed" });
      }
    }
    /**
     * Special handling of a first-page, an attempt to load our overlay as quickly as possible
     */
    handleFirstPageLoad() {
      if ("disabled" in this.userValues.privatePlayerMode) return;
      const validParams = VideoParams.forWatchPage(this.environment.getPlayerPageHref());
      if (!validParams) return;
      this.sideEffects.add("add css to head", () => {
        const style = document.createElement("style");
        style.innerText = this.settings.selectors.videoElementContainer + " { opacity: 0!important }";
        if (document.head) {
          document.head.appendChild(style);
        }
        return () => {
          if (style.isConnected) {
            document.head.removeChild(style);
          }
        };
      });
      this.sideEffects.add("wait for first video element", () => {
        const int = setInterval(() => {
          this.watchForVideoBeingAdded({ via: "first page load" });
        }, 100);
        return () => {
          clearInterval(int);
        };
      });
    }
    /**
     * @param {import("./util").VideoParams} params
     */
    addSmallDaxOverlay(params) {
      const containerElement = document.querySelector(this.settings.selectors.videoElementContainer);
      if (!containerElement || !(containerElement instanceof HTMLElement)) {
        console.error("no container element");
        return;
      }
      this.sideEffects.add("adding small dax \u{1F425} icon overlay", () => {
        const href = params.toPrivatePlayerUrl();
        const icon = new IconOverlay();
        icon.appendSmallVideoOverlay(containerElement, href, (href2) => {
          this.messages.openDuckPlayer(new OpenInDuckPlayerMsg({ href: href2 }));
        });
        return () => {
          icon.destroy();
        };
      });
    }
    /**
     * @param {{ignoreCache?: boolean, via?: string}} [opts]
     */
    watchForVideoBeingAdded(opts = {}) {
      const params = VideoParams.forWatchPage(this.environment.getPlayerPageHref());
      if (!params) {
        if (this.lastVideoId) {
          this.destroy();
          this.lastVideoId = null;
        }
        return;
      }
      const conditions = [
        // cache overridden
        opts.ignoreCache,
        // first visit
        !this.lastVideoId,
        // new video id
        this.lastVideoId && this.lastVideoId !== params.id
        // different
      ];
      if (conditions.some(Boolean)) {
        const videoElement = document.querySelector(this.settings.selectors.videoElement);
        const targetElement = document.querySelector(this.settings.selectors.videoElementContainer);
        if (!videoElement || !targetElement) {
          return null;
        }
        const userValues = this.userValues;
        this.lastVideoId = params.id;
        this.destroy();
        if ("enabled" in userValues.privatePlayerMode) {
          return this.addSmallDaxOverlay(params);
        }
        if ("alwaysAsk" in userValues.privatePlayerMode) {
          if (this.environment.hasOneTimeOverride()) return;
          if (this.ui.allowFirstVideo === true && !this.didAllowFirstVideo) {
            this.didAllowFirstVideo = true;
            return console.count("Allowing the first video");
          }
          if (this.userValues.overlayInteracted) {
            return this.addSmallDaxOverlay(params);
          }
          this.stopVideoFromPlaying();
          if (this.environment.layout === "mobile") {
            if (this.shouldShowDrawerVariant()) {
              const drawerTargetElement = document.querySelector(
                /** @type {string} */
                this.settings.selectors.drawerContainer
              );
              if (drawerTargetElement) {
                return this.appendMobileDrawer(targetElement, drawerTargetElement, params);
              }
            }
            return this.appendMobileOverlay(targetElement, params);
          }
          return this.appendDesktopOverlay(targetElement, params);
        }
      }
    }
    shouldShowDrawerVariant() {
      return this.settings.videoDrawer?.state === "enabled" && this.settings.selectors.drawerContainer;
    }
    /**
     * @param {Element} targetElement
     * @param {import("./util").VideoParams} params
     */
    appendMobileOverlay(targetElement, params) {
      this.messages.sendPixel(new Pixel({ name: "overlay" }));
      this.sideEffects.add(`appending ${DDGVideoOverlayMobile.CUSTOM_TAG_NAME} to the page`, () => {
        const elem = (
          /** @type {DDGVideoOverlayMobile} */
          document.createElement(DDGVideoOverlayMobile.CUSTOM_TAG_NAME)
        );
        elem.testMode = this.environment.isTestMode();
        elem.text = mobileStrings(this.environment.strings("overlays.json"));
        elem.addEventListener(DDGVideoOverlayMobile.OPEN_INFO, () => this.messages.openInfo());
        elem.addEventListener(DDGVideoOverlayMobile.OPT_OUT, (e) => {
          return this.mobileOptOut(e.detail.remember).catch(console.error);
        });
        elem.addEventListener(DDGVideoOverlayMobile.OPT_IN, (e) => {
          return this.mobileOptIn(e.detail.remember, params).catch(console.error);
        });
        targetElement.appendChild(elem);
        return () => {
          document.querySelector(DDGVideoOverlayMobile.CUSTOM_TAG_NAME)?.remove();
        };
      });
    }
    /**
     * @param {Element} targetElement
     * @param {Element} drawerTargetElement
     * @param {import("./util").VideoParams} params
     */
    appendMobileDrawer(targetElement, drawerTargetElement, params) {
      this.messages.sendPixel(new Pixel({ name: "overlay" }));
      this.sideEffects.add(
        `appending ${DDGVideoDrawerMobile.CUSTOM_TAG_NAME} and ${DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME} to the page`,
        () => {
          const thumbnailOverlay = (
            /** @type {DDGVideoThumbnailOverlay} */
            document.createElement(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)
          );
          thumbnailOverlay.testMode = this.environment.isTestMode();
          targetElement.appendChild(thumbnailOverlay);
          const drawer = (
            /** @type {DDGVideoDrawerMobile} */
            document.createElement(DDGVideoDrawerMobile.CUSTOM_TAG_NAME)
          );
          drawer.testMode = this.environment.isTestMode();
          drawer.text = mobileStrings(this.environment.strings("overlays.json"));
          drawer.addEventListener(DDGVideoDrawerMobile.OPEN_INFO, () => this.messages.openInfo());
          drawer.addEventListener(DDGVideoDrawerMobile.OPT_OUT, (e) => {
            return this.mobileOptOut(e.detail.remember).catch(console.error);
          });
          drawer.addEventListener(DDGVideoDrawerMobile.DISMISS, () => {
            return this.dismissOverlay();
          });
          drawer.addEventListener(DDGVideoDrawerMobile.THUMBNAIL_CLICK, () => {
            return this.dismissOverlay();
          });
          drawer.addEventListener(DDGVideoDrawerMobile.OPT_IN, (e) => {
            return this.mobileOptIn(e.detail.remember, params).catch(console.error);
          });
          drawerTargetElement.appendChild(drawer);
          if (thumbnailOverlay.container) {
            this.appendThumbnail(thumbnailOverlay.container);
          }
          return () => {
            document.querySelector(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)?.remove();
            drawer?.onAnimationEnd(() => {
              document.querySelector(DDGVideoDrawerMobile.CUSTOM_TAG_NAME)?.remove();
            });
          };
        }
      );
    }
    /**
     * @param {Element} targetElement
     * @param {import("./util").VideoParams} params
     */
    appendDesktopOverlay(targetElement, params) {
      this.messages.sendPixel(new Pixel({ name: "overlay" }));
      this.sideEffects.add(`appending ${DDGVideoOverlay.CUSTOM_TAG_NAME} to the page`, () => {
        const elem = new DDGVideoOverlay({
          environment: this.environment,
          params,
          ui: this.ui,
          manager: this
        });
        targetElement.appendChild(elem);
        return () => {
          document.querySelector(DDGVideoOverlay.CUSTOM_TAG_NAME)?.remove();
        };
      });
    }
    /**
     * Just brute-force calling video.pause() for as long as the user is seeing the overlay.
     */
    stopVideoFromPlaying() {
      this.sideEffects.add(`pausing the <video> element with selector '${this.settings.selectors.videoElement}'`, () => {
        const int = setInterval(() => {
          const video = (
            /** @type {HTMLVideoElement} */
            document.querySelector(this.settings.selectors.videoElement)
          );
          if (video?.isConnected) {
            video.pause();
          }
        }, 10);
        return () => {
          clearInterval(int);
          const video = (
            /** @type {HTMLVideoElement} */
            document.querySelector(this.settings.selectors.videoElement)
          );
          if (video?.isConnected) {
            video.play();
          }
        };
      });
    }
    /**
     * @param {HTMLElement} overlayElement
     */
    appendThumbnail(overlayElement) {
      const params = VideoParams.forWatchPage(this.environment.getPlayerPageHref());
      const videoId = params?.id;
      const imageUrl = this.environment.getLargeThumbnailSrc(videoId);
      appendImageAsBackground(overlayElement, ".ddg-vpo-bg", imageUrl);
    }
    /**
     * If the checkbox was checked, this action means that we want to 'always'
     * use the private player
     *
     * But, if the checkbox was not checked, then we want to keep the state
     * as 'alwaysAsk'
     *
     * @param {boolean} remember
     * @param {VideoParams} params
     */
    userOptIn(remember, params) {
      let privatePlayerMode = { alwaysAsk: {} };
      if (remember) {
        this.messages.sendPixel(new Pixel({ name: "play.use", remember: "1" }));
        privatePlayerMode = { enabled: {} };
      } else {
        this.messages.sendPixel(new Pixel({ name: "play.use", remember: "0" }));
      }
      const outgoing = {
        overlayInteracted: false,
        privatePlayerMode
      };
      this.messages.setUserValues(outgoing).then(() => {
        if (this.environment.opensVideoOverlayLinksViaMessage) {
          return this.messages.openDuckPlayer(new OpenInDuckPlayerMsg({ href: params.toPrivatePlayerUrl() }));
        }
        return this.environment.setHref(params.toPrivatePlayerUrl());
      }).catch((e) => console.error("error setting user choice", e));
    }
    /**
     * @param {boolean} remember
     * @param {import("./util").VideoParams} params
     */
    userOptOut(remember, params) {
      if (remember) {
        this.messages.sendPixel(new Pixel({ name: "play.do_not_use", remember: "1" }));
        const privatePlayerMode = { alwaysAsk: {} };
        this.messages.setUserValues({
          privatePlayerMode,
          overlayInteracted: true
        }).then((values) => {
          this.userValues = values;
        }).then(() => this.watchForVideoBeingAdded({ ignoreCache: true, via: "userOptOut" })).catch((e) => console.error("could not set userChoice for opt-out", e));
      } else {
        this.messages.sendPixel(new Pixel({ name: "play.do_not_use", remember: "0" }));
        this.destroy();
        this.addSmallDaxOverlay(params);
      }
    }
    /**
     * @param {boolean} remember
     * @param {import("./util").VideoParams} params
     */
    async mobileOptIn(remember, params) {
      const pixel = remember ? new Pixel({ name: "play.use", remember: "1" }) : new Pixel({ name: "play.use", remember: "0" });
      this.messages.sendPixel(pixel);
      const outgoing = {
        overlayInteracted: false,
        privatePlayerMode: remember ? { enabled: {} } : { alwaysAsk: {} }
      };
      const result = await this.messages.setUserValues(outgoing);
      if (this.environment.debug) {
        console.log("did receive new values", result);
      }
      return this.messages.openDuckPlayer(new OpenInDuckPlayerMsg({ href: params.toPrivatePlayerUrl() }));
    }
    /**
     * @param {boolean} remember
     */
    async mobileOptOut(remember) {
      const pixel = remember ? new Pixel({ name: "play.do_not_use", remember: "1" }) : new Pixel({ name: "play.do_not_use", remember: "0" });
      this.messages.sendPixel(pixel);
      if (!remember) {
        return this.destroy();
      }
      const next = {
        privatePlayerMode: { disabled: {} },
        overlayInteracted: false
      };
      if (this.environment.debug) {
        console.log("sending user values:", next);
      }
      const updatedValues = await this.messages.setUserValues(next);
      this.userValues = updatedValues;
      if (this.environment.debug) {
        console.log("user values response:", updatedValues);
      }
      this.destroy();
    }
    dismissOverlay() {
      const pixel = new Pixel({ name: "play.do_not_use.dismiss" });
      this.messages.sendPixel(pixel);
      return this.destroy();
    }
    /**
     * Remove elements, event listeners etc
     */
    destroy() {
      this.sideEffects.destroy();
    }
  };

  // src/features/duckplayer/components/index.js
  init_define_import_meta_trackerLookup();
  function registerCustomElements() {
    if (!customElementsGet(DDGVideoOverlay.CUSTOM_TAG_NAME)) {
      customElementsDefine(DDGVideoOverlay.CUSTOM_TAG_NAME, DDGVideoOverlay);
    }
    if (!customElementsGet(DDGVideoOverlayMobile.CUSTOM_TAG_NAME)) {
      customElementsDefine(DDGVideoOverlayMobile.CUSTOM_TAG_NAME, DDGVideoOverlayMobile);
    }
    if (!customElementsGet(DDGVideoDrawerMobile.CUSTOM_TAG_NAME)) {
      customElementsDefine(DDGVideoDrawerMobile.CUSTOM_TAG_NAME, DDGVideoDrawerMobile);
    }
    if (!customElementsGet(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)) {
      customElementsDefine(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME, DDGVideoThumbnailOverlay);
    }
  }

  // src/features/duckplayer/overlays.js
  async function initOverlays(settings, environment, messages) {
    const domState = new DomState();
    let initialSetup;
    try {
      initialSetup = await messages.initialSetup();
    } catch (e) {
      console.warn(e);
      return;
    }
    if (!initialSetup) {
      console.warn("cannot continue without user settings");
      return;
    }
    let { userValues, ui } = initialSetup;
    let thumbnails = thumbnailsFeatureFromOptions({ userValues, settings, messages, environment, ui });
    let videoOverlays = videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui });
    if (thumbnails || videoOverlays) {
      if (videoOverlays) {
        registerCustomElements();
        videoOverlays?.init("page-load");
      }
      domState.onLoaded(() => {
        thumbnails?.init();
        if (videoOverlays) {
          let prev = globalThis.location.href;
          setInterval(() => {
            if (globalThis.location.href !== prev) {
              videoOverlays?.init("href-changed");
            }
            prev = globalThis.location.href;
          }, 500);
        }
      });
    }
    function update() {
      thumbnails?.destroy();
      videoOverlays?.destroy();
      thumbnails = thumbnailsFeatureFromOptions({ userValues, settings, messages, environment, ui });
      thumbnails?.init();
      videoOverlays = videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui });
      videoOverlays?.init("preferences-changed");
    }
    messages.onUserValuesChanged((_userValues) => {
      userValues = _userValues;
      update();
    });
    messages.onUIValuesChanged((_ui) => {
      ui = _ui;
      update();
    });
  }
  function thumbnailsFeatureFromOptions(options) {
    return thumbnailOverlays(options) || clickInterceptions(options);
  }
  function thumbnailOverlays({ userValues, settings, messages, environment, ui }) {
    if (settings.thumbnailOverlays.state !== "enabled") return null;
    const conditions = [
      // must be in 'always ask' mode
      "alwaysAsk" in userValues.privatePlayerMode,
      // must not be set to play in DuckPlayer
      ui?.playInDuckPlayer !== true,
      // must be a desktop layout
      environment.layout === "desktop"
    ];
    if (!conditions.every(Boolean)) return null;
    return new Thumbnails({
      environment,
      settings,
      messages
    });
  }
  function clickInterceptions({ userValues, settings, messages, environment, ui }) {
    if (settings.clickInterception.state !== "enabled") return null;
    const conditions = [
      // either enabled via prefs
      "enabled" in userValues.privatePlayerMode,
      // or has a one-time override
      ui?.playInDuckPlayer === true
    ];
    if (!conditions.some(Boolean)) return null;
    return new ClickInterception({
      environment,
      settings,
      messages
    });
  }
  function videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui }) {
    if (settings.videoOverlays.state !== "enabled") return void 0;
    return new VideoOverlay({ userValues, settings, environment, messages, ui });
  }

  // src/features/duck-player.js
  var DuckPlayerFeature = class extends ContentFeature {
    init(args) {
      if (isBeingFramed()) return;
      const overlaySettings = this.getFeatureSetting("overlays");
      const overlaysEnabled = overlaySettings?.youtube?.state === "enabled";
      const serpProxyEnabled = overlaySettings?.serpProxy?.state === "enabled";
      if (!overlaysEnabled && !serpProxyEnabled) {
        return;
      }
      if (!this.messaging) {
        throw new Error("cannot operate duck player without a messaging backend");
      }
      const locale = args?.locale || args?.language || "en";
      const env = new Environment({
        debug: this.isDebug,
        injectName: "apple-isolated",
        platform: this.platform,
        locale
      });
      const comms = new DuckPlayerOverlayMessages(this.messaging, env);
      if (overlaysEnabled) {
        initOverlays(overlaySettings.youtube, env, comms);
      } else if (serpProxyEnabled) {
        comms.serpProxy();
      }
    }
  };

  // src/features/duck-player-native.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/messages.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/constants.js
  init_define_import_meta_trackerLookup();
  var MSG_NAME_INITIAL_SETUP2 = "initialSetup";
  var MSG_NAME_CURRENT_TIMESTAMP = "onCurrentTimestamp";
  var MSG_NAME_MEDIA_CONTROL = "onMediaControl";
  var MSG_NAME_MUTE_AUDIO = "onMuteAudio";
  var MSG_NAME_YOUTUBE_ERROR = "onYoutubeError";
  var MSG_NAME_URL_CHANGE = "onUrlChanged";
  var MSG_NAME_FEATURE_READY = "onDuckPlayerFeatureReady";
  var MSG_NAME_SCRIPTS_READY = "onDuckPlayerScriptsReady";
  var MSG_NAME_DISMISS_OVERLAY = "didDismissOverlay";

  // src/features/duckplayer-native/messages.js
  var DuckPlayerNativeMessages = class {
    /**
     * @param {Messaging} messaging
     * @param {Environment} environment
     * @internal
     */
    constructor(messaging, environment) {
      this.messaging = messaging;
      this.environment = environment;
    }
    /**
     * @returns {Promise<import('../duck-player-native.js').InitialSettings>}
     */
    initialSetup() {
      return this.messaging.request(MSG_NAME_INITIAL_SETUP2);
    }
    /**
     * Notifies with current timestamp as a string
     * @param {string} timestamp
     */
    notifyCurrentTimestamp(timestamp) {
      return this.messaging.notify(MSG_NAME_CURRENT_TIMESTAMP, { timestamp });
    }
    /**
     * Subscribe to media control events
     * @param {(mediaControlSettings: MediaControlSettings) => void} callback
     */
    subscribeToMediaControl(callback) {
      return this.messaging.subscribe(MSG_NAME_MEDIA_CONTROL, callback);
    }
    /**
     * Subscribe to mute audio events
     * @param {(muteSettings: MuteSettings) => void} callback
     */
    subscribeToMuteAudio(callback) {
      return this.messaging.subscribe(MSG_NAME_MUTE_AUDIO, callback);
    }
    /**
     * Subscribe to URL change events
     * @param {(urlSettings: UrlChangeSettings) => void} callback
     */
    subscribeToURLChange(callback) {
      return this.messaging.subscribe(MSG_NAME_URL_CHANGE, callback);
    }
    /**
     * Notifies browser of YouTube error
     * @param {YouTubeError} error
     */
    notifyYouTubeError(error) {
      this.messaging.notify(MSG_NAME_YOUTUBE_ERROR, { error });
    }
    /**
     * Notifies browser that the feature is ready
     */
    notifyFeatureIsReady() {
      this.messaging.notify(MSG_NAME_FEATURE_READY, {});
    }
    /**
     * Notifies browser that scripts are ready to be acalled
     */
    notifyScriptIsReady() {
      this.messaging.notify(MSG_NAME_SCRIPTS_READY, {});
    }
    /**
     * Notifies browser that the overlay was dismissed
     */
    notifyOverlayDismissed() {
      this.messaging.notify(MSG_NAME_DISMISS_OVERLAY, {});
    }
  };

  // src/features/duckplayer-native/sub-feature.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/sub-features/duck-player-native-youtube.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/mute-audio.js
  init_define_import_meta_trackerLookup();
  function muteAudio(mute) {
    document.querySelectorAll("audio, video").forEach((media) => {
      media.muted = mute;
    });
  }

  // src/features/duckplayer-native/get-current-timestamp.js
  init_define_import_meta_trackerLookup();
  function getCurrentTimestamp(selector) {
    const video = (
      /** @type {HTMLVideoElement|null} */
      document.querySelector(selector)
    );
    return video?.currentTime || 0;
  }
  function pollTimestamp(interval = 300, callback, selectors) {
    if (!callback || !selectors) {
      console.error("Timestamp polling failed. No callback or selectors defined");
      return () => {
      };
    }
    const isShowingAd = () => {
      return selectors.adShowing && !!document.querySelector(selectors.adShowing);
    };
    const timestampPolling = setInterval(() => {
      if (isShowingAd()) return;
      const timestamp = getCurrentTimestamp(selectors.videoElement);
      callback(timestamp);
    }, interval);
    return () => {
      clearInterval(timestampPolling);
    };
  }

  // src/features/duckplayer-native/pause-video.js
  init_define_import_meta_trackerLookup();
  function stopVideoFromPlaying(videoSelector) {
    const int = setInterval(() => {
      const video = (
        /** @type {HTMLVideoElement} */
        document.querySelector(videoSelector)
      );
      if (video?.isConnected) {
        video.pause();
      }
    }, 10);
    return () => {
      clearInterval(int);
      const video = (
        /** @type {HTMLVideoElement} */
        document.querySelector(videoSelector)
      );
      if (video?.isConnected) {
        video.play();
      }
    };
  }
  var MUTE_ELEMENTS_QUERY = "audio, video";
  function muteAllElements() {
    const int = setInterval(() => {
      const elements = Array.from(document.querySelectorAll(MUTE_ELEMENTS_QUERY));
      elements.forEach((element) => {
        if (element?.isConnected) {
          element.muted = true;
        }
      });
    }, 10);
    return () => {
      clearInterval(int);
      const elements = Array.from(document.querySelectorAll(MUTE_ELEMENTS_QUERY));
      elements.forEach((element) => {
        if (element?.isConnected) {
          element.muted = false;
        }
      });
    };
  }

  // src/features/duckplayer-native/overlays/thumbnail-overlay.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/overlays/thumbnail-overlay.css
  var thumbnail_overlay_default = `/* -- VIDEO PLAYER OVERLAY */
:host {
    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    right: 0;
    z-index: 10000;
    --title-size: 16px;
    --title-line-height: 20px;
    --title-gap: 16px;
    --button-gap: 6px;
    --logo-size: 32px;
    --logo-gap: 8px;
    --gutter: 16px;
}
/* iphone 15 */
@media screen and (min-width: 390px) {
    :host {
        --title-size: 20px;
        --title-line-height: 25px;
        --button-gap: 16px;
        --logo-size: 40px;
        --logo-gap: 12px;
        --title-gap: 16px;
    }
}
/* iphone 15 Pro Max */
@media screen and (min-width: 430px) {
    :host {
        --title-size: 22px;
        --title-gap: 24px;
        --button-gap: 20px;
        --logo-gap: 16px;
    }
}
/* small landscape */
@media screen and (min-width: 568px) {
}
/* large landscape */
@media screen and (min-width: 844px) {
    :host {
        --title-gap: 30px;
        --button-gap: 24px;
        --logo-size: 48px;
    }
}


:host * {
    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
}

:root *, :root *:after, :root *:before {
    box-sizing: border-box;
}

.ddg-video-player-overlay {
    width: 100%;
    height: 100%;
    padding-left: var(--gutter);
    padding-right: var(--gutter);

    @media screen and (min-width: 568px) {
        padding: 0;
    }
}

.bg {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    color: white;
    background: rgba(0, 0, 0, 0.6);
    background-position: center;
    text-align: center;
}

.logo {
    content: " ";
    position: absolute;
    display: block;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: transparent;
    background-image: url('data:image/svg+xml,<svg width="90" height="64" viewBox="0 0 90 64" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" clip-rule="evenodd" d="M88.119 9.88293C87.0841 6.01134 84.0348 2.96133 80.1625 1.92639C73.1438 0.0461578 44.9996 0.0461578 44.9996 0.0461578C44.9996 0.0461578 16.8562 0.0461578 9.83751 1.92639C5.96518 2.96133 2.91592 6.01134 1.88097 9.88293C0 16.9023 0 31.5456 0 31.5456C0 31.5456 0 46.1896 1.88097 53.2083C2.91592 57.0799 5.96518 60.1306 9.83751 61.1648C16.8562 63.0458 44.9996 63.0458 44.9996 63.0458C44.9996 63.0458 73.1438 63.0458 80.1625 61.1648C84.0348 60.1306 87.0841 57.0799 88.119 53.2083C90 46.1896 90 31.5456 90 31.5456C90 31.5456 90 16.9023 88.119 9.88293Z" fill="%23FF0000"/><path fill-rule="evenodd" clip-rule="evenodd" d="M36.8184 45.3313L60.2688 31.792L36.8184 18.2512V45.3313Z" fill="%23FFFFFE"/></svg>');
    background-size: 90px 64px;
    background-position: center center;
    background-repeat: no-repeat;
}
`;

  // src/features/duckplayer-native/overlays/thumbnail-overlay.js
  var _DDGVideoThumbnailOverlay = class _DDGVideoThumbnailOverlay extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "policy", createPolicy());
      /** @type {Logger} */
      __publicField(this, "logger");
      /** @type {boolean} */
      __publicField(this, "testMode", false);
      /** @type {HTMLElement} */
      __publicField(this, "container");
      /** @type {string} */
      __publicField(this, "href");
    }
    static register() {
      if (!customElementsGet(_DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)) {
        customElementsDefine(_DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME, _DDGVideoThumbnailOverlay);
      }
    }
    connectedCallback() {
      this.createMarkupAndStyles();
    }
    createMarkupAndStyles() {
      const shadow = this.attachShadow({ mode: this.testMode ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = thumbnail_overlay_default;
      const container = document.createElement("div");
      container.classList.add("wrapper");
      const content = this.render();
      container.innerHTML = this.policy.createHTML(content);
      shadow.append(style, container);
      this.container = container;
      const overlay = container.querySelector(".ddg-video-player-overlay");
      if (overlay) {
        overlay.addEventListener("click", () => {
          this.dispatchEvent(new Event(_DDGVideoThumbnailOverlay.OVERLAY_CLICKED));
        });
      }
      this.logger?.log("Created", _DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME, "with container", container);
      this.appendThumbnail();
    }
    appendThumbnail() {
      const params = VideoParams.forWatchPage(this.href);
      const imageUrl = params?.toLargeThumbnailUrl();
      if (!imageUrl) {
        this.logger?.warn("Could not get thumbnail url for video id", params?.id);
        return;
      }
      if (this.testMode) {
        this.logger?.log("Appending thumbnail", imageUrl);
      }
      appendImageAsBackground(this.container, ".ddg-vpo-bg", imageUrl);
    }
    /**
     * @returns {string}
     */
    render() {
      return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="logo"></div>
            </div>
        `.toString();
    }
  };
  __publicField(_DDGVideoThumbnailOverlay, "CUSTOM_TAG_NAME", "ddg-video-thumbnail-overlay-mobile");
  __publicField(_DDGVideoThumbnailOverlay, "OVERLAY_CLICKED", "overlay-clicked");
  var DDGVideoThumbnailOverlay2 = _DDGVideoThumbnailOverlay;
  function showThumbnailOverlay(targetElement, environment, onClick) {
    const logger = new Logger({
      id: "THUMBNAIL_OVERLAY",
      shouldLog: () => environment.isTestMode()
    });
    DDGVideoThumbnailOverlay2.register();
    const overlay = (
      /** @type {DDGVideoThumbnailOverlay} */
      document.createElement(DDGVideoThumbnailOverlay2.CUSTOM_TAG_NAME)
    );
    overlay.logger = logger;
    overlay.testMode = environment.isTestMode();
    overlay.href = environment.getPlayerPageHref();
    if (onClick) {
      overlay.addEventListener(DDGVideoThumbnailOverlay2.OVERLAY_CLICKED, onClick);
    }
    targetElement.appendChild(overlay);
    return () => {
      document.querySelector(DDGVideoThumbnailOverlay2.CUSTOM_TAG_NAME)?.remove();
    };
  }

  // src/features/duckplayer-native/sub-features/duck-player-native-youtube.js
  var DuckPlayerNativeYoutube = class {
    /**
     * @param {object} options
     * @param {DuckPlayerNativeSelectors} options.selectors
     * @param {Environment} options.environment
     * @param {DuckPlayerNativeMessages} options.messages
     * @param {boolean} options.paused
     */
    constructor({ selectors, environment, messages, paused }) {
      this.environment = environment;
      this.messages = messages;
      this.selectors = selectors;
      this.paused = paused;
      this.sideEffects = new SideEffects({
        debug: environment.isTestMode()
      });
      this.logger = new Logger({
        id: "DUCK_PLAYER_NATIVE",
        shouldLog: () => this.environment.isTestMode()
      });
    }
    onInit() {
      this.sideEffects.add("subscribe to media control", () => {
        return this.messages.subscribeToMediaControl(({ pause }) => {
          this.mediaControlHandler(pause);
        });
      });
      this.sideEffects.add("subscribing to mute audio", () => {
        return this.messages.subscribeToMuteAudio(({ mute }) => {
          this.logger.log("Running mute audio handler. Mute:", mute);
          muteAudio(mute);
        });
      });
    }
    onLoad() {
      this.sideEffects.add("started polling current timestamp", () => {
        const handler = (timestamp) => {
          this.messages.notifyCurrentTimestamp(timestamp.toFixed(0));
        };
        return pollTimestamp(300, handler, this.selectors);
      });
      if (this.paused) {
        this.mediaControlHandler(!!this.paused);
      }
    }
    /**
     * @param {boolean} pause
     */
    mediaControlHandler(pause) {
      this.logger.log("Running media control handler. Pause:", pause);
      const videoElement = this.selectors?.videoElement;
      const videoElementContainer = this.selectors?.videoElementContainer;
      if (!videoElementContainer || !videoElement) {
        this.logger.warn("Missing media control selectors in config");
        return;
      }
      const targetElement = document.querySelector(videoElementContainer);
      if (targetElement) {
        if (this.paused === pause) return;
        this.paused = pause;
        if (pause) {
          this.sideEffects.add("stopping video from playing", () => stopVideoFromPlaying(videoElement));
          this.sideEffects.add("muting all elements", () => muteAllElements());
          this.sideEffects.add("appending thumbnail", () => {
            const clickHandler = () => {
              this.messages.notifyOverlayDismissed();
              this.mediaControlHandler(false);
            };
            return showThumbnailOverlay(
              /** @type {HTMLElement} */
              targetElement,
              this.environment,
              clickHandler
            );
          });
        } else {
          this.sideEffects.destroy("stopping video from playing");
          this.sideEffects.destroy("muting all elements");
          this.sideEffects.destroy("appending thumbnail");
        }
      }
    }
    destroy() {
      this.sideEffects.destroy();
    }
  };

  // src/features/duckplayer-native/sub-features/duck-player-native-no-cookie.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/custom-error/custom-error.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/custom-error/custom-error.css
  var custom_error_default = `/* -- VIDEO PLAYER OVERLAY */
:host {
    --title-size: 16px;
    --title-line-height: 20px;
    --title-gap: 16px;
    --button-gap: 6px;
    --padding: 4px;
    --logo-size: 32px;
    --logo-gap: 8px;
    --gutter: 16px;
    --background-color: black;
    --background-color-alt: #2f2f2f;

    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    right: 0;
    z-index: 1000;
    height: 100vh;
}
/* iphone 15 */
@media screen and (min-width: 390px) {
    :host {
        --title-size: 20px;
        --title-line-height: 25px;
        --button-gap: 16px;
        --logo-size: 40px;
        --logo-gap: 12px;
        --title-gap: 16px;
    }
}
/* iphone 15 Pro Max */
@media screen and (min-width: 430px) {
    :host {
        --title-size: 22px;
        --title-gap: 24px;
        --button-gap: 20px;
        --logo-gap: 16px;
    }
}
/* small landscape */
@media screen and (min-width: 568px) {
}
/* large landscape */
@media screen and (min-width: 844px) {
    :host {
        --title-gap: 30px;
        --button-gap: 24px;
        --logo-size: 48px;
    }
}


:host * {
    font-family: system, -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
}

:root *, :root *:after, :root *:before {
    box-sizing: border-box;
}

.wrapper {
    align-items: center;
    background-color: var(--background-color);
    display: flex;
    height: 100%;
    justify-content: center;
    padding: var(--padding);
}

.error {
    align-items: center;
    display: grid;
    justify-items: center;
}

.error.mobile {
    border-radius: var(--inner-radius);
    overflow: auto;

    /* Prevents automatic text resizing */
    text-size-adjust: 100%;
    -webkit-text-size-adjust: 100%;

    @media screen and (min-width: 600px) and (min-height: 600px) {
        aspect-ratio: 16 / 9;
    }
}

.error.framed {
    padding: 4px;
    border: 4px solid var(--background-color-alt);
    border-radius: 16px;
}

.container {
    background: var(--background-color);
    column-gap: 24px;
    display: flex;
    flex-flow: row;
    margin: 0;
    max-width: 680px;
    padding: 0 40px;
    row-gap: 4px;
}

.mobile .container {
    flex-flow: column;
    padding: 0 24px;

    @media screen and (min-height: 320px) {
        margin: 16px 0;
    }

    @media screen and (min-width: 375px) and (min-height: 400px) {
        margin: 36px 0;
    }
}

.content {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin: 16px 0;

    @media screen and (min-width: 600px) {
        margin: 24px 0;
    }
}


.icon {
    align-self: center;
    display: flex;
    justify-content: center;

    &::before {
        content: ' ';
        display: block;
        background-image: url("data:image/svg+xml,%3Csvg fill='none' viewBox='0 0 96 96' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath fill='red' d='M47.5 70.802c1.945 0 3.484-1.588 3.841-3.5C53.076 58.022 61.218 51 71 51h4.96c2.225 0 4.04-1.774 4.04-4 0-.026-.007-9.022-1.338-14.004a8.02 8.02 0 0 0-5.659-5.658C68.014 26 48 26 48 26s-20.015 0-25.004 1.338a8.01 8.01 0 0 0-5.658 5.658C16 37.986 16 48.401 16 48.401s0 10.416 1.338 15.405a8.01 8.01 0 0 0 5.658 5.658c4.99 1.338 24.504 1.338 24.504 1.338'/%3E%3Cpath fill='%23fff' d='m41.594 58 16.627-9.598-16.627-9.599z'/%3E%3Cpath fill='%23EB102D' d='M87 71c0 8.837-7.163 16-16 16s-16-7.163-16-16 7.163-16 16-16 16 7.163 16 16'/%3E%3Cpath fill='%23fff' d='M73 77.8a2 2 0 1 1-4 0 2 2 0 0 1 4 0m-2.039-4.4c-.706 0-1.334-.49-1.412-1.12l-.942-8.75c-.079-.7.55-1.33 1.412-1.33h1.962c.785 0 1.492.63 1.413 1.33l-.942 8.75c-.157.63-.784 1.12-1.49 1.12Z'/%3E%3Cpath fill='%23CCC' d='M92.501 59c.298 0 .595.12.823.354.454.468.454 1.23 0 1.698l-2.333 2.4a1.145 1.145 0 0 1-1.65 0 1.227 1.227 0 0 1 0-1.698l2.333-2.4c.227-.234.524-.354.822-.354zm-1.166 10.798h3.499c.641 0 1.166.54 1.166 1.2s-.525 1.2-1.166 1.2h-3.499c-.641 0-1.166-.54-1.166-1.2s.525-1.2 1.166-1.2m-1.982 8.754c.227-.234.525-.354.822-.354h.006c.297 0 .595.12.822.354l2.332 2.4c.455.467.455 1.23 0 1.697a1.145 1.145 0 0 1-1.65 0l-2.332-2.4a1.227 1.227 0 0 1 0-1.697'/%3E%3C/svg%3E%0A");
        background-repeat: no-repeat;
        height: 96px;
        width: 96px;
    }

    @media screen and (max-width: 320px) {
        display: none;
    }

    @media screen and (min-width: 600px) and (min-height: 600px) {
        justify-content: start;

        &::before {
            background-image: url("data:image/svg+xml,%3Csvg fill='none' viewBox='0 0 128 96' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath fill='%23888' d='M16.912 31.049a1.495 1.495 0 0 1 2.114-2.114l1.932 1.932 1.932-1.932a1.495 1.495 0 0 1 2.114 2.114l-1.932 1.932 1.932 1.932a1.495 1.495 0 0 1-2.114 2.114l-1.932-1.933-1.932 1.933a1.494 1.494 0 1 1-2.114-2.114l1.932-1.932zM.582 52.91a1.495 1.495 0 0 1 2.113-2.115l1.292 1.292 1.291-1.292a1.495 1.495 0 1 1 2.114 2.114L6.1 54.2l1.292 1.292a1.495 1.495 0 1 1-2.113 2.114l-1.292-1.292-1.292 1.292a1.495 1.495 0 1 1-2.114-2.114l1.292-1.291zm104.972-15.452a1.496 1.496 0 0 1 2.114-2.114l1.291 1.292 1.292-1.292a1.495 1.495 0 0 1 2.114 2.114l-1.292 1.291 1.292 1.292a1.494 1.494 0 1 1-2.114 2.114l-1.292-1.292-1.291 1.292a1.495 1.495 0 0 1-2.114-2.114l1.292-1.292zM124.5 54c-.825 0-1.5-.675-1.5-1.5s.675-1.5 1.5-1.5 1.5.675 1.5 1.5-.675 1.5-1.5 1.5M24 67c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2' opacity='.2'/%3E%3Cpath fill='red' d='M63.5 70.802c1.945 0 3.484-1.588 3.841-3.5C69.076 58.022 77.218 51 87 51h4.96c2.225 0 4.04-1.774 4.04-4 0-.026-.007-9.022-1.338-14.004a8.02 8.02 0 0 0-5.659-5.658C84.014 26 64 26 64 26s-20.014 0-25.004 1.338a8.01 8.01 0 0 0-5.658 5.658C32 37.986 32 48.401 32 48.401s0 10.416 1.338 15.405a8.01 8.01 0 0 0 5.658 5.658c4.99 1.338 24.504 1.338 24.504 1.338'/%3E%3Cpath fill='%23fff' d='m57.594 58 16.627-9.598-16.627-9.599z'/%3E%3Cpath fill='%23EB102D' d='M103 71c0 8.837-7.163 16-16 16s-16-7.163-16-16 7.163-16 16-16 16 7.163 16 16'/%3E%3Cpath fill='%23fff' d='M89 77.8a2 2 0 1 1-4 0 2 2 0 0 1 4 0m-2.039-4.4c-.706 0-1.334-.49-1.412-1.12l-.942-8.75c-.079-.7.55-1.33 1.412-1.33h1.962c.785 0 1.492.63 1.413 1.33l-.942 8.75c-.157.63-.784 1.12-1.49 1.12Z'/%3E%3Cpath fill='%23CCC' d='M108.501 59c.298 0 .595.12.823.354.454.468.454 1.23 0 1.698l-2.333 2.4a1.145 1.145 0 0 1-1.65 0 1.226 1.226 0 0 1 0-1.698l2.332-2.4c.228-.234.525-.354.823-.354zm-1.166 10.798h3.499c.641 0 1.166.54 1.166 1.2s-.525 1.2-1.166 1.2h-3.499c-.641 0-1.166-.54-1.166-1.2s.525-1.2 1.166-1.2m-1.982 8.754c.227-.234.525-.354.822-.354h.006c.297 0 .595.12.822.354l2.333 2.4c.454.467.454 1.23 0 1.697a1.146 1.146 0 0 1-1.651 0l-2.332-2.4a1.226 1.226 0 0 1 0-1.697'/%3E%3C/svg%3E%0A");
            height: 96px;
            width: 128px;
        }
    }
}

.heading {
    color: #fff;
    font-size: 20px;
    font-weight: 700;
    line-height: calc(24 / 20);
    margin: 0;
}

.messages {
    color: #ccc;
    font-size: 16px;
    line-height: calc(24 / 16);
}

div.messages {
    display: flex;
    flex-direction: column;
    gap: 24px;

    & p {
        margin: 0;
    }
}

p.messages {
    margin: 0;
}

ul.messages {
    li {
        list-style: disc;
        margin-left: 24px;
    }
}
`;

  // src/features/duckplayer-native/custom-error/custom-error.js
  var _CustomError = class _CustomError extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "policy", createPolicy());
      /** @type {Logger} */
      __publicField(this, "logger");
      /** @type {boolean} */
      __publicField(this, "testMode", false);
      /** @type {YouTubeError} */
      __publicField(this, "error");
      /** @type {string} */
      __publicField(this, "title", "");
      /** @type {string[]} */
      __publicField(this, "messages", []);
    }
    static register() {
      if (!customElementsGet(_CustomError.CUSTOM_TAG_NAME)) {
        customElementsDefine(_CustomError.CUSTOM_TAG_NAME, _CustomError);
      }
    }
    connectedCallback() {
      this.createMarkupAndStyles();
    }
    createMarkupAndStyles() {
      const shadow = this.attachShadow({ mode: this.testMode ? "open" : "closed" });
      const style = document.createElement("style");
      style.innerText = custom_error_default;
      const container = document.createElement("div");
      container.classList.add("wrapper");
      const content = this.render();
      container.innerHTML = this.policy.createHTML(content);
      shadow.append(style, container);
      this.container = container;
      this.logger?.log("Created", _CustomError.CUSTOM_TAG_NAME, "with container", container);
    }
    /**
     * @returns {string}
     */
    render() {
      if (!this.title || !this.messages) {
        console.warn("Missing error title or messages. Please assign before rendering");
        return "";
      }
      const { title, messages } = this;
      const messagesHtml = messages.map((message) => html`<p>${message}</p>`);
      return html`
            <div class="error mobile">
                <div class="container">
                    <span class="icon"></span>

                    <div class="content">
                        <h1 class="heading">${title}</h1>
                        <div class="messages">${messagesHtml}</div>
                    </div>
                </div>
            </div>
        `.toString();
    }
  };
  __publicField(_CustomError, "CUSTOM_TAG_NAME", "ddg-video-error");
  var CustomError = _CustomError;
  function getErrorStrings(errorId, t) {
    switch (errorId) {
      case "sign-in-required":
        return {
          title: t("signInRequiredErrorHeading2"),
          messages: [t("signInRequiredErrorMessage2a"), t("signInRequiredErrorMessage2b")]
        };
      case "age-restricted":
        return {
          title: t("ageRestrictedErrorHeading2"),
          messages: [t("ageRestrictedErrorMessage2a"), t("ageRestrictedErrorMessage2b")]
        };
      case "no-embed":
        return {
          title: t("noEmbedErrorHeading2"),
          messages: [t("noEmbedErrorMessage2a"), t("noEmbedErrorMessage2b")]
        };
      case "unknown":
      default:
        return {
          title: t("unknownErrorHeading2"),
          messages: [t("unknownErrorMessage2a"), t("unknownErrorMessage2b")]
        };
    }
  }
  function showError(targetElement, errorId, environment, t) {
    const { title, messages } = getErrorStrings(errorId, t);
    const logger = new Logger({
      id: "CUSTOM_ERROR",
      shouldLog: () => environment.isTestMode()
    });
    CustomError.register();
    const customError = (
      /** @type {CustomError} */
      document.createElement(CustomError.CUSTOM_TAG_NAME)
    );
    customError.logger = logger;
    customError.testMode = environment.isTestMode();
    customError.title = title;
    customError.messages = messages;
    targetElement.appendChild(customError);
    return () => {
      document.querySelector(CustomError.CUSTOM_TAG_NAME)?.remove();
    };
  }

  // src/features/duckplayer-native/error-detection.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/youtube-errors.js
  init_define_import_meta_trackerLookup();
  var YOUTUBE_ERRORS = {
    ageRestricted: "age-restricted",
    signInRequired: "sign-in-required",
    noEmbed: "no-embed",
    unknown: "unknown"
  };
  var YOUTUBE_ERROR_IDS = Object.values(YOUTUBE_ERRORS);
  function checkForError(errorSelector, node) {
    if (node?.nodeType === Node.ELEMENT_NODE) {
      const element = (
        /** @type {HTMLElement} */
        node
      );
      const isError = element.matches(errorSelector) || !!element.querySelector(errorSelector);
      return isError;
    }
    return false;
  }
  function getErrorType(windowObject, signInRequiredSelector, logger) {
    const currentWindow = (
      /** @type {Window & typeof globalThis & { ytcfg: object }} */
      windowObject
    );
    const currentDocument = currentWindow.document;
    if (!currentWindow || !currentDocument) {
      logger?.warn("Window or document missing!");
      return YOUTUBE_ERRORS.unknown;
    }
    let playerResponse;
    if (!currentWindow.ytcfg) {
      logger?.warn("ytcfg missing!");
    } else {
      logger?.log("Got ytcfg", currentWindow.ytcfg);
    }
    try {
      const playerResponseJSON = currentWindow.ytcfg?.get("PLAYER_VARS")?.embedded_player_response;
      logger?.log("Player response", playerResponseJSON);
      playerResponse = JSON.parse(playerResponseJSON);
    } catch (e) {
      logger?.log("Could not parse player response", e);
    }
    if (typeof playerResponse === "object") {
      const {
        previewPlayabilityStatus: { desktopLegacyAgeGateReason, status }
      } = playerResponse;
      if (status === "UNPLAYABLE") {
        if (desktopLegacyAgeGateReason === 1) {
          logger?.log("AGE RESTRICTED ERROR");
          return YOUTUBE_ERRORS.ageRestricted;
        }
        logger?.log("NO EMBED ERROR");
        return YOUTUBE_ERRORS.noEmbed;
      }
    }
    try {
      if (signInRequiredSelector && !!currentDocument.querySelector(signInRequiredSelector)) {
        logger?.log("SIGN-IN ERROR");
        return YOUTUBE_ERRORS.signInRequired;
      }
    } catch (e) {
      logger?.log("Sign-in required query failed", e);
    }
    logger?.log("UNKNOWN ERROR");
    return YOUTUBE_ERRORS.unknown;
  }

  // src/features/duckplayer-native/error-detection.js
  var ErrorDetection = class {
    /**
     * @param {ErrorDetectionSettings} settings
     */
    constructor({ selectors, callback, testMode = false }) {
      /** @type {Logger} */
      __publicField(this, "logger");
      /** @type {DuckPlayerNativeSelectors} */
      __publicField(this, "selectors");
      /** @type {ErrorDetectionCallback} */
      __publicField(this, "callback");
      /** @type {boolean} */
      __publicField(this, "testMode");
      if (!selectors?.youtubeError || !selectors?.signInRequiredError || !callback) {
        throw new Error("Missing selectors or callback props");
      }
      this.selectors = selectors;
      this.callback = callback;
      this.testMode = testMode;
      this.logger = new Logger({
        id: "ERROR_DETECTION",
        shouldLog: () => this.testMode
      });
    }
    /**
     *
     * @returns {(() => void)|void}
     */
    observe() {
      const documentBody = document?.body;
      if (documentBody) {
        if (checkForError(this.selectors.youtubeError, documentBody)) {
          const error = getErrorType(window, this.selectors.signInRequiredError, this.logger);
          this.handleError(error);
          return;
        }
        const observer = new MutationObserver(this.handleMutation.bind(this));
        observer.observe(documentBody, {
          childList: true,
          subtree: true
          // Observe all descendants of the body
        });
        return () => {
          observer.disconnect();
        };
      }
    }
    /**
     *
     * @param {YouTubeError} errorId
     */
    handleError(errorId) {
      if (this.callback) {
        this.logger.log("Calling error handler for", errorId);
        this.callback(errorId);
      } else {
        this.logger.warn("No error callback found");
      }
    }
    /**
     * Mutation handler that checks new nodes for error states
     *
     * @type {MutationCallback}
     */
    handleMutation(mutationsList) {
      for (const mutation of mutationsList) {
        if (mutation.type === "childList") {
          mutation.addedNodes.forEach((node) => {
            if (checkForError(this.selectors.youtubeError, node)) {
              this.logger.log("A node with an error has been added to the document:", node);
              const error = getErrorType(window, this.selectors.signInRequiredError, this.logger);
              this.handleError(error);
            }
          });
        }
      }
    }
  };

  // src/features/duckplayer-native/sub-features/duck-player-native-no-cookie.js
  var DuckPlayerNativeNoCookie = class {
    /**
     * @param {object} options
     * @param {Environment} options.environment
     * @param {DuckPlayerNativeMessages} options.messages
     * @param {DuckPlayerNativeSelectors} options.selectors
     * @param {TranslationFn} options.t
     */
    constructor({ environment, messages, selectors, t }) {
      this.environment = environment;
      this.selectors = selectors;
      this.messages = messages;
      this.t = t;
      this.sideEffects = new SideEffects({
        debug: environment.isTestMode()
      });
      this.logger = new Logger({
        id: "DUCK_PLAYER_NATIVE",
        shouldLog: () => this.environment.isTestMode()
      });
    }
    onInit() {
    }
    onLoad() {
      this.sideEffects.add("started polling current timestamp", () => {
        const handler = (timestamp) => {
          this.messages.notifyCurrentTimestamp(timestamp.toFixed(0));
        };
        return pollTimestamp(300, handler, this.selectors);
      });
      this.logger.log("Setting up error detection");
      const errorContainer = this.selectors?.errorContainer;
      const signInRequiredError = this.selectors?.signInRequiredError;
      if (!errorContainer || !signInRequiredError) {
        this.logger.warn("Missing error selectors in configuration");
        return;
      }
      const errorHandler = (errorId) => {
        this.logger.log("Received error", errorId);
        this.messages.notifyYouTubeError(errorId);
        const targetElement = document.querySelector(errorContainer);
        if (targetElement) {
          showError(
            /** @type {HTMLElement} */
            targetElement,
            errorId,
            this.environment,
            this.t
          );
        }
      };
      const errorDetectionSettings = {
        selectors: this.selectors,
        testMode: this.environment.isTestMode(),
        callback: errorHandler
      };
      this.sideEffects.add("setting up error detection", () => {
        const errorDetection = new ErrorDetection(errorDetectionSettings);
        const destroy = errorDetection.observe();
        return () => {
          if (destroy) destroy();
        };
      });
    }
    destroy() {
      this.sideEffects.destroy();
    }
  };

  // src/features/duckplayer-native/sub-features/duck-player-native-serp.js
  init_define_import_meta_trackerLookup();
  var DuckPlayerNativeSerp = class {
    onLoad() {
      window.dispatchEvent(
        new CustomEvent("ddg-serp-yt-response", {
          detail: {
            kind: "initialSetup",
            data: {
              privatePlayerMode: { enabled: {} },
              overlayInteracted: false
            }
          },
          composed: true,
          bubbles: true
        })
      );
    }
    onInit() {
    }
    destroy() {
    }
  };

  // src/features/duckplayer-native/sub-feature.js
  function setupDuckPlayerForYouTube(selectors, paused, environment, messages) {
    return new DuckPlayerNativeYoutube({
      selectors,
      environment,
      messages,
      paused
    });
  }
  function setupDuckPlayerForNoCookie(selectors, environment, messages, t) {
    return new DuckPlayerNativeNoCookie({
      selectors,
      environment,
      messages,
      t
    });
  }
  function setupDuckPlayerForSerp() {
    return new DuckPlayerNativeSerp();
  }

  // src/features/duck-player-native.js
  var DuckPlayerNativeFeature = class extends ContentFeature {
    constructor() {
      super(...arguments);
      /** @type {DuckPlayerNativeSubFeature | null} */
      __publicField(this, "currentPage");
      /** @type {TranslationFn} */
      __publicField(this, "t");
    }
    async init(args) {
      if (isBeingFramed()) return;
      const selectors = this.getFeatureSetting("selectors");
      if (!selectors) {
        console.warn("No selectors found. Check remote config. Feature will not be initialized.");
        return;
      }
      const locale = args?.locale || args?.language || "en";
      const env = new Environment({
        debug: this.isDebug,
        injectName: "apple-isolated",
        platform: this.platform,
        locale
      });
      this.t = (key) => env.strings("native.json")[key];
      const messages = new DuckPlayerNativeMessages(this.messaging, env);
      messages.subscribeToURLChange(({ pageType }) => {
        const playbackPaused = false;
        this.urlDidChange(pageType, selectors, playbackPaused, env, messages);
      });
      let initialSetup;
      try {
        initialSetup = await messages.initialSetup();
      } catch (e) {
        console.warn("Failed to get initial setup", e);
        return;
      }
      if (initialSetup.pageType) {
        const playbackPaused = initialSetup.playbackPaused || false;
        this.urlDidChange(initialSetup.pageType, selectors, playbackPaused, env, messages);
      }
    }
    /**
     *
     * @param {UrlChangeSettings['pageType']} pageType
     * @param {DuckPlayerNativeSettings['selectors']} selectors
     * @param {boolean} playbackPaused
     * @param {Environment} env
     * @param {DuckPlayerNativeMessages} messages
     */
    urlDidChange(pageType, selectors, playbackPaused, env, messages) {
      let nextPage = null;
      const logger = new Logger({
        id: "DUCK_PLAYER_NATIVE",
        shouldLog: () => env.isTestMode()
      });
      switch (pageType) {
        case "NOCOOKIE":
          nextPage = setupDuckPlayerForNoCookie(selectors, env, messages, this.t);
          break;
        case "YOUTUBE":
          nextPage = setupDuckPlayerForYouTube(selectors, playbackPaused, env, messages);
          break;
        case "SERP":
          nextPage = setupDuckPlayerForSerp();
          break;
        case "UNKNOWN":
        default:
          console.warn("No known pageType");
      }
      if (this.currentPage) {
        this.currentPage.destroy();
      }
      if (nextPage) {
        logger.log("Running init handlers");
        nextPage.onInit();
        this.currentPage = nextPage;
        if (document.readyState === "loading") {
          const loadHandler = () => {
            logger.log("Running deferred load handlers");
            nextPage.onLoad();
            messages.notifyScriptIsReady();
          };
          document.addEventListener("DOMContentLoaded", loadHandler, { once: true });
        } else {
          logger.log("Running load handlers immediately");
          nextPage.onLoad();
          messages.notifyScriptIsReady();
        }
      }
    }
  };
  var duck_player_native_default = DuckPlayerNativeFeature;

  // src/features/broker-protection.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/execute.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/actions/actions.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/actions/extract.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/utils/utils.js
  init_define_import_meta_trackerLookup();
  function getElement(doc = document, selector) {
    if (isXpath(selector)) {
      return safeQuerySelectorXPath(doc, selector);
    }
    return safeQuerySelector(doc, selector);
  }
  function getElementByTagName(doc = document, name) {
    return safeQuerySelector(doc, `[name="${name}"]`);
  }
  function getElementWithSrcStart(node = document, src) {
    return safeQuerySelector(node, `[src^="${src}"]`);
  }
  function getElements(doc = document, selector) {
    if (isXpath(selector)) {
      return safeQuerySelectorAllXpath(doc, selector);
    }
    return safeQuerySelectorAll(doc, selector);
  }
  function getElementMatches(element, selector) {
    try {
      if (isXpath(selector)) {
        return matchesXPath(element, selector) ? element : null;
      } else {
        return element.matches(selector) ? element : null;
      }
    } catch (e) {
      console.error("getElementMatches threw: ", e);
      return null;
    }
  }
  function matchesXPath(element, selector) {
    const xpathResult = document.evaluate(selector, element, null, XPathResult.BOOLEAN_TYPE, null);
    return xpathResult.booleanValue;
  }
  function isXpath(selector) {
    if (!(typeof selector === "string")) return false;
    if (selector === ".") return true;
    return selector.startsWith("//") || selector.startsWith("./") || selector.startsWith("(");
  }
  function safeQuerySelectorAll(element, selector) {
    try {
      if (element && "querySelectorAll" in element) {
        return Array.from(element?.querySelectorAll?.(selector));
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  function safeQuerySelector(element, selector) {
    try {
      if (element && "querySelector" in element) {
        return element?.querySelector?.(selector);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  function safeQuerySelectorXPath(element, selector) {
    try {
      const match = document.evaluate(selector, element, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      const single = match?.singleNodeValue;
      if (single) {
        return (
          /** @type {HTMLElement} */
          single
        );
      }
      return null;
    } catch (e) {
      console.log("safeQuerySelectorXPath threw", e);
      return null;
    }
  }
  function safeQuerySelectorAllXpath(element, selector) {
    try {
      const xpathResult = document.evaluate(selector, element, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
      if (xpathResult) {
        const matchedNodes = [];
        for (let i = 0; i < xpathResult.snapshotLength; i++) {
          const item = xpathResult.snapshotItem(i);
          if (item) matchedNodes.push(
            /** @type {HTMLElement} */
            item
          );
        }
        return (
          /** @type {HTMLElement[]} */
          matchedNodes
        );
      }
      return null;
    } catch (e) {
      console.log("safeQuerySelectorAllXpath threw", e);
      return null;
    }
  }
  function generateRandomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1) + min);
  }
  function cleanArray(input, prev = []) {
    if (!Array.isArray(input)) {
      if (input === null) return prev;
      if (input === void 0) return prev;
      if (typeof input === "string") {
        const trimmed = input.trim();
        if (trimmed.length > 0) {
          prev.push(
            /** @type {NonNullable<T>} */
            trimmed
          );
        }
      } else {
        prev.push(input);
      }
      return prev;
    }
    for (const item of input) {
      prev.push(...cleanArray(item));
    }
    return prev;
  }
  function nonEmptyString(input) {
    if (typeof input !== "string") return false;
    return input.trim().length > 0;
  }
  function matchingPair(a2, b2) {
    if (!nonEmptyString(a2)) return false;
    if (!nonEmptyString(b2)) return false;
    return a2.toLowerCase().trim() === b2.toLowerCase().trim();
  }
  function sortAddressesByStateAndCity(addresses) {
    return addresses.sort((a2, b2) => {
      if (a2.state < b2.state) {
        return -1;
      }
      if (a2.state > b2.state) {
        return 1;
      }
      return a2.city.localeCompare(b2.city);
    });
  }
  async function hashObject(profile) {
    const msgUint8 = new TextEncoder().encode(JSON.stringify(profile));
    const hashBuffer = await crypto.subtle.digest("SHA-1", msgUint8);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map((b2) => b2.toString(16).padStart(2, "0")).join("");
    return hashHex;
  }

  // src/features/broker-protection/types.js
  init_define_import_meta_trackerLookup();
  var PirError = class _PirError {
    /**
     * @param {object} params
     * @param {boolean} params.success
     * @param {object} params.error
     * @param {string} params.error.message
     */
    constructor(params) {
      this.success = params.success;
      this.error = params.error;
    }
    /**
     * @param {string} message
     * @return {PirError}
     * @static
     * @memberof PirError
     */
    static create(message) {
      return new _PirError({ success: false, error: { message } });
    }
    /**
     * @param {object} error
     * @return {error is PirError}
     * @static
     * @memberof PirError
     */
    static isError(error) {
      return error instanceof _PirError && error.success === false;
    }
  };
  var PirSuccess = class _PirSuccess {
    /**
     * @param {object} params
     * @param {boolean} params.success
     * @param {T} params.response
     */
    constructor(params) {
      this.success = params.success;
      this.response = params.response;
    }
    /**
     * @template T
     * @param {T} response
     * @return {PirSuccess<T>}
     * @static
     * @memberof PirSuccess
     */
    static create(response) {
      return new _PirSuccess({ success: true, response });
    }
    static createEmpty() {
      return new _PirSuccess({ success: true, response: null });
    }
    /**
     * @param {object} params
     * @return {params is PirSuccess}
     * @static
     * @memberof PirSuccess
     */
    static isSuccess(params) {
      return params instanceof _PirSuccess && params.success === true;
    }
  };
  var ErrorResponse = class _ErrorResponse {
    /**
     * @param {object} params
     * @param {string} params.actionID
     * @param {string} params.message
     */
    constructor(params) {
      this.error = params;
    }
    /**
     * @param {ActionResponse} response
     * @return {response is ErrorResponse}
     * @static
     * @memberof ErrorResponse
     */
    static isErrorResponse(response) {
      return response instanceof _ErrorResponse;
    }
    /**
     * @param {object} params
     * @param {PirAction['id']} params.actionID
     * @param {string} [params.context]
     * @return {(message: string) => ErrorResponse}
     * @static
     * @memberof ErrorResponse
     */
    static generateErrorResponseFunction({ actionID, context = "" }) {
      return (message) => new _ErrorResponse({ actionID, message: [context, message].filter(Boolean).join(": ") });
    }
  };
  var SuccessResponse = class _SuccessResponse {
    /**
     * @param {SuccessResponseInterface} params
     */
    constructor(params) {
      this.success = params;
    }
    /**
     * @param {SuccessResponseInterface} params
     * @return {SuccessResponse}
     * @static
     * @memberof SuccessResponse
     */
    static create(params) {
      return new _SuccessResponse(params);
    }
  };
  var ProfileResult = class {
    /**
     * @param {object} params
     * @param {boolean} params.result - whether we consider this a 'match'
     * @param {string[]} params.matchedFields - a list of the fields in the data that were matched.
     * @param {number} params.score - value to determine
     * @param {HTMLElement} [params.element] - the parent element that was matched. Not present in JSON
     * @param {Record<string, any>} params.scrapedData
     */
    constructor(params) {
      this.scrapedData = params.scrapedData;
      this.result = params.result;
      this.score = params.score;
      this.element = params.element;
      this.matchedFields = params.matchedFields;
    }
    /**
     * Convert this structure into a format that can be sent between JS contexts/native
     * @return {{result: boolean, score: number, matchedFields: string[], scrapedData: Record<string, any>}}
     */
    asData() {
      return {
        scrapedData: this.scrapedData,
        result: this.result,
        score: this.score,
        matchedFields: this.matchedFields
      };
    }
  };

  // src/features/broker-protection/comparisons/is-same-age.js
  init_define_import_meta_trackerLookup();
  function isSameAge(userAge, ageFound) {
    const ageVariance = 2;
    userAge = parseInt(userAge);
    ageFound = parseInt(ageFound);
    if (isNaN(ageFound)) {
      return false;
    }
    if (Math.abs(userAge - ageFound) < ageVariance) {
      return true;
    }
    return false;
  }

  // src/features/broker-protection/comparisons/is-same-name.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/comparisons/constants.js
  init_define_import_meta_trackerLookup();
  var names = {
    /** @type {null | Record<string, string[]>} */
    _memo: null,
    /**
     * This is wrapped in a way to prevent initialization in the top-level context
     * when hoisted by bundlers
     * @return {Record<string, string[]>}
     */
    get nicknames() {
      if (this._memo !== null) return this._memo;
      this._memo = {
        aaron: ["erin", "ronnie", "ron"],
        abbigail: ["nabby", "abby", "gail", "abbe", "abbi", "abbey", "abbie"],
        abbigale: ["nabby", "abby", "gail", "abbe", "abbi", "abbey", "abbie"],
        abednego: ["bedney"],
        abel: ["ebbie", "ab", "abe", "eb"],
        abiel: ["ab"],
        abigail: ["nabby", "abby", "gail", "abbe", "abbi", "abbey", "abbie"],
        abigale: ["nabby", "abby", "gail", "abbe", "abbi", "abbey", "abbie"],
        abijah: ["ab", "bige"],
        abner: ["ab"],
        abraham: ["ab", "abe"],
        abram: ["ab", "abe"],
        absalom: ["app", "ab", "abbie"],
        ada: ["addy", "adie"],
        adaline: ["delia", "lena", "dell", "addy", "ada", "adie"],
        addison: ["addie", "addy"],
        adela: ["della", "adie"],
        adelaide: ["heidi", "adele", "dell", "addy", "della", "adie"],
        adelbert: ["del", "albert", "delbert", "bert"],
        adele: ["addy", "dell"],
        adeline: ["delia", "lena", "dell", "addy", "ada"],
        adelphia: ["philly", "delphia", "adele", "dell", "addy"],
        adena: ["dena", "dina", "deena", "adina"],
        adolphus: ["dolph", "ado", "adolph"],
        adrian: ["rian"],
        adriane: ["riane"],
        adrienne: ["addie", "rienne", "enne"],
        agatha: ["aggy", "aga"],
        agnes: ["inez", "aggy", "nessa"],
        aileen: ["lena", "allie"],
        alan: ["al"],
        alanson: ["al", "lanson"],
        alastair: ["al"],
        alazama: ["ali"],
        albert: ["bert", "al"],
        alberta: ["bert", "allie", "bertie"],
        aldo: ["al"],
        aldrich: ["riche", "rich", "richie"],
        aleksandr: ["alex", "alek"],
        aleva: ["levy", "leve"],
        alex: ["al"],
        alexander: ["alex", "al", "sandy", "alec"],
        alexandra: ["alex", "sandy", "alla", "sandra"],
        alexandria: ["drina", "alexander", "alla", "sandra", "alex"],
        alexis: ["lexi", "alex"],
        alfonse: ["al"],
        alfred: ["freddy", "al", "fred"],
        alfreda: ["freddy", "alfy", "freda", "frieda"],
        algernon: ["algy"],
        alice: ["lisa", "elsie", "allie"],
        alicia: ["lisa", "elsie", "allie"],
        aline: ["adeline"],
        alison: ["ali", "allie"],
        alixandra: ["alix"],
        allan: ["al", "alan", "allen"],
        allen: ["al", "allan", "alan"],
        allisandra: ["ali", "ally", "allie"],
        allison: ["ali", "ally", "allie"],
        allyson: ["ali", "ally", "allie"],
        allyssa: ["ali", "ally", "allie"],
        almena: ["mena", "ali", "ally", "allie"],
        almina: ["minnie"],
        almira: ["myra"],
        alonzo: ["lon", "al", "lonzo"],
        alphinias: ["alphus"],
        althea: ["ally"],
        alverta: ["virdie", "vert"],
        alyssa: ["lissia", "al", "ally"],
        alzada: ["zada"],
        amanda: ["mandy", "manda"],
        ambrose: ["brose"],
        amelia: ["amy", "mel", "millie", "emily"],
        amos: ["moses"],
        anastasia: ["ana", "stacy"],
        anderson: ["andy"],
        andre: ["drea"],
        andrea: ["drea", "rea", "andrew", "andi", "andy"],
        andrew: ["andy", "drew"],
        andriane: ["ada", "adri", "rienne"],
        angela: ["angel", "angie"],
        angelica: ["angie", "angel", "angelika", "angelique"],
        angelina: ["angel", "angie", "lina"],
        ann: ["annie", "nan"],
        anna: ["anne", "ann", "annie", "nan"],
        anne: ["annie", "ann", "nan"],
        annette: ["anna", "nettie"],
        annie: ["ann", "anna"],
        anselm: ["ansel", "selma", "anse", "ance"],
        anthony: ["ant", "tony"],
        antoinette: ["tony", "netta", "ann"],
        antonia: ["tony", "netta", "ann"],
        antonio: ["ant", "tony"],
        appoline: ["appy", "appie"],
        aquilla: ["quil", "quillie"],
        ara: ["belle", "arry"],
        arabella: ["ara", "bella", "arry", "belle"],
        arabelle: ["ara", "bella", "arry", "belle"],
        araminta: ["armida", "middie", "ruminta", "minty"],
        archibald: ["archie"],
        archilles: ["kill", "killis"],
        ariadne: ["arie", "ari"],
        arielle: ["arie"],
        aristotle: ["telly"],
        arizona: ["onie", "ona"],
        arlene: ["arly", "lena"],
        armanda: ["mandy"],
        armena: ["mena", "arry"],
        armilda: ["milly"],
        arminda: ["mindie"],
        arminta: ["minite", "minnie"],
        arnold: ["arnie"],
        aron: ["erin", "ronnie", "ron"],
        artelepsa: ["epsey"],
        artemus: ["art"],
        arthur: ["art"],
        arthusa: ["thursa"],
        arzada: ["zaddi"],
        asahel: ["asa"],
        asaph: ["asa"],
        asenath: ["sene", "assene", "natty"],
        ashley: ["ash", "leah", "lee", "ashly"],
        aubrey: ["bree"],
        audrey: ["dee", "audree"],
        august: ["gus"],
        augusta: ["tina", "aggy", "gatsy", "gussie"],
        augustina: ["tina", "aggy", "gatsy", "gussie"],
        augustine: ["gus", "austin", "august"],
        augustus: ["gus", "austin", "august"],
        aurelia: ["ree", "rilly", "orilla", "aurilla", "ora"],
        avarilla: ["rilla"],
        azariah: ["riah", "aze"],
        bab: ["barby"],
        babs: ["barby", "barbara", "bab"],
        barbara: ["barby", "babs", "bab", "bobbie", "barbie"],
        barbery: ["barbara"],
        barbie: ["barbara"],
        barnabas: ["barney"],
        barney: ["barnabas"],
        bart: ["bartholomew"],
        bartholomew: ["bartel", "bat", "meus", "bart", "mees"],
        barticus: ["bart"],
        bazaleel: ["basil"],
        bea: ["beatrice"],
        beatrice: ["bea", "trisha", "trixie", "trix"],
        becca: ["beck"],
        beck: ["becky"],
        bedelia: ["delia", "bridgit"],
        belinda: ["belle", "linda"],
        bella: ["belle", "arabella", "isabella"],
        benedict: ["bennie", "ben"],
        benjamin: ["benjy", "jamie", "bennie", "ben", "benny"],
        benjy: ["benjamin"],
        bernard: ["barney", "bernie", "berney", "berny"],
        berney: ["bernie"],
        bert: ["bertie", "bob", "bobby"],
        bertha: ["bert", "birdie", "bertie"],
        bertram: ["bert"],
        bess: ["bessie"],
        beth: ["betsy", "betty", "elizabeth"],
        bethena: ["beth", "thaney"],
        beverly: ["bev"],
        bezaleel: ["zeely"],
        biddie: ["biddy"],
        bill: ["william", "billy", "robert", "willie", "fred"],
        billy: ["william", "robert", "fred"],
        blanche: ["bea"],
        bob: ["rob", "robert"],
        bobby: ["rob", "bob"],
        boetius: ["bo"],
        brad: ["bradford", "ford"],
        bradford: ["ford", "brad"],
        bradley: ["brad"],
        brady: ["brody"],
        breanna: ["bree", "bri"],
        breeanna: ["bree"],
        brenda: ["brandy"],
        brian: ["bryan", "bryant"],
        brianna: ["bri"],
        bridget: ["bridie", "biddy", "bridgie", "biddie"],
        brittany: ["britt", "brittnie"],
        brittney: ["britt", "brittnie"],
        broderick: ["ricky", "brody", "brady", "rick", "rod"],
        bryanna: ["brianna", "bri", "briana", "ana", "anna"],
        caitlin: ["cait", "caity"],
        caitlyn: ["cait", "caity"],
        caldonia: ["calliedona"],
        caleb: ["cal"],
        california: ["callie"],
        calista: ["kissy"],
        calpurnia: ["cally"],
        calvin: ["vin", "vinny", "cal"],
        cameron: ["ron", "cam", "ronny"],
        camile: ["cammie"],
        camille: ["millie", "cammie"],
        campbell: ["cam"],
        candace: ["candy", "dacey"],
        carla: ["karla", "carly"],
        carlotta: ["lottie"],
        carlton: ["carl"],
        carmellia: ["mellia"],
        carmelo: ["melo"],
        carmon: ["charm", "cammie", "carm"],
        carol: ["lynn", "carrie", "carolann", "cassie", "caroline", "carole", "carri", "kari", "kara"],
        carolann: ["carol", "carole"],
        caroline: ["lynn", "carol", "carrie", "cassie", "carole"],
        carolyn: ["lynn", "carrie", "cassie"],
        carrie: ["cassie"],
        carthaette: ["etta", "etty"],
        casey: ["k.c."],
        casper: ["jasper"],
        cassandra: ["sandy", "cassie", "sandra"],
        cassidy: ["cassie", "cass"],
        caswell: ["cass"],
        catherine: ["kathy", "katy", "lena", "kittie", "kit", "trina", "cathy", "kay", "cassie", "casey"],
        cathleen: ["kathy", "katy", "lena", "kittie", "kit", "trina", "cathy", "kay", "cassie", "casey"],
        cathy: ["kathy", "cathleen", "catherine"],
        cecilia: ["cissy", "celia"],
        cedric: ["ced", "rick", "ricky"],
        celeste: ["lessie", "celia"],
        celinda: ["linda", "lynn", "lindy"],
        charity: ["chat"],
        charles: ["charlie", "chuck", "carl", "chick"],
        charlie: ["charles", "chuck"],
        charlotte: ["char", "sherry", "lottie", "lotta"],
        chauncey: ["chan"],
        chelsey: ["chelsie"],
        cheryl: ["cher"],
        chesley: ["chet"],
        chester: ["chet"],
        chet: ["chester"],
        chick: ["charlotte", "caroline", "chuck"],
        chloe: ["clo"],
        chris: ["kris"],
        christa: ["chris"],
        christian: ["chris", "kit"],
        christiana: ["kris", "kristy", "ann", "tina", "christy", "chris", "crissy"],
        christiano: ["chris"],
        christina: ["kris", "kristy", "tina", "christy", "chris", "crissy", "chrissy"],
        christine: ["kris", "kristy", "chrissy", "tina", "chris", "crissy", "christy"],
        christoph: ["chris"],
        christopher: ["chris", "kit"],
        christy: ["crissy"],
        cicely: ["cilla"],
        cinderella: ["arilla", "rella", "cindy", "rilla"],
        cindy: ["cinderella"],
        claire: ["clair", "clare", "clara"],
        clara: ["clarissa"],
        clare: ["clara"],
        clarence: ["clare", "clair"],
        clarinda: ["clara"],
        clarissa: ["cissy", "clara"],
        claudia: ["claud"],
        cleatus: ["cleat"],
        clement: ["clem"],
        clementine: ["clement", "clem"],
        cliff: ["clifford"],
        clifford: ["ford", "cliff"],
        clifton: ["tony", "cliff"],
        cole: ["colie"],
        columbus: ["clum"],
        con: ["conny"],
        conrad: ["conny", "con"],
        constance: ["connie"],
        cordelia: ["cordy", "delia"],
        corey: ["coco", "cordy", "ree"],
        corinne: ["cora", "ora"],
        cornelia: ["nelly", "cornie", "nelia", "corny", "nelle"],
        cornelius: ["conny", "niel", "corny", "con", "neil"],
        cory: ["coco", "cordy", "ree"],
        courtney: ["curt", "court"],
        crystal: ["chris", "tal", "stal", "crys"],
        curtis: ["curt"],
        cynthia: ["cintha", "cindy"],
        cyrenius: ["swene", "cy", "serene", "renius", "cene"],
        cyrus: ["cy"],
        dahl: ["dal"],
        dalton: ["dahl", "dal"],
        daniel: ["dan", "danny", "dann"],
        danielle: ["ellie", "dani"],
        danny: ["daniel"],
        daphne: ["daph", "daphie"],
        darlene: ["lena", "darry"],
        david: ["dave", "day", "davey"],
        daycia: ["daisha", "dacia"],
        deanne: ["ann", "dee"],
        debbie: ["deb", "debra", "deborah", "debby"],
        debby: ["deb"],
        debora: ["deb", "debbie", "debby"],
        deborah: ["deb", "debbie", "debby"],
        debra: ["deb", "debbie"],
        deidre: ["deedee"],
        delbert: ["bert", "del"],
        delia: ["fidelia", "cordelia", "delius"],
        delilah: ["lil", "lila", "dell", "della"],
        deliverance: ["delly", "dilly", "della"],
        della: ["adela", "delilah", "adelaide", "dell"],
        delores: ["lolly", "lola", "della", "dee", "dell"],
        delpha: ["philadelphia"],
        delphine: ["delphi", "del", "delf"],
        demaris: ["dea", "maris", "mary"],
        demerias: ["dea", "maris", "mary"],
        democrates: ["mock"],
        dennis: ["denny", "dennie"],
        dennison: ["denny", "dennis"],
        derek: ["derrek", "rick", "ricky"],
        derick: ["rick", "ricky"],
        derrick: ["ricky", "eric", "rick"],
        deuteronomy: ["duty"],
        diana: ["dicey", "didi", "di"],
        diane: ["dicey", "didi", "di", "dianne", "dian"],
        dicey: ["dicie"],
        dick: ["rick", "richard"],
        dickson: ["dick"],
        domenic: ["dom", "nic"],
        dominic: ["dom", "nic"],
        dominick: ["dom", "nick", "nicky"],
        dominico: ["dom"],
        donald: ["dony", "donnie", "don", "donny"],
        donato: ["don"],
        donna: ["dona"],
        donovan: ["dony", "donnie", "don", "donny"],
        dorcus: ["darkey"],
        dorinda: ["dorothea", "dora"],
        doris: ["dora"],
        dorothea: ["doda", "dora"],
        dorothy: ["dortha", "dolly", "dot", "dotty", "dora", "dottie"],
        dotha: ["dotty"],
        dotty: ["dot"],
        douglas: ["doug"],
        drusilla: ["silla"],
        duncan: ["dunk"],
        earnest: ["ernestine", "ernie"],
        ebbie: ["eb"],
        ebenezer: ["ebbie", "eben", "eb"],
        eddie: ["ed"],
        eddy: ["ed"],
        edgar: ["ed", "eddie", "eddy"],
        edith: ["edie", "edye"],
        edmond: ["ed", "eddie", "eddy"],
        edmund: ["ed", "eddie", "ted", "eddy", "ned"],
        edna: ["edny"],
        eduardo: ["ed", "eddie", "eddy"],
        edward: ["teddy", "ed", "ned", "ted", "eddy", "eddie"],
        edwin: ["ed", "eddie", "win", "eddy", "ned"],
        edwina: ["edwin"],
        edyth: ["edie", "edye"],
        edythe: ["edie", "edye"],
        egbert: ["bert", "burt"],
        eighta: ["athy"],
        eileen: ["helen"],
        elaine: ["lainie", "helen"],
        elbert: ["albert", "bert"],
        elbertson: ["elbert", "bert"],
        eldora: ["dora"],
        eleanor: ["lanna", "nora", "nelly", "ellie", "elaine", "ellen", "lenora"],
        eleazer: ["lazar"],
        elena: ["helen"],
        elias: ["eli", "lee", "lias"],
        elijah: ["lige", "eli"],
        eliphalel: ["life"],
        eliphalet: ["left"],
        elisa: ["lisa"],
        elisha: ["lish", "eli"],
        eliza: ["elizabeth"],
        elizabeth: ["libby", "lisa", "lib", "lizzy", "lizzie", "eliza", "betsy", "liza", "betty", "bessie", "bess", "beth", "liz"],
        ella: ["ellen", "el"],
        ellen: ["nellie", "nell", "helen"],
        ellender: ["nellie", "ellen", "helen"],
        ellie: ["elly"],
        ellswood: ["elsey"],
        elminie: ["minnie"],
        elmira: ["ellie", "elly", "mira"],
        elnora: ["nora"],
        eloise: ["heloise", "louise"],
        elouise: ["louise"],
        elsie: ["elsey"],
        elswood: ["elsey"],
        elvira: ["elvie"],
        elwood: ["woody"],
        elysia: ["lisa", "lissa"],
        elze: ["elsey"],
        emanuel: ["manuel", "manny"],
        emeline: ["em", "emmy", "emma", "milly", "emily"],
        emil: ["emily", "em"],
        emily: ["emmy", "millie", "emma", "mel", "em"],
        emma: ["emmy", "em"],
        epaphroditius: ["dite", "ditus", "eppa", "dyche", "dyce"],
        ephraim: ["eph"],
        erasmus: ["raze", "rasmus"],
        eric: ["rick", "ricky"],
        ernest: ["ernie"],
        ernestine: ["teeny", "ernest", "tina", "erna"],
        erwin: ["irwin"],
        eseneth: ["senie"],
        essy: ["es"],
        estella: ["essy", "stella"],
        estelle: ["essy", "stella"],
        esther: ["hester", "essie"],
        eudicy: ["dicey"],
        eudora: ["dora"],
        eudoris: ["dossie", "dosie"],
        eugene: ["gene"],
        eunice: ["nicie"],
        euphemia: ["effie", "effy"],
        eurydice: ["dicey"],
        eustacia: ["stacia", "stacy"],
        eva: ["eve"],
        evaline: ["eva", "lena", "eve"],
        evangeline: ["ev", "evan", "vangie"],
        evelyn: ["evelina", "ev", "eve"],
        experience: ["exie"],
        ezekiel: ["zeke", "ez"],
        ezideen: ["ez"],
        ezra: ["ez"],
        faith: ["fay"],
        fallon: ["falon", "fal", "fall", "fallie", "fally", "falcon", "lon", "lonnie"],
        felicia: ["fel", "felix", "feli"],
        felicity: ["flick", "tick"],
        feltie: ["felty"],
        ferdinand: ["freddie", "freddy", "ferdie", "fred"],
        ferdinando: ["nando", "ferdie", "fred"],
        fidelia: ["delia"],
        fionna: ["fiona"],
        flora: ["florence"],
        florence: ["flossy", "flora", "flo"],
        floyd: ["lloyd"],
        fran: ["frannie"],
        frances: ["sis", "cissy", "frankie", "franniey", "fran", "francie", "frannie", "fanny", "franny"],
        francie: ["francine"],
        francine: ["franniey", "fran", "frannie", "francie", "franny"],
        francis: ["fran", "frankie", "frank"],
        frankie: ["frank", "francis"],
        franklin: ["fran", "frank"],
        franklind: ["fran", "frank"],
        freda: ["frieda"],
        frederica: ["frederick", "freddy", "erika", "erica", "rickey"],
        frederick: ["freddie", "freddy", "fritz", "fred", "erick", "ricky", "derick", "rick"],
        fredericka: ["freddy", "ricka", "freda", "frieda", "ericka", "rickey"],
        frieda: ["freddie", "freddy", "fred"],
        gabriel: ["gabe", "gabby"],
        gabriella: ["ella", "gabby"],
        gabrielle: ["ella", "gabby"],
        gareth: ["gary", "gare"],
        garrett: ["gare", "gary", "garry", "rhett", "garratt", "garret", "barrett", "jerry"],
        garrick: ["garri"],
        genevieve: ["jean", "eve", "jenny"],
        geoffrey: ["geoff", "jeff"],
        george: ["georgie"],
        georgiana: ["georgia"],
        georgine: ["george"],
        gerald: ["gerry", "jerry"],
        geraldine: ["gerry", "gerrie", "jerry", "dina", "gerri"],
        gerhardt: ["gay"],
        gertie: ["gertrude", "gert"],
        gertrude: ["gertie", "gert", "trudy"],
        gilbert: ["bert", "gil", "wilber"],
        giovanni: ["gio"],
        glenn: ["glen"],
        gloria: ["glory"],
        governor: ["govie"],
        greenberry: ["green", "berry"],
        greggory: ["gregg"],
        gregory: ["greg"],
        gretchen: ["margaret"],
        griselda: ["grissel"],
        gum: ["monty"],
        gus: ["gussie"],
        gustavus: ["gus", "gussie"],
        gwen: ["wendy"],
        gwendolyn: ["gwen", "wendy"],
        hailey: ["hayley", "haylee"],
        hamilton: ["ham"],
        hannah: ["nan", "nanny", "anna"],
        harold: ["hal", "harry", "hap", "haps"],
        harriet: ["hattie"],
        harrison: ["harry", "hap", "haps"],
        harry: ["harold", "henry", "hap", "haps"],
        haseltine: ["hassie"],
        haylee: ["hayley", "hailey"],
        hayley: ["hailey", "haylee"],
        heather: ["hetty"],
        helen: ["lena", "ella", "ellen", "ellie"],
        helena: ["eileen", "lena", "nell", "nellie", "eleanor", "elaine", "ellen", "aileen"],
        helene: ["lena", "ella", "ellen", "ellie"],
        heloise: ["lois", "eloise", "elouise"],
        henrietta: ["hank", "etta", "etty", "retta", "nettie", "henny"],
        henry: ["hank", "hal", "harry", "hap", "haps"],
        hephsibah: ["hipsie"],
        hepsibah: ["hipsie"],
        herbert: ["bert", "herb"],
        herman: ["harman", "dutch"],
        hermione: ["hermie"],
        hester: ["hessy", "esther", "hetty"],
        hezekiah: ["hy", "hez", "kiah"],
        hillary: ["hilary"],
        hipsbibah: ["hipsie"],
        hiram: ["hy"],
        honora: ["honey", "nora", "norry", "norah"],
        hopkins: ["hopp", "hop"],
        horace: ["horry"],
        hortense: ["harty", "tensey"],
        hosea: ["hosey", "hosie"],
        howard: ["hal", "howie"],
        hubert: ["bert", "hugh", "hub"],
        ian: ["john"],
        ignatius: ["natius", "iggy", "nate", "nace"],
        ignatzio: ["naz", "iggy", "nace"],
        immanuel: ["manuel", "emmanuel"],
        india: ["indie", "indy"],
        inez: ["agnes"],
        iona: ["onnie"],
        irene: ["rena"],
        irvin: ["irving"],
        irving: ["irv"],
        irwin: ["erwin"],
        isaac: ["ike", "zeke"],
        isabel: ["tibbie", "bell", "nib", "belle", "bella", "nibby", "ib", "issy"],
        isabella: ["tibbie", "nib", "belle", "bella", "nibby", "ib", "issy"],
        isabelle: ["tibbie", "nib", "belle", "bella", "nibby", "ib", "issy"],
        isadora: ["issy", "dora"],
        isadore: ["izzy"],
        isaiah: ["zadie", "zay"],
        isidore: ["izzy"],
        iva: ["ivy"],
        ivan: ["john"],
        jackson: ["jack"],
        jacob: ["jaap", "jake", "jay"],
        jacobus: ["jacob"],
        jacqueline: ["jackie", "jack", "jacqui"],
        jahoda: ["hody", "hodie", "hoda"],
        jakob: ["jake"],
        jalen: ["jay", "jaye", "len", "lenny", "lennie", "jaylin", "alen", "al", "haylen", "jaelin", "jaelyn", "jailyn", "jaylyn"],
        james: ["jimmy", "jim", "jamie", "jimmie", "jem"],
        jamey: ["james", "jamie"],
        jamie: ["james"],
        jane: ["janie", "jessie", "jean", "jennie"],
        janet: ["jan", "jessie"],
        janice: ["jan"],
        jannett: ["nettie"],
        jasper: ["jap", "casper"],
        jayme: ["jay"],
        jean: ["jane", "jeannie"],
        jeanette: ["jessie", "jean", "janet", "nettie"],
        jeanne: ["jane", "jeannie"],
        jebadiah: ["jeb"],
        jedediah: ["dyer", "jed", "diah"],
        jedidiah: ["dyer", "jed", "diah"],
        jefferey: ["jeff"],
        jefferson: ["sonny", "jeff"],
        jeffery: ["jeff"],
        jeffrey: ["geoff", "jeff"],
        jehiel: ["hiel"],
        jehu: ["hugh", "gee"],
        jemima: ["mima"],
        jennet: ["jessie", "jenny", "jenn"],
        jennifer: ["jennie", "jenn", "jen", "jenny", "jenni"],
        jeremiah: ["jereme", "jerry"],
        jeremy: ["jezza", "jez"],
        jerita: ["rita"],
        jerry: ["jereme", "geraldine", "gerry", "geri"],
        jessica: ["jessie", "jess"],
        jessie: ["jane", "jess", "janet"],
        jillian: ["jill"],
        jim: ["jimmie"],
        jincy: ["jane"],
        jinsy: ["jane"],
        joan: ["jo", "nonie"],
        joann: ["jo"],
        joanna: ["hannah", "jody", "jo", "joan", "jodi"],
        joanne: ["jo"],
        jody: ["jo"],
        joe: ["joey"],
        johann: ["john"],
        johanna: ["jo"],
        johannah: ["hannah", "jody", "joan", "nonie", "jo"],
        johannes: ["jonathan", "john", "johnny"],
        john: ["jon", "johnny", "jonny", "jonnie", "jack", "jock", "ian"],
        johnathan: ["johnathon", "jonathan", "jonathon", "jon", "jonny", "john", "johny", "jonnie", "nathan"],
        johnathon: ["johnathan", "jonathon", "jonathan", "jon", "jonny", "john", "johny", "jonnie"],
        jon: ["john", "johnny", "jonny", "jonnie"],
        jonathan: ["johnathan", "johnathon", "jonathon", "jon", "jonny", "john", "johny", "jonnie", "nathan"],
        jonathon: ["johnathan", "johnathon", "jonathan", "jon", "jonny", "john", "johny", "jonnie"],
        joseph: ["jody", "jos", "joe", "joey"],
        josephine: ["fina", "jody", "jo", "josey", "joey", "josie"],
        josetta: ["jettie"],
        josey: ["josophine"],
        joshua: ["jos", "josh", "joe"],
        josiah: ["jos"],
        josophine: ["jo", "joey", "josey"],
        joyce: ["joy"],
        juanita: ["nita", "nettie"],
        judah: ["juder", "jude"],
        judith: ["judie", "juda", "judy", "judi", "jude"],
        judson: ["sonny", "jud"],
        judy: ["judith"],
        julia: ["julie", "jill"],
        julian: ["jule"],
        julias: ["jule"],
        julie: ["julia", "jule"],
        june: ["junius"],
        junior: ["junie", "june", "jr"],
        justin: ["justus", "justina", "juston"],
        kaitlin: ["kait", "kaitie"],
        kaitlyn: ["kait", "kaitie"],
        kaitlynn: ["kait", "kaitie"],
        kalli: ["kali", "cali"],
        kameron: ["kam"],
        karla: ["carla", "carly"],
        kasey: ["k.c."],
        katarina: ["catherine", "tina"],
        kate: ["kay"],
        katelin: ["kay", "kate", "kaye"],
        katelyn: ["kay", "kate", "kaye"],
        katherine: ["kathy", "katy", "lena", "kittie", "kaye", "kit", "trina", "cathy", "kay", "kate", "cassie"],
        kathleen: ["kathy", "katy", "lena", "kittie", "kit", "trina", "cathy", "kay", "cassie"],
        kathryn: ["kathy", "katie", "kate"],
        katia: ["kate", "katie"],
        katy: ["kathy", "katie", "kate"],
        kayla: ["kay"],
        kelley: ["kellie", "kelli", "kelly"],
        kendall: ["ken", "kenny"],
        kendra: ["kenj", "kenji", "kay", "kenny"],
        kendrick: ["ken", "kenny"],
        kendrik: ["ken", "kenny"],
        kenneth: ["ken", "kenny", "kendrick"],
        kenny: ["ken", "kenneth"],
        kent: ["ken", "kenny", "kendrick"],
        kerry: ["kerri"],
        kevin: ["kev"],
        keziah: ["kizza", "kizzie"],
        kimberley: ["kim", "kimberly", "kimberli"],
        kimberly: ["kim", "kimberli", "kimberley"],
        kingsley: ["king"],
        kingston: ["king"],
        kit: ["kittie"],
        kris: ["chris"],
        kristel: ["kris"],
        kristen: ["chris"],
        kristin: ["chris"],
        kristine: ["kris", "kristy", "tina", "christy", "chris", "crissy"],
        kristopher: ["chris", "kris"],
        kristy: ["chris"],
        kymberly: ["kym"],
        lafayette: ["laffie", "fate"],
        lamont: ["monty"],
        laodicia: ["dicy", "cenia"],
        larry: ["laurence", "lawrence"],
        latisha: ["tish", "tisha"],
        laurel: ["laurie"],
        lauren: ["ren", "laurie"],
        laurence: ["lorry", "larry", "lon", "lonny", "lorne"],
        laurinda: ["laura", "lawrence"],
        lauryn: ["laurie"],
        laveda: ["veda"],
        laverne: ["vernon", "verna"],
        lavina: ["vina", "viney", "ina"],
        lavinia: ["vina", "viney", "ina"],
        lavonia: ["vina", "vonnie", "wyncha", "viney"],
        lavonne: ["von"],
        lawrence: ["lorry", "larry", "lon", "lonny", "lorne", "lawrie"],
        leanne: ["lea", "annie"],
        lecurgus: ["curg"],
        leilani: ["lani"],
        lemuel: ["lem"],
        lena: ["ellen"],
        lenora: ["nora", "lee"],
        leo: ["leon"],
        leonard: ["lineau", "leo", "leon", "len", "lenny"],
        leonidas: ["lee", "leon"],
        leonora: ["nora", "nell", "nellie"],
        leonore: ["nora", "honor", "elenor"],
        leroy: ["roy", "lee", "l.r."],
        lesley: ["les"],
        leslie: ["les"],
        lester: ["les"],
        letitia: ["tish", "titia", "lettice", "lettie"],
        levi: ["lee"],
        levicy: ["vicy"],
        levone: ["von"],
        lib: ["libby"],
        lidia: ["lyddy"],
        lil: ["lilly", "lily"],
        lillah: ["lil", "lilly", "lily", "lolly"],
        lillian: ["lil", "lilly", "lolly"],
        lilly: ["lily", "lil"],
        lincoln: ["link"],
        linda: ["lindy", "lynn"],
        lindsay: ["lindsey", "lindsie", "lindsy"],
        lindy: ["lynn"],
        lionel: ["leon"],
        lisa: ["liz"],
        littleberry: ["little", "berry", "l.b."],
        lizzie: ["liz"],
        lois: ["lou", "louise"],
        lonzo: ["lon"],
        lorelei: ["lori", "lorrie", "laurie"],
        lorenzo: ["loren"],
        loretta: ["etta", "lorrie", "retta", "lorie"],
        lorraine: ["lorrie", "lorie"],
        lotta: ["lottie"],
        lou: ["louis", "lu"],
        louis: ["lewis", "louise", "louie", "lou"],
        louisa: ["eliza", "lou", "lois"],
        louise: ["eliza", "lou", "lois"],
        louvinia: ["vina", "vonnie", "wyncha", "viney"],
        lucas: ["luke"],
        lucia: ["lucy", "lucius"],
        lucias: ["luke"],
        lucille: ["cille", "lu", "lucy", "lou"],
        lucina: ["sinah"],
        lucinda: ["lu", "lucy", "cindy", "lou"],
        lucretia: ["creasey"],
        lucy: ["lucinda"],
        luella: ["lula", "ella", "lu"],
        luke: ["lucas"],
        lunetta: ["nettie"],
        lurana: ["lura"],
        luther: ["luke"],
        lydia: ["lyddy"],
        lyndon: ["lindy", "lynn"],
        mabel: ["mehitabel", "amabel"],
        mac: ["mc"],
        mack: ["mac", "mc"],
        mackenzie: ["kenzy", "mac", "mack"],
        maddison: ["maddie", "maddi"],
        maddy: ["madelyn", "madeline", "madge"],
        madeline: ["maggie", "lena", "magda", "maddy", "madge", "maddie", "maddi", "madie", "maud"],
        madelyn: ["maddy", "madie"],
        madie: ["madeline", "madelyn"],
        madison: ["mattie", "maddy"],
        maegen: ["meg"],
        magdalena: ["maggie", "lena"],
        magdelina: ["lena", "magda", "madge", "maggie"],
        mahala: ["hallie"],
        makayla: ["kayla"],
        malachi: ["mally"],
        malcolm: ["mac", "mal", "malc"],
        malinda: ["lindy"],
        manda: ["mandy"],
        mandie: ["amanda"],
        mandy: ["amanda"],
        manerva: ["minerva", "nervie", "eve", "nerva"],
        manny: ["manuel"],
        manoah: ["noah"],
        manola: ["nonnie"],
        manuel: ["emanuel", "manny"],
        marcus: ["mark", "marc"],
        margaret: [
          "maggie",
          "meg",
          "peg",
          "midge",
          "margy",
          "margie",
          "madge",
          "peggy",
          "maggy",
          "marge",
          "daisy",
          "margery",
          "gretta",
          "rita"
        ],
        margaretta: ["maggie", "meg", "peg", "midge", "margie", "madge", "peggy", "marge", "daisy", "margery", "gretta", "rita"],
        margarita: [
          "maggie",
          "meg",
          "metta",
          "midge",
          "greta",
          "megan",
          "maisie",
          "madge",
          "marge",
          "daisy",
          "peggie",
          "rita",
          "margo"
        ],
        marge: ["margery", "margaret", "margaretta"],
        margie: ["marjorie"],
        marguerite: ["peggy"],
        mariah: ["mary", "maria"],
        marian: ["marianna", "marion"],
        marie: ["mae", "mary"],
        marietta: [
          "mariah",
          "mercy",
          "polly",
          "may",
          "molly",
          "mitzi",
          "minnie",
          "mollie",
          "mae",
          "maureen",
          "marion",
          "marie",
          "mamie",
          "mary",
          "maria"
        ],
        marilyn: ["mary"],
        marion: ["mary"],
        marissa: ["rissa"],
        marjorie: ["margy", "margie"],
        marni: ["marnie"],
        marsha: ["marcie", "mary", "marcia"],
        martha: ["marty", "mattie", "mat", "patsy", "patty"],
        martin: ["marty"],
        martina: ["tina"],
        martine: ["tine"],
        marv: ["marvin"],
        marvin: ["marv"],
        mary: ["mamie", "molly", "mae", "polly", "mitzi", "marie"],
        masayuki: ["masa"],
        mat: ["mattie"],
        mathew: ["mat", "maty", "matt"],
        mathilda: ["tillie", "patty"],
        matilda: ["tilly", "maud", "matty", "tilla"],
        matthew: ["thys", "matt", "thias", "mattie", "matty"],
        matthews: ["matt", "mattie", "matty"],
        matthias: ["thys", "matt", "thias"],
        maud: ["middy"],
        maureen: ["mary"],
        maurice: ["morey"],
        mavery: ["mave"],
        mavine: ["mave"],
        maximillian: ["max"],
        maxine: ["max"],
        maxwell: ["max"],
        may: ["mae"],
        mckenna: ["ken", "kenna", "meaka"],
        medora: ["dora"],
        megan: ["meg"],
        meghan: ["meg"],
        mehitabel: ["hetty", "mitty", "mabel", "hitty"],
        melanie: ["mellie"],
        melchizedek: ["zadock", "dick"],
        melinda: ["linda", "mel", "lynn", "mindy", "lindy"],
        melissa: ["lisa", "mel", "missy", "milly", "lissa"],
        mellony: ["mellia"],
        melody: ["lodi"],
        melvin: ["mel"],
        melvina: ["vina"],
        mercedes: ["merci", "sadie", "mercy"],
        merv: ["mervin"],
        mervin: ["merv"],
        mervyn: ["merv"],
        micajah: ["cage"],
        michael: ["micky", "mike", "micah", "mick", "mikey", "mickey"],
        micheal: ["mike", "miky", "mikey"],
        michelle: ["mickey", "shelley", "shely", "chelle", "shellie", "shelly"],
        mick: ["micky"],
        miguel: ["miguell", "miguael", "miguaell", "miguail", "miguaill", "miguayl", "miguayll", "michael", "mike", "miggy"],
        mike: ["micky", "mick", "michael"],
        mildred: ["milly"],
        millicent: ["missy", "milly"],
        minerva: ["minnie"],
        minnie: ["wilhelmina"],
        miranda: ["randy", "mandy", "mira"],
        miriam: ["mimi", "mitzi", "mitzie"],
        missy: ["melissa"],
        mitch: ["mitchell"],
        mitchell: ["mitch"],
        mitzi: ["mary", "mittie", "mitty"],
        mitzie: ["mittie", "mitty"],
        monet: ["nettie"],
        monica: ["monna", "monnie"],
        monteleon: ["monte"],
        montesque: ["monty"],
        montgomery: ["monty", "gum"],
        monty: ["lamont"],
        morris: ["morey"],
        mortimer: ["mort"],
        moses: ["amos", "mose", "moss"],
        muriel: ["mur"],
        myrtle: ["myrt", "myrti", "mert"],
        nadine: ["nada", "deedee"],
        nancy: ["ann", "nan", "nanny"],
        naomi: ["omi"],
        napoleon: ["nap", "nappy", "leon"],
        natalie: ["natty", "nettie"],
        natasha: ["tasha", "nat"],
        nathan: ["nate", "nat"],
        nathaniel: ["than", "nathan", "nate", "nat", "natty"],
        nelle: ["nelly"],
        nelson: ["nels"],
        newt: ["newton"],
        newton: ["newt"],
        nicholas: ["nick", "claes", "claas", "nic", "nicky", "nico", "nickie"],
        nicholette: ["nickey", "nikki", "cole", "nicki", "nicky", "nichole", "nicole"],
        nicodemus: ["nick", "nic", "nicky", "nico", "nickie"],
        nicole: ["nole", "nikki", "cole", "nicki", "nicky"],
        nikolas: ["nick", "claes", "nic", "nicky", "nico", "nickie"],
        nikole: ["nikki"],
        nora: ["nonie"],
        norbert: ["bert", "norby"],
        norbusamte: ["norbu"],
        norman: ["norm"],
        nowell: ["noel"],
        obadiah: ["dyer", "obed", "obie", "diah"],
        obediah: ["obie"],
        obedience: ["obed", "beda", "beedy", "biddie"],
        obie: ["obediah"],
        octavia: ["tave", "tavia"],
        odell: ["odo"],
        olive: ["nollie", "livia", "ollie"],
        oliver: ["ollie"],
        olivia: ["nollie", "livia", "ollie"],
        ollie: ["oliver"],
        onicyphorous: ["cyphorus", "osaforus", "syphorous", "one", "cy", "osaforum"],
        orilla: ["rilly", "ora"],
        orlando: ["roland"],
        orphelia: ["phelia"],
        ossy: ["ozzy"],
        oswald: ["ozzy", "waldo", "ossy"],
        otis: ["ode", "ote"],
        pamela: ["pam"],
        pandora: ["dora"],
        parmelia: ["amelia", "milly", "melia"],
        parthenia: ["teeny", "parsuny", "pasoonie", "phenie"],
        patience: ["pat", "patty"],
        patricia: ["tricia", "pat", "patsy", "patty", "patti", "trish", "trisha"],
        patrick: ["pate", "peter", "pat", "patsy", "paddy"],
        patsy: ["patty"],
        patty: ["patricia"],
        paul: ["polly"],
        paula: ["polly", "lina"],
        paulina: ["polly", "lina"],
        pauline: ["polly"],
        peggy: ["peg"],
        pelegrine: ["perry"],
        penelope: ["penny"],
        percival: ["percy"],
        peregrine: ["perry"],
        permelia: ["melly", "milly", "mellie"],
        pernetta: ["nettie"],
        persephone: ["seph", "sephy"],
        peter: ["pete", "pate"],
        petronella: ["nellie"],
        pheney: ["josephine"],
        pheriba: ["pherbia", "ferbie"],
        philadelphia: ["delphia"],
        philander: ["fie"],
        philetus: ["leet", "phil"],
        philinda: ["linda", "lynn", "lindy"],
        philip: ["phil", "pip"],
        philipina: ["phoebe", "penie", "pip"],
        phillip: ["phil", "pip"],
        philly: ["delphia"],
        philomena: ["menaalmena"],
        phoebe: ["fifi"],
        pinckney: ["pink"],
        pleasant: ["ples"],
        pocahontas: ["pokey"],
        posthuma: ["humey"],
        prescott: ["scotty", "scott", "pres"],
        priscilla: ["prissy", "cissy", "cilla"],
        providence: ["provy"],
        prudence: ["prue", "prudy"],
        prudy: ["prudence"],
        rachel: ["shelly", "rachael"],
        rafaela: ["rafa"],
        ramona: ["mona"],
        randolph: ["dolph", "randy"],
        raphael: ["ralph"],
        ray: ["raymond"],
        raymond: ["ray"],
        reba: ["beck", "becca"],
        rebecca: ["beck", "becca", "reba", "becky"],
        reggie: ["reginald", "reg"],
        regina: ["reggie", "gina"],
        reginald: ["reggie", "naldo", "reg", "renny"],
        relief: ["leafa"],
        reuben: ["rube"],
        reynold: ["reginald"],
        rhoda: ["rodie"],
        rhodella: ["della"],
        rhyna: ["rhynie"],
        ricardo: ["rick", "ricky"],
        rich: ["dick", "rick"],
        richard: ["dick", "dickon", "dickie", "dicky", "rick", "rich", "ricky", "richie"],
        rick: ["ricky"],
        ricky: ["dick", "rich"],
        robert: ["hob", "hobkin", "dob", "rob", "bobby", "dobbin", "bob", "bill", "billy", "robby"],
        roberta: ["robbie", "bert", "bobbie", "birdie", "bertie", "roby", "birtie"],
        roberto: ["rob"],
        roderick: ["rod", "erick", "rickie", "roddy"],
        rodger: ["roge", "bobby", "hodge", "rod", "robby", "rupert", "robin"],
        rodney: ["rod"],
        roger: ["roge", "bobby", "hodge", "rod", "robby", "rupert", "robin"],
        roland: ["rollo", "lanny", "orlando", "rolly"],
        ron: ["ronnie", "ronny"],
        ronald: ["naldo", "ron", "ronny", "ronnie"],
        ronny: ["ronald"],
        rosa: ["rose"],
        rosabel: ["belle", "roz", "rosa", "rose"],
        rosabella: ["belle", "roz", "rosa", "rose", "bella"],
        rosaenn: ["ann"],
        rosaenna: ["ann"],
        rosalinda: ["linda", "roz", "rosa", "rose"],
        rosalyn: ["linda", "roz", "rosa", "rose"],
        roscoe: ["ross"],
        rose: ["rosie"],
        roseann: ["rose", "ann", "rosie", "roz"],
        roseanna: ["rose", "ann", "rosie", "roz"],
        roseanne: ["ann"],
        rosemary: ["rosemarie", "marie", "mary", "rose", "rosey"],
        rosina: ["sina"],
        roxane: ["rox", "roxie"],
        roxanna: ["roxie", "rose", "ann"],
        roxanne: ["roxie", "rose", "ann"],
        rudolph: ["dolph", "rudy", "olph", "rolf"],
        rudolphus: ["dolph", "rudy", "olph", "rolf"],
        russell: ["russ", "rusty"],
        ryan: ["ry"],
        sabrina: ["brina"],
        safieel: ["safie"],
        salome: ["loomie"],
        salvador: ["sal", "sally"],
        sam: ["sammy"],
        samantha: ["sam", "sammy", "mantha"],
        sampson: ["sam", "sammy"],
        samson: ["sam", "sammy"],
        samuel: ["sam", "sammy"],
        samyra: ["sam", "sammy", "myra"],
        sandra: ["sandy", "cassandra"],
        sandy: ["sandra"],
        sanford: ["sandy"],
        sarah: ["sally", "sadie", "sara"],
        sarilla: ["silla"],
        savannah: ["vannie", "anna", "savanna"],
        scott: ["scotty", "sceeter", "squat", "scottie"],
        sebastian: ["sebby", "seb"],
        selma: ["anselm"],
        serena: ["rena"],
        serilla: ["rilla"],
        seymour: ["see", "morey"],
        shaina: ["sha", "shay"],
        sharon: ["sha", "shay"],
        shaun: ["shawn"],
        shawn: ["shaun"],
        sheila: ["cecilia"],
        sheldon: ["shelly"],
        shelton: ["tony", "shel", "shelly"],
        sheridan: ["dan", "danny", "sher"],
        sheryl: ["sher", "sheri", "sherry", "sherryl", "sherri", "cheri", "cherie"],
        shirley: ["sherry", "lee", "shirl"],
        sibbilla: ["sybill", "sibbie", "sibbell"],
        sidney: ["syd", "sid"],
        sigfired: ["sid"],
        sigfrid: ["sid"],
        sigismund: ["sig"],
        silas: ["si"],
        silence: ["liley"],
        silvester: ["vester", "si", "sly", "vest", "syl"],
        simeon: ["si", "sion"],
        simon: ["si", "sion"],
        smith: ["smitty"],
        socrates: ["crate"],
        solomon: ["sal", "salmon", "sol", "solly", "saul", "zolly"],
        sondra: ["dre", "sonnie"],
        sophia: ["sophie"],
        sophronia: ["frona", "sophia", "fronia"],
        stacey: ["stacy", "staci", "stacie"],
        stacie: ["stacy", "stacey", "staci"],
        stacy: ["staci"],
        stephan: ["steve"],
        stephanie: ["stephie", "annie", "steph", "stevie", "stephine", "stephany", "stephani", "steffi", "steffie"],
        stephen: ["steve", "steph"],
        steven: ["steve", "steph", "stevie"],
        stuart: ["stu"],
        sue: ["susie", "susan"],
        sullivan: ["sully", "van"],
        susan: ["hannah", "susie", "sue", "sukey", "suzie"],
        susannah: ["hannah", "susie", "sue", "sukey"],
        susie: ["suzie"],
        suzanne: ["suki", "sue", "susie"],
        sybill: ["sibbie"],
        sydney: ["sid"],
        sylvanus: ["sly", "syl"],
        sylvester: ["sy", "sly", "vet", "syl", "vester", "si", "vessie"],
        tabby: ["tabitha"],
        tabitha: ["tabby"],
        tamarra: ["tammy"],
        tammie: ["tammy", "tami"],
        tammy: ["tammie", "tami"],
        tanafra: ["tanny"],
        tasha: ["tash", "tashie"],
        ted: ["teddy"],
        temperance: ["tempy"],
        terence: ["terry"],
        teresa: ["terry", "tess", "tessa", "tessie"],
        terri: ["terrie", "terry", "teri"],
        terry: ["terence"],
        tess: ["teresa", "theresa"],
        tessa: ["teresa", "theresa"],
        thad: ["thaddeus"],
        thaddeus: ["thad"],
        theo: ["theodore"],
        theodora: ["dora"],
        theodore: ["theo", "ted", "teddy"],
        theodosia: ["theo", "dosia", "theodosius"],
        theophilus: ["ophi"],
        theotha: ["otha"],
        theresa: ["tessie", "thirza", "tessa", "terry", "tracy", "tess", "thursa", "traci", "tracie"],
        thom: ["thomas", "tommy", "tom"],
        thomas: ["thom", "tommy", "tom"],
        thomasa: ["tamzine"],
        tiffany: ["tiff", "tiffy"],
        tilford: ["tillie"],
        tim: ["timmy"],
        timothy: ["tim", "timmy"],
        tina: ["christina"],
        tisha: ["tish"],
        tobias: ["bias", "toby"],
        tom: ["thomas", "tommy"],
        tony: ["anthony"],
        tranquilla: ["trannie", "quilla"],
        trish: ["trisha", "patricia"],
        trix: ["trixie"],
        trudy: ["gertrude"],
        tryphena: ["phena"],
        unice: ["eunice", "nicie"],
        uriah: ["riah"],
        ursula: ["sulie", "sula"],
        valentina: ["felty", "vallie", "val"],
        valentine: ["felty"],
        valeri: ["valerie", "val"],
        valerie: ["val"],
        vanburen: ["buren"],
        vandalia: ["vannie"],
        vanessa: ["essa", "vanna", "nessa"],
        vernisee: ["nicey"],
        veronica: ["vonnie", "ron", "ronna", "ronie", "frony", "franky", "ronnie", "ronny"],
        vic: ["vicki", "vickie", "vicky", "victor"],
        vicki: ["vickie", "vicky", "victoria"],
        victor: ["vic"],
        victoria: ["torie", "vic", "vicki", "tory", "vicky", "tori", "torri", "torrie", "vickie"],
        vijay: ["vij"],
        vincent: ["vic", "vince", "vinnie", "vin", "vinny"],
        vincenzo: ["vic", "vinnie", "vin", "vinny", "vince"],
        vinson: ["vinny", "vinnie", "vin", "vince"],
        viola: ["ola", "vi"],
        violetta: ["lettie"],
        virginia: ["jane", "jennie", "ginny", "virgy", "ginger"],
        vivian: ["vi", "viv"],
        waldo: ["ozzy", "ossy"],
        wallace: ["wally"],
        wally: ["walt"],
        walter: ["wally", "walt"],
        washington: ["wash"],
        webster: ["webb"],
        wendy: ["wen"],
        wesley: ["wes"],
        westley: ["west", "wes", "farmboy"],
        wilber: ["will", "bert"],
        wilbur: ["willy", "willie", "will"],
        wilda: ["willie"],
        wilfred: ["will", "willie", "fred", "wil"],
        wilhelm: ["wil", "willie"],
        wilhelmina: ["mina", "wilma", "willie", "minnie"],
        will: ["bill", "willie", "wilbur", "fred"],
        william: ["willy", "bell", "bela", "bill", "will", "billy", "willie", "wil"],
        willie: ["william", "fred"],
        willis: ["willy", "bill"],
        wilma: ["william", "billiewilhelm"],
        wilson: ["will", "willy", "willie"],
        winfield: ["field", "winny", "win"],
        winifred: ["freddie", "winnie", "winnet"],
        winnie: ["winnifred"],
        winnifred: ["freddie", "freddy", "winny", "winnie", "fred"],
        winny: ["winnifred"],
        winton: ["wint"],
        woodrow: ["woody", "wood", "drew"],
        yeona: ["onie", "ona"],
        yoshihiko: ["yoshi"],
        yulan: ["lan", "yul"],
        yvonne: ["vonna"],
        zach: ["zack", "zak"],
        zachariah: ["zachy", "zach", "zeke", "zac", "zack", "zak", "zakk"],
        zachary: ["zachy", "zach", "zeke", "zac", "zack", "zak", "zakk"],
        zachery: ["zachy", "zach", "zeke", "zac", "zack", "zak", "zakk"],
        zack: ["zach", "zak"],
        zebedee: ["zeb"],
        zedediah: ["dyer", "zed", "diah"],
        zephaniah: ["zeph"]
      };
      return this._memo;
    }
  };
  var states = {
    AL: "Alabama",
    AK: "Alaska",
    AZ: "Arizona",
    AR: "Arkansas",
    CA: "California",
    CO: "Colorado",
    CT: "Connecticut",
    DC: "District of Columbia",
    DE: "Delaware",
    FL: "Florida",
    GA: "Georgia",
    HI: "Hawaii",
    ID: "Idaho",
    IL: "Illinois",
    IN: "Indiana",
    IA: "Iowa",
    KS: "Kansas",
    KY: "Kentucky",
    LA: "Louisiana",
    ME: "Maine",
    MD: "Maryland",
    MA: "Massachusetts",
    MI: "Michigan",
    MN: "Minnesota",
    MS: "Mississippi",
    MO: "Missouri",
    MT: "Montana",
    NE: "Nebraska",
    NV: "Nevada",
    NH: "New Hampshire",
    NJ: "New Jersey",
    NM: "New Mexico",
    NY: "New York",
    NC: "North Carolina",
    ND: "North Dakota",
    OH: "Ohio",
    OK: "Oklahoma",
    OR: "Oregon",
    PA: "Pennsylvania",
    RI: "Rhode Island",
    SC: "South Carolina",
    SD: "South Dakota",
    TN: "Tennessee",
    TX: "Texas",
    UT: "Utah",
    VT: "Vermont",
    VA: "Virginia",
    WA: "Washington",
    WV: "West Virginia",
    WI: "Wisconsin",
    WY: "Wyoming"
  };

  // src/features/broker-protection/comparisons/is-same-name.js
  function isSameName(fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix) {
    if (!fullNameExtracted) {
      return false;
    }
    if (!userFirstName || !userLastName) return false;
    fullNameExtracted = fullNameExtracted.toLowerCase().trim().replace(".", "");
    userFirstName = userFirstName.toLowerCase();
    userMiddleName = userMiddleName ? userMiddleName.toLowerCase() : null;
    userLastName = userLastName.toLowerCase();
    userSuffix = userSuffix ? userSuffix.toLowerCase() : null;
    const names2 = getNames(userFirstName);
    for (const firstName of names2) {
      const nameCombo1 = `${firstName} ${userLastName}`;
      if (fullNameExtracted === nameCombo1) {
        return true;
      }
      if (!userMiddleName) {
        const combinedLength = firstName.length + userLastName.length;
        const matchesFirstAndLast = fullNameExtracted.startsWith(firstName) && fullNameExtracted.endsWith(userLastName) && fullNameExtracted.length > combinedLength;
        if (matchesFirstAndLast) {
          return true;
        }
      }
      if (userSuffix) {
        const nameCombo1WithSuffix = `${firstName} ${userLastName} ${userSuffix}`;
        if (fullNameExtracted === nameCombo1WithSuffix) {
          return true;
        }
      }
      if (userLastName && userLastName.includes("-")) {
        const userLastNameOption2 = userLastName.split("-").join(" ");
        const userLastNameOption3 = userLastName.split("-").join("");
        const userLastNameOption4 = userLastName.split("-")[0];
        const comparisons = [
          `${firstName} ${userLastNameOption2}`,
          `${firstName} ${userLastNameOption3}`,
          `${firstName} ${userLastNameOption4}`
        ];
        if (comparisons.includes(fullNameExtracted)) {
          return true;
        }
      }
      if (userFirstName && userFirstName.includes("-")) {
        const userFirstNameOption2 = userFirstName.split("-").join(" ");
        const userFirstNameOption3 = userFirstName.split("-").join("");
        const userFirstNameOption4 = userFirstName.split("-")[0];
        const comparisons = [
          `${userFirstNameOption2} ${userLastName}`,
          `${userFirstNameOption3} ${userLastName}`,
          `${userFirstNameOption4} ${userLastName}`
        ];
        if (comparisons.includes(fullNameExtracted)) {
          return true;
        }
      }
      if (userMiddleName) {
        const comparisons = [
          `${firstName} ${userMiddleName} ${userLastName}`,
          `${firstName} ${userMiddleName} ${userLastName} ${userSuffix}`,
          `${firstName} ${userMiddleName[0]} ${userLastName}`,
          `${firstName} ${userMiddleName[0]} ${userLastName} ${userSuffix}`,
          `${firstName} ${userMiddleName}${userLastName}`,
          `${firstName} ${userMiddleName}${userLastName} ${userSuffix}`
        ];
        if (comparisons.includes(fullNameExtracted)) {
          return true;
        }
        if (userLastName && userLastName.includes("-")) {
          const userLastNameOption2 = userLastName.split("-").join(" ");
          const userLastNameOption3 = userLastName.split("-").join("");
          const userLastNameOption4 = userLastName.split("-")[0];
          const comparisons2 = [
            `${firstName} ${userMiddleName} ${userLastNameOption2}`,
            `${firstName} ${userMiddleName} ${userLastNameOption4}`,
            `${firstName} ${userMiddleName[0]} ${userLastNameOption2}`,
            `${firstName} ${userMiddleName[0]} ${userLastNameOption3}`,
            `${firstName} ${userMiddleName[0]} ${userLastNameOption4}`
          ];
          if (comparisons2.includes(fullNameExtracted)) {
            return true;
          }
        }
        if (userFirstName && userFirstName.includes("-")) {
          const userFirstNameOption2 = userFirstName.split("-").join(" ");
          const userFirstNameOption3 = userFirstName.split("-").join("");
          const userFirstNameOption4 = userFirstName.split("-")[0];
          const comparisons2 = [
            `${userFirstNameOption2} ${userMiddleName} ${userLastName}`,
            `${userFirstNameOption3} ${userMiddleName} ${userLastName}`,
            `${userFirstNameOption4} ${userMiddleName} ${userLastName}`,
            `${userFirstNameOption2} ${userMiddleName[0]} ${userLastName}`,
            `${userFirstNameOption3} ${userMiddleName[0]} ${userLastName}`,
            `${userFirstNameOption4} ${userMiddleName[0]} ${userLastName}`
          ];
          if (comparisons2.includes(fullNameExtracted)) {
            return true;
          }
        }
      }
    }
    return false;
  }
  function getNames(name) {
    if (!noneEmptyString(name)) {
      return /* @__PURE__ */ new Set();
    }
    name = name.toLowerCase();
    const nicknames = names.nicknames;
    return /* @__PURE__ */ new Set([name, ...getNicknames(name, nicknames), ...getFullNames(name, nicknames)]);
  }
  function getNicknames(name, nicknames) {
    const emptySet = /* @__PURE__ */ new Set();
    if (!noneEmptyString(name)) {
      return emptySet;
    }
    name = name.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(nicknames, name)) {
      return new Set(nicknames[name]);
    }
    return emptySet;
  }
  function getFullNames(name, nicknames) {
    const fullNames = /* @__PURE__ */ new Set();
    if (!noneEmptyString(name)) {
      return fullNames;
    }
    name = name.toLowerCase();
    for (const fullName of Object.keys(nicknames)) {
      if (nicknames[fullName].includes(name)) {
        fullNames.add(fullName);
      }
    }
    return fullNames;
  }
  function noneEmptyString(input) {
    if (typeof input !== "string") return false;
    return input.trim().length > 0;
  }

  // src/features/broker-protection/comparisons/address.js
  init_define_import_meta_trackerLookup();
  function addressMatch(userAddresses, foundAddresses) {
    return userAddresses.some((user) => {
      return foundAddresses.some((found) => {
        return matchingPair(user.city, found.city) && matchingPair(user.state, found.state);
      });
    });
  }
  function getStateFromAbbreviation(stateAbbreviation) {
    if (stateAbbreviation == null || stateAbbreviation.trim() === "") {
      return null;
    }
    const state = stateAbbreviation.toUpperCase();
    return states[state] || null;
  }

  // src/features/broker-protection/extractors/age.js
  init_define_import_meta_trackerLookup();
  var AgeExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} _extractorParams
     */
    extract(strs, _extractorParams) {
      if (!strs[0]) return null;
      return strs[0].match(/\d+/)?.[0] ?? null;
    }
  };

  // src/features/broker-protection/extractors/name.js
  init_define_import_meta_trackerLookup();
  var NameExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} _extractorParams
     */
    extract(strs, _extractorParams) {
      if (!strs[0]) return null;
      return strs[0].replace(/\n/g, " ").trim();
    }
  };
  var AlternativeNamesExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     * @returns {string[]}
     */
    extract(strs, extractorParams) {
      return strs.map((x2) => stringToList(x2, extractorParams.separator)).flat();
    }
  };

  // src/features/broker-protection/extractors/address.js
  init_define_import_meta_trackerLookup();
  var import_parse_address = __toESM(require_address(), 1);
  var CityStateExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
      const cityStateList = strs.map((str) => stringToList(str, extractorParams.separator)).flat();
      return getCityStateCombos(cityStateList);
    }
  };
  var AddressFullExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
      return strs.map((str) => str.replace("\n", " ")).map((str) => stringToList(str, extractorParams.separator)).flat().map((str) => import_parse_address.default.parseLocation(str) || {}).filter((parsed) => Boolean(parsed?.city)).map((addr) => {
        return { city: addr.city, state: addr.state || null };
      });
    }
  };
  function getCityStateCombos(inputList) {
    const output = [];
    for (let item of inputList) {
      let words;
      item = item.replace(/,?\s*\d{5}(-\d{4})?/, "");
      item = item.replace(/,$/, "");
      if (item.includes(",")) {
        words = item.split(",").map((item2) => item2.trim());
      } else {
        words = item.split(" ").map((item2) => item2.trim());
      }
      if (words.length === 1) {
        continue;
      }
      const state = words.pop();
      const city = words.join(" ");
      if (state && !Object.keys(states).includes(state.toUpperCase())) {
        continue;
      }
      output.push({ city, state: state || null });
    }
    return output;
  }

  // src/features/broker-protection/extractors/phone.js
  init_define_import_meta_trackerLookup();
  var PhoneExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
      return strs.map((str) => stringToList(str, extractorParams.separator)).flat().map((str) => str.replace(/\D/g, ""));
    }
  };

  // src/features/broker-protection/extractors/relatives.js
  init_define_import_meta_trackerLookup();
  var RelativesExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
      return strs.map((x2) => stringToList(x2, extractorParams.separator)).flat().map((x2) => x2.split(",")[0]);
    }
  };

  // src/features/broker-protection/extractors/profile-url.js
  init_define_import_meta_trackerLookup();
  var ProfileUrlExtractor = class {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
      if (strs.length === 0) return null;
      const profile = {
        profileUrl: strs[0],
        identifier: strs[0]
      };
      if (!extractorParams.identifierType || !extractorParams.identifier) {
        return profile;
      }
      const profileUrl = strs[0];
      profile.identifier = this.getIdFromProfileUrl(profileUrl, extractorParams.identifierType, extractorParams.identifier);
      return profile;
    }
    /**
     * Parse a profile id from a profile URL
     * @param {string} profileUrl
     * @param {import('../actions/extract.js').IdentifierType} identifierType
     * @param {string} identifier
     * @return {string}
     */
    getIdFromProfileUrl(profileUrl, identifierType, identifier) {
      const parsedUrl = new URL(profileUrl);
      const urlParams = parsedUrl.searchParams;
      if (identifierType === "param" && urlParams.has(identifier)) {
        const profileId = urlParams.get(identifier);
        return profileId || profileUrl;
      }
      return profileUrl;
    }
  };
  var ProfileHashTransformer = class {
    /**
     * @param {Record<string, any>} profile
     * @param {Record<string, any> } params
     * @return {Promise<Record<string, any>>}
     */
    async transform(profile, params) {
      if (params?.profileUrl?.identifierType !== "hash") {
        return profile;
      }
      return {
        ...profile,
        identifier: await hashObject(profile)
      };
    }
  };

  // src/features/broker-protection/actions/extract.js
  async function extract(action, userData, root = document) {
    const extractResult = extractProfiles(action, userData, root);
    if ("error" in extractResult) {
      return new ErrorResponse({ actionID: action.id, message: extractResult.error });
    }
    const filteredPromises = extractResult.results.filter((x2) => x2.result === true).map((x2) => aggregateFields(x2.scrapedData)).map((profile) => applyPostTransforms(profile, action.profile));
    const filtered = await Promise.all(filteredPromises);
    const debugResults = extractResult.results.map((result) => result.asData());
    return new SuccessResponse({
      actionID: action.id,
      actionType: action.actionType,
      response: filtered,
      meta: {
        userData,
        extractResults: debugResults
      }
    });
  }
  function extractProfiles(action, userData, root = document) {
    const profilesElementList = getElements(root, action.selector) ?? [];
    if (profilesElementList.length === 0) {
      if (!action.noResultsSelector) {
        return { error: "no root elements found for " + action.selector };
      }
      const foundNoResultsElement = getElement(root, action.noResultsSelector);
      if (!foundNoResultsElement) {
        return { error: "no results found for " + action.selector + " or the no results selector " + action.noResultsSelector };
      }
    }
    return {
      results: profilesElementList.map((element) => {
        const elementFactory = (_2, value) => {
          return value?.findElements ? cleanArray(getElements(element, value.selector)) : cleanArray(getElement(element, value.selector) || getElementMatches(element, value.selector));
        };
        const scrapedData = createProfile(elementFactory, action.profile);
        const { result, score, matchedFields } = scrapedDataMatchesUserData(userData, scrapedData);
        return new ProfileResult({
          scrapedData,
          result,
          score,
          element,
          matchedFields
        });
      })
    };
  }
  function createProfile(elementFactory, extractData) {
    const output = {};
    for (const [key, value] of Object.entries(extractData)) {
      if (!value?.selector) {
        output[key] = null;
      } else {
        const elements = elementFactory(key, value);
        const evaluatedValues = stringValuesFromElements(elements, key, value);
        const noneEmptyArray = cleanArray(evaluatedValues);
        const extractedValue = extractValue(key, value, noneEmptyArray);
        output[key] = extractedValue || null;
      }
    }
    return output;
  }
  function stringValuesFromElements(elements, key, extractField) {
    return elements.map((element) => {
      let elementValue;
      if ("innerText" in element) {
        elementValue = rules[key]?.(element) ?? element?.innerText ?? null;
      } else if ("textContent" in element) {
        elementValue = rules[key]?.(element) ?? element?.textContent ?? null;
      }
      if (!elementValue) {
        return elementValue;
      }
      if (extractField?.afterText) {
        elementValue = elementValue?.split(extractField.afterText)[1]?.trim() || elementValue;
      }
      if (extractField?.beforeText) {
        elementValue = elementValue?.split(extractField.beforeText)[0].trim() || elementValue;
      }
      elementValue = removeCommonSuffixesAndPrefixes(elementValue);
      return elementValue;
    });
  }
  function scrapedDataMatchesUserData(userData, scrapedData) {
    const matchedFields = [];
    if (isSameName(scrapedData.name, userData.firstName, userData.middleName, userData.lastName)) {
      matchedFields.push("name");
    } else {
      return { matchedFields, score: matchedFields.length, result: false };
    }
    if (scrapedData.age) {
      if (isSameAge(scrapedData.age, userData.age)) {
        matchedFields.push("age");
      } else {
        return { matchedFields, score: matchedFields.length, result: false };
      }
    }
    const addressFields = ["addressCityState", "addressCityStateList", "addressFull", "addressFullList"];
    for (const addressField of addressFields) {
      if (addressField in scrapedData) {
        if (addressMatch(userData.addresses, scrapedData[addressField])) {
          matchedFields.push(addressField);
          return { matchedFields, score: matchedFields.length, result: true };
        }
      }
    }
    if (scrapedData.phone) {
      if (userData.phone === scrapedData.phone) {
        matchedFields.push("phone");
        return { matchedFields, score: matchedFields.length, result: true };
      }
    }
    return { matchedFields, score: matchedFields.length, result: false };
  }
  function aggregateFields(profile) {
    const combinedAddresses = [
      ...profile.addressCityState || [],
      ...profile.addressCityStateList || [],
      ...profile.addressFullList || [],
      ...profile.addressFull || []
    ];
    const addressMap = new Map(combinedAddresses.map((addr) => [`${addr.city},${addr.state}`, addr]));
    const addresses = sortAddressesByStateAndCity([...addressMap.values()]);
    const phoneArray = profile.phone || [];
    const phoneListArray = profile.phoneList || [];
    const phoneNumbers = [.../* @__PURE__ */ new Set([...phoneArray, ...phoneListArray])].sort((a2, b2) => parseInt(a2) - parseInt(b2));
    const relatives = [...new Set(profile.relativesList)].sort();
    const alternativeNames = [...new Set(profile.alternativeNamesList)].sort();
    return {
      name: profile.name,
      alternativeNames,
      age: profile.age,
      addresses,
      phoneNumbers,
      relatives,
      ...profile.profileUrl
    };
  }
  function extractValue(outputFieldKey, extractorParams, elementValues) {
    switch (outputFieldKey) {
      case "age":
        return new AgeExtractor().extract(elementValues, extractorParams);
      case "name":
        return new NameExtractor().extract(elementValues, extractorParams);
      // all addresses are processed the same way
      case "addressFull":
      case "addressFullList":
        return new AddressFullExtractor().extract(elementValues, extractorParams);
      case "addressCityState":
      case "addressCityStateList":
        return new CityStateExtractor().extract(elementValues, extractorParams);
      case "alternativeNamesList":
        return new AlternativeNamesExtractor().extract(elementValues, extractorParams);
      case "relativesList":
        return new RelativesExtractor().extract(elementValues, extractorParams);
      case "phone":
      case "phoneList":
        return new PhoneExtractor().extract(elementValues, extractorParams);
      case "profileUrl":
        return new ProfileUrlExtractor().extract(elementValues, extractorParams);
    }
    return null;
  }
  async function applyPostTransforms(profile, params) {
    const transforms = [
      // creates a hash if needed
      new ProfileHashTransformer()
    ];
    let output = profile;
    for (const knownTransform of transforms) {
      output = await knownTransform.transform(output, params);
    }
    return output;
  }
  function stringToList(inputList, separator) {
    const defaultSeparator = /[|\n•·]/;
    return cleanArray(inputList.split(separator || defaultSeparator));
  }
  var rules = {
    profileUrl: function(link) {
      return link?.href ?? null;
    }
  };
  function removeCommonSuffixesAndPrefixes(elementValue) {
    const regexes = [
      // match text such as +3 more when it appears at the end of a string
      /\+\s*\d+.*$/
    ];
    const startsWith = [
      "Associated persons:",
      "AKA:",
      "Known as:",
      "Also known as:",
      "Has lived in:",
      "Used to live:",
      "Used to live in:",
      "Lives in:",
      "Related to:",
      "No other aliases.",
      "RESIDES IN"
    ];
    const endsWith = [" -", "years old"];
    for (const regex of regexes) {
      elementValue = elementValue.replace(regex, "").trim();
    }
    for (const prefix of startsWith) {
      if (elementValue.startsWith(prefix)) {
        elementValue = elementValue.slice(prefix.length).trim();
      }
    }
    for (const suffix of endsWith) {
      if (elementValue.endsWith(suffix)) {
        elementValue = elementValue.slice(0, 0 - suffix.length).trim();
      }
    }
    return elementValue;
  }

  // src/features/broker-protection/actions/fill-form.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/actions/generators.js
  init_define_import_meta_trackerLookup();
  function generatePhoneNumber() {
    const areaCode = generateRandomInt(200, 899).toString();
    const exchangeCode = "555";
    const lineNumber = generateRandomInt(100, 199).toString().padStart(4, "0");
    return `${areaCode}${exchangeCode}${lineNumber}`;
  }
  function generateZipCode() {
    const zipCode = generateRandomInt(1e4, 99999).toString();
    return zipCode;
  }
  function generateStreetAddress() {
    const streetDigits = generateRandomInt(1, 5);
    const streetNumber = generateRandomInt(2, streetDigits * 1e3);
    const streetNames = [
      "Main",
      "Elm",
      "Maple",
      "Oak",
      "Pine",
      "Cedar",
      "Hill",
      "Lake",
      "Sunset",
      "Washington",
      "Lincoln",
      "Marshall",
      "Spring",
      "Ridge",
      "Valley",
      "Meadow",
      "Forest"
    ];
    const streetName = streetNames[generateRandomInt(0, streetNames.length - 1)];
    const suffixes = ["", "St", "Ave", "Blvd", "Rd", "Ct", "Dr", "Ln", "Pkwy", "Pl", "Ter", "Way"];
    const suffix = suffixes[generateRandomInt(0, suffixes.length - 1)];
    return `${streetNumber} ${streetName}${suffix ? " " + suffix : ""}`;
  }

  // src/features/broker-protection/actions/fill-form.js
  function fillForm(action, userData, root = document) {
    const form = getElement(root, action.selector);
    if (!form) return new ErrorResponse({ actionID: action.id, message: "missing form" });
    if (!userData) return new ErrorResponse({ actionID: action.id, message: "user data was absent" });
    form.scrollIntoView?.();
    const results = fillMany(form, action.elements, userData);
    const errors = results.filter((x2) => x2.result === false).map((x2) => {
      if ("error" in x2) return x2.error;
      return "unknown error";
    });
    if (errors.length > 0) {
      return new ErrorResponse({ actionID: action.id, message: errors.join(", ") });
    }
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
  }
  function fillMany(root, elements, data2) {
    const results = [];
    for (const element of elements) {
      const inputElem = getElement(root, element.selector);
      if (!inputElem) {
        results.push({ result: false, error: `element not found for selector: "${element.selector}"` });
        continue;
      }
      if (element.type === "$file_id$") {
        results.push(setImageUpload(inputElem));
      } else if (element.type === "$generated_phone_number$") {
        results.push(setValueForInput(inputElem, generatePhoneNumber()));
      } else if (element.type === "$generated_zip_code$") {
        results.push(setValueForInput(inputElem, generateZipCode()));
      } else if (element.type === "$generated_random_number$") {
        if (!element.min || !element.max) {
          results.push({
            result: false,
            error: `element found with selector '${element.selector}', but missing min and/or max values`
          });
          continue;
        }
        const minInt = parseInt(element?.min);
        const maxInt = parseInt(element?.max);
        if (isNaN(minInt) || isNaN(maxInt)) {
          results.push({
            result: false,
            error: `element found with selector '${element.selector}', but min or max was not a number`
          });
          continue;
        }
        results.push(setValueForInput(inputElem, generateRandomInt(parseInt(element.min), parseInt(element.max)).toString()));
      } else if (element.type === "$generated_street_address$") {
        results.push(setValueForInput(inputElem, generateStreetAddress()));
      } else if (element.type === "cityState") {
        if (!Object.prototype.hasOwnProperty.call(data2, "city") || !Object.prototype.hasOwnProperty.call(data2, "state")) {
          results.push({
            result: false,
            error: `element found with selector '${element.selector}', but data didn't contain the keys 'city' and 'state'`
          });
          continue;
        }
        results.push(setValueForInput(inputElem, data2.city + ", " + data2.state));
      } else {
        if (isElementTypeOptional(element.type)) {
          continue;
        }
        if (!Object.prototype.hasOwnProperty.call(data2, element.type)) {
          results.push({
            result: false,
            error: `element found with selector '${element.selector}', but data didn't contain the key '${element.type}'`
          });
          continue;
        }
        if (!data2[element.type]) {
          results.push({
            result: false,
            error: `data contained the key '${element.type}', but it wasn't something we can fill: ${data2[element.type]}`
          });
          continue;
        }
        results.push(setValueForInput(inputElem, data2[element.type]));
      }
    }
    return results;
  }
  function isElementTypeOptional(type) {
    if (type === "middleName") {
      return true;
    }
    return false;
  }
  function setValueForInput(el, val) {
    let target;
    if (el.tagName === "INPUT") target = window.HTMLInputElement;
    if (el.tagName === "SELECT") target = window.HTMLSelectElement;
    if (!target) {
      return { result: false, error: `input type was not supported: ${el.tagName}` };
    }
    const originalSet = Object.getOwnPropertyDescriptor(target.prototype, "value")?.set;
    if (!originalSet || typeof originalSet.call !== "function") {
      return { result: false, error: "cannot access original value setter" };
    }
    try {
      if (el.tagName === "INPUT") {
        el.dispatchEvent(new Event("keydown", { bubbles: true }));
        originalSet.call(el, val);
        const events = [
          new Event("input", { bubbles: true }),
          new Event("keyup", { bubbles: true }),
          new Event("change", { bubbles: true })
        ];
        events.forEach((ev) => el.dispatchEvent(ev));
        originalSet.call(el, val);
        events.forEach((ev) => el.dispatchEvent(ev));
        el.blur();
      } else if (el.tagName === "SELECT") {
        originalSet.call(el, val);
        const events = [
          new Event("mousedown", { bubbles: true }),
          new Event("mouseup", { bubbles: true }),
          new Event("click", { bubbles: true }),
          new Event("change", { bubbles: true })
        ];
        events.forEach((ev) => el.dispatchEvent(ev));
        events.forEach((ev) => el.dispatchEvent(ev));
        el.blur();
      }
      return { result: true };
    } catch (e) {
      return { result: false, error: `setValueForInput exception: ${e}` };
    }
  }
  function setImageUpload(element) {
    const base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/B8AAusB9VF9PmUAAAAASUVORK5CYII=";
    try {
      const binaryString = window.atob(base64PNG);
      const length = binaryString.length;
      const bytes = new Uint8Array(length);
      for (let i = 0; i < length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }
      const blob = new Blob([bytes], { type: "image/png" });
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(new File([blob], "id.png", { type: "image/png" }));
      element.files = dataTransfer.files;
      return { result: true };
    } catch (e) {
      return { result: false, error: e.toString() };
    }
  }

  // src/features/broker-protection/actions/click.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/actions/build-url-transforms.js
  init_define_import_meta_trackerLookup();
  function transformUrl(action, userData) {
    const url = new URL(action.url);
    url.search = processSearchParams(url.searchParams, action, userData).toString();
    url.pathname = processPathname(url.pathname, action, userData);
    return { url: url.toString() };
  }
  var baseTransforms = /* @__PURE__ */ new Map([
    ["firstName", (value) => capitalize(value)],
    ["lastName", (value) => capitalize(value)],
    ["state", (value) => value.toLowerCase()],
    ["city", (value) => capitalize(value)],
    ["age", (value) => value.toString()]
  ]);
  var optionalTransforms = /* @__PURE__ */ new Map([
    ["hyphenated", (value) => value.split(" ").join("-")],
    ["capitalize", (value) => capitalize(value)],
    ["downcase", (value) => value.toLowerCase()],
    ["upcase", (value) => value.toUpperCase()],
    ["snakecase", (value) => value.split(" ").join("_")],
    ["stateFull", (value) => getStateFromAbbreviation(value)],
    ["defaultIfEmpty", (value, argument) => value || argument || ""],
    [
      "ageRange",
      (value, _2, action) => {
        if (!action.ageRange) return value;
        const ageNumber = Number(value);
        const ageRange = action.ageRange.find((range) => {
          const [min, max] = range.split("-");
          return ageNumber >= Number(min) && ageNumber <= Number(max);
        });
        return ageRange || value;
      }
    ]
  ]);
  function processSearchParams(searchParams, action, userData) {
    const updatedPairs = [...searchParams].map(([key, value]) => {
      const processedValue = processTemplateStringWithUserData(value, action, userData);
      return [key, processedValue];
    });
    return new URLSearchParams(updatedPairs);
  }
  function processPathname(pathname, action, userData) {
    return pathname.split("/").filter(Boolean).map((segment) => processTemplateStringWithUserData(segment, action, userData)).join("/");
  }
  function processTemplateStringWithUserData(input, action, userData) {
    return String(input).replace(/\$%7B(.+?)%7D|\$\{(.+?)}/g, (_2, encodedValue, plainValue) => {
      const comparison = encodedValue ?? plainValue;
      const [dataKey, ...transforms] = comparison.split(/\||%7C/);
      const data2 = userData[dataKey];
      return applyTransforms(dataKey, data2, transforms, action);
    });
  }
  function applyTransforms(dataKey, value, transformNames, action) {
    const subject = String(value || "");
    const baseTransform = baseTransforms.get(dataKey);
    let outputString = baseTransform ? baseTransform(subject) : subject;
    for (const transformName of transformNames) {
      const [name, argument] = transformName.split(":");
      const transform = optionalTransforms.get(name);
      if (transform) {
        outputString = transform(outputString, argument, action);
      }
    }
    return outputString;
  }
  function capitalize(s) {
    const words = s.split(" ");
    const capitalizedWords = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1));
    return capitalizedWords.join(" ");
  }

  // src/features/broker-protection/actions/click.js
  function click(action, userData, root = document) {
    let elements = [];
    if (action.choices?.length) {
      const choices = evaluateChoices(action, userData);
      if (choices === null) {
        return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
      } else if ("error" in choices) {
        return new ErrorResponse({ actionID: action.id, message: `Unable to evaluate choices: ${choices.error}` });
      } else if (!("elements" in choices)) {
        return new ErrorResponse({ actionID: action.id, message: "No elements provided to click action" });
      }
      elements = choices.elements;
    } else {
      if (!("elements" in action)) {
        return new ErrorResponse({ actionID: action.id, message: "No elements provided to click action" });
      }
      elements = action.elements;
    }
    if (!elements || !elements.length) {
      return new ErrorResponse({ actionID: action.id, message: "No elements provided to click action" });
    }
    for (const element of elements) {
      let rootElement;
      try {
        rootElement = selectRootElement(element, userData, root);
      } catch (error) {
        return new ErrorResponse({ actionID: action.id, message: `Could not find root element: ${error.message}` });
      }
      const elements2 = getElements(rootElement, element.selector);
      if (!elements2?.length) {
        if (element.failSilently) {
          return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
        }
        return new ErrorResponse({
          actionID: action.id,
          message: `could not find element to click with selector '${element.selector}'!`
        });
      }
      const loopLength = element.multiple && element.multiple === true ? elements2.length : 1;
      for (let i = 0; i < loopLength; i++) {
        const elem = elements2[i];
        if ("disabled" in elem) {
          if (elem.disabled && !element.failSilently) {
            return new ErrorResponse({ actionID: action.id, message: `could not click disabled element ${element.selector}'!` });
          }
        }
        if ("click" in elem && typeof elem.click === "function") {
          elem.click();
        }
      }
    }
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
  }
  function selectRootElement(clickElement, userData, root = document) {
    if (!clickElement.parent) return root;
    if (clickElement.parent.profileMatch) {
      const extraction = extractProfiles(clickElement.parent.profileMatch, userData, root);
      if ("results" in extraction) {
        const sorted = extraction.results.filter((x2) => x2.result === true).sort((a2, b2) => b2.score - a2.score);
        const first = sorted[0];
        if (first && first.element) {
          return first.element;
        }
      }
    }
    throw new Error("`parent` was present on the element, but the configuration is not supported");
  }
  function getComparisonFunction(operator) {
    switch (operator) {
      case "=":
      case "==":
      case "===":
        return (a2, b2) => a2 === b2;
      case "!=":
      case "!==":
        return (a2, b2) => a2 !== b2;
      case "<":
        return (a2, b2) => a2 < b2;
      case "<=":
        return (a2, b2) => a2 <= b2;
      case ">":
        return (a2, b2) => a2 > b2;
      case ">=":
        return (a2, b2) => a2 >= b2;
      default:
        throw new Error(`Invalid operator: ${operator}`);
    }
  }
  function evaluateChoices(action, userData) {
    if ("elements" in action) {
      return { error: "Elements should be nested inside of choices" };
    }
    for (const choice of action.choices) {
      if (!("condition" in choice) || !("elements" in choice)) {
        return { error: "All choices must have a condition and elements" };
      }
      const comparison = runComparison(choice, action, userData);
      if ("error" in comparison) {
        return { error: comparison.error };
      } else if ("result" in comparison && comparison.result === true) {
        return { elements: choice.elements };
      }
    }
    if (!("default" in action)) {
      return { error: "All conditions failed and no default action was provided" };
    }
    if (action.default === null) {
      return null;
    }
    if (!("elements" in action.default)) {
      return { error: "Default action must have elements" };
    }
    return { elements: action.default.elements };
  }
  function runComparison(choice, action, userData) {
    let compare;
    let left;
    let right;
    try {
      compare = getComparisonFunction(choice.condition.operation);
    } catch (error) {
      return { error: `Unable to get comparison function: ${error.message}` };
    }
    try {
      left = processTemplateStringWithUserData(choice.condition.left, action, userData);
      right = processTemplateStringWithUserData(choice.condition.right, action, userData);
    } catch (error) {
      return { error: `Unable to resolve left/right comparison arguments: ${error.message}` };
    }
    let result;
    try {
      result = compare(left, right);
    } catch (error) {
      return { error: `Comparison failed with the following error: ${error.message}` };
    }
    return { result };
  }

  // src/features/broker-protection/actions/expectation.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/utils/expectations.js
  init_define_import_meta_trackerLookup();
  function expectMany(expectations, root) {
    return expectations.map((expectation2) => {
      switch (expectation2.type) {
        case "element":
          return elementExpectation(expectation2, root);
        case "text":
          return textExpectation(expectation2, root);
        case "url":
          return urlExpectation(expectation2);
        default: {
          return {
            result: false,
            error: `unknown expectation type: ${expectation2.type}`
          };
        }
      }
    });
  }
  function elementExpectation(expectation2, root) {
    if (expectation2.parent) {
      const parent = getElement(root, expectation2.parent);
      if (!parent) {
        return {
          result: false,
          error: `parent element not found with selector: ${expectation2.parent}`
        };
      }
      parent.scrollIntoView();
    }
    const elementExists = getElement(root, expectation2.selector) !== null;
    if (!elementExists) {
      return {
        result: false,
        error: `element with selector ${expectation2.selector} not found.`
      };
    }
    return { result: true };
  }
  function textExpectation(expectation2, root) {
    const elem = getElement(root, expectation2.selector);
    if (!elem) {
      return {
        result: false,
        error: `element with selector ${expectation2.selector} not found.`
      };
    }
    if (!expectation2.expect) {
      return {
        result: false,
        error: "missing key: 'expect'"
      };
    }
    const textExists = Boolean(elem?.textContent?.includes(expectation2.expect));
    if (!textExists) {
      return {
        result: false,
        error: `expected element with selector ${expectation2.selector} to have text: ${expectation2.expect}, but it didn't`
      };
    }
    return { result: true };
  }
  function urlExpectation(expectation2) {
    const url = window.location.href;
    if (!expectation2.expect) {
      return {
        result: false,
        error: "missing key: 'expect'"
      };
    }
    if (!url.includes(expectation2.expect)) {
      return {
        result: false,
        error: `expected URL to include ${expectation2.expect}, but it didn't`
      };
    }
    return { result: true };
  }

  // src/features/broker-protection/actions/expectation.js
  function expectation(action, root = document) {
    const results = expectMany(action.expectations, root);
    const errors = results.filter((x2, index) => {
      if (x2.result === true) return false;
      if (action.expectations[index].failSilently) return false;
      return true;
    }).map((x2) => {
      return "error" in x2 ? x2.error : "unknown error";
    });
    if (errors.length > 0) {
      return new ErrorResponse({ actionID: action.id, message: errors.join(", ") });
    }
    const runActions = results.every((x2) => x2.result === true);
    if (action.actions?.length && runActions) {
      return new SuccessResponse({
        actionID: action.id,
        actionType: action.actionType,
        response: null,
        next: action.actions
      });
    }
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
  }

  // src/features/broker-protection/actions/navigate.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/captcha.service.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/utils/url.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/utils/safe-call.js
  init_define_import_meta_trackerLookup();
  function safeCall(fn, { errorMessage } = {}) {
    try {
      return fn();
    } catch (e) {
      console.error(errorMessage ?? "[safeCall] Error:", e);
      return null;
    }
  }
  function safeCallWithError(fn, { errorMessage } = {}) {
    const message = errorMessage ?? "[safeCallWithError] Error";
    return safeCall(fn, { errorMessage: message }) ?? PirError.create(message);
  }

  // src/features/broker-protection/utils/url.js
  function getUrlParameter(url, param) {
    if (!url || !param) {
      return null;
    }
    return safeCall(() => new URL(url).searchParams.get(param), { errorMessage: `[getUrlParameter] Error parsing URL: ${url}` });
  }
  function removeUrlQueryParams(url) {
    if (!url) {
      return "";
    }
    return url.split("?")[0];
  }

  // src/features/broker-protection/captcha-services/get-captcha-provider.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/providers/registry.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/factory.js
  init_define_import_meta_trackerLookup();
  var CaptchaFactory = class {
    constructor() {
      this.providers = /* @__PURE__ */ new Map();
    }
    /**
     * Register a captcha provider
     * @param {import('./providers/provider.interface').CaptchaProvider} provider - The provider to register
     */
    registerProvider(provider) {
      this.providers.set(provider.getType(), provider);
    }
    /**
     * Get a provider by type
     * @param {string} type - The provider type
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    getProviderByType(type) {
      return this.providers.get(type) || null;
    }
    /**
     * Detect the captcha provider based on the element
     * @param {Document | HTMLElement} root
     * @param {HTMLElement} element - The element to check
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    detectProvider(root, element) {
      return this._getAllProviders().find((provider) => provider.isSupportedForElement(root, element)) || null;
    }
    /**
     * Detect the captcha provider based on the root document
     * @param {HTMLElement} element - The element to check
     * @returns {import('./providers/provider.interface').CaptchaProvider|null}
     */
    detectSolveProvider(element) {
      return this._getAllProviders().find((provider) => provider.canSolve(element)) || null;
    }
    /**
     * Get all registered providers
     * @private
     * @returns {Array<import('./providers/provider.interface').CaptchaProvider>}
     */
    _getAllProviders() {
      return Array.from(this.providers.values());
    }
  };

  // src/features/broker-protection/captcha-services/providers/recaptcha.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/utils/sitekey.js
  init_define_import_meta_trackerLookup();
  function getSiteKeyFromSearchParam({ captchaElement, siteKeyAttrName }) {
    if (!captchaElement) {
      throw Error("[getSiteKeyFromSearchParam] could not find captcha");
    }
    if (!("src" in captchaElement)) {
      throw Error("[getSiteKeyFromSearchParam] missing src attribute");
    }
    return getUrlParameter(String(captchaElement.src), siteKeyAttrName);
  }

  // src/features/broker-protection/captcha-services/utils/stringify-function.js
  init_define_import_meta_trackerLookup();
  function stringifyFunction({ functionName, functionBody, args }) {
    return safeCall(
      () => `;(function(args) {
        ${functionBody.toString()};
        ${functionName}(args);
    })(${JSON.stringify(args)});`,
      { errorMessage: `[stringifyFunction] error stringifying function ${functionName}` }
    );
  }

  // src/features/broker-protection/captcha-services/utils/token.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/utils/element.js
  init_define_import_meta_trackerLookup();
  function isElementType(element, tag) {
    if (Array.isArray(tag)) {
      return tag.some((t) => isElementType(element, t));
    }
    return element.tagName.toLowerCase() === tag.toLowerCase();
  }

  // src/features/broker-protection/captcha-services/utils/token.js
  function injectTokenIntoElement({ captchaContainerElement, captchaInputElement, elementName, token }) {
    let element;
    if (captchaInputElement) {
      element = captchaInputElement;
    } else if (elementName) {
      element = getElementByTagName(captchaContainerElement, elementName);
    } else {
      return PirError.create(`[injectTokenIntoElement] must pass in either captcha input element or element name`);
    }
    if (!element) {
      return PirError.create(`[injectTokenIntoElement] could not find element to inject token into`);
    }
    return safeCallWithError(
      () => {
        if (isInputElement(element) && ["text", "hidden"].includes(element.type) || isTextAreaElement(element)) {
          element.value = token;
          return PirSuccess.create({ injected: true });
        } else {
          return PirError.create(`[injectTokenIntoElement] element is neither a text input or textarea`);
        }
      },
      { errorMessage: `[injectTokenIntoElement] error injecting token into element` }
    );
  }
  function isInputElement(element) {
    return isElementType(element, "input");
  }
  function isTextAreaElement(element) {
    return isElementType(element, "textarea");
  }

  // src/features/broker-protection/actions/captcha-callback.js
  init_define_import_meta_trackerLookup();
  function captchaCallback(args) {
    const clients = findRecaptchaClients(globalThis);
    if (clients.length === 0) {
      return console.log("cannot find clients");
    }
    if (typeof clients[0].function === "function") {
      try {
        clients[0].function(args.token);
        console.log("called function with path", clients[0].callback);
      } catch (e) {
        console.error("could not call function");
      }
    }
    function findRecaptchaClients(target) {
      if (typeof target.___grecaptcha_cfg === "undefined") {
        console.log("target.___grecaptcha_cfg not found in ", location.href);
        return [];
      }
      return Object.entries(target.___grecaptcha_cfg.clients || {}).map(([cid, client]) => {
        const cidNumber = parseInt(cid, 10);
        const data2 = {
          id: cid,
          version: cidNumber >= 1e4 ? "V3" : "V2"
        };
        const objects = Object.entries(client).filter(([, value]) => value && typeof value === "object");
        objects.forEach(([toplevelKey, toplevel]) => {
          const found = Object.entries(toplevel).find(
            ([, value]) => value && typeof value === "object" && "sitekey" in value && "size" in value
          );
          if (typeof toplevel === "object" && typeof HTMLElement !== "undefined" && toplevel instanceof HTMLElement && toplevel.tagName === "DIV") {
            data2.pageurl = toplevel.baseURI;
          }
          if (found) {
            const [sublevelKey, sublevel] = found;
            data2.sitekey = sublevel.sitekey;
            const callbackKey = data2.version === "V2" ? "callback" : "promise-callback";
            const callback = sublevel[callbackKey];
            if (!callback) {
              data2.callback = null;
              data2.function = null;
            } else {
              data2.function = callback;
              data2.callback = ["___grecaptcha_cfg", "clients", cid, toplevelKey, sublevelKey, callbackKey];
            }
          }
        });
        return data2;
      });
    }
  }

  // src/features/broker-protection/captcha-services/providers/recaptcha.js
  var _config;
  var ReCaptchaProvider = class {
    /**
     * @param {ReCaptchaProviderConfig} config
     */
    constructor(config2) {
      /**
       * @type {ReCaptchaProviderConfig}
       */
      __privateAdd(this, _config);
      __privateSet(this, _config, config2);
    }
    getType() {
      return __privateGet(this, _config).type;
    }
    /**
     * @param {Document | HTMLElement} _root
     * @param {HTMLElement} captchaContainerElement
     */
    isSupportedForElement(_root, captchaContainerElement) {
      return !!this._getCaptchaElement(captchaContainerElement);
    }
    /**
     * @param {HTMLElement} captchaContainerElement
     */
    getCaptchaIdentifier(captchaContainerElement) {
      return Promise.resolve(
        safeCallWithError(
          () => getSiteKeyFromSearchParam({ captchaElement: this._getCaptchaElement(captchaContainerElement), siteKeyAttrName: "k" }),
          { errorMessage: "[ReCaptchaProvider.getCaptchaIdentifier] could not extract site key" }
        )
      );
    }
    getSupportingCodeToInject() {
      return null;
    }
    /**
     * @param {HTMLElement} _captchaContainerElement - The element containing the captcha
     * @param {string} token
     */
    getSolveCallback(_captchaContainerElement, token) {
      return stringifyFunction({
        functionBody: captchaCallback,
        functionName: "captchaCallback",
        args: { token }
      });
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     */
    canSolve(captchaContainerElement) {
      return !!getElementByTagName(captchaContainerElement, __privateGet(this, _config).responseElementName);
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token
     */
    injectToken(captchaContainerElement, token) {
      return injectTokenIntoElement({ captchaContainerElement, elementName: __privateGet(this, _config).responseElementName, token });
    }
    /**
     * @private
     * @param {HTMLElement} captchaContainerElement
     */
    _getCaptchaElement(captchaContainerElement) {
      return getElementWithSrcStart(captchaContainerElement, __privateGet(this, _config).providerUrl);
    }
  };
  _config = new WeakMap();

  // src/features/broker-protection/captcha-services/providers/image.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/utils/image.js
  init_define_import_meta_trackerLookup();
  function svgToBase64Jpg(svgElement, backgroundColor = "white") {
    const svgString = new XMLSerializer().serializeToString(svgElement);
    const svgDataUrl = "data:image/svg+xml;base64," + btoa(svgString);
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement("canvas");
        const ctx = canvas.getContext("2d");
        if (!ctx) {
          reject(new Error("Could not get 2D context from canvas"));
          return;
        }
        canvas.width = img.width;
        canvas.height = img.height;
        ctx.fillStyle = backgroundColor;
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0);
        const jpgBase64 = canvas.toDataURL("image/jpeg");
        resolve(jpgBase64);
      };
      img.onerror = (error) => {
        reject(error);
      };
      img.src = svgDataUrl;
    });
  }
  function imageToBase64(imageElement) {
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      throw Error("[imageToBase64] Could not get 2D context from canvas");
    }
    canvas.width = imageElement.width;
    canvas.height = imageElement.height;
    ctx.drawImage(imageElement, 0, 0, canvas.width, canvas.height);
    const base64String = canvas.toDataURL("image/jpeg");
    return base64String;
  }

  // src/features/broker-protection/captcha-services/providers/image.js
  var ImageProvider = class {
    getType() {
      return "image";
    }
    /**
     * @param {Document | HTMLElement} _root
     * @param {HTMLElement} captchaImageElement - The captcha image element
     */
    isSupportedForElement(_root, captchaImageElement) {
      if (!captchaImageElement) {
        return false;
      }
      return isElementType(captchaImageElement, ["img", "svg"]);
    }
    /**
     * @param {HTMLElement} captchaImageElement - The captcha image element
     */
    async getCaptchaIdentifier(captchaImageElement) {
      if (isSVGElement(captchaImageElement)) {
        return await svgToBase64Jpg(captchaImageElement);
      }
      if (isImgElement(captchaImageElement)) {
        return imageToBase64(captchaImageElement);
      }
      return PirError.create(
        `[ImageProvider.getCaptchaIdentifier] could not extract Base64 from image with tag name: ${captchaImageElement.tagName}`
      );
    }
    getSupportingCodeToInject() {
      return null;
    }
    /**
     * @param {HTMLElement} captchaInputElement - The captcha input element
     */
    canSolve(captchaInputElement) {
      return isElementType(captchaInputElement, ["input", "textarea"]);
    }
    /**
     * @param {HTMLInputElement} captchaInputElement - The captcha input element
     * @param {string} token - The solved captcha token
     */
    injectToken(captchaInputElement, token) {
      return injectTokenIntoElement({ captchaInputElement, token });
    }
    /**
     * @param {HTMLElement} _captchaInputElement - The element containing the captcha
     * @param {string} _token - The solved captcha token
     */
    getSolveCallback(_captchaInputElement, _token) {
      return stringifyFunction({
        functionBody: function callbackNoop() {
        },
        functionName: "callbackNoop",
        args: {}
      });
    }
  };
  function isSVGElement(element) {
    return isElementType(element, "svg");
  }
  function isImgElement(element) {
    return isElementType(element, "img");
  }

  // src/features/broker-protection/captcha-services/providers/cloudflare-turnstile.js
  init_define_import_meta_trackerLookup();

  // src/features/broker-protection/captcha-services/utils/attribute.js
  init_define_import_meta_trackerLookup();
  function getAttributeValue({ element, attrName }) {
    if (!element) {
      throw Error("[getAttributeValue] element parameter is required");
    }
    const attributeValue = element.getAttribute(attrName);
    if (!attributeValue) {
      throw Error(`[getAttributeValue] ${attrName} is not defined or has no value`);
    }
    return attributeValue;
  }

  // src/features/broker-protection/captcha-services/providers/cloudflare-turnstile.js
  var _config2;
  var CloudFlareTurnstileProvider = class {
    constructor() {
      /**
       * @type {CloudFlareTurnstileProviderConfig}
       */
      __privateAdd(this, _config2);
      __privateSet(this, _config2, {
        providerUrl: "https://challenges.cloudflare.com/turnstile/v0",
        responseElementName: "cf-turnstile-response"
      });
    }
    getType() {
      return "cloudFlareTurnstile";
    }
    /**
     * @param {Document | HTMLElement} root
     * @param {HTMLElement} _captchaContainerElement
     * @returns {boolean} Whether the captcha is supported for the element
     */
    isSupportedForElement(root, _captchaContainerElement) {
      return !!this._getCaptchaScript(root);
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     */
    getCaptchaIdentifier(captchaContainerElement) {
      const sitekeyAttribute = "data-sitekey";
      return Promise.resolve(
        safeCallWithError(() => getAttributeValue({ element: captchaContainerElement, attrName: sitekeyAttribute }), {
          errorMessage: `[CloudFlareTurnstileProvider.getCaptchaIdentifier] could not extract site key from attribute: ${sitekeyAttribute}`
        })
      );
    }
    getSupportingCodeToInject() {
      return null;
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @returns {boolean} Whether the captcha can be solved
     */
    canSolve(captchaContainerElement) {
      const callbackAttribute = "data-callback";
      const hasCallback = safeCallWithError(() => getAttributeValue({ element: captchaContainerElement, attrName: callbackAttribute }), {
        errorMessage: `[CloudFlareTurnstileProvider.canSolve] could not extract callback function name from attribute: ${callbackAttribute}`
      });
      if (PirError.isError(hasCallback)) {
        return false;
      }
      const hasResponseElement = safeCallWithError(() => getElementByTagName(captchaContainerElement, __privateGet(this, _config2).responseElementName), {
        errorMessage: `[CloudFlareTurnstileProvider.canSolve] could not find response element: ${__privateGet(this, _config2).responseElementName}`
      });
      if (PirError.isError(hasResponseElement)) {
        return false;
      }
      return true;
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token - The solved captcha token
     */
    injectToken(captchaContainerElement, token) {
      return injectTokenIntoElement({ captchaContainerElement, elementName: __privateGet(this, _config2).responseElementName, token });
    }
    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token - The solved captcha token
     */
    getSolveCallback(captchaContainerElement, token) {
      const callbackAttribute = "data-callback";
      const callbackFunctionName = safeCallWithError(
        () => getAttributeValue({ element: captchaContainerElement, attrName: callbackAttribute }),
        {
          errorMessage: `[CloudFlareTurnstileProvider.getSolveCallback] could not extract callback function name from attribute: ${callbackAttribute}`
        }
      );
      if (PirError.isError(callbackFunctionName)) {
        return callbackFunctionName;
      }
      return stringifyFunction({
        /**
         * @param {Object} args - The arguments passed to the function
         * @param {string} args.callbackFunctionName - The callback function name
         * @param {string} args.token - The solved captcha token
         */
        functionBody: function cloudflareCaptchaCallback(args) {
          window[args.callbackFunctionName](args.token);
        },
        functionName: "cloudflareCaptchaCallback",
        args: { callbackFunctionName, token }
      });
    }
    /**
     * @private
     * @param {Document | HTMLElement} root - The root element to search in
     */
    _getCaptchaScript(root) {
      return getElementWithSrcStart(root, __privateGet(this, _config2).providerUrl);
    }
  };
  _config2 = new WeakMap();

  // src/features/broker-protection/captcha-services/providers/registry.js
  var captchaFactory = new CaptchaFactory();
  captchaFactory.registerProvider(
    new ReCaptchaProvider({
      type: "recaptcha2",
      providerUrl: "https://www.google.com/recaptcha/api2",
      responseElementName: "g-recaptcha-response"
    })
  );
  captchaFactory.registerProvider(
    new ReCaptchaProvider({
      type: "recaptchaEnterprise",
      providerUrl: "https://www.google.com/recaptcha/enterprise",
      responseElementName: "g-recaptcha-response"
    })
  );
  captchaFactory.registerProvider(new CloudFlareTurnstileProvider());
  captchaFactory.registerProvider(new ImageProvider());

  // src/features/broker-protection/captcha-services/get-captcha-provider.js
  function getCaptchaProvider(root, captchaContainer, captchaType) {
    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
      return PirError.create(`[getCaptchaProvider] could not find captcha provider with type ${captchaType}`);
    }
    if (captchaProvider.isSupportedForElement(root, captchaContainer)) {
      return captchaProvider;
    }
    const detectedProvider = captchaFactory.detectProvider(root, captchaContainer);
    if (!detectedProvider) {
      return PirError.create(
        `[getCaptchaProvider] could not detect captcha provider for ${captchaType} captcha and element ${captchaContainer}`
      );
    }
    console.warn(
      `[getCaptchaProvider] mismatch between expected capctha type ${captchaType} and detected type ${detectedProvider.getType()}`
    );
    return detectedProvider;
  }
  function getCaptchaSolveProvider(captchaContainer, captchaType) {
    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
      return PirError.create(`[getCaptchaSolveProvider] could not find captcha provider with type ${captchaType}`);
    }
    if (captchaProvider.canSolve(captchaContainer)) {
      return captchaProvider;
    }
    const detectedProvider = captchaFactory.detectSolveProvider(captchaContainer);
    if (!detectedProvider) {
      return PirError.create(
        `[getCaptchaSolveProvider] could not detect captcha provider for ${captchaType} captcha and element ${captchaContainer}`
      );
    }
    console.warn(
      `[getCaptchaSolveProvider] mismatch between expected captha type ${captchaType} and detected type ${detectedProvider.getType()}`
    );
    return detectedProvider;
  }

  // src/features/broker-protection/actions/captcha-deprecated.js
  init_define_import_meta_trackerLookup();
  function getCaptchaInfo(action, root = document) {
    const pageUrl = window.location.href;
    if (!action.selector) {
      return new ErrorResponse({ actionID: action.id, message: "missing selector" });
    }
    const captchaDiv = getElement(root, action.selector);
    if (!captchaDiv) {
      return new ErrorResponse({ actionID: action.id, message: `could not find captchaDiv with selector ${action.selector}` });
    }
    const captcha = getElement(captchaDiv, '[src^="https://www.google.com/recaptcha"]') || getElement(captchaDiv, '[src^="https://newassets.hcaptcha.com/captcha"');
    if (!captcha) return new ErrorResponse({ actionID: action.id, message: "could not find captcha" });
    if (!("src" in captcha)) return new ErrorResponse({ actionID: action.id, message: "missing src attribute" });
    const captchaUrl = String(captcha.src);
    let captchaType;
    let siteKey;
    if (captchaUrl.includes("recaptcha/api2")) {
      captchaType = "recaptcha2";
      siteKey = new URL(captchaUrl).searchParams.get("k");
    } else if (captchaUrl.includes("recaptcha/enterprise")) {
      captchaType = "recaptchaEnterprise";
      siteKey = new URL(captchaUrl).searchParams.get("k");
    } else if (captchaUrl.includes("hcaptcha.com/captcha/v1")) {
      captchaType = "hcaptcha";
      if (captcha instanceof Element) {
        siteKey = captcha.getAttribute("data-sitekey");
      }
      if (!siteKey) {
        try {
          siteKey = new URL(captchaUrl).searchParams.get("sitekey");
        } catch (e) {
          console.warn("error parsing captchaUrl", captchaUrl);
        }
      }
      if (!siteKey) {
        try {
          const hash = new URL(captchaUrl).hash.slice(1);
          siteKey = new URLSearchParams(hash).get("sitekey");
        } catch (e) {
          console.warn("error parsing captchaUrl hash", captchaUrl);
        }
      }
    }
    if (!captchaType) {
      return new ErrorResponse({ actionID: action.id, message: "Could not extract captchaType." });
    }
    if (!siteKey) {
      return new ErrorResponse({ actionID: action.id, message: "Could not extract siteKey." });
    }
    const pageUrlWithoutParams = pageUrl?.split("?")[0];
    const responseData = {
      siteKey,
      url: pageUrlWithoutParams,
      type: captchaType
    };
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: responseData });
  }
  function solveCaptcha(action, token, root = document) {
    const selectors = ["h-captcha-response", "g-recaptcha-response"];
    let solved = false;
    for (const selector of selectors) {
      const match = root.getElementsByName(selector)[0];
      if (match) {
        match.innerHTML = token;
        solved = true;
        break;
      }
    }
    if (solved) {
      const json = JSON.stringify({ token });
      const javascript = `;(function(args) {
            ${captchaCallback.toString()};
            captchaCallback(args);
        })(${json});`;
      return new SuccessResponse({
        actionID: action.id,
        actionType: action.actionType,
        response: { callback: { eval: javascript } }
      });
    }
    return new ErrorResponse({ actionID: action.id, message: "could not solve captcha" });
  }

  // src/features/broker-protection/captcha-services/captcha.service.js
  var getCaptchaContainer = (root, selector) => {
    if (!selector) {
      return PirError.create("missing selector");
    }
    const captchaContainer = getElement(root, selector);
    if (!captchaContainer) {
      return PirError.create(`could not find captcha container with selector ${selector}`);
    }
    return captchaContainer;
  };
  function getSupportingCodeToInject(action) {
    const { id: actionID, actionType, injectCaptchaHandler: captchaType } = action;
    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: "getSupportingCodeToInject" });
    if (!captchaType) {
      return SuccessResponse.create({ actionID, actionType, response: {} });
    }
    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
      return createError(`could not find captchaProvider with type ${captchaType}`);
    }
    return SuccessResponse.create({ actionID, actionType, response: { code: captchaProvider.getSupportingCodeToInject() } });
  }
  async function getCaptchaInfo2(action, root = document) {
    const { id: actionID, actionType, captchaType, selector } = action;
    if (!captchaType) {
      return getCaptchaInfo(action, root);
    }
    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: `[getCaptchaInfo] captchaType: ${captchaType}` });
    const captchaContainer = getCaptchaContainer(root, selector);
    if (PirError.isError(captchaContainer)) {
      return createError(captchaContainer.error.message);
    }
    const captchaProvider = getCaptchaProvider(root, captchaContainer, captchaType);
    if (PirError.isError(captchaProvider)) {
      return createError(captchaProvider.error.message);
    }
    const captchaIdentifier = await captchaProvider.getCaptchaIdentifier(captchaContainer);
    if (!captchaIdentifier) {
      return createError(`could not extract captcha identifier from the container with selector ${selector}`);
    }
    if (PirError.isError(captchaIdentifier)) {
      return createError(captchaIdentifier.error.message);
    }
    const response = {
      url: removeUrlQueryParams(window.location.href),
      // query params (which may include PII)
      siteKey: captchaIdentifier,
      type: captchaProvider.getType()
    };
    return SuccessResponse.create({ actionID, actionType, response });
  }
  function solveCaptcha2(action, token, root = document) {
    const { id: actionID, actionType, captchaType, selector } = action;
    if (!captchaType) {
      return solveCaptcha(action, token, root);
    }
    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: `[solveCaptcha] captchaType: ${captchaType}` });
    const captchaContainer = getCaptchaContainer(root, selector);
    if (PirError.isError(captchaContainer)) {
      return createError(captchaContainer.error.message);
    }
    const captchaSolveProvider = getCaptchaSolveProvider(captchaContainer, captchaType);
    if (PirError.isError(captchaSolveProvider)) {
      return createError(captchaSolveProvider.error.message);
    }
    if (!captchaSolveProvider.canSolve(captchaContainer)) {
      return createError("cannot solve captcha");
    }
    const tokenResponse = captchaSolveProvider.injectToken(captchaContainer, token);
    if (PirError.isError(tokenResponse)) {
      return createError(tokenResponse.error.message);
    }
    if (!tokenResponse.response.injected) {
      return createError("could not inject token");
    }
    return SuccessResponse.create({
      actionID,
      actionType,
      response: { callback: { eval: captchaSolveProvider.getSolveCallback(captchaContainer, token) } }
    });
  }

  // src/features/broker-protection/actions/build-url.js
  init_define_import_meta_trackerLookup();
  function buildUrl(action, userData) {
    const result = replaceTemplatedUrl(action, userData);
    if ("error" in result) {
      return new ErrorResponse({ actionID: action.id, message: result.error });
    }
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: { url: result.url } });
  }
  function replaceTemplatedUrl(action, userData) {
    const url = action?.url;
    if (!url) {
      return { error: "Error: No url provided." };
    }
    try {
      const _2 = new URL(action.url);
    } catch (e) {
      return { error: "Error: Invalid URL provided." };
    }
    if (!userData) {
      return { url };
    }
    return transformUrl(action, userData);
  }

  // src/features/broker-protection/actions/navigate.js
  function navigate(action, userData) {
    const { id: actionID, actionType } = action;
    const urlResult = buildUrl(action, userData);
    if (urlResult instanceof ErrorResponse) {
      return urlResult;
    }
    const codeToInjectResponse = getSupportingCodeToInject(action);
    if (codeToInjectResponse instanceof ErrorResponse) {
      return codeToInjectResponse;
    }
    const response = {
      ...urlResult.success.response,
      ...codeToInjectResponse.success.response
    };
    return new SuccessResponse({ actionID, actionType, response });
  }

  // src/features/broker-protection/actions/condition.js
  init_define_import_meta_trackerLookup();
  function condition(action, root = document) {
    const results = expectMany(action.expectations, root);
    const errors = results.filter((x2, index) => {
      if (x2.result === true) return false;
      if (action.expectations[index].failSilently) return false;
      return true;
    }).map((x2) => {
      return "error" in x2 ? x2.error : "unknown error";
    });
    if (errors.length > 0) {
      return new ErrorResponse({ actionID: action.id, message: errors.join(", ") });
    }
    const returnActions = results.every((x2) => x2.result === true);
    if (action.actions?.length && returnActions) {
      return new SuccessResponse({
        actionID: action.id,
        actionType: action.actionType,
        response: { actions: action.actions }
      });
    }
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: { actions: [] } });
  }

  // src/features/broker-protection/execute.js
  async function execute(action, inputData, root = document) {
    try {
      switch (action.actionType) {
        case "navigate":
          return navigate(action, data(action, inputData, "userProfile"));
        case "extract":
          return await extract(action, data(action, inputData, "userProfile"), root);
        case "click":
          return click(action, data(action, inputData, "userProfile"), root);
        case "expectation":
          return expectation(action, root);
        case "fillForm":
          return fillForm(action, data(action, inputData, "extractedProfile"), root);
        case "getCaptchaInfo":
          return await getCaptchaInfo2(action, root);
        case "solveCaptcha":
          return solveCaptcha2(action, data(action, inputData, "token"), root);
        case "condition":
          return condition(action, root);
        default: {
          return new ErrorResponse({
            actionID: action.id,
            message: `unimplemented actionType: ${action.actionType}`
          });
        }
      }
    } catch (e) {
      console.log("unhandled exception: ", e);
      return new ErrorResponse({
        actionID: action.id,
        message: `unhandled exception: ${e.message}`
      });
    }
  }
  function data(action, data2, defaultSource) {
    if (!data2) return null;
    const source = action.dataSource || defaultSource;
    if (Object.prototype.hasOwnProperty.call(data2, source)) {
      return data2[source];
    }
    return null;
  }

  // src/timer-utils.js
  init_define_import_meta_trackerLookup();
  var DEFAULT_RETRY_CONFIG = {
    interval: { ms: 0 },
    maxAttempts: 1
  };
  async function retry(fn, config2 = DEFAULT_RETRY_CONFIG) {
    let lastResult;
    const exceptions = [];
    for (let i = 0; i < config2.maxAttempts; i++) {
      try {
        lastResult = await Promise.resolve(fn());
      } catch (e) {
        exceptions.push(e.toString());
      }
      if (lastResult && "success" in lastResult) break;
      if (i === config2.maxAttempts - 1) break;
      await new Promise((resolve) => setTimeout(resolve, config2.interval.ms));
    }
    return { result: lastResult, exceptions };
  }

  // src/features/broker-protection.js
  var BrokerProtection = class extends ContentFeature {
    init() {
      this.messaging.subscribe("onActionReceived", async (params) => {
        try {
          const action = params.state.action;
          const data2 = params.state.data;
          if (!action) {
            return this.messaging.notify("actionError", { error: "No action found." });
          }
          const { results, exceptions } = await this.exec(action, data2);
          if (results) {
            const parent = results[0];
            const errors = results.filter((x2) => "error" in x2);
            if (results.length === 1 || errors.length === 0) {
              return this.messaging.notify("actionCompleted", { result: parent });
            }
            const joinedErrors = errors.map((x2) => x2.error.message).join(", ");
            const response = new ErrorResponse({
              actionID: action.id,
              message: "Secondary actions failed: " + joinedErrors
            });
            return this.messaging.notify("actionCompleted", { result: response });
          } else {
            return this.messaging.notify("actionError", { error: "No response found, exceptions: " + exceptions.join(", ") });
          }
        } catch (e) {
          console.log("unhandled exception: ", e);
          this.messaging.notify("actionError", { error: e.toString() });
        }
      });
    }
    /**
     * Recursively execute actions with the same dataset, collecting all results/exceptions for
     * later analysis
     * @param {any} action
     * @param {Record<string, any>} data
     * @return {Promise<{results: ActionResponse[], exceptions: string[]}>}
     */
    async exec(action, data2) {
      const retryConfig = this.retryConfigFor(action);
      const { result, exceptions } = await retry(() => execute(action, data2, document), retryConfig);
      if (result) {
        if ("success" in result && Array.isArray(result.success.next)) {
          const nextResults = [];
          const nextExceptions = [];
          for (const nextAction of result.success.next) {
            const { results: subResults, exceptions: subExceptions } = await this.exec(nextAction, data2);
            nextResults.push(...subResults);
            nextExceptions.push(...subExceptions);
          }
          return { results: [result, ...nextResults], exceptions: exceptions.concat(nextExceptions) };
        }
        return { results: [result], exceptions: [] };
      }
      return { results: [], exceptions };
    }
    /**
     * Define default retry configurations for certain actions
     *
     * @param {any} action
     * @returns
     */
    retryConfigFor(action) {
      const retryConfig = action.retry?.environment === "web" ? action.retry : void 0;
      if (!retryConfig && action.actionType === "extract") {
        return {
          interval: { ms: 1e3 },
          maxAttempts: 30
        };
      }
      if (!retryConfig && (action.actionType === "expectation" || action.actionType === "condition")) {
        if (action.expectations.some((x2) => x2.type === "element")) {
          return {
            interval: { ms: 1e3 },
            maxAttempts: 30
          };
        }
      }
      return retryConfig;
    }
  };

  // src/features/performance-metrics.js
  init_define_import_meta_trackerLookup();

  // src/features/breakage-reporting/utils.js
  init_define_import_meta_trackerLookup();
  function getJsPerformanceMetrics() {
    const paintResources = performance.getEntriesByType("paint");
    const firstPaint = paintResources.find((entry) => entry.name === "first-contentful-paint");
    return firstPaint ? [firstPaint.startTime] : [];
  }

  // src/features/performance-metrics.js
  var PerformanceMetrics = class extends ContentFeature {
    init() {
      this.messaging.subscribe("getVitals", () => {
        const vitals = getJsPerformanceMetrics();
        this.messaging.notify("vitalsResult", { vitals });
      });
    }
  };

  // src/features/click-to-load.js
  init_define_import_meta_trackerLookup();

  // src/features/click-to-load/ctl-assets.js
  init_define_import_meta_trackerLookup();
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

  // src/features/click-to-load/ctl-config.js
  init_define_import_meta_trackerLookup();

  // ../build/locales/ctl-locales.js
  init_define_import_meta_trackerLookup();
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

  // src/features/click-to-load/components/ctl-placeholder-blocked.js
  init_define_import_meta_trackerLookup();

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

  // src/features/click-to-load/components/ctl-login-button.js
  init_define_import_meta_trackerLookup();

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
  init_define_import_meta_trackerLookup();
  function registerCustomElements2() {
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
  function makeToggleButtonWithText(text2, mode, isActive = false, toggleClassNames = "", textCssStyles = "", dataKey = "") {
    const wrapper = document.createElement("div");
    wrapper.style.cssText = styles.toggleButtonWrapper;
    const toggleButton = makeToggleButton(mode, isActive, toggleClassNames, dataKey);
    const textDiv = document.createElement("div");
    textDiv.style.cssText = styles.contentText + styles.toggleButtonText + styles[mode].toggleButtonText + textCssStyles;
    textDiv.textContent = text2;
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
      __publicField(this, "listenForUpdateChanges", true);
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
      registerCustomElements2();
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

  // src/features/message-bridge.js
  init_define_import_meta_trackerLookup();

  // src/features/message-bridge/schema.js
  init_define_import_meta_trackerLookup();

  // src/type-utils.js
  init_define_import_meta_trackerLookup();
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

  // src/features/message-bridge.js
  var MessageBridge = class extends ContentFeature {
    constructor() {
      super(...arguments);
      /** @type {Captured} */
      __publicField(this, "captured", captured_globals_exports);
      /**
       * A mapping of feature names to instances of `Messaging`.
       * This allows the bridge to handle more than 1 feature at a time.
       * @type {Map<string, Messaging>}
       */
      __publicField(this, "proxies", new Map2());
      /**
       * If any subscriptions are created, we store the cleanup functions
       * for later use.
       * @type {Map<string, () => void>}
       */
      __publicField(this, "subscriptions", new Map2());
      /**
       * This side of the bridge can only be instantiated once,
       * so we use this flag to ensure we can handle multiple invocations
       */
      __publicField(this, "installed", false);
    }
    init(args) {
      if (isBeingFramed() || !isSecureContext) return;
      if (!args.messageSecret) return;
      const { captured } = this;
      function appendToken(eventName) {
        return `${eventName}-${args.messageSecret}`;
      }
      const reply = (incoming) => {
        if (!args.messageSecret) return this.log("ignoring because args.messageSecret was absent");
        const eventName = appendToken(incoming.name + "-" + incoming.id);
        const event = new captured.CustomEvent(eventName, { detail: incoming });
        captured.dispatchEvent(event);
      };
      const accept = (ClassType, callback) => {
        captured.addEventListener(appendToken(ClassType.NAME), (e) => {
          this.log(`${ClassType.NAME}`, JSON.stringify(e.detail));
          const instance = ClassType.create(e.detail);
          if (instance) {
            callback(instance);
          } else {
            this.log("Failed to create an instance");
          }
        });
      };
      this.log(`bridge is installing...`);
      accept(InstallProxy, (install) => {
        this.installProxyFor(install, args.messagingConfig, reply);
      });
      accept(ProxyNotification, (notification) => this.proxyNotification(notification));
      accept(ProxyRequest, (request) => this.proxyRequest(request, reply));
      accept(SubscriptionRequest, (subscription) => this.proxySubscription(subscription, reply));
      accept(SubscriptionUnsubscribe, (unsubscribe) => this.removeSubscription(unsubscribe.id));
    }
    /**
     * Installing a feature proxy is the act of creating a fresh instance of 'Messaging', but
     * using the same underlying transport
     *
     * @param {InstallProxy} install
     * @param {import('@duckduckgo/messaging').MessagingConfig} config
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    installProxyFor(install, config2, reply) {
      const { id, featureName } = install;
      if (this.proxies.has(featureName)) return this.log("ignoring `installProxyFor` because it exists", featureName);
      const allowed = this.getFeatureSettingEnabled(featureName);
      if (!allowed) {
        return this.log("not installing proxy, because", featureName, "was not enabled");
      }
      const ctx = { ...this.messaging.messagingContext, featureName };
      const messaging = new Messaging(ctx, config2);
      this.proxies.set(featureName, messaging);
      this.log("did install proxy for ", featureName);
      reply(new DidInstall({ id }));
    }
    /**
     * @param {ProxyRequest} request
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    async proxyRequest(request, reply) {
      const { id, featureName, method, params } = request;
      const proxy = this.proxies.get(featureName);
      if (!proxy) return this.log("proxy was not installed for ", featureName);
      this.log("will proxy", request);
      try {
        const result = await proxy.request(method, params);
        const responseEvent = new ProxyResponse({
          method,
          featureName,
          result,
          id
        });
        reply(responseEvent);
      } catch (e) {
        const errorResponseEvent = new ProxyResponse({
          method,
          featureName,
          error: { message: e.message },
          id
        });
        reply(errorResponseEvent);
      }
    }
    /**
     * @param {SubscriptionRequest} subscription
     * @param {(payload: {name: string; id: string} & Record<string, any>) => void} reply
     */
    proxySubscription(subscription, reply) {
      const { id, featureName, subscriptionName } = subscription;
      const proxy = this.proxies.get(subscription.featureName);
      if (!proxy) return this.log("proxy was not installed for", featureName);
      this.log("will setup subscription", subscription);
      const prev = this.subscriptions.get(id);
      if (prev) {
        this.removeSubscription(id);
      }
      const unsubscribe = proxy.subscribe(subscriptionName, (data2) => {
        const responseEvent = new SubscriptionResponse({
          subscriptionName,
          featureName,
          params: data2,
          id
        });
        reply(responseEvent);
      });
      this.subscriptions.set(id, unsubscribe);
    }
    /**
     * @param {string} id
     */
    removeSubscription(id) {
      const unsubscribe = this.subscriptions.get(id);
      this.log(`will remove subscription`, id);
      unsubscribe?.();
      this.subscriptions.delete(id);
    }
    /**
     * @param {ProxyNotification} notification
     */
    proxyNotification(notification) {
      const proxy = this.proxies.get(notification.featureName);
      if (!proxy) return this.log("proxy was not installed for", notification.featureName);
      this.log("will proxy notification", notification);
      proxy.notify(notification.method, notification.params);
    }
    /**
     * @param {Parameters<console['log']>} args
     */
    log(...args) {
      if (this.isDebug) {
        console.log("[isolated]", ...args);
      }
    }
    load(_args2) {
    }
  };
  var message_bridge_default = MessageBridge;

  // src/features/favicon.js
  init_define_import_meta_trackerLookup();
  var Favicon = class extends ContentFeature {
    init() {
      if (this.platform.name === "ios") return;
      if (isBeingFramed()) return;
      window.addEventListener("DOMContentLoaded", () => {
        this.send();
        this.monitorChanges();
      });
    }
    monitorChanges() {
      if (this.getFeatureSetting("monitor") === false) return;
      let trailing;
      let lastEmitTime = performance.now();
      const interval = 50;
      monitor(() => {
        clearTimeout(trailing);
        const currentTime = performance.now();
        const delta = currentTime - lastEmitTime;
        if (delta >= interval) {
          this.send();
        } else {
          trailing = setTimeout(() => {
            this.send();
          }, 50);
        }
        lastEmitTime = currentTime;
      });
    }
    send() {
      const favicons = getFaviconList();
      this.notify("faviconFound", { favicons, documentUrl: document.URL });
    }
  };
  var favicon_default = Favicon;
  function monitor(changeObservedCallback) {
    const target = document.head;
    if (!target) return;
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes" && mutation.target instanceof HTMLLinkElement) {
          changeObservedCallback();
          return;
        }
        if (mutation.type === "childList") {
          for (const addedNode of mutation.addedNodes) {
            if (addedNode instanceof HTMLLinkElement) {
              changeObservedCallback();
              return;
            }
          }
          for (const removedNode of mutation.removedNodes) {
            if (removedNode instanceof HTMLLinkElement) {
              changeObservedCallback();
              return;
            }
          }
        }
      }
    });
    observer.observe(target, { attributeFilter: ["rel", "href"], attributes: true, subtree: true, childList: true });
  }
  function getFaviconList() {
    const selectors = [
      "link[href][rel='favicon']",
      "link[href][rel*='icon']",
      "link[href][rel='apple-touch-icon']",
      "link[href][rel='apple-touch-icon-precomposed']"
    ];
    const elements = document.head.querySelectorAll(selectors.join(","));
    return Array.from(elements).map((link) => {
      const href = link.href || "";
      const rel = link.getAttribute("rel") || "";
      return { href, rel };
    });
  }

  // ddg:platformFeatures:ddg:platformFeatures
  var ddg_platformFeatures_default = {
    ddg_feature_duckPlayer: DuckPlayerFeature,
    ddg_feature_duckPlayerNative: duck_player_native_default,
    ddg_feature_brokerProtection: BrokerProtection,
    ddg_feature_performanceMetrics: PerformanceMetrics,
    ddg_feature_clickToLoad: ClickToLoad,
    ddg_feature_messageBridge: message_bridge_default,
    ddg_feature_favicon: favicon_default
  };

  // src/url-change.js
  init_define_import_meta_trackerLookup();
  var urlChangeListeners = /* @__PURE__ */ new Set();
  function registerForURLChanges(listener) {
    if (urlChangeListeners.size === 0) {
      listenForURLChanges();
    }
    urlChangeListeners.add(listener);
  }
  function handleURLChange(navigationType = "unknown") {
    for (const listener of urlChangeListeners) {
      listener(navigationType);
    }
  }
  function listenForURLChanges() {
    const urlChangedInstance = new ContentFeature("urlChanged", {}, {});
    if ("navigation" in globalThis && "addEventListener" in globalThis.navigation) {
      const navigations = /* @__PURE__ */ new WeakMap();
      globalThis.navigation.addEventListener("navigate", (event) => {
        navigations.set(event.target, event.navigationType);
      });
      globalThis.navigation.addEventListener("navigatesuccess", (event) => {
        const navigationType = navigations.get(event.target);
        handleURLChange(navigationType);
        navigations.delete(event.target);
      });
      return;
    }
    if (isBeingFramed()) {
      return;
    }
    const historyMethodProxy = new DDGProxy(urlChangedInstance, History.prototype, "pushState", {
      apply(target, thisArg, args) {
        const changeResult = DDGReflect.apply(target, thisArg, args);
        handleURLChange("push");
        return changeResult;
      }
    });
    historyMethodProxy.overload();
    window.addEventListener("popstate", () => {
      handleURLChange("traverse");
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
      trackerLookup: define_import_meta_trackerLookup_default,
      injectName: "apple-isolated"
    };
    const bundledFeatureNames = typeof importConfig.injectName === "string" ? platformSupport[importConfig.injectName] : [];
    const featuresToLoad = isGloballyDisabled(args) ? platformSpecificFeatures : args.site.enabledFeatures || bundledFeatureNames;
    for (const featureName of bundledFeatureNames) {
      if (featuresToLoad.includes(featureName)) {
        const ContentFeature2 = ddg_platformFeatures_default["ddg_feature_" + featureName];
        const featureInstance = new ContentFeature2(featureName, importConfig, args);
        if (!featureInstance.getFeatureSettingEnabled("additionalCheck", "enabled")) {
          continue;
        }
        featureInstance.callLoad();
        features.push({ featureName, featureInstance });
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
    resolvedFeatures.forEach(({ featureInstance, featureName }) => {
      if (!isFeatureBroken(args, featureName) || alwaysInitExtensionFeatures(args, featureName)) {
        if (!featureInstance.getFeatureSettingEnabled("additionalCheck", "enabled")) {
          return;
        }
        featureInstance.callInit(args);
        if (featureInstance.listenForUrlChanges || featureInstance.urlChanged) {
          registerForURLChanges((navigationType) => {
            featureInstance.recomputeSiteObject();
            featureInstance?.urlChanged(navigationType);
          });
        }
      }
    });
    while (updates.length) {
      const update = updates.pop();
      await updateFeaturesInner(update);
    }
    mark.end();
    if (args.debug) {
      performanceMonitor.measureAll();
    }
  }
  function alwaysInitExtensionFeatures(args, featureName) {
    return args.platform.name === "extension" && alwaysInitFeatures.has(featureName);
  }
  async function updateFeaturesInner(args) {
    const resolvedFeatures = await Promise.all(features);
    resolvedFeatures.forEach(({ featureInstance, featureName }) => {
      if (!isFeatureBroken(initArgs, featureName) && featureInstance.listenForUpdateChanges) {
        featureInstance.update(args);
      }
    });
  }

  // entry-points/apple.js
  function initCode() {
    const config2 = $CONTENT_SCOPE$;
    const userUnprotectedDomains = $USER_UNPROTECTED_DOMAINS$;
    const userPreferences = $USER_PREFERENCES$;
    const processedConfig = processConfig(config2, userUnprotectedDomains, userPreferences, platformSpecificFeatures);
    const handlerNames = [];
    if (true) {
      handlerNames.push("contentScopeScriptsIsolated");
    } else {
      handlerNames.push("contentScopeScripts");
    }
    processedConfig.messagingConfig = new WebkitMessagingConfig({
      webkitMessageHandlerNames: handlerNames,
      secret: "",
      hasModernWebkitAPI: true
    });
    load({
      platform: processedConfig.platform,
      site: processedConfig.site,
      bundledConfig: processedConfig.bundledConfig,
      messagingConfig: processedConfig.messagingConfig,
      messageSecret: processedConfig.messageSecret
    });
    init(processedConfig);
  }
  initCode();
})();
