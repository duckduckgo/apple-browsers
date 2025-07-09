import { sjcl } from '../lib/sjcl.js';

export function getDataKeySync(sessionKey, domainKey, inputData) {
    // eslint-disable-next-line new-cap
    const hmac = new sjcl.misc.hmac(sjcl.codec.utf8String.toBits(sessionKey + domainKey), sjcl.hash.sha256);
    return sjcl.codec.hex.fromBits(hmac.encrypt(inputData));
}
