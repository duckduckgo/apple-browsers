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
  var __esm = (fn, res) => function __init() {
    return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
  };
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
  function processConfig(data, userList, preferences, platformSpecificFeatures2 = []) {
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
    const enabledFeatures = computeEnabledFeatures(data, topLevelHostname, preferences.platform?.version, platformSpecificFeatures2);
    const isBroken = isUnprotectedDomain(topLevelHostname, data.unprotectedTemporary);
    output.site = Object.assign(site, {
      isBroken,
      allowlisted,
      enabledFeatures
    });
    output.featureSettings = parseFeatureSettings(data, enabledFeatures);
    output.bundledConfig = data;
    return output;
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

  // src/features/web-compat.js
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

  // ../messaging/lib/android-adsjs.js
  init_define_import_meta_trackerLookup();
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
          const data = (
            /** @type {MessageEvent} */
            event.data
          );
          if (typeof data === "string") {
            const parsedData = JSON.parse(data);
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
      } catch (e) {
        if (this.messagingContext.env === "development") {
          console.error("[Messaging] Failed to send notification:", e);
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

  // src/features/web-compat.js
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
  var MSG_DEVICE_ENUMERATION = "deviceEnumeration";
  function canShare(data) {
    if (typeof data !== "object") return false;
    data = Object.assign({}, data);
    for (const key of ["url", "title", "text", "files"]) {
      if (data[key] === void 0 || data[key] === null) {
        delete data[key];
      }
    }
    if (!("url" in data) && !("title" in data) && !("text" in data)) return false;
    if ("files" in data) {
      if (!(Array.isArray(data.files) || data.files instanceof FileList)) return false;
      if (data.files.length > 0) return false;
    }
    if ("title" in data && typeof data.title !== "string") return false;
    if ("text" in data && typeof data.text !== "string") return false;
    if ("url" in data) {
      if (typeof data.url !== "string") return false;
      try {
        const url = new URL2(data.url, location.href);
        if (url.protocol !== "http:" && url.protocol !== "https:") return false;
      } catch (err) {
        return false;
      }
    }
    return true;
  }
  function cleanShareData(data) {
    const dataToSend = {};
    for (const key of ["title", "text", "url"]) {
      if (key in data) dataToSend[key] = data[key];
    }
    if ("url" in data) {
      dataToSend.url = new URL2(data.url, location.href).href;
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
      if (this.getFeatureSettingEnabled("disableDeviceEnumeration")) {
        this.preventDeviceEnumeration();
      }
      if (this.getFeatureSettingEnabled("enumerateDevices")) {
        this.deviceEnumerationFix();
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
        value: async (data) => {
          if (!canShare(data)) return Promise.reject(new TypeError("Invalid share data"));
          if (__privateGet(this, _activeShareRequest)) {
            return Promise.reject(new DOMException("Share already in progress", "InvalidStateError"));
          }
          if (!navigator.userActivation.isActive) {
            return Promise.reject(new DOMException("Share must be initiated by a user gesture", "InvalidStateError"));
          }
          const dataToSend = cleanShareData(data);
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
    /**
     * Prevents device enumeration by returning an empty array when enabled
     */
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
          /**
           * @returns {Promise<MediaDeviceInfo[]>}
           */
          apply() {
            return Promise.resolve([]);
          }
        });
        enumerateDevicesProxy.overload();
      }
    }
    /**
     * Creates a valid MediaDeviceInfo or InputDeviceInfo object that passes instanceof checks
     * @param {'videoinput' | 'audioinput' | 'audiooutput'} kind - The device kind
     * @returns {MediaDeviceInfo | InputDeviceInfo}
     */
    createMediaDeviceInfo(kind) {
      let deviceInfo;
      if (kind === "videoinput" || kind === "audioinput") {
        if (typeof InputDeviceInfo !== "undefined" && InputDeviceInfo.prototype) {
          deviceInfo = Object.create(InputDeviceInfo.prototype);
        } else {
          deviceInfo = Object.create(MediaDeviceInfo.prototype);
        }
      } else {
        deviceInfo = Object.create(MediaDeviceInfo.prototype);
      }
      Object.defineProperties(deviceInfo, {
        deviceId: {
          value: "default",
          writable: false,
          configurable: false,
          enumerable: true
        },
        kind: {
          value: kind,
          writable: false,
          configurable: false,
          enumerable: true
        },
        label: {
          value: "",
          writable: false,
          configurable: false,
          enumerable: true
        },
        groupId: {
          value: "default-group",
          writable: false,
          configurable: false,
          enumerable: true
        },
        toJSON: {
          value: function() {
            return {
              deviceId: this.deviceId,
              kind: this.kind,
              label: this.label,
              groupId: this.groupId
            };
          },
          writable: false,
          configurable: false,
          enumerable: true
        }
      });
      return deviceInfo;
    }
    /**
     * Fixes device enumeration to handle permission prompts gracefully
     */
    deviceEnumerationFix() {
      if (!window.MediaDevices) {
        return;
      }
      const enumerateDevicesProxy = new DDGProxy(this, MediaDevices.prototype, "enumerateDevices", {
        /**
         * @param {MediaDevices['enumerateDevices']} target
         * @param {MediaDevices} thisArg
         * @param {Parameters<MediaDevices['enumerateDevices']>} args
         * @returns {Promise<MediaDeviceInfo[]>}
         */
        apply: async (target, thisArg, args) => {
          try {
            const response = await this.messaging.request(MSG_DEVICE_ENUMERATION, {});
            if (response.willPrompt) {
              const devices = [];
              if (response.videoInput) {
                devices.push(this.createMediaDeviceInfo("videoinput"));
              }
              if (response.audioInput) {
                devices.push(this.createMediaDeviceInfo("audioinput"));
              }
              if (response.audioOutput) {
                devices.push(this.createMediaDeviceInfo("audiooutput"));
              }
              return Promise.resolve(devices);
            } else {
              return DDGReflect.apply(target, thisArg, args);
            }
          } catch (err) {
            return DDGReflect.apply(target, thisArg, args);
          }
        }
      });
      enumerateDevicesProxy.overload();
    }
  };
  _activeShareRequest = new WeakMap();
  _activeScreenLockRequest = new WeakMap();
  var web_compat_default = WebCompat;

  // src/features/duck-player-native.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/messages.js
  init_define_import_meta_trackerLookup();

  // src/features/duckplayer-native/constants.js
  init_define_import_meta_trackerLookup();
  var MSG_NAME_INITIAL_SETUP = "initialSetup";
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
      return this.messaging.request(MSG_NAME_INITIAL_SETUP);
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
  function createPolicy() {
    if (globalThis.trustedTypes) {
      return globalThis.trustedTypes?.createPolicy?.("ddg-default", { createHTML: (s) => s });
    }
    return {
      createHTML: (s) => s
    };
  }

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
  var DDGVideoThumbnailOverlay = _DDGVideoThumbnailOverlay;
  function showThumbnailOverlay(targetElement, environment, onClick) {
    const logger = new Logger({
      id: "THUMBNAIL_OVERLAY",
      shouldLog: () => environment.isTestMode()
    });
    DDGVideoThumbnailOverlay.register();
    const overlay = (
      /** @type {DDGVideoThumbnailOverlay} */
      document.createElement(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)
    );
    overlay.logger = logger;
    overlay.testMode = environment.isTestMode();
    overlay.href = environment.getPlayerPageHref();
    if (onClick) {
      overlay.addEventListener(DDGVideoThumbnailOverlay.OVERLAY_CLICKED, onClick);
    }
    targetElement.appendChild(overlay);
    return () => {
      document.querySelector(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)?.remove();
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
        injectName: "apple",
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

  // src/features/scriptlets.js
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/scriptlets/set-cookie.js
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/helpers/add-event-listener-utils.ts
  init_define_import_meta_trackerLookup();
  var validateType = (type) => {
    return typeof type !== "undefined";
  };
  var validateListener = (listener) => {
    return typeof listener !== "undefined" && (typeof listener === "function" || typeof listener === "object" && listener !== null && "handleEvent" in listener && typeof listener.handleEvent === "function");
  };
  var listenerToString = (listener) => {
    return typeof listener === "function" ? listener.toString() : listener.handleEvent.toString();
  };

  // src/features/Scriptlets/src/helpers/number-utils.ts
  init_define_import_meta_trackerLookup();
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
  };
  var nativeIsFinite = (num) => {
    const native = Number.isFinite || window.isFinite;
    return native(num);
  };
  var getNumberFromString = (rawString) => {
    const parsedDelay = parseInt(rawString, 10);
    const validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
    return validDelay;
  };
  function getRandomIntInclusive(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min + 1) + min);
  }

  // src/features/Scriptlets/src/helpers/array-utils.ts
  init_define_import_meta_trackerLookup();
  var nodeListToArray = (nodeList) => {
    const nodes = [];
    for (let i = 0; i < nodeList.length; i += 1) {
      nodes.push(nodeList[i]);
    }
    return nodes;
  };

  // src/features/Scriptlets/src/helpers/log-message.ts
  init_define_import_meta_trackerLookup();
  var logMessage = (source, message, forced = false, convertMessageToString = true) => {
    const {
      name,
      verbose
    } = source;
    if (!forced && !verbose) {
      return;
    }
    const nativeConsole = console.log;
    if (!convertMessageToString) {
      nativeConsole(`${name}:`, message);
      return;
    }
    nativeConsole(`${name}: ${message}`);
  };

  // src/features/Scriptlets/src/helpers/hit.ts
  init_define_import_meta_trackerLookup();
  var hit = (source) => {
    const ADGUARD_PREFIX = "[AdGuard]";
    if (!source.verbose) {
      return;
    }
    try {
      const trace = console.trace.bind(console);
      let label = `${ADGUARD_PREFIX} `;
      if (source.engine === "corelibs") {
        label += source.ruleText;
      } else {
        if (source.domainName) {
          label += `${source.domainName}`;
        }
        if (source.args) {
          label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
        } else {
          label += `#%#//scriptlet('${source.name}')`;
        }
      }
      if (trace) {
        trace(label);
      }
    } catch (e) {
    }
    if (typeof window.__debug === "function") {
      window.__debug(source);
    }
  };

  // src/features/Scriptlets/src/helpers/cookie-utils.ts
  init_define_import_meta_trackerLookup();
  var isValidCookiePath = (rawPath) => rawPath === "/" || rawPath === "none";
  var getCookiePath = (rawPath) => {
    if (rawPath === "/") {
      return "path=/";
    }
    return "";
  };
  var serializeCookie = (name, rawValue, rawPath, domainValue = "", shouldEncodeValue = true) => {
    const HOST_PREFIX = "__Host-";
    const SECURE_PREFIX = "__Secure-";
    const COOKIE_BREAKER = ";";
    if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
      return null;
    }
    const value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
    let resultCookie = `${name}=${value}`;
    if (name.startsWith(HOST_PREFIX)) {
      resultCookie += "; path=/; secure";
      if (domainValue) {
        console.debug(
          `Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`
        );
      }
      return resultCookie;
    }
    const path = getCookiePath(rawPath);
    if (path) {
      resultCookie += `; ${path}`;
    }
    if (name.startsWith(SECURE_PREFIX)) {
      resultCookie += "; secure";
    }
    if (domainValue) {
      resultCookie += `; domain=${domainValue}`;
    }
    return resultCookie;
  };
  var getLimitedCookieValue = (value) => {
    if (!value) {
      return null;
    }
    const allowedCookieValues = /* @__PURE__ */ new Set([
      "true",
      "t",
      "false",
      "f",
      "yes",
      "y",
      "no",
      "n",
      "ok",
      "on",
      "off",
      "accept",
      "accepted",
      "notaccepted",
      "reject",
      "rejected",
      "allow",
      "allowed",
      "disallow",
      "deny",
      "enable",
      "enabled",
      "disable",
      "disabled",
      "necessary",
      "required",
      "hide",
      "hidden",
      "essential",
      "nonessential",
      "checked",
      "unchecked",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedCookieValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        return null;
      }
      if (Math.abs(validValue) < 0 || Math.abs(validValue) > 32767) {
        return null;
      }
    } else {
      return null;
    }
    return validValue;
  };
  var isCookieSetWithValue = (cookieString, name, value) => {
    return cookieString.split(";").some((cookieStr) => {
      const pos = cookieStr.indexOf("=");
      if (pos === -1) {
        return false;
      }
      const cookieName = cookieStr.slice(0, pos).trim();
      const cookieValue = cookieStr.slice(pos + 1).trim();
      return name === cookieName && value === cookieValue;
    });
  };
  var getTrustedCookieOffsetMs = (offsetExpiresSec) => {
    const ONE_YEAR_EXPIRATION_KEYWORD = "1year";
    const ONE_DAY_EXPIRATION_KEYWORD = "1day";
    const MS_IN_SEC = 1e3;
    const SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    const SECONDS_IN_DAY = 24 * 60 * 60;
    let parsedSec;
    if (offsetExpiresSec === ONE_YEAR_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_YEAR;
    } else if (offsetExpiresSec === ONE_DAY_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_DAY;
    } else {
      parsedSec = Number.parseInt(offsetExpiresSec, 10);
      if (Number.isNaN(parsedSec)) {
        return null;
      }
    }
    return parsedSec * MS_IN_SEC;
  };

  // src/features/Scriptlets/src/helpers/noop-utils.ts
  init_define_import_meta_trackerLookup();
  var noopFunc = () => {
  };
  var noopCallbackFunc = () => noopFunc;
  var noopNull = () => null;
  var trueFunc = () => true;
  var falseFunc = () => false;
  var noopArray = () => [];
  var noopObject = () => ({});
  var throwFunc = () => {
    throw new Error();
  };
  var noopPromiseReject = () => Promise.reject();
  var noopPromiseResolve = (responseBody = "{}", responseUrl = "", responseType = "basic") => {
    if (typeof Response === "undefined") {
      return;
    }
    const response = new Response(responseBody, {
      headers: {
        "Content-Length": `${responseBody.length}`
      },
      status: 200,
      statusText: "OK"
    });
    if (responseType === "opaque") {
      Object.defineProperties(response, {
        body: { value: null },
        status: { value: 0 },
        ok: { value: false },
        statusText: { value: "" },
        url: { value: "" },
        type: { value: responseType }
      });
    } else {
      Object.defineProperties(response, {
        url: { value: responseUrl },
        type: { value: responseType }
      });
    }
    return Promise.resolve(response);
  };

  // src/features/Scriptlets/src/helpers/object-utils.ts
  init_define_import_meta_trackerLookup();
  var isEmptyObject = (obj) => {
    return Object.keys(obj).length === 0 && !obj.prototype;
  };
  function setPropertyAccess(object, property, descriptor) {
    const currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
    if (currentDescriptor && !currentDescriptor.configurable) {
      return false;
    }
    Object.defineProperty(object, property, descriptor);
    return true;
  }

  // src/features/Scriptlets/src/helpers/script-source-utils.ts
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/helpers/string-utils.ts
  init_define_import_meta_trackerLookup();
  var escapeRegExp = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  var toRegExp = (rawInput) => {
    const input = rawInput || "";
    const DEFAULT_VALUE = ".?";
    const FORWARD_SLASH = "/";
    if (input === "") {
      return new RegExp(DEFAULT_VALUE);
    }
    const delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
    const flagsPart = input.substring(delimiterIndex + 1);
    const regExpPart = input.substring(0, delimiterIndex + 1);
    const isValidRegExpFlag = (flag) => {
      if (!flag) {
        return false;
      }
      try {
        new RegExp("", flag);
        return true;
      } catch (ex) {
        return false;
      }
    };
    const getRegExpFlags = (regExpStr, flagsStr) => {
      if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
        return flagsStr;
      }
      return "";
    };
    const flags = getRegExpFlags(regExpPart, flagsPart);
    if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
      const regExpInput = flags ? regExpPart : input;
      return new RegExp(regExpInput.slice(1, -1), flags);
    }
    const escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(escaped);
  };
  var isValidStrPattern = (input) => {
    const FORWARD_SLASH = "/";
    let str = escapeRegExp(input);
    if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
      str = input.slice(1, -1);
    }
    let isValid;
    try {
      isValid = new RegExp(str);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
  };
  var substringAfter = (str, separator) => {
    if (!str) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? "" : str.substring(index + separator.length);
  };
  var substringBefore = (str, separator) => {
    if (!str || !separator) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? str : str.substring(0, index);
  };
  var isValidMatchStr = (match) => {
    const INVERT_MARKER = "!";
    let str = match;
    if (match?.startsWith(INVERT_MARKER)) {
      str = match.slice(1);
    }
    return isValidStrPattern(str);
  };
  var isValidMatchNumber = (match) => {
    const INVERT_MARKER = "!";
    let str = match;
    if (match?.startsWith(INVERT_MARKER)) {
      str = match.slice(1);
    }
    const num = parseFloat(str);
    return !nativeIsNaN(num) && nativeIsFinite(num);
  };
  var parseMatchArg = (match) => {
    const INVERT_MARKER = "!";
    const isInvertedMatch = match ? match?.startsWith(INVERT_MARKER) : false;
    const matchValue = isInvertedMatch ? match.slice(1) : match;
    const matchRegexp = toRegExp(matchValue);
    return { isInvertedMatch, matchRegexp, matchValue };
  };
  var parseDelayArg = (delay) => {
    const INVERT_MARKER = "!";
    const isInvertedDelayMatch = delay?.startsWith(INVERT_MARKER);
    const delayValue = isInvertedDelayMatch ? delay.slice(1) : delay;
    const parsedDelay = parseInt(delayValue, 10);
    const delayMatch = nativeIsNaN(parsedDelay) ? null : parsedDelay;
    return { isInvertedDelayMatch, delayMatch };
  };
  function objectToString(obj) {
    if (!obj || typeof obj !== "object") {
      return String(obj);
    }
    if (isEmptyObject(obj)) {
      return "{}";
    }
    return Object.entries(obj).map((pair) => {
      const key = pair[0];
      const value = pair[1];
      let recordValueStr = value;
      if (value instanceof Object) {
        recordValueStr = `{ ${objectToString(value)} }`;
      }
      return `${key}:"${recordValueStr}"`;
    }).join(" ");
  }
  function getRandomStrByLength(length) {
    let result = "";
    const characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=~";
    const charactersLength = characters.length;
    for (let i = 0; i < length; i += 1) {
      result += characters.charAt(Math.floor(Math.random() * charactersLength));
    }
    return result;
  }
  function generateRandomResponse(customResponseText) {
    let customResponse = customResponseText;
    if (customResponse === "true") {
      customResponse = Math.random().toString(36).slice(-10);
      return customResponse;
    }
    customResponse = customResponse.replace("length:", "");
    const rangeRegex = /^\d+-\d+$/;
    if (!rangeRegex.test(customResponse)) {
      return null;
    }
    let rangeMin = getNumberFromString(customResponse.split("-")[0]);
    let rangeMax = getNumberFromString(customResponse.split("-")[1]);
    if (!nativeIsFinite(rangeMin) || !nativeIsFinite(rangeMax)) {
      return null;
    }
    if (rangeMin > rangeMax) {
      const temp = rangeMin;
      rangeMin = rangeMax;
      rangeMax = temp;
    }
    const LENGTH_RANGE_LIMIT = 500 * 1e3;
    if (rangeMax > LENGTH_RANGE_LIMIT) {
      return null;
    }
    const length = getRandomIntInclusive(rangeMin, rangeMax);
    customResponse = getRandomStrByLength(length);
    return customResponse;
  }

  // src/features/Scriptlets/src/helpers/script-source-utils.ts
  var shouldAbortInlineOrInjectedScript = (stackMatch, stackTrace) => {
    const INLINE_SCRIPT_STRING = "inlineScript";
    const INJECTED_SCRIPT_STRING = "injectedScript";
    const INJECTED_SCRIPT_MARKER = "<anonymous>";
    const isInlineScript = (match) => match.includes(INLINE_SCRIPT_STRING);
    const isInjectedScript = (match) => match.includes(INJECTED_SCRIPT_STRING);
    if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
      return false;
    }
    let documentURL = window.location.href;
    const pos = documentURL.indexOf("#");
    if (pos !== -1) {
      documentURL = documentURL.slice(0, pos);
    }
    const stackSteps = stackTrace.split("\n").slice(2).map((line) => line.trim());
    const stackLines = stackSteps.map((line) => {
      let stack;
      const getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
      if (getStackTraceValues) {
        let stackURL = getStackTraceValues[2];
        const stackLine = getStackTraceValues[3];
        const stackCol = getStackTraceValues[4];
        if (stackURL?.startsWith("(")) {
          stackURL = stackURL.slice(1);
        }
        if (stackURL?.startsWith(INJECTED_SCRIPT_MARKER)) {
          stackURL = INJECTED_SCRIPT_STRING;
          let stackFunction = getStackTraceValues[1] !== void 0 ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
          if (stackFunction?.startsWith("at")) {
            stackFunction = stackFunction.slice(2).trim();
          }
          stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
        } else if (stackURL === documentURL) {
          stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
        } else {
          stack = `${stackURL}${stackLine}${stackCol}`.trim();
        }
      } else {
        stack = line;
      }
      return stack;
    });
    if (stackLines) {
      for (let index = 0; index < stackLines.length; index += 1) {
        if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
          return true;
        }
        if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
          return true;
        }
      }
    }
    return false;
  };

  // src/features/Scriptlets/src/helpers/prevent-utils.ts
  init_define_import_meta_trackerLookup();
  var isValidCallback = (callback) => {
    return callback instanceof Function || typeof callback === "string";
  };
  var parseRawDelay = (delay) => {
    const parsedDelay = Math.floor(parseInt(delay, 10));
    return typeof parsedDelay === "number" && !nativeIsNaN(parsedDelay) ? parsedDelay : delay;
  };
  var isPreventionNeeded = ({
    callback,
    delay,
    matchCallback,
    matchDelay
  }) => {
    if (!isValidCallback(callback)) {
      return false;
    }
    if (!isValidMatchStr(matchCallback) || matchDelay && !isValidMatchNumber(matchDelay)) {
      return false;
    }
    const { isInvertedMatch, matchRegexp } = parseMatchArg(matchCallback);
    const { isInvertedDelayMatch, delayMatch } = parseDelayArg(matchDelay);
    const parsedDelay = parseRawDelay(delay);
    let shouldPrevent = false;
    const callbackStr = String(callback);
    if (delayMatch === null) {
      shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch;
    } else if (!matchCallback) {
      shouldPrevent = parsedDelay === delayMatch !== isInvertedDelayMatch;
    } else {
      shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch && parsedDelay === delayMatch !== isInvertedDelayMatch;
    }
    return shouldPrevent;
  };

  // src/features/Scriptlets/src/helpers/prevent-window-open-utils.ts
  init_define_import_meta_trackerLookup();
  var handleOldReplacement = (replacement) => {
    let result;
    if (!replacement) {
      result = noopFunc;
    } else if (replacement === "trueFunc") {
      result = trueFunc;
    } else if (replacement.includes("=")) {
      const isProp = replacement.startsWith("{") && replacement.endsWith("}");
      if (isProp) {
        const propertyPart = replacement.slice(1, -1);
        const propertyName = substringBefore(propertyPart, "=");
        const propertyValue = substringAfter(propertyPart, "=");
        if (propertyValue === "noopFunc") {
          result = {};
          result[propertyName] = noopFunc;
        }
      }
    }
    return result;
  };
  var createDecoy = (args) => {
    let TagName;
    ((TagName2) => {
      TagName2["Object"] = "object";
      TagName2["Iframe"] = "iframe";
    })(TagName || (TagName = {}));
    let UrlPropNameOf;
    ((UrlPropNameOf2) => {
      UrlPropNameOf2["Object"] = "data";
      UrlPropNameOf2["Iframe"] = "src";
    })(UrlPropNameOf || (UrlPropNameOf = {}));
    const { replacement, url, delay } = args;
    let tag;
    if (replacement === "obj") {
      tag = "object" /* Object */;
    } else {
      tag = "iframe" /* Iframe */;
    }
    const decoy = document.createElement(tag);
    if (decoy instanceof HTMLObjectElement) {
      decoy["data" /* Object */] = url;
    } else if (decoy instanceof HTMLIFrameElement) {
      decoy["src" /* Iframe */] = url;
    }
    decoy.style.setProperty("height", "1px", "important");
    decoy.style.setProperty("position", "fixed", "important");
    decoy.style.setProperty("top", "-1px", "important");
    decoy.style.setProperty("width", "1px", "important");
    document.body.appendChild(decoy);
    setTimeout(() => decoy.remove(), delay * 1e3);
    return decoy;
  };
  var getPreventGetter = (nativeGetter) => {
    const preventGetter = (target, prop) => {
      if (prop && prop === "closed") {
        return false;
      }
      if (typeof nativeGetter === "function") {
        return noopFunc;
      }
      return prop && target[prop];
    };
    return preventGetter;
  };

  // src/features/Scriptlets/src/helpers/match-stack.ts
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/helpers/regexp-utils.ts
  init_define_import_meta_trackerLookup();
  var getNativeRegexpTest = () => {
    const descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
    const nativeRegexTest = descriptor?.value;
    if (descriptor && typeof descriptor.value === "function") {
      return nativeRegexTest;
    }
    throw new Error("RegExp.prototype.test is not a function");
  };
  var backupRegExpValues = () => {
    try {
      const arrayOfRegexpValues = [];
      for (let index = 1; index < 10; index += 1) {
        const value = `$${index}`;
        if (!RegExp[value]) {
          break;
        }
        arrayOfRegexpValues.push(RegExp[value]);
      }
      return arrayOfRegexpValues;
    } catch (error) {
      return [];
    }
  };
  var restoreRegExpValues = (array) => {
    if (!array.length) {
      return;
    }
    try {
      let stringPattern = "";
      if (array.length === 1) {
        stringPattern = `(${array[0]})`;
      } else {
        stringPattern = array.reduce((accumulator, currentValue, currentIndex) => {
          if (currentIndex === 1) {
            return `(${accumulator}),(${currentValue})`;
          }
          return `${accumulator},(${currentValue})`;
        });
      }
      const regExpGroup = new RegExp(stringPattern);
      array.toString().replace(regExpGroup, "");
    } catch (error) {
      const message = `Failed to restore RegExp values: ${error}`;
      console.log(message);
    }
  };

  // src/features/Scriptlets/src/helpers/match-stack.ts
  var matchStackTrace = (stackMatch, stackTrace) => {
    if (!stackMatch || stackMatch === "") {
      return true;
    }
    const regExpValues = backupRegExpValues();
    if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return true;
    }
    const stackRegexp = toRegExp(stackMatch);
    const refinedStackTrace = stackTrace.split("\n").slice(2).map((line) => line.trim()).join("\n");
    if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
      restoreRegExpValues(regExpValues);
    }
    return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
  };

  // src/features/Scriptlets/src/helpers/response-utils.ts
  init_define_import_meta_trackerLookup();
  var modifyResponse = (origResponse, replacement = {
    body: "{}"
  }) => {
    const headers = {};
    origResponse?.headers?.forEach((value, key) => {
      headers[key] = value;
    });
    const modifiedResponse = new Response(replacement.body, {
      status: origResponse.status,
      statusText: origResponse.statusText,
      headers
    });
    Object.defineProperties(modifiedResponse, {
      url: {
        value: origResponse.url
      },
      type: {
        value: replacement.type || origResponse.type
      }
    });
    return modifiedResponse;
  };

  // src/features/Scriptlets/src/helpers/request-utils.ts
  init_define_import_meta_trackerLookup();
  var getRequestProps = () => {
    return [
      "url",
      "method",
      "headers",
      "body",
      "credentials",
      "cache",
      "redirect",
      "referrer",
      "referrerPolicy",
      "integrity",
      "keepalive",
      "signal",
      "mode"
    ];
  };
  var getRequestData = (request) => {
    const requestInitOptions = getRequestProps();
    const entries = requestInitOptions.map((key) => {
      const value = request[key];
      return [key, value];
    });
    return Object.fromEntries(entries);
  };
  var getFetchData = (args, nativeRequestClone) => {
    const fetchPropsObj = {};
    const resource = args[0];
    let fetchUrl;
    let fetchInit;
    if (resource instanceof Request) {
      const realData = nativeRequestClone.call(resource);
      const requestData = getRequestData(realData);
      fetchUrl = requestData.url;
      fetchInit = requestData;
    } else {
      fetchUrl = resource;
      fetchInit = args[1];
    }
    fetchPropsObj.url = fetchUrl;
    if (fetchInit instanceof Object) {
      const props = Object.keys(fetchInit);
      props.forEach((prop) => {
        fetchPropsObj[prop] = fetchInit[prop];
      });
    }
    return fetchPropsObj;
  };
  var parseMatchProps = (propsToMatchStr) => {
    const PROPS_DIVIDER = " ";
    const PAIRS_MARKER = ":";
    const isRequestProp = (prop) => {
      return getRequestProps().includes(prop);
    };
    const propsObj = {};
    const props = propsToMatchStr.split(PROPS_DIVIDER);
    props.forEach((prop) => {
      const dividerInd = prop.indexOf(PAIRS_MARKER);
      const key = prop.slice(0, dividerInd);
      if (isRequestProp(key)) {
        const value = prop.slice(dividerInd + 1);
        propsObj[key] = value;
      } else {
        propsObj.url = prop;
      }
    });
    return propsObj;
  };
  var isValidParsedData = (data) => {
    return Object.values(data).every((value) => isValidStrPattern(value));
  };
  var getMatchPropsData = (data) => {
    const matchData = {};
    const dataKeys = Object.keys(data);
    dataKeys.forEach((key) => {
      matchData[key] = toRegExp(data[key]);
    });
    return matchData;
  };

  // src/features/Scriptlets/src/helpers/storage-utils.ts
  init_define_import_meta_trackerLookup();
  var setStorageItem = (source, storage, key, value) => {
    try {
      storage.setItem(key, value);
    } catch (e) {
      const message = `Unable to set storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };
  var removeStorageItem = (source, storage, key) => {
    try {
      if (key.startsWith("/") && (key.endsWith("/") || key.endsWith("/i")) && isValidStrPattern(key)) {
        const regExpKey = toRegExp(key);
        const storageKeys = Object.keys(storage);
        storageKeys.forEach((storageKey) => {
          if (regExpKey.test(storageKey)) {
            storage.removeItem(storageKey);
          }
        });
      } else {
        storage.removeItem(key);
      }
    } catch (e) {
      const message = `Unable to remove storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };
  var getLimitedStorageItemValue = (value) => {
    if (typeof value !== "string") {
      throw new Error("Invalid value");
    }
    const allowedStorageValues = /* @__PURE__ */ new Set([
      "undefined",
      "false",
      "true",
      "null",
      "",
      "yes",
      "no",
      "on",
      "off",
      "accept",
      "accepted",
      "reject",
      "rejected",
      "allowed",
      "denied",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedStorageValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (value === "emptyArr") {
      validValue = "[]";
    } else if (value === "emptyObj") {
      validValue = "{}";
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        throw new Error("Invalid value");
      }
      if (Math.abs(validValue) > 32767) {
        throw new Error("Invalid value");
      }
    } else if (value === "$remove$") {
      validValue = "$remove$";
    } else {
      throw new Error("Invalid value");
    }
    return validValue;
  };

  // src/features/Scriptlets/src/helpers/create-on-error-handler.ts
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/helpers/random-id.ts
  init_define_import_meta_trackerLookup();
  function randomId() {
    return Math.random().toString(36).slice(2, 9);
  }

  // src/features/Scriptlets/src/helpers/create-on-error-handler.ts
  function createOnErrorHandler(rid) {
    const nativeOnError = window.onerror;
    return function onError(error, ...args) {
      if (typeof error === "string" && error.includes(rid)) {
        return true;
      }
      if (nativeOnError instanceof Function) {
        return nativeOnError.apply(window, [error, ...args]);
      }
      return false;
    };
  }

  // src/features/Scriptlets/src/helpers/get-descriptor-addon.ts
  init_define_import_meta_trackerLookup();
  function getDescriptorAddon() {
    return {
      isAbortingSuspended: false,
      isolateCallback(cb, ...args) {
        this.isAbortingSuspended = true;
        try {
          const result = cb(...args);
          this.isAbortingSuspended = false;
          return result;
        } catch {
          const rid = randomId();
          this.isAbortingSuspended = false;
          throw new ReferenceError(rid);
        }
      }
    };
  }

  // src/features/Scriptlets/src/helpers/get-property-in-chain.ts
  init_define_import_meta_trackerLookup();
  function getPropertyInChain(base, chain) {
    const pos = chain.indexOf(".");
    if (pos === -1) {
      return { base, prop: chain };
    }
    const prop = chain.slice(0, pos);
    if (base === null) {
      return { base, prop, chain };
    }
    const nextBase = base[prop];
    chain = chain.slice(pos + 1);
    if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
      return { base, prop, chain };
    }
    if (nextBase === null) {
      return { base, prop, chain };
    }
    if (nextBase !== void 0) {
      return getPropertyInChain(nextBase, chain);
    }
    Object.defineProperty(base, prop, { configurable: true });
    return { base, prop, chain };
  }

  // src/features/Scriptlets/src/helpers/match-request-props.ts
  init_define_import_meta_trackerLookup();
  var matchRequestProps = (source, propsToMatch, requestData) => {
    if (propsToMatch === "" || propsToMatch === "*") {
      return true;
    }
    let isMatched;
    const parsedData = parseMatchProps(propsToMatch);
    if (!isValidParsedData(parsedData)) {
      logMessage(source, `Invalid parameter: ${propsToMatch}`);
      isMatched = false;
    } else {
      const matchData = getMatchPropsData(parsedData);
      const matchKeys = Object.keys(matchData);
      isMatched = matchKeys.every((matchKey) => {
        const matchValue = matchData[matchKey];
        const dataValue = requestData[matchKey];
        return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && matchValue?.test(dataValue);
      });
    }
    return isMatched;
  };

  // src/features/Scriptlets/src/helpers/observer.ts
  init_define_import_meta_trackerLookup();
  var getAddedNodes = (mutations) => {
    const nodes = [];
    for (let i = 0; i < mutations.length; i += 1) {
      const { addedNodes } = mutations[i];
      for (let j2 = 0; j2 < addedNodes.length; j2 += 1) {
        nodes.push(addedNodes[j2]);
      }
    }
    return nodes;
  };
  var observeDocumentWithTimeout = (callback, options = { subtree: true, childList: true }, timeout = 1e4) => {
    const documentObserver = new MutationObserver((mutations, observer) => {
      observer.disconnect();
      callback(mutations, observer);
      observer.observe(document.documentElement, options);
    });
    documentObserver.observe(document.documentElement, options);
    if (typeof timeout === "number") {
      setTimeout(() => documentObserver.disconnect(), timeout);
    }
  };

  // src/features/Scriptlets/src/helpers/parse-keyword-value.ts
  init_define_import_meta_trackerLookup();
  var parseKeywordValue = (rawValue) => {
    const NOW_VALUE_KEYWORD = "$now$";
    const CURRENT_DATE_KEYWORD = "$currentDate$";
    const CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
    let parsedValue = rawValue;
    if (rawValue === NOW_VALUE_KEYWORD) {
      parsedValue = Date.now().toString();
    } else if (rawValue === CURRENT_DATE_KEYWORD) {
      parsedValue = Date();
    } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
      parsedValue = (/* @__PURE__ */ new Date()).toISOString();
    }
    return parsedValue;
  };

  // src/features/Scriptlets/src/helpers/node-text-utils.ts
  init_define_import_meta_trackerLookup();

  // src/features/Scriptlets/src/helpers/trusted-types-utils.ts
  init_define_import_meta_trackerLookup();
  var getTrustedTypesApi = (source) => {
    const policyApi = source?.api?.policy;
    if (policyApi) {
      return policyApi;
    }
    const POLICY_NAME = "AGPolicy";
    const trustedTypesWindow = window;
    const trustedTypes = trustedTypesWindow.trustedTypes;
    const isSupported = !!trustedTypes;
    const TrustedTypeEnum = {
      HTML: "TrustedHTML",
      Script: "TrustedScript",
      ScriptURL: "TrustedScriptURL"
    };
    if (!isSupported) {
      return {
        name: POLICY_NAME,
        isSupported,
        TrustedType: TrustedTypeEnum,
        createHTML: (input) => input,
        createScript: (input) => input,
        createScriptURL: (input) => input,
        create: (type, input) => input,
        getAttributeType: () => null,
        convertAttributeToTrusted: (tagName, attribute, value) => value,
        getPropertyType: () => null,
        convertPropertyToTrusted: (tagName, property, value) => value,
        isHTML: () => false,
        isScript: () => false,
        isScriptURL: () => false
      };
    }
    const policy = trustedTypes.createPolicy(POLICY_NAME, {
      createHTML: (input) => input,
      createScript: (input) => input,
      createScriptURL: (input) => input
    });
    const createHTML = (input) => policy.createHTML(input);
    const createScript = (input) => policy.createScript(input);
    const createScriptURL = (input) => policy.createScriptURL(input);
    const create = (type, input) => {
      switch (type) {
        case TrustedTypeEnum.HTML:
          return createHTML(input);
        case TrustedTypeEnum.Script:
          return createScript(input);
        case TrustedTypeEnum.ScriptURL:
          return createScriptURL(input);
        default:
          return input;
      }
    };
    const getAttributeType = trustedTypes.getAttributeType.bind(trustedTypes);
    const convertAttributeToTrusted = (tagName, attribute, value, elementNS, attrNS) => {
      const type = getAttributeType(tagName, attribute, elementNS, attrNS);
      return type ? create(type, value) : value;
    };
    const getPropertyType = trustedTypes.getPropertyType.bind(trustedTypes);
    const convertPropertyToTrusted = (tagName, property, value, elementNS) => {
      const type = getPropertyType(tagName, property, elementNS);
      return type ? create(type, value) : value;
    };
    const isHTML = trustedTypes.isHTML.bind(trustedTypes);
    const isScript = trustedTypes.isScript.bind(trustedTypes);
    const isScriptURL = trustedTypes.isScriptURL.bind(trustedTypes);
    return {
      name: POLICY_NAME,
      isSupported,
      TrustedType: TrustedTypeEnum,
      createHTML,
      createScript,
      createScriptURL,
      create,
      getAttributeType,
      convertAttributeToTrusted,
      getPropertyType,
      convertPropertyToTrusted,
      isHTML,
      isScript,
      isScriptURL
    };
  };

  // src/features/Scriptlets/src/helpers/node-text-utils.ts
  var handleExistingNodes = (selector, handler, parentSelector) => {
    const processNodes = (parent) => {
      if (selector === "#text") {
        const textNodes = nodeListToArray(parent.childNodes).filter((node) => node.nodeType === Node.TEXT_NODE);
        handler(textNodes);
      } else {
        const nodes = nodeListToArray(parent.querySelectorAll(selector));
        handler(nodes);
      }
    };
    const parents = parentSelector ? document.querySelectorAll(parentSelector) : [document];
    parents.forEach((parent) => processNodes(parent));
  };
  var handleMutations = (mutations, handler, selector, parentSelector) => {
    const addedNodes = getAddedNodes(mutations);
    if (selector && parentSelector) {
      addedNodes.forEach(() => {
        handleExistingNodes(selector, handler, parentSelector);
      });
    } else {
      handler(addedNodes);
    }
  };
  var isTargetNode = (node, nodeNameMatch, textContentMatch) => {
    const { nodeName, textContent } = node;
    const nodeNameLowerCase = nodeName.toLowerCase();
    return textContent !== null && textContent !== "" && (nodeNameMatch instanceof RegExp ? nodeNameMatch.test(nodeNameLowerCase) : nodeNameMatch === nodeNameLowerCase) && (textContentMatch instanceof RegExp ? textContentMatch.test(textContent) : textContent.includes(textContentMatch));
  };
  var replaceNodeText = (source, node, pattern, replacement) => {
    const { textContent } = node;
    if (textContent) {
      let modifiedText = textContent.replace(pattern, replacement);
      if (node.nodeName === "SCRIPT") {
        const trustedTypesApi = getTrustedTypesApi(source);
        modifiedText = trustedTypesApi.createScript(modifiedText);
      }
      node.textContent = modifiedText;
      hit(source);
    }
  };
  var parseNodeTextParams = (nodeName, textMatch, pattern = null) => {
    const REGEXP_START_MARKER = "/";
    const isStringNameMatch = !(nodeName.startsWith(REGEXP_START_MARKER) && nodeName.endsWith(REGEXP_START_MARKER));
    const selector = isStringNameMatch ? nodeName : "*";
    const nodeNameMatch = isStringNameMatch ? nodeName : toRegExp(nodeName);
    const textContentMatch = !textMatch.startsWith(REGEXP_START_MARKER) ? textMatch : toRegExp(textMatch);
    let patternMatch;
    if (pattern) {
      patternMatch = !pattern.startsWith(REGEXP_START_MARKER) ? pattern : toRegExp(pattern);
    }
    return {
      selector,
      nodeNameMatch,
      textContentMatch,
      patternMatch
    };
  };

  // src/features/Scriptlets/src/scriptlets/set-cookie.js
  function setCookie(source, name, value, path = "/", domain = "") {
    const validValue = getLimitedCookieValue(value);
    if (validValue === null) {
      logMessage(source, `Invalid cookie value: '${validValue}'`);
      return;
    }
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    const cookieToSet = serializeCookie(name, validValue, path, domain);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    hit(source);
    document.cookie = cookieToSet;
  }
  var setCookieNames = [
    "set-cookie",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-cookie.js",
    "ubo-set-cookie.js",
    "ubo-set-cookie"
  ];
  setCookie.primaryName = setCookieNames[0];
  setCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    getLimitedCookieValue,
    serializeCookie,
    isValidCookiePath,
    getCookiePath
  ];

  // src/features/Scriptlets/src/scriptlets/trusted-set-cookie.js
  init_define_import_meta_trackerLookup();
  function trustedSetCookie(source, name, value, offsetExpiresSec = "", path = "/", domain = "") {
    if (typeof name === "undefined") {
      logMessage(source, "Cookie name should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Cookie value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    let cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    if (offsetExpiresSec) {
      const parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
      if (!parsedOffsetMs) {
        logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
        return;
      }
      const expires = Date.now() + parsedOffsetMs;
      cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
    }
    document.cookie = cookieToSet;
    hit(source);
  }
  var trustedSetCookieNames = [
    "trusted-set-cookie"
    // trusted scriptlets support no aliases
  ];
  trustedSetCookie.primaryName = trustedSetCookieNames[0];
  trustedSetCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    serializeCookie,
    isValidCookiePath,
    getTrustedCookieOffsetMs,
    parseKeywordValue,
    getCookiePath
  ];

  // src/features/Scriptlets/src/scriptlets/set-cookie-reload.js
  init_define_import_meta_trackerLookup();
  function setCookieReload(source, name, value, path = "/", domain = "") {
    if (isCookieSetWithValue(document.cookie, name, value)) {
      return;
    }
    const validValue = getLimitedCookieValue(value);
    if (validValue === null) {
      logMessage(source, `Invalid cookie value: '${value}'`);
      return;
    }
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    const cookieToSet = serializeCookie(name, validValue, path, domain);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    document.cookie = cookieToSet;
    hit(source);
    if (isCookieSetWithValue(document.cookie, name, value)) {
      window.location.reload();
    }
  }
  var setCookieReloadNames = [
    "set-cookie-reload",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-cookie-reload.js",
    "ubo-set-cookie-reload.js",
    "ubo-set-cookie-reload"
  ];
  setCookieReload.primaryName = setCookieReloadNames[0];
  setCookieReload.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    getLimitedCookieValue,
    serializeCookie,
    isValidCookiePath,
    getCookiePath
  ];

  // src/features/Scriptlets/src/scriptlets/remove-cookie.js
  init_define_import_meta_trackerLookup();
  function removeCookie(source, match) {
    const matchRegexp = toRegExp(match);
    const removeCookieFromHost = (cookieName, hostName) => {
      const cookieSpec = `${cookieName}=`;
      const domain1 = `; domain=${hostName}`;
      const domain2 = `; domain=.${hostName}`;
      const path = "; path=/";
      const expiration = "; expires=Thu, 01 Jan 1970 00:00:00 GMT";
      document.cookie = cookieSpec + expiration;
      document.cookie = cookieSpec + domain1 + expiration;
      document.cookie = cookieSpec + domain2 + expiration;
      document.cookie = cookieSpec + path + expiration;
      document.cookie = cookieSpec + domain1 + path + expiration;
      document.cookie = cookieSpec + domain2 + path + expiration;
      hit(source);
    };
    const rmCookie = () => {
      document.cookie.split(";").forEach((cookieStr) => {
        const pos = cookieStr.indexOf("=");
        if (pos === -1) {
          return;
        }
        const cookieName = cookieStr.slice(0, pos).trim();
        if (!matchRegexp.test(cookieName)) {
          return;
        }
        const hostParts = document.location.hostname.split(".");
        for (let i = 0; i <= hostParts.length - 1; i += 1) {
          const hostName = hostParts.slice(i).join(".");
          if (hostName) {
            removeCookieFromHost(cookieName, hostName);
          }
        }
      });
    };
    rmCookie();
    window.addEventListener("beforeunload", rmCookie);
  }
  var removeCookieNames = [
    "remove-cookie",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "cookie-remover.js",
    "ubo-cookie-remover.js",
    "ubo-cookie-remover",
    "remove-cookie.js",
    "ubo-remove-cookie.js",
    "ubo-remove-cookie",
    "abp-cookie-remover"
  ];
  removeCookie.primaryName = removeCookieNames[0];
  removeCookie.injections = [toRegExp, hit];

  // src/features/Scriptlets/src/scriptlets/set-constant.js
  init_define_import_meta_trackerLookup();
  function setConstant(source, property, value, stack = "", valueWrapper = "", setProxyTrap = false) {
    const uboAliases = [
      "set-constant.js",
      "ubo-set-constant.js",
      "set.js",
      "ubo-set.js",
      "ubo-set-constant",
      "ubo-set"
    ];
    if (uboAliases.includes(source.name)) {
      if (stack.length !== 1 && !getNumberFromString(stack)) {
        valueWrapper = stack;
      }
      stack = void 0;
    }
    if (!property || !matchStackTrace(stack, new Error().stack)) {
      return;
    }
    let isProxyTrapSet = false;
    const emptyArr = noopArray();
    const emptyObj = noopObject();
    let constantValue;
    if (value === "undefined") {
      constantValue = void 0;
    } else if (value === "false") {
      constantValue = false;
    } else if (value === "true") {
      constantValue = true;
    } else if (value === "null") {
      constantValue = null;
    } else if (value === "emptyArr") {
      constantValue = emptyArr;
    } else if (value === "emptyObj") {
      constantValue = emptyObj;
    } else if (value === "noopFunc") {
      constantValue = noopFunc;
    } else if (value === "noopCallbackFunc") {
      constantValue = noopCallbackFunc;
    } else if (value === "trueFunc") {
      constantValue = trueFunc;
    } else if (value === "falseFunc") {
      constantValue = falseFunc;
    } else if (value === "throwFunc") {
      constantValue = throwFunc;
    } else if (value === "noopPromiseResolve") {
      constantValue = noopPromiseResolve;
    } else if (value === "noopPromiseReject") {
      constantValue = noopPromiseReject;
    } else if (/^\d+$/.test(value)) {
      constantValue = parseFloat(value);
      if (nativeIsNaN(constantValue)) {
        return;
      }
      if (Math.abs(constantValue) > 32767) {
        return;
      }
    } else if (value === "-1") {
      constantValue = -1;
    } else if (value === "") {
      constantValue = "";
    } else if (value === "yes") {
      constantValue = "yes";
    } else if (value === "no") {
      constantValue = "no";
    } else {
      return;
    }
    const valueWrapperNames = [
      "asFunction",
      "asCallback",
      "asResolved",
      "asRejected"
    ];
    if (valueWrapperNames.includes(valueWrapper)) {
      const valueWrappersMap = {
        asFunction(v2) {
          return () => v2;
        },
        asCallback(v2) {
          return () => (() => v2);
        },
        asResolved(v2) {
          return Promise.resolve(v2);
        },
        asRejected(v2) {
          return Promise.reject(v2);
        }
      };
      constantValue = valueWrappersMap[valueWrapper](constantValue);
    }
    let canceled = false;
    const mustCancel = (value2) => {
      if (canceled) {
        return canceled;
      }
      canceled = value2 !== void 0 && constantValue !== void 0 && typeof value2 !== typeof constantValue && value2 !== null;
      return canceled;
    };
    const trapProp = (base, prop, configurable, handler) => {
      if (!handler.init(base[prop])) {
        return false;
      }
      const origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
      let prevSetter;
      if (origDescriptor instanceof Object) {
        if (!origDescriptor.configurable) {
          const message = `Property '${prop}' is not configurable`;
          logMessage(source, message);
          return false;
        }
        if (base[prop]) {
          base[prop] = constantValue;
        }
        if (origDescriptor.set instanceof Function) {
          prevSetter = origDescriptor.set;
        }
      }
      Object.defineProperty(base, prop, {
        configurable,
        get() {
          return handler.get();
        },
        set(a2) {
          if (prevSetter !== void 0) {
            prevSetter(a2);
          }
          if (a2 instanceof Object) {
            const propertiesToCheck = property.split(".").slice(1);
            if (setProxyTrap && !isProxyTrapSet) {
              isProxyTrapSet = true;
              a2 = new Proxy(a2, {
                get: (target, propertyKey, val) => {
                  propertiesToCheck.reduce((object, currentProp, index, array) => {
                    const currentObj = object?.[currentProp];
                    if (index === array.length - 1 && currentObj !== constantValue) {
                      object[currentProp] = constantValue;
                    }
                    return currentObj || object;
                  }, target);
                  return Reflect.get(target, propertyKey, val);
                }
              });
            }
          }
          handler.set(a2);
        }
      });
      return true;
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      const { base } = chainInfo;
      const { prop, chain } = chainInfo;
      const inChainPropHandler = {
        factValue: void 0,
        init(a2) {
          this.factValue = a2;
          return true;
        },
        get() {
          return this.factValue;
        },
        set(a2) {
          if (this.factValue === a2) {
            return;
          }
          this.factValue = a2;
          if (a2 instanceof Object) {
            setChainPropAccess(a2, chain);
          }
        }
      };
      const endPropHandler = {
        init(a2) {
          if (mustCancel(a2)) {
            return false;
          }
          return true;
        },
        get() {
          return constantValue;
        },
        set(a2) {
          if (!mustCancel(a2)) {
            return;
          }
          constantValue = a2;
        }
      };
      if (!chain) {
        const isTrapped = trapProp(base, prop, false, endPropHandler);
        if (isTrapped) {
          hit(source);
        }
        return;
      }
      if (base !== void 0 && base[prop] === null) {
        trapProp(base, prop, true, inChainPropHandler);
        return;
      }
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        trapProp(base, prop, true, inChainPropHandler);
      }
      const propValue = owner[prop];
      if (propValue instanceof Object || typeof propValue === "object" && propValue !== null) {
        setChainPropAccess(propValue, chain);
      }
      trapProp(base, prop, true, inChainPropHandler);
    };
    setChainPropAccess(window, property);
  }
  var setConstantNames = [
    "set-constant",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-constant.js",
    "ubo-set-constant.js",
    "set.js",
    "ubo-set.js",
    "ubo-set-constant",
    "ubo-set",
    "abp-override-property-read"
  ];
  setConstant.primaryName = setConstantNames[0];
  setConstant.injections = [
    hit,
    logMessage,
    getNumberFromString,
    noopArray,
    noopObject,
    noopFunc,
    noopCallbackFunc,
    trueFunc,
    falseFunc,
    throwFunc,
    noopPromiseReject,
    noopPromiseResolve,
    getPropertyInChain,
    matchStackTrace,
    nativeIsNaN,
    isEmptyObject,
    // following helpers should be imported and injected
    // because they are used by helpers above
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    setPropertyAccess,
    toRegExp,
    backupRegExpValues,
    restoreRegExpValues
  ];

  // src/features/Scriptlets/src/scriptlets/set-local-storage-item.js
  init_define_import_meta_trackerLookup();
  function setLocalStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified.");
      return;
    }
    let validValue;
    try {
      validValue = getLimitedStorageItemValue(value);
    } catch {
      logMessage(source, `Invalid storage item value: '${value}'`);
      return;
    }
    const { localStorage: localStorage2 } = window;
    if (validValue === "$remove$") {
      removeStorageItem(source, localStorage2, key);
    } else {
      setStorageItem(source, localStorage2, key, validValue);
    }
    hit(source);
  }
  var setLocalStorageItemNames = [
    "set-local-storage-item",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-local-storage-item.js",
    "ubo-set-local-storage-item.js",
    "ubo-set-local-storage-item"
  ];
  setLocalStorageItem.primaryName = setLocalStorageItemNames[0];
  setLocalStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    removeStorageItem,
    getLimitedStorageItemValue,
    // following helpers are needed for helpers above
    isValidStrPattern,
    toRegExp,
    escapeRegExp
  ];

  // src/features/Scriptlets/src/scriptlets/abort-current-inline-script.js
  init_define_import_meta_trackerLookup();
  function abortCurrentInlineScript(source, property, search) {
    const searchRegexp = toRegExp(search);
    const rid = randomId();
    const SRC_DATA_MARKER = "data:text/javascript;base64,";
    const getCurrentScript = () => {
      if ("currentScript" in document) {
        return document.currentScript;
      }
      const scripts = document.getElementsByTagName("script");
      return scripts[scripts.length - 1];
    };
    const ourScript = getCurrentScript();
    const abort = () => {
      const scriptEl = getCurrentScript();
      if (!scriptEl) {
        return;
      }
      let content = scriptEl.textContent;
      try {
        const textContentGetter = Object.getOwnPropertyDescriptor(Node.prototype, "textContent").get;
        content = textContentGetter.call(scriptEl);
      } catch (e) {
      }
      if (content.length === 0 && typeof scriptEl.src !== "undefined" && scriptEl.src?.startsWith(SRC_DATA_MARKER)) {
        const encodedContent = scriptEl.src.slice(SRC_DATA_MARKER.length);
        content = window.atob(encodedContent);
      }
      if (scriptEl instanceof HTMLScriptElement && content.length > 0 && scriptEl !== ourScript && searchRegexp.test(content)) {
        hit(source);
        throw new ReferenceError(rid);
      }
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      let { base } = chainInfo;
      const { prop, chain } = chainInfo;
      if (base instanceof Object === false && base === null) {
        const props = property2.split(".");
        const propIndex = props.indexOf(prop);
        const baseName = props[propIndex - 1];
        const message = `The scriptlet had been executed before the ${baseName} was loaded.`;
        logMessage(source, message);
        return;
      }
      if (chain) {
        const setter = (a2) => {
          base = a2;
          if (a2 instanceof Object) {
            setChainPropAccess(a2, chain);
          }
        };
        Object.defineProperty(owner, prop, {
          get: () => base,
          set: setter
        });
        return;
      }
      let currentValue = base[prop];
      let origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
      if (origDescriptor instanceof Object === false || origDescriptor.get instanceof Function === false) {
        currentValue = base[prop];
        origDescriptor = void 0;
      }
      const descriptorWrapper = Object.assign(getDescriptorAddon(), {
        currentValue,
        get() {
          if (!this.isAbortingSuspended) {
            this.isolateCallback(abort);
          }
          if (origDescriptor instanceof Object) {
            return origDescriptor.get.call(base);
          }
          return this.currentValue;
        },
        set(newValue) {
          if (!this.isAbortingSuspended) {
            this.isolateCallback(abort);
          }
          if (origDescriptor instanceof Object) {
            origDescriptor.set.call(base, newValue);
          } else {
            this.currentValue = newValue;
          }
        }
      });
      setPropertyAccess(base, prop, {
        // Call wrapped getter and setter to keep isAbortingSuspended & isolateCallback values
        get() {
          return descriptorWrapper.get.call(descriptorWrapper);
        },
        set(newValue) {
          descriptorWrapper.set.call(descriptorWrapper, newValue);
        }
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortCurrentInlineScriptNames = [
    "abort-current-inline-script",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-current-script.js",
    "ubo-abort-current-script.js",
    "acs.js",
    "ubo-acs.js",
    // "ubo"-aliases with no "js"-ending
    "ubo-abort-current-script",
    "ubo-acs",
    // obsolete but supported aliases
    "abort-current-inline-script.js",
    "ubo-abort-current-inline-script.js",
    "acis.js",
    "ubo-acis.js",
    "ubo-abort-current-inline-script",
    "ubo-acis",
    "abp-abort-current-inline-script"
  ];
  abortCurrentInlineScript.primaryName = abortCurrentInlineScriptNames[0];
  abortCurrentInlineScript.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    toRegExp,
    createOnErrorHandler,
    hit,
    logMessage,
    isEmptyObject,
    getDescriptorAddon
  ];

  // src/features/Scriptlets/src/scriptlets/abort-on-property-read.js
  init_define_import_meta_trackerLookup();
  function abortOnPropertyRead(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      throw new ReferenceError(rid);
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      let { base } = chainInfo;
      const { prop, chain } = chainInfo;
      if (chain) {
        const setter = (a2) => {
          base = a2;
          if (a2 instanceof Object) {
            setChainPropAccess(a2, chain);
          }
        };
        Object.defineProperty(owner, prop, {
          get: () => base,
          set: setter
        });
        return;
      }
      setPropertyAccess(base, prop, {
        get: abort,
        set: () => {
        }
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortOnPropertyReadNames = [
    "abort-on-property-read",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-on-property-read.js",
    "ubo-abort-on-property-read.js",
    "aopr.js",
    "ubo-aopr.js",
    "ubo-abort-on-property-read",
    "ubo-aopr",
    "abp-abort-on-property-read"
  ];
  abortOnPropertyRead.primaryName = abortOnPropertyReadNames[0];
  abortOnPropertyRead.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isEmptyObject
  ];

  // src/features/Scriptlets/src/scriptlets/abort-on-property-write.js
  init_define_import_meta_trackerLookup();
  function abortOnPropertyWrite(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      throw new ReferenceError(rid);
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      let { base } = chainInfo;
      const { prop, chain } = chainInfo;
      if (chain) {
        const setter = (a2) => {
          base = a2;
          if (a2 instanceof Object) {
            setChainPropAccess(a2, chain);
          }
        };
        Object.defineProperty(owner, prop, {
          get: () => base,
          set: setter
        });
        return;
      }
      setPropertyAccess(base, prop, { set: abort });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortOnPropertyWriteNames = [
    "abort-on-property-write",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-on-property-write.js",
    "ubo-abort-on-property-write.js",
    "aopw.js",
    "ubo-aopw.js",
    "ubo-abort-on-property-write",
    "ubo-aopw",
    "abp-abort-on-property-write"
  ];
  abortOnPropertyWrite.primaryName = abortOnPropertyWriteNames[0];
  abortOnPropertyWrite.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isEmptyObject
  ];

  // src/features/Scriptlets/src/scriptlets/prevent-addEventListener.js
  init_define_import_meta_trackerLookup();
  function preventAddEventListener(source, typeSearch, listenerSearch, additionalArgName, additionalArgValue) {
    const typeSearchRegexp = toRegExp(typeSearch);
    const listenerSearchRegexp = toRegExp(listenerSearch);
    let elementToMatch;
    if (additionalArgName) {
      if (additionalArgName !== "elements") {
        logMessage(source, `Invalid "additionalArgName": ${additionalArgName}
Only "elements" is supported.`);
        return;
      }
      if (!additionalArgValue) {
        logMessage(source, '"additionalArgValue" is required.');
        return;
      }
      elementToMatch = additionalArgValue;
    }
    const elementMatches = (element) => {
      if (elementToMatch === void 0) {
        return true;
      }
      if (elementToMatch === "window") {
        return element === window;
      }
      if (elementToMatch === "document") {
        return element === document;
      }
      if (element && element.matches && element.matches(elementToMatch)) {
        return true;
      }
      return false;
    };
    const nativeAddEventListener = window.EventTarget.prototype.addEventListener;
    function addEventListenerWrapper(type, listener, ...args) {
      let shouldPrevent = false;
      if (validateType(type) && validateListener(listener)) {
        shouldPrevent = typeSearchRegexp.test(type.toString()) && listenerSearchRegexp.test(listenerToString(listener)) && elementMatches(this);
      }
      if (shouldPrevent) {
        hit(source);
        return void 0;
      }
      let context = this;
      if (this && this.constructor?.name === "Window" && this !== window) {
        context = window;
      }
      return nativeAddEventListener.apply(context, [type, listener, ...args]);
    }
    const descriptor = {
      configurable: true,
      set: () => {
      },
      get: () => addEventListenerWrapper
    };
    Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
    Object.defineProperty(window, "addEventListener", descriptor);
    Object.defineProperty(document, "addEventListener", descriptor);
  }
  var preventAddEventListenerNames = [
    "prevent-addEventListener",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "addEventListener-defuser.js",
    "ubo-addEventListener-defuser.js",
    "aeld.js",
    "ubo-aeld.js",
    "ubo-addEventListener-defuser",
    "ubo-aeld",
    "abp-prevent-listener"
  ];
  preventAddEventListener.primaryName = preventAddEventListenerNames[0];
  preventAddEventListener.injections = [
    hit,
    toRegExp,
    validateType,
    validateListener,
    listenerToString,
    logMessage
  ];

  // src/features/Scriptlets/src/scriptlets/prevent-window-open.js
  init_define_import_meta_trackerLookup();
  function preventWindowOpen(source, match = "*", delay, replacement) {
    const nativeOpen = window.open;
    const isNewSyntax = match !== "0" && match !== "1";
    const oldOpenWrapper = (str, ...args) => {
      match = Number(match) > 0;
      if (!isValidStrPattern(delay)) {
        logMessage(source, `Invalid parameter: ${delay}`);
        return nativeOpen.apply(window, [str, ...args]);
      }
      const searchRegexp = toRegExp(delay);
      if (match !== searchRegexp.test(str)) {
        return nativeOpen.apply(window, [str, ...args]);
      }
      hit(source);
      return handleOldReplacement(replacement);
    };
    const newOpenWrapper = (url, ...args) => {
      const shouldLog = replacement && replacement.includes("log");
      if (shouldLog) {
        const argsStr = args && args.length > 0 ? `, ${args.join(", ")}` : "";
        const message = `${url}${argsStr}`;
        logMessage(source, message, true);
        hit(source);
      }
      let shouldPrevent = false;
      if (match === "*") {
        shouldPrevent = true;
      } else if (isValidMatchStr(match)) {
        const { isInvertedMatch, matchRegexp } = parseMatchArg(match);
        shouldPrevent = matchRegexp.test(url) !== isInvertedMatch;
      } else {
        logMessage(source, `Invalid parameter: ${match}`);
        shouldPrevent = false;
      }
      if (shouldPrevent) {
        const parsedDelay = parseInt(delay, 10);
        let result;
        if (nativeIsNaN(parsedDelay)) {
          result = noopNull();
        } else {
          const decoyArgs = { replacement, url, delay: parsedDelay };
          const decoy = createDecoy(decoyArgs);
          let popup = decoy.contentWindow;
          if (typeof popup === "object" && popup !== null) {
            Object.defineProperty(popup, "closed", { value: false });
            Object.defineProperty(popup, "opener", { value: window });
            Object.defineProperty(popup, "frameElement", { value: null });
          } else {
            const nativeGetter = decoy.contentWindow && decoy.contentWindow.get;
            Object.defineProperty(decoy, "contentWindow", {
              get: getPreventGetter(nativeGetter)
            });
            popup = decoy.contentWindow;
          }
          result = popup;
        }
        hit(source);
        return result;
      }
      return nativeOpen.apply(window, [url, ...args]);
    };
    window.open = isNewSyntax ? newOpenWrapper : oldOpenWrapper;
    window.open.toString = nativeOpen.toString.bind(nativeOpen);
  }
  var preventWindowOpenNames = [
    "prevent-window-open",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "window.open-defuser.js",
    "ubo-window.open-defuser.js",
    "ubo-window.open-defuser",
    "nowoif.js",
    "ubo-nowoif.js",
    "ubo-nowoif",
    "no-window-open-if.js",
    "ubo-no-window-open-if.js",
    "ubo-no-window-open-if"
  ];
  preventWindowOpen.primaryName = preventWindowOpenNames[0];
  preventWindowOpen.injections = [
    hit,
    isValidStrPattern,
    escapeRegExp,
    isValidMatchStr,
    toRegExp,
    nativeIsNaN,
    parseMatchArg,
    handleOldReplacement,
    createDecoy,
    getPreventGetter,
    noopNull,
    logMessage,
    noopFunc,
    trueFunc,
    substringBefore,
    substringAfter
  ];

  // src/features/Scriptlets/src/scriptlets/prevent-setTimeout.js
  init_define_import_meta_trackerLookup();
  function preventSetTimeout(source, matchCallback, matchDelay) {
    const shouldLog = typeof matchCallback === "undefined" && typeof matchDelay === "undefined";
    const handlerWrapper = (target, thisArg, args) => {
      const callback = args[0];
      const delay = args[1];
      let shouldPrevent = false;
      if (shouldLog) {
        hit(source);
        logMessage(source, `setTimeout(${String(callback)}, ${delay})`, true);
      } else {
        shouldPrevent = isPreventionNeeded({
          callback,
          delay,
          matchCallback,
          matchDelay
        });
      }
      if (shouldPrevent) {
        hit(source);
        args[0] = noopFunc;
      }
      return target.apply(thisArg, args);
    };
    const setTimeoutHandler = {
      apply: handlerWrapper
    };
    window.setTimeout = new Proxy(window.setTimeout, setTimeoutHandler);
  }
  var preventSetTimeoutNames = [
    "prevent-setTimeout",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-setTimeout-if.js",
    // new implementation of setTimeout-defuser.js
    "ubo-no-setTimeout-if.js",
    "nostif.js",
    // new short name of no-setTimeout-if
    "ubo-nostif.js",
    "ubo-no-setTimeout-if",
    "ubo-nostif",
    // old scriptlet names which should be supported as well.
    // should be removed eventually.
    // do not remove until other filter lists maintainers use them
    "setTimeout-defuser.js",
    "ubo-setTimeout-defuser.js",
    "ubo-setTimeout-defuser",
    "std.js",
    "ubo-std.js",
    "ubo-std"
  ];
  preventSetTimeout.primaryName = preventSetTimeoutNames[0];
  preventSetTimeout.injections = [
    hit,
    noopFunc,
    isPreventionNeeded,
    logMessage,
    // following helpers should be injected as helpers above use them
    parseMatchArg,
    parseDelayArg,
    toRegExp,
    nativeIsNaN,
    isValidCallback,
    isValidMatchStr,
    escapeRegExp,
    isValidStrPattern,
    nativeIsFinite,
    isValidMatchNumber,
    parseRawDelay
  ];

  // src/features/Scriptlets/src/scriptlets/remove-node-text.js
  init_define_import_meta_trackerLookup();
  function removeNodeText(source, nodeName, textMatch, parentSelector) {
    const {
      selector,
      nodeNameMatch,
      textContentMatch
    } = parseNodeTextParams(nodeName, textMatch);
    const handleNodes = (nodes) => nodes.forEach((node) => {
      const shouldReplace = isTargetNode(
        node,
        nodeNameMatch,
        textContentMatch
      );
      if (shouldReplace) {
        const ALL_TEXT_PATTERN = /^.*$/s;
        const REPLACEMENT = "";
        replaceNodeText(source, node, ALL_TEXT_PATTERN, REPLACEMENT);
      }
    });
    if (document.documentElement) {
      handleExistingNodes(selector, handleNodes, parentSelector);
    }
    observeDocumentWithTimeout((mutations) => handleMutations(mutations, handleNodes, selector, parentSelector));
  }
  var removeNodeTextNames = [
    "remove-node-text",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "remove-node-text.js",
    "ubo-remove-node-text.js",
    "rmnt.js",
    "ubo-rmnt.js",
    "ubo-remove-node-text",
    "ubo-rmnt"
  ];
  removeNodeText.primaryName = removeNodeTextNames[0];
  removeNodeText.injections = [
    observeDocumentWithTimeout,
    handleExistingNodes,
    handleMutations,
    replaceNodeText,
    isTargetNode,
    parseNodeTextParams,
    // following helpers should be imported and injected
    // because they are used by helpers above
    hit,
    nodeListToArray,
    getAddedNodes,
    toRegExp,
    getTrustedTypesApi
  ];

  // src/features/Scriptlets/src/scriptlets/prevent-fetch.js
  init_define_import_meta_trackerLookup();
  function preventFetch(source, propsToMatch, responseBody = "emptyObj", responseType) {
    if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    const nativeRequestClone = Request.prototype.clone;
    let strResponseBody;
    if (responseBody === "" || responseBody === "emptyObj") {
      strResponseBody = "{}";
    } else if (responseBody === "emptyArr") {
      strResponseBody = "[]";
    } else if (responseBody === "emptyStr") {
      strResponseBody = "";
    } else if (responseBody === "true" || responseBody.match(/^length:\d+-\d+$/)) {
      strResponseBody = generateRandomResponse(responseBody);
    } else {
      logMessage(source, `Invalid responseBody parameter: '${responseBody}'`);
      return;
    }
    const isResponseTypeSpecified = typeof responseType !== "undefined";
    const isResponseTypeSupported = (responseType2) => {
      const SUPPORTED_TYPES = [
        "basic",
        "cors",
        "opaque"
      ];
      return SUPPORTED_TYPES.includes(responseType2);
    };
    if (isResponseTypeSpecified && !isResponseTypeSupported(responseType)) {
      logMessage(source, `Invalid responseType parameter: '${responseType}'`);
      return;
    }
    const getResponseType = (request) => {
      try {
        const { mode } = request;
        if (mode === void 0 || mode === "cors" || mode === "no-cors") {
          const fetchURL = new URL(request.url);
          if (fetchURL.origin === document.location.origin) {
            return "basic";
          }
          return mode === "no-cors" ? "opaque" : "cors";
        }
      } catch (error) {
        logMessage(source, `Could not determine response type: ${error}`);
      }
      return void 0;
    };
    const handlerWrapper = async (target, thisArg, args) => {
      let shouldPrevent = false;
      const fetchData = getFetchData(args, nativeRequestClone);
      if (typeof propsToMatch === "undefined") {
        logMessage(source, `fetch( ${objectToString(fetchData)} )`, true);
        hit(source);
        return Reflect.apply(target, thisArg, args);
      }
      shouldPrevent = matchRequestProps(source, propsToMatch, fetchData);
      if (shouldPrevent) {
        hit(source);
        let finalResponseType;
        try {
          finalResponseType = responseType || getResponseType(fetchData);
          const origResponse = await Reflect.apply(target, thisArg, args);
          if (!origResponse.ok) {
            return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
          }
          return modifyResponse(
            origResponse,
            {
              body: strResponseBody,
              type: finalResponseType
            }
          );
        } catch (ex) {
          return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
        }
      }
      return Reflect.apply(target, thisArg, args);
    };
    const fetchHandler = {
      apply: handlerWrapper
    };
    fetch = new Proxy(fetch, fetchHandler);
  }
  var preventFetchNames = [
    "prevent-fetch",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "prevent-fetch.js",
    "ubo-prevent-fetch.js",
    "ubo-prevent-fetch",
    "no-fetch-if.js",
    "ubo-no-fetch-if.js",
    "ubo-no-fetch-if"
  ];
  preventFetch.primaryName = preventFetchNames[0];
  preventFetch.injections = [
    hit,
    getFetchData,
    objectToString,
    matchRequestProps,
    logMessage,
    noopPromiseResolve,
    modifyResponse,
    toRegExp,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getRequestData,
    getRequestProps,
    parseMatchProps,
    isValidParsedData,
    getMatchPropsData,
    generateRandomResponse,
    nativeIsFinite,
    nativeIsNaN,
    getNumberFromString,
    getRandomIntInclusive,
    getRandomStrByLength
  ];

  // src/features/scriptlets.js
  var Scriptlets = class extends ContentFeature {
    init() {
      if (isBeingFramed()) {
        return;
      }
      const source = {
        verbose: false
      };
      const scriptlets = this.getFeatureSetting("scriptlets");
      for (const scriptlet of scriptlets) {
        source.name = scriptlet.name;
        source.args = Object.values(scriptlet.attrs);
        this.runScriptlet(scriptlet, source);
      }
    }
    runScriptlet(scriptlet, source) {
      const attrs = scriptlet.attrs || {};
      this.addDebugFlag();
      if (scriptlet.name === "setCookie") {
        setCookie(source, attrs.name, attrs.value, attrs.path, attrs.domain);
      }
      if (scriptlet.name === "trustedSetCookie") {
        trustedSetCookie(source, attrs.name, attrs.value, attrs.path, attrs.domain);
      }
      if (scriptlet.name === "setCookieReload") {
        setCookieReload(source, attrs.name, attrs.value, attrs.path, attrs.domain);
      }
      if (scriptlet.name === "removeCookie") {
        removeCookie(source, attrs.match);
      }
      if (scriptlet.name === "setConstant") {
        setConstant(source, attrs.property, attrs.value, attrs.stack, attrs.valueWrapper, attrs.setProxyTrap);
      }
      if (scriptlet.name === "setLocalStorageItem") {
        setLocalStorageItem(source, attrs.key, attrs.value);
      }
      if (scriptlet.name === "abortCurrentInlineScript") {
        abortCurrentInlineScript(source, attrs.property, attrs.search);
      }
      if (scriptlet.name === "abortOnPropertyRead") {
        abortOnPropertyRead(source, attrs.property);
      }
      if (scriptlet.name === "abortOnPropertyWrite") {
        abortOnPropertyWrite(source, attrs.property);
      }
      if (scriptlet.name === "preventAddEventListener") {
        preventAddEventListener(source, attrs.typeSearch, attrs.listenerSearch, attrs.additionalArgName, attrs.additionalArgValue);
      }
      if (scriptlet.name === "preventWindowOpen") {
        preventWindowOpen(source, attrs.match, attrs.delay, attrs.replacement);
      }
      if (scriptlet.name === "preventSetTimeout") {
        preventSetTimeout(source, attrs.matchCallback, attrs.matchDelay);
      }
      if (scriptlet.name === "removeNodeText") {
        removeNodeText(source, attrs.nodeName, attrs.textMatch, attrs.parentSelector);
      }
      if (scriptlet.name === "preventFetch") {
        preventFetch(source, attrs.propsToMatch, attrs.responseBody, attrs.responseType);
      }
    }
  };
  var scriptlets_default = Scriptlets;

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
  var store = {};
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
              const existingBridge = store[featureName];
              if (existingBridge) return existingBridge;
              const bridge = createPageWorldBridge(featureName, args.messageSecret);
              store[featureName] = bridge;
              return bridge;
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

  // ddg:platformFeatures:ddg:platformFeatures
  var ddg_platformFeatures_default = {
    ddg_feature_webCompat: web_compat_default,
    ddg_feature_duckPlayerNative: duck_player_native_default,
    ddg_feature_scriptlets: scriptlets_default,
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
    ddg_feature_apiManipulation: ApiManipulation
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
      injectName: "apple"
    };
    const bundledFeatureNames = typeof importConfig.injectName === "string" ? platformSupport[importConfig.injectName] : [];
    const featuresToLoad = isGloballyDisabled(args) ? platformSpecificFeatures : args.site.enabledFeatures || bundledFeatureNames;
    for (const featureName of bundledFeatureNames) {
      if (featuresToLoad.includes(featureName)) {
        const ContentFeature2 = ddg_platformFeatures_default["ddg_feature_" + featureName];
        const featureInstance2 = new ContentFeature2(featureName, importConfig, args);
        if (!featureInstance2.getFeatureSettingEnabled("additionalCheck", "enabled")) {
          continue;
        }
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
        if (!featureInstance2.getFeatureSettingEnabled("additionalCheck", "enabled")) {
          return;
        }
        featureInstance2.callInit(args);
        if (featureInstance2.listenForUrlChanges || featureInstance2.urlChanged) {
          registerForURLChanges((navigationType) => {
            featureInstance2.recomputeSiteObject();
            featureInstance2?.urlChanged(navigationType);
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
      if (!isFeatureBroken(initArgs, featureName) && featureInstance2.listenForUpdateChanges) {
        featureInstance2.update(args);
      }
    });
  }

  // entry-points/apple.js
  function initCode() {
    const config = $CONTENT_SCOPE$;
    const userUnprotectedDomains = $USER_UNPROTECTED_DOMAINS$;
    const userPreferences = $USER_PREFERENCES$;
    const processedConfig = processConfig(config, userUnprotectedDomains, userPreferences, platformSpecificFeatures);
    const handlerNames = [];
    if (false) {
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
