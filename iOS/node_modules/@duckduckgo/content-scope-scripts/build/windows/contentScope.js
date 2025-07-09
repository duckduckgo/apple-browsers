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

  // ../node_modules/seedrandom/lib/alea.js
  var require_alea = __commonJS({
    "../node_modules/seedrandom/lib/alea.js"(exports, module) {
      init_define_import_meta_trackerLookup();
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
          var mash = function(data2) {
            data2 = String(data2);
            for (var i = 0; i < data2.length; i++) {
              n += data2.charCodeAt(i);
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
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
    }
  });

  // ../node_modules/seedrandom/seedrandom.js
  var require_seedrandom = __commonJS({
    "../node_modules/seedrandom/seedrandom.js"(exports, module) {
      init_define_import_meta_trackerLookup();
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
      init_define_import_meta_trackerLookup();
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
        return function recurseChain(values, level) {
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
        }([str], 0);
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
        var parser2 = {};
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
        parser2.normalize_address = function(parts) {
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
        parser2.parseAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.address);
          return parser2.normalize_address(parts);
        };
        parser2.parseInformalAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.informal_address);
          return parser2.normalize_address(parts);
        };
        parser2.parsePoAddress = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.po_address);
          return parser2.normalize_address(parts);
        };
        parser2.parseLocation = function(address) {
          lazyInit();
          if (XRegExp(Addr_Match.corner, "xi").test(address)) {
            return parser2.parseIntersection(address);
          }
          if (XRegExp("^" + Addr_Match.po_box, "xi").test(address)) {
            return parser2.parsePoAddress(address);
          }
          return parser2.parseAddress(address) || parser2.parseInformalAddress(address);
        };
        parser2.parseIntersection = function(address) {
          lazyInit();
          var parts = XRegExp.exec(address, Addr_Match.intersection);
          parts = parser2.normalize_address(parts);
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
            return parser2;
          });
        } else if (typeof exports !== "undefined") {
          exports.parseIntersection = parser2.parseIntersection;
          exports.parseLocation = parser2.parseLocation;
          exports.parseInformalAddress = parser2.parseInformalAddress;
          exports.parseAddress = parser2.parseAddress;
        } else {
          root.addressParser = root.addressParser || parser2;
        }
      })();
    }
  });

  // entry-points/windows.js
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
  var OriginalCustomEvent = typeof CustomEvent === "undefined" ? null : CustomEvent;
  var originalWindowDispatchEvent = typeof window === "undefined" ? null : window.dispatchEvent.bind(window);
  function registerMessageSecret(secret) {
    messageSecret = secret;
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

  // src/features/cookie.js
  init_define_import_meta_trackerLookup();

  // src/cookie.js
  init_define_import_meta_trackerLookup();
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
    constructor(config, messagingContext) {
      /**
       * @type {{name: string, length: number}}
       * @internal
       */
      __publicField(this, "algoObj", {
        name: "AES-GCM",
        length: 256
      });
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
    constructor(messagingContext, config) {
      this.messagingContext = messagingContext;
      this.transport = getTransport(config, this.messagingContext);
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
    notify(name, data2 = {}) {
      const message = new NotificationMessage({
        context: this.messagingContext.context,
        featureName: this.messagingContext.featureName,
        method: name,
        params: data2
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

  // src/config-feature.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/index.js
  init_define_import_meta_trackerLookup();

  // ../node_modules/immutable-json-patch/lib/esm/immutableJSONPatch.js
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
    const injectName = "windows";
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

  // src/features/fingerprinting-audio.js
  init_define_import_meta_trackerLookup();

  // src/crypto.js
  init_define_import_meta_trackerLookup();

  // lib/sjcl.js
  init_define_import_meta_trackerLookup();
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
    sjcl2.hash.sha256.hash = function(data2) {
      return new sjcl2.hash.sha256().update(data2).finalize();
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
      update: function(data2) {
        if (typeof data2 === "string") {
          data2 = sjcl2.codec.utf8String.toBits(data2);
        }
        var i, b2 = this._buffer = sjcl2.bitArray.concat(this._buffer, data2), ol = this._length, nl = this._length = ol + sjcl2.bitArray.bitLength(data2);
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
    sjcl2.misc.hmac.prototype.encrypt = sjcl2.misc.hmac.prototype.mac = function(data2) {
      if (!this._updated) {
        this.update(data2);
        return this.digest(data2);
      } else {
        throw new sjcl2.exception.invalid("encrypt on already updated hmac called!");
      }
    };
    sjcl2.misc.hmac.prototype.reset = function() {
      this._resultHash = new this._hash(this._baseHash[0]);
      this._updated = false;
    };
    sjcl2.misc.hmac.prototype.update = function(data2) {
      this._updated = true;
      this._resultHash.update(data2);
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
        const data2 = cacheData.get(thisArg);
        const timeNow = Date.now();
        if (data2 && data2.args === JSON.stringify(args2) && data2.expires > timeNow) {
          data2.expires = timeNow + cacheExpiry;
          cacheData.set(thisArg, data2);
          return data2;
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
  init_define_import_meta_trackerLookup();
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

  // src/features/fingerprinting-canvas.js
  init_define_import_meta_trackerLookup();

  // src/canvas.js
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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

  // src/features/navigator-interface.js
  init_define_import_meta_trackerLookup();

  // src/features/message-bridge/create-page-world-bridge.js
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
  init_define_import_meta_trackerLookup();
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
  function extractTimeoutRules(rules2) {
    if (!shouldInjectStyleTag) {
      return rules2;
    }
    const strictHideRules = [];
    const timeoutRules = [];
    rules2.forEach((rule) => {
      if (rule.type === "hide") {
        strictHideRules.push(rule);
      } else {
        timeoutRules.push(rule);
      }
    });
    injectStyleTag(strictHideRules);
    return timeoutRules;
  }
  function injectStyleTag(rules2) {
    let selector = "";
    rules2.forEach((rule, i) => {
      if (i !== rules2.length - 1) {
        selector = selector.concat(rule.selector, ",");
      } else {
        selector = selector.concat(rule.selector);
      }
    });
    const styleTagProperties = "display:none!important;min-height:0!important;height:0!important;";
    const styleTagContents = `${forgivingSelector(selector)} {${styleTagProperties}}`;
    injectGlobalStyles(styleTagContents);
  }
  function hideAdNodes(rules2) {
    const document2 = globalThis.document;
    rules2.forEach((rule) => {
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
    applyRules(rules2) {
      const timeoutRules = extractTimeoutRules(rules2);
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
  init_define_import_meta_trackerLookup();
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
  init_define_import_meta_trackerLookup();
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

  // src/features/windows-permission-usage.js
  init_define_import_meta_trackerLookup();
  var WindowsPermissionUsage = class extends ContentFeature {
    init() {
      const Permission = {
        Geolocation: "geolocation",
        Camera: "camera",
        Microphone: "microphone"
      };
      const Status = {
        Inactive: "inactive",
        Accessed: "accessed",
        Active: "active",
        Paused: "paused"
      };
      const isFrameInsideFrame = window.self !== window.top && window.parent !== window.top;
      function windowsPostMessage(name, data2) {
        windowsInteropPostMessage({
          Feature: "Permissions",
          Name: name,
          Data: data2
        });
      }
      function signalPermissionStatus(permission, status) {
        windowsPostMessage("PermissionStatusMessage", { permission, status });
        console.debug(`Permission '${permission}' is ${status}`);
      }
      let pauseWatchedPositions = false;
      const watchedPositions = /* @__PURE__ */ new Set();
      const watchPositionProxy = new DDGProxy(this, Geolocation.prototype, "watchPosition", {
        apply(target, thisArg, args) {
          if (isFrameInsideFrame) {
            throw new DOMException("Permission denied");
          }
          const successHandler = args[0];
          args[0] = function(position) {
            if (pauseWatchedPositions) {
              signalPermissionStatus(Permission.Geolocation, Status.Paused);
            } else {
              signalPermissionStatus(Permission.Geolocation, Status.Active);
              successHandler?.(position);
            }
          };
          const id = DDGReflect.apply(target, thisArg, args);
          watchedPositions.add(id);
          return id;
        }
      });
      watchPositionProxy.overload();
      const clearWatchProxy = new DDGProxy(this, Geolocation.prototype, "clearWatch", {
        apply(target, thisArg, args) {
          DDGReflect.apply(target, thisArg, args);
          if (args[0] && watchedPositions.delete(args[0]) && watchedPositions.size === 0) {
            signalPermissionStatus(Permission.Geolocation, Status.Inactive);
          }
        }
      });
      clearWatchProxy.overload();
      const getCurrentPositionProxy = new DDGProxy(this, Geolocation.prototype, "getCurrentPosition", {
        apply(target, thisArg, args) {
          const successHandler = args[0];
          args[0] = function(position) {
            signalPermissionStatus(Permission.Geolocation, Status.Accessed);
            successHandler?.(position);
          };
          return DDGReflect.apply(target, thisArg, args);
        }
      });
      getCurrentPositionProxy.overload();
      const userMediaStreams = /* @__PURE__ */ new Set();
      const videoTracks = /* @__PURE__ */ new Set();
      const audioTracks = /* @__PURE__ */ new Set();
      function getTracks(permission) {
        switch (permission) {
          case Permission.Camera:
            return videoTracks;
          case Permission.Microphone:
            return audioTracks;
        }
      }
      function stopTracks(streamTracks) {
        streamTracks?.forEach((track) => track.stop());
      }
      function clearAllGeolocationWatch() {
        watchedPositions.forEach((id) => navigator.geolocation.clearWatch(id));
      }
      function pause(permission) {
        switch (permission) {
          case Permission.Camera:
          case Permission.Microphone: {
            const streamTracks = getTracks(permission);
            streamTracks?.forEach((track) => {
              track.enabled = false;
            });
            break;
          }
          case Permission.Geolocation:
            pauseWatchedPositions = true;
            signalPermissionStatus(Permission.Geolocation, Status.Paused);
            break;
        }
      }
      function resume(permission) {
        switch (permission) {
          case Permission.Camera:
          case Permission.Microphone: {
            const streamTracks = getTracks(permission);
            streamTracks?.forEach((track) => {
              track.enabled = true;
            });
            break;
          }
          case Permission.Geolocation:
            pauseWatchedPositions = false;
            signalPermissionStatus(Permission.Geolocation, Status.Active);
            break;
        }
      }
      function stop(permission) {
        switch (permission) {
          case Permission.Camera:
            stopTracks(videoTracks);
            break;
          case Permission.Microphone:
            stopTracks(audioTracks);
            break;
          case Permission.Geolocation:
            pauseWatchedPositions = false;
            clearAllGeolocationWatch();
            break;
        }
      }
      function monitorTrack(track) {
        if (track.readyState === "ended") return;
        if (track.kind === "video" && !videoTracks.has(track)) {
          console.debug(`New video stream track ${track.id}`);
          track.addEventListener("ended", videoTrackEnded);
          track.addEventListener("mute", signalVideoTracksState);
          track.addEventListener("unmute", signalVideoTracksState);
          videoTracks.add(track);
        } else if (track.kind === "audio" && !audioTracks.has(track)) {
          console.debug(`New audio stream track ${track.id}`);
          track.addEventListener("ended", audioTrackEnded);
          track.addEventListener("mute", signalAudioTracksState);
          track.addEventListener("unmute", signalAudioTracksState);
          audioTracks.add(track);
        }
      }
      function handleTrackEnded(track) {
        if (track.kind === "video" && videoTracks.has(track)) {
          console.debug(`Video stream track ${track.id} ended`);
          track.removeEventListener("ended", videoTrackEnded);
          track.removeEventListener("mute", signalVideoTracksState);
          track.removeEventListener("unmute", signalVideoTracksState);
          videoTracks.delete(track);
          signalVideoTracksState();
        } else if (track.kind === "audio" && audioTracks.has(track)) {
          console.debug(`Audio stream track ${track.id} ended`);
          track.removeEventListener("ended", audioTrackEnded);
          track.removeEventListener("mute", signalAudioTracksState);
          track.removeEventListener("unmute", signalAudioTracksState);
          audioTracks.delete(track);
          signalAudioTracksState();
        }
      }
      function videoTrackEnded(e) {
        handleTrackEnded(e.target);
      }
      function audioTrackEnded(e) {
        handleTrackEnded(e.target);
      }
      function signalTracksState(permission) {
        const tracks = getTracks(permission);
        if (!tracks) return;
        const allTrackCount = tracks.size;
        if (allTrackCount === 0) {
          signalPermissionStatus(permission, Status.Inactive);
          return;
        }
        let mutedTrackCount = 0;
        tracks.forEach((track) => {
          mutedTrackCount += !track.enabled || track.muted ? 1 : 0;
        });
        if (mutedTrackCount === allTrackCount) {
          signalPermissionStatus(permission, Status.Paused);
        } else {
          if (mutedTrackCount > 0) {
            console.debug(`Some ${permission} tracks are still active: ${allTrackCount - mutedTrackCount}/${allTrackCount}`);
          }
          signalPermissionStatus(permission, Status.Active);
        }
      }
      let signalVideoTracksStateTimer;
      function signalVideoTracksState() {
        clearTimeout(signalVideoTracksStateTimer);
        signalVideoTracksStateTimer = setTimeout(() => signalTracksState(Permission.Camera), 100);
      }
      let signalAudioTracksStateTimer;
      function signalAudioTracksState() {
        clearTimeout(signalAudioTracksStateTimer);
        signalAudioTracksStateTimer = setTimeout(() => signalTracksState(Permission.Microphone), 100);
      }
      const stopTrackProxy = new DDGProxy(this, MediaStreamTrack.prototype, "stop", {
        apply(target, thisArg, args) {
          handleTrackEnded(thisArg);
          return DDGReflect.apply(target, thisArg, args);
        }
      });
      stopTrackProxy.overload();
      const cloneTrackProxy = new DDGProxy(this, MediaStreamTrack.prototype, "clone", {
        apply(target, thisArg, args) {
          const clonedTrack = DDGReflect.apply(target, thisArg, args);
          if (clonedTrack && (videoTracks.has(thisArg) || audioTracks.has(thisArg))) {
            console.debug(`Media stream track ${thisArg.id} has been cloned to track ${clonedTrack.id}`);
            monitorTrack(clonedTrack);
          }
          return clonedTrack;
        }
      });
      cloneTrackProxy.overload();
      const trackEnabledPropertyDescriptor = Object.getOwnPropertyDescriptor(MediaStreamTrack.prototype, "enabled");
      this.defineProperty(MediaStreamTrack.prototype, "enabled", {
        // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
        configurable: trackEnabledPropertyDescriptor.configurable,
        // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
        enumerable: trackEnabledPropertyDescriptor.enumerable,
        get: function() {
          return trackEnabledPropertyDescriptor.get.bind(this)();
        },
        set: function() {
          const result = trackEnabledPropertyDescriptor.set.bind(this)(...arguments);
          if (videoTracks.has(this)) {
            signalVideoTracksState();
          } else if (audioTracks.has(this)) {
            signalAudioTracksState();
          }
          return result;
        }
      });
      const getTracksMethodNames = ["getTracks", "getAudioTracks", "getVideoTracks"];
      for (const methodName of getTracksMethodNames) {
        const getTracksProxy = new DDGProxy(this, MediaStream.prototype, methodName, {
          apply(target, thisArg, args) {
            const tracks = DDGReflect.apply(target, thisArg, args);
            if (userMediaStreams.has(thisArg)) {
              tracks.forEach(monitorTrack);
            }
            return tracks;
          }
        });
        getTracksProxy.overload();
      }
      const cloneMediaStreamProxy = new DDGProxy(this, MediaStream.prototype, "clone", {
        apply(target, thisArg, args) {
          const clonedStream = DDGReflect.apply(target, thisArg, args);
          if (userMediaStreams.has(thisArg)) {
            console.debug(`User stream ${thisArg.id} has been cloned to stream ${clonedStream.id}`);
            userMediaStreams.add(clonedStream);
          }
          return clonedStream;
        }
      });
      cloneMediaStreamProxy.overload();
      if (window.MediaDevices) {
        const getUserMediaProxy = new DDGProxy(this, MediaDevices.prototype, "getUserMedia", {
          apply(target, thisArg, args) {
            if (isFrameInsideFrame) {
              return Promise.reject(new DOMException("Permission denied"));
            }
            const videoRequested = args[0]?.video;
            const audioRequested = args[0]?.audio;
            if (videoRequested && (videoRequested.pan || videoRequested.tilt || videoRequested.zoom)) {
              return Promise.reject(new DOMException("Pan-tilt-zoom is not supported"));
            }
            return DDGReflect.apply(target, thisArg, args).then(function(stream) {
              console.debug(`User stream ${stream.id} has been acquired`);
              userMediaStreams.add(stream);
              if (videoRequested) {
                const newVideoTracks = stream.getVideoTracks();
                if (newVideoTracks?.length > 0) {
                  signalPermissionStatus(Permission.Camera, Status.Active);
                }
                newVideoTracks.forEach(monitorTrack);
              }
              if (audioRequested) {
                const newAudioTracks = stream.getAudioTracks();
                if (newAudioTracks?.length > 0) {
                  signalPermissionStatus(Permission.Microphone, Status.Active);
                }
                newAudioTracks.forEach(monitorTrack);
              }
              return stream;
            });
          }
        });
        getUserMediaProxy.overload();
      }
      function performAction(action, permission) {
        if (action && permission) {
          switch (action) {
            case "pause":
              pause(permission);
              break;
            case "resume":
              resume(permission);
              break;
            case "stop":
              stop(permission);
              break;
          }
        }
      }
      windowsInteropAddEventListener("message", function({ data: data2 }) {
        if (data2?.action && data2?.permission) {
          performAction(data2?.action, data2?.permission);
        }
      });
      const permissionsToDisable = [
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        { name: "Bluetooth", prototype: () => Bluetooth.prototype, method: "requestDevice", isPromise: true },
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        { name: "USB", prototype: () => USB.prototype, method: "requestDevice", isPromise: true },
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        { name: "Serial", prototype: () => Serial.prototype, method: "requestPort", isPromise: true },
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        { name: "HID", prototype: () => HID.prototype, method: "requestDevice", isPromise: true },
        { name: "Protocol handler", prototype: () => Navigator.prototype, method: "registerProtocolHandler", isPromise: false },
        { name: "MIDI", prototype: () => Navigator.prototype, method: "requestMIDIAccess", isPromise: true }
      ];
      for (const { name, prototype, method, isPromise } of permissionsToDisable) {
        try {
          const protoObj = prototype();
          if (!protoObj || !(method in protoObj)) continue;
          const proxy = new DDGProxy(this, protoObj, method, {
            apply() {
              if (isPromise) {
                return Promise.reject(new DOMException("Permission denied"));
              } else {
                throw new DOMException("Permission denied");
              }
            }
          });
          proxy.overload();
        } catch (error) {
          console.info(`Could not disable access to ${name} because of error`, error);
        }
      }
      const permissionsToDelete = [
        { name: "Idle detection", permission: "IdleDetector" },
        { name: "NFC", permission: "NDEFReader" },
        { name: "Orientation", permission: "ondeviceorientation" },
        { name: "Motion", permission: "ondevicemotion" }
      ];
      for (const { permission } of permissionsToDelete) {
        if (permission in window) {
          Reflect.deleteProperty(window, permission);
        }
      }
    }
  };

  // src/features/duck-player.js
  init_define_import_meta_trackerLookup();

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
        injectName: "windows",
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
    constructor(config) {
      /**
       * @type {ReCaptchaProviderConfig}
       */
      __privateAdd(this, _config);
      __privateSet(this, _config, config);
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
    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
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
  async function retry(fn, config = DEFAULT_RETRY_CONFIG) {
    let lastResult;
    const exceptions = [];
    for (let i = 0; i < config.maxAttempts; i++) {
      try {
        lastResult = await Promise.resolve(fn());
      } catch (e) {
        exceptions.push(e.toString());
      }
      if (lastResult && "success" in lastResult) break;
      if (i === config.maxAttempts - 1) break;
      await new Promise((resolve) => setTimeout(resolve, config.interval.ms));
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

  // src/features/breakage-reporting.js
  init_define_import_meta_trackerLookup();

  // src/features/breakage-reporting/utils.js
  init_define_import_meta_trackerLookup();
  function getJsPerformanceMetrics() {
    const paintResources = performance.getEntriesByType("paint");
    const firstPaint = paintResources.find((entry) => entry.name === "first-contentful-paint");
    return firstPaint ? [firstPaint.startTime] : [];
  }

  // src/features/breakage-reporting.js
  var BreakageReporting = class extends ContentFeature {
    init() {
      this.messaging.subscribe("getBreakageReportValues", () => {
        const jsPerformance = getJsPerformanceMetrics();
        const referrer = document.referrer;
        this.messaging.notify("breakageReportResult", {
          jsPerformance,
          referrer
        });
      });
    }
  };

  // src/features/message-bridge.js
  init_define_import_meta_trackerLookup();
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
      const { captured: captured2 } = this;
      function appendToken(eventName) {
        return `${eventName}-${args.messageSecret}`;
      }
      const reply = (incoming) => {
        if (!args.messageSecret) return this.log("ignoring because args.messageSecret was absent");
        const eventName = appendToken(incoming.name + "-" + incoming.id);
        const event = new captured2.CustomEvent(eventName, { detail: incoming });
        captured2.dispatchEvent(event);
      };
      const accept = (ClassType, callback) => {
        captured2.addEventListener(appendToken(ClassType.NAME), (e) => {
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
    installProxyFor(install, config, reply) {
      const { id, featureName } = install;
      if (this.proxies.has(featureName)) return this.log("ignoring `installProxyFor` because it exists", featureName);
      const allowed = this.getFeatureSettingEnabled(featureName);
      if (!allowed) {
        return this.log("not installing proxy, because", featureName, "was not enabled");
      }
      const ctx = { ...this.messaging.messagingContext, featureName };
      const messaging = new Messaging(ctx, config);
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

  // src/features/web-compat.js
  init_define_import_meta_trackerLookup();
  function windowSizingFix() {
    if (window.outerHeight !== 0 && window.outerWidth !== 0) {
      return;
    }
    window.outerHeight = window.innerHeight;
    window.outerWidth = window.innerWidth;
  }
  var MSG_WEB_SHARE = "webShare";
  var MSG_PERMISSIONS_QUERY = "permissionsQuery";
  var MSG_SCREEN_LOCK = "screenLock";
  var MSG_SCREEN_UNLOCK = "screenUnlock";
  function canShare(data2) {
    if (typeof data2 !== "object") return false;
    if (!("url" in data2) && !("title" in data2) && !("text" in data2)) return false;
    if ("files" in data2) return false;
    if ("title" in data2 && typeof data2.title !== "string") return false;
    if ("text" in data2 && typeof data2.text !== "string") return false;
    if ("url" in data2) {
      if (typeof data2.url !== "string") return false;
      try {
        const url = new URL2(data2.url, location.href);
        if (url.protocol !== "http:" && url.protocol !== "https:") return false;
      } catch (err) {
        return false;
      }
    }
    if (window !== window.top) return false;
    return true;
  }
  function cleanShareData(data2) {
    const dataToSend = {};
    for (const key of ["title", "text", "url"]) {
      if (key in data2) dataToSend[key] = data2[key];
    }
    if ("url" in data2) {
      dataToSend.url = new URL2(data2.url, location.href).href;
    }
    if ("url" in dataToSend && "text" in dataToSend) {
      dataToSend.text = `${dataToSend.text} ${dataToSend.url}`;
      delete dataToSend.url;
    }
    if (!("url" in dataToSend) && !("text" in dataToSend)) {
      dataToSend.text = "";
    }
    return dataToSend;
  }
  var _activeShareRequest, _activeScreenLockRequest;
  var WebCompat = class extends ContentFeature {
    constructor() {
      super(...arguments);
      /** @type {Promise<any> | null} */
      __privateAdd(this, _activeShareRequest, null);
      /** @type {Promise<any> | null} */
      __privateAdd(this, _activeScreenLockRequest, null);
    }
    init() {
      if (this.getFeatureSettingEnabled("windowSizing")) {
        windowSizingFix();
      }
      if (this.getFeatureSettingEnabled("navigatorCredentials")) {
        this.navigatorCredentialsFix();
      }
      if (this.getFeatureSettingEnabled("safariObject")) {
        this.safariObjectFix();
      }
      if (this.getFeatureSettingEnabled("messageHandlers")) {
        this.messageHandlersFix();
      }
      if (this.getFeatureSettingEnabled("notification")) {
        this.notificationFix();
      }
      if (this.getFeatureSettingEnabled("permissions")) {
        const settings = this.getFeatureSetting("permissions");
        this.permissionsFix(settings);
      }
      if (this.getFeatureSettingEnabled("cleanIframeValue")) {
        this.cleanIframeValue();
      }
      if (this.getFeatureSettingEnabled("mediaSession")) {
        this.mediaSessionFix();
      }
      if (this.getFeatureSettingEnabled("presentation")) {
        this.presentationFix();
      }
      if (this.getFeatureSettingEnabled("webShare")) {
        this.shimWebShare();
      }
      if (this.getFeatureSettingEnabled("viewportWidth")) {
        this.viewportWidthFix();
      }
      if (this.getFeatureSettingEnabled("screenLock")) {
        this.screenLockFix();
      }
      if (this.getFeatureSettingEnabled("modifyLocalStorage")) {
        this.modifyLocalStorage();
      }
      if (this.getFeatureSettingEnabled("modifyCookies")) {
        this.modifyCookies();
      }
      if (this.getFeatureSettingEnabled("disableDeviceEnumeration") || this.getFeatureSettingEnabled("disableDeviceEnumerationFrames")) {
        this.preventDeviceEnumeration();
      }
    }
    /** Shim Web Share API in Android WebView */
    shimWebShare() {
      if (typeof navigator.canShare === "function" || typeof navigator.share === "function") return;
      this.defineProperty(Navigator.prototype, "canShare", {
        configurable: true,
        enumerable: true,
        writable: true,
        value: canShare
      });
      this.defineProperty(Navigator.prototype, "share", {
        configurable: true,
        enumerable: true,
        writable: true,
        value: async (data2) => {
          if (!canShare(data2)) return Promise.reject(new TypeError("Invalid share data"));
          if (__privateGet(this, _activeShareRequest)) {
            return Promise.reject(new DOMException("Share already in progress", "InvalidStateError"));
          }
          if (!navigator.userActivation.isActive) {
            return Promise.reject(new DOMException("Share must be initiated by a user gesture", "InvalidStateError"));
          }
          const dataToSend = cleanShareData(data2);
          __privateSet(this, _activeShareRequest, this.request(MSG_WEB_SHARE, dataToSend));
          let resp;
          try {
            resp = await __privateGet(this, _activeShareRequest);
          } catch (err) {
            throw new DOMException(err.message, "DataError");
          } finally {
            __privateSet(this, _activeShareRequest, null);
          }
          if (resp.failure) {
            switch (resp.failure.name) {
              case "AbortError":
              case "NotAllowedError":
              case "DataError":
                throw new DOMException(resp.failure.message, resp.failure.name);
              default:
                throw new DOMException(resp.failure.message, "DataError");
            }
          }
        }
      });
    }
    /**
     * Notification fix for adding missing API for Android WebView.
     */
    notificationFix() {
      if (window.Notification) {
        return;
      }
      this.defineProperty(window, "Notification", {
        value: () => {
        },
        writable: true,
        configurable: true,
        enumerable: false
      });
      this.defineProperty(window.Notification, "requestPermission", {
        value: () => {
          return Promise.resolve("denied");
        },
        writable: true,
        configurable: true,
        enumerable: true
      });
      this.defineProperty(window.Notification, "permission", {
        get: () => "denied",
        configurable: true,
        enumerable: false
      });
      this.defineProperty(window.Notification, "maxActions", {
        get: () => 2,
        configurable: true,
        enumerable: true
      });
    }
    cleanIframeValue() {
      function cleanValueData(val) {
        const clone = Object.assign({}, val);
        const deleteKeys = ["iframeProto", "iframeData", "remap"];
        for (const key of deleteKeys) {
          if (key in clone) {
            delete clone[key];
          }
        }
        val.iframeData = clone;
        return val;
      }
      window.XMLHttpRequest.prototype.send = new Proxy(window.XMLHttpRequest.prototype.send, {
        apply(target, thisArg, args) {
          const body = args[0];
          const cleanKey = "bi_wvdp";
          if (body && typeof body === "string" && body.includes(cleanKey)) {
            const parts = body.split("&").map((part) => {
              return part.split("=");
            });
            if (parts.length > 0) {
              parts.forEach((part) => {
                if (part[0] === cleanKey) {
                  const val = JSON.parse(decodeURIComponent(part[1]));
                  part[1] = encodeURIComponent(JSON.stringify(cleanValueData(val)));
                }
              });
              args[0] = parts.map((part) => {
                return part.join("=");
              }).join("&");
            }
          }
          return Reflect.apply(target, thisArg, args);
        }
      });
    }
    /**
     * Adds missing permissions API for Android WebView.
     */
    permissionsFix(settings) {
      if (window.navigator.permissions) {
        return;
      }
      const permissions = {};
      class PermissionStatus extends EventTarget {
        constructor(name, state) {
          super();
          this.name = name;
          this.state = state;
          this.onchange = null;
        }
      }
      permissions.query = new Proxy(
        async (query) => {
          this.addDebugFlag();
          if (!query) {
            throw new TypeError("Failed to execute 'query' on 'Permissions': 1 argument required, but only 0 present.");
          }
          if (!query.name) {
            throw new TypeError(
              "Failed to execute 'query' on 'Permissions': Failed to read the 'name' property from 'PermissionDescriptor': Required member is undefined."
            );
          }
          if (!settings.supportedPermissions || !(query.name in settings.supportedPermissions)) {
            throw new TypeError(
              `Failed to execute 'query' on 'Permissions': Failed to read the 'name' property from 'PermissionDescriptor': The provided value '${query.name}' is not a valid enum value of type PermissionName.`
            );
          }
          const permSetting = settings.supportedPermissions[query.name];
          const returnName = permSetting.name || query.name;
          let returnStatus = settings.permissionResponse || "prompt";
          if (permSetting.native) {
            try {
              const response = await this.messaging.request(MSG_PERMISSIONS_QUERY, query);
              returnStatus = response.state || "prompt";
            } catch (err) {
            }
          }
          return Promise.resolve(new PermissionStatus(returnName, returnStatus));
        },
        {
          get(target, name) {
            return Reflect.get(target, name);
          }
        }
      );
      window.navigator.permissions = permissions;
    }
    /**
     * Fixes screen lock/unlock APIs for Android WebView.
     */
    screenLockFix() {
      const validOrientations = [
        "any",
        "natural",
        "landscape",
        "portrait",
        "portrait-primary",
        "portrait-secondary",
        "landscape-primary",
        "landscape-secondary",
        "unsupported"
      ];
      this.wrapProperty(globalThis.ScreenOrientation.prototype, "lock", {
        value: async (requestedOrientation) => {
          if (!requestedOrientation) {
            return Promise.reject(
              new TypeError("Failed to execute 'lock' on 'ScreenOrientation': 1 argument required, but only 0 present.")
            );
          }
          if (!validOrientations.includes(requestedOrientation)) {
            return Promise.reject(
              new TypeError(
                `Failed to execute 'lock' on 'ScreenOrientation': The provided value '${requestedOrientation}' is not a valid enum value of type OrientationLockType.`
              )
            );
          }
          if (__privateGet(this, _activeScreenLockRequest)) {
            return Promise.reject(new DOMException("Screen lock already in progress", "AbortError"));
          }
          __privateSet(this, _activeScreenLockRequest, this.messaging.request(MSG_SCREEN_LOCK, { orientation: requestedOrientation }));
          let resp;
          try {
            resp = await __privateGet(this, _activeScreenLockRequest);
          } catch (err) {
            throw new DOMException(err.message, "DataError");
          } finally {
            __privateSet(this, _activeScreenLockRequest, null);
          }
          if (resp.failure) {
            switch (resp.failure.name) {
              case "TypeError":
                return Promise.reject(new TypeError(resp.failure.message));
              case "InvalidStateError":
                return Promise.reject(new DOMException(resp.failure.message, resp.failure.name));
              default:
                return Promise.reject(new DOMException(resp.failure.message, "DataError"));
            }
          }
          return Promise.resolve();
        }
      });
      this.wrapProperty(globalThis.ScreenOrientation.prototype, "unlock", {
        value: () => {
          this.messaging.request(MSG_SCREEN_UNLOCK, {});
        }
      });
    }
    /**
     * Add missing navigator.credentials API
     */
    navigatorCredentialsFix() {
      try {
        if ("credentials" in navigator && "get" in navigator.credentials) {
          return;
        }
        const value = {
          get() {
            return Promise.reject(new Error());
          }
        };
        this.defineProperty(Navigator.prototype, "credentials", {
          value,
          configurable: true,
          enumerable: true,
          writable: true
        });
      } catch {
      }
    }
    safariObjectFix() {
      try {
        if (window.safari) {
          return;
        }
        this.defineProperty(window, "safari", {
          value: {},
          writable: true,
          configurable: true,
          enumerable: true
        });
        this.defineProperty(window.safari, "pushNotification", {
          value: {},
          configurable: true,
          enumerable: true
        });
        this.defineProperty(window.safari.pushNotification, "toString", {
          value: () => {
            return "[object SafariRemoteNotification]";
          },
          configurable: true,
          enumerable: true
        });
        class SafariRemoteNotificationPermission {
          constructor() {
            this.deviceToken = null;
            this.permission = "denied";
          }
        }
        this.defineProperty(window.safari.pushNotification, "permission", {
          value: () => {
            return new SafariRemoteNotificationPermission();
          },
          configurable: true,
          enumerable: true
        });
        this.defineProperty(window.safari.pushNotification, "requestPermission", {
          value: (_name, _domain, _options, callback) => {
            if (typeof callback === "function") {
              callback(new SafariRemoteNotificationPermission());
              return;
            }
            const reason = "Invalid 'callback' value passed to safari.pushNotification.requestPermission(). Expected a function.";
            throw new Error(reason);
          },
          configurable: true,
          enumerable: true
        });
      } catch {
      }
    }
    mediaSessionFix() {
      try {
        if (window.navigator.mediaSession && this.injectName !== "integration") {
          return;
        }
        class MyMediaSession {
          constructor() {
            __publicField(this, "metadata", null);
            /** @type {MediaSession['playbackState']} */
            __publicField(this, "playbackState", "none");
          }
          setActionHandler() {
          }
          setCameraActive() {
          }
          setMicrophoneActive() {
          }
          setPositionState() {
          }
        }
        this.shimInterface("MediaSession", MyMediaSession, {
          disallowConstructor: true,
          allowConstructorCall: false,
          wrapToString: true
        });
        this.shimProperty(Navigator.prototype, "mediaSession", new MyMediaSession(), true);
        this.shimInterface(
          "MediaMetadata",
          class {
            constructor(metadata = {}) {
              this.title = metadata.title;
              this.artist = metadata.artist;
              this.album = metadata.album;
              this.artwork = metadata.artwork;
            }
          },
          {
            disallowConstructor: false,
            allowConstructorCall: false,
            wrapToString: true
          }
        );
      } catch {
      }
    }
    presentationFix() {
      try {
        if (window.navigator.presentation && this.injectName !== "integration") {
          return;
        }
        const MyPresentation = class {
          get defaultRequest() {
            return null;
          }
          get receiver() {
            return null;
          }
        };
        this.shimInterface("Presentation", MyPresentation, {
          disallowConstructor: true,
          allowConstructorCall: false,
          wrapToString: true
        });
        this.shimInterface(
          // @ts-expect-error Presentation API is still experimental, TS types are missing
          "PresentationAvailability",
          class {
            // class definition is empty because there's no way to get an instance of it anyways
          },
          {
            disallowConstructor: true,
            allowConstructorCall: false,
            wrapToString: true
          }
        );
        this.shimInterface(
          // @ts-expect-error Presentation API is still experimental, TS types are missing
          "PresentationRequest",
          class {
            // class definition is empty because there's no way to get an instance of it anyways
          },
          {
            disallowConstructor: true,
            allowConstructorCall: false,
            wrapToString: true
          }
        );
        this.shimProperty(Navigator.prototype, "presentation", new MyPresentation(), true);
      } catch {
      }
    }
    /**
     * Support for modifying localStorage entries
     */
    modifyLocalStorage() {
      const settings = this.getFeatureSetting("modifyLocalStorage");
      if (!settings || !settings.changes) return;
      settings.changes.forEach((change) => {
        if (change.action === "delete") {
          localStorage.removeItem(change.key);
        }
      });
    }
    /**
     * Support for modifying cookies
     */
    modifyCookies() {
      const settings = this.getFeatureSetting("modifyCookies");
      if (!settings || !settings.changes) return;
      settings.changes.forEach((change) => {
        if (change.action === "delete") {
          const pathValue = change.path ? `; path=${change.path}` : "";
          const domainValue = change.domain ? `; domain=${change.domain}` : "";
          document.cookie = `${change.key}=; expires=Thu, 01 Jan 1970 00:00:00 GMT${pathValue}${domainValue}`;
        }
      });
    }
    /**
     * Support for proxying `window.webkit.messageHandlers`
     */
    messageHandlersFix() {
      const settings = this.getFeatureSetting("messageHandlers");
      if (!globalThis.webkit?.messageHandlers) return;
      if (!settings) return;
      const proxy = new Proxy(globalThis.webkit.messageHandlers, {
        get(target, messageName, receiver) {
          const handlerName = String(messageName);
          if (settings.handlerStrategies.reflect.includes(handlerName)) {
            return Reflect.get(target, messageName, receiver);
          }
          if (settings.handlerStrategies.undefined.includes(handlerName)) {
            return void 0;
          }
          if (settings.handlerStrategies.polyfill.includes("*") || settings.handlerStrategies.polyfill.includes(handlerName)) {
            return {
              postMessage() {
                return Promise.resolve({});
              }
            };
          }
        }
      });
      globalThis.webkit = {
        ...globalThis.webkit,
        messageHandlers: proxy
      };
    }
    viewportWidthFix() {
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => this.viewportWidthFixInner());
      } else {
        this.viewportWidthFixInner();
      }
    }
    /**
     * create or update a viewport tag with the given content
     * @param {HTMLMetaElement|null} viewportTag
     * @param {string} forcedValue
     */
    forceViewportTag(viewportTag, forcedValue) {
      const viewportTagExists = Boolean(viewportTag);
      if (!viewportTag) {
        viewportTag = document.createElement("meta");
        viewportTag.setAttribute("name", "viewport");
      }
      viewportTag.setAttribute("content", forcedValue);
      if (!viewportTagExists) {
        document.head.appendChild(viewportTag);
      }
    }
    viewportWidthFixInner() {
      const viewportTags = document.querySelectorAll("meta[name=viewport i]");
      const viewportTag = viewportTags.length === 0 ? null : viewportTags[viewportTags.length - 1];
      const viewportContent = viewportTag?.getAttribute("content") || "";
      const viewportContentParts = viewportContent ? viewportContent.split(/,|;/) : [];
      const parsedViewportContent = viewportContentParts.map((part) => {
        const [key, value] = part.split("=").map((p) => p.trim().toLowerCase());
        return [key, value];
      });
      const { forcedDesktopValue, forcedMobileValue } = this.getFeatureSetting("viewportWidth");
      if (typeof forcedDesktopValue === "string" && this.desktopModeEnabled) {
        this.forceViewportTag(viewportTag, forcedDesktopValue);
        return;
      } else if (typeof forcedMobileValue === "string" && !this.desktopModeEnabled) {
        this.forceViewportTag(viewportTag, forcedMobileValue);
        return;
      }
      const forcedValues = {};
      if (this.forcedZoomEnabled) {
        forcedValues["initial-scale"] = 1;
        forcedValues["user-scalable"] = "yes";
        forcedValues["maximum-scale"] = 10;
      }
      if (this.getFeatureSettingEnabled("plainTextViewPort") && document.contentType === "text/plain") {
        forcedValues.width = "device-width";
        forcedValues["initial-scale"] = 1;
      } else if (!viewportTag || this.desktopModeEnabled) {
        forcedValues.width = screen.width >= 1280 ? 1280 : 980;
        forcedValues["initial-scale"] = (screen.width / forcedValues.width).toFixed(3);
        forcedValues["user-scalable"] = "yes";
        const minimumScalePart = parsedViewportContent.find(([key]) => key === "minimum-scale");
        if (minimumScalePart) {
          forcedValues["minimum-scale"] = 0;
        }
      } else {
        const widthPart = parsedViewportContent.find(([key]) => key === "width");
        const initialScalePart = parsedViewportContent.find(([key]) => key === "initial-scale");
        if (!widthPart && initialScalePart) {
          const parsedInitialScale = parseFloat(initialScalePart[1]);
          if (parsedInitialScale !== 1) {
            forcedValues.width = "device-width";
          }
        }
      }
      const newContent = [];
      Object.keys(forcedValues).forEach((key) => {
        newContent.push(`${key}=${forcedValues[key]}`);
      });
      if (newContent.length > 0) {
        parsedViewportContent.forEach(([key], idx) => {
          if (!(key in forcedValues)) {
            newContent.push(viewportContentParts[idx].trim());
          }
        });
        this.forceViewportTag(viewportTag, newContent.join(", "));
      }
    }
    preventDeviceEnumeration() {
      if (!window.MediaDevices) {
        return;
      }
      let disableDeviceEnumeration = false;
      const isFrame = window.self !== window.top;
      if (isFrame) {
        disableDeviceEnumeration = this.getFeatureSettingEnabled("disableDeviceEnumerationFrames");
      } else {
        disableDeviceEnumeration = this.getFeatureSettingEnabled("disableDeviceEnumeration");
      }
      if (disableDeviceEnumeration) {
        const enumerateDevicesProxy = new DDGProxy(this, MediaDevices.prototype, "enumerateDevices", {
          apply() {
            return Promise.resolve([]);
          }
        });
        enumerateDevicesProxy.overload();
      }
    }
  };
  _activeShareRequest = new WeakMap();
  _activeScreenLockRequest = new WeakMap();
  var web_compat_default = WebCompat;

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
    ddg_feature_windowsPermissionUsage: WindowsPermissionUsage,
    ddg_feature_duckPlayer: DuckPlayerFeature,
    ddg_feature_brokerProtection: BrokerProtection,
    ddg_feature_breakageReporting: BreakageReporting,
    ddg_feature_messageBridge: message_bridge_default,
    ddg_feature_webCompat: web_compat_default
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
      trackerLookup: define_import_meta_trackerLookup_default,
      injectName: "windows"
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
    resolvedFeatures.forEach(({ featureInstance: featureInstance2, featureName }) => {
      if (!isFeatureBroken(initArgs, featureName) && featureInstance2.update) {
        featureInstance2.update(args);
      }
    });
  }

  // entry-points/windows.js
  function initCode() {
    const config = $CONTENT_SCOPE$;
    const userUnprotectedDomains = $USER_UNPROTECTED_DOMAINS$;
    const userPreferences = $USER_PREFERENCES$;
    const processedConfig = processConfig(config, userUnprotectedDomains, userPreferences, platformSpecificFeatures);
    processedConfig.messagingConfig = new WindowsMessagingConfig({
      methods: {
        // @ts-expect-error - Type 'unknown' is not assignable to type...
        postMessage: windowsInteropPostMessage,
        // @ts-expect-error - Type 'unknown' is not assignable to type...
        addEventListener: windowsInteropAddEventListener,
        // @ts-expect-error - Type 'unknown' is not assignable to type...
        removeEventListener: windowsInteropRemoveEventListener
      }
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
