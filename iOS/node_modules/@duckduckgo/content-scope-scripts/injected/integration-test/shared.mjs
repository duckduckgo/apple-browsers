export function windowsGlobalPolyfills() {
    // @ts-expect-error - testing
    if (typeof Bluetooth === 'undefined') {
        globalThis.Bluetooth = {};
        globalThis.Bluetooth.prototype = {
            requestDevice: async () => {
                /* noop */
            },
        };
    }
    // @ts-expect-error - testing
    if (typeof USB === 'undefined') {
        globalThis.USB = {};
        globalThis.USB.prototype = {
            requestDevice: async () => {
                /* noop */
            },
        };
    }

    // @ts-expect-error - testing
    if (typeof Serial === 'undefined') {
        globalThis.Serial = {};
        globalThis.Serial.prototype = {
            requestPort: async () => {
                /* noop */
            },
        };
    }
    // @ts-expect-error - testing
    if (typeof HID === 'undefined') {
        globalThis.HID = {};
        globalThis.HID.prototype = {
            requestDevice: async () => {
                /* noop */
            },
        };
    }
}
