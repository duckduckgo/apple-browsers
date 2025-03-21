function init(window) {
    // values of properties are being set by this script on purpose to be 'outlier' values,
    // so the test can verify protection in a platform agnostic way

    const BatteryManager = function BatteryManager () {}
    Object.defineProperty(BatteryManager.prototype, 'charging', { get: () => false, configurable: true });
    Object.defineProperty(BatteryManager.prototype, 'chargingTime', { get: () => 12345, configurable: true });
    Object.defineProperty(BatteryManager.prototype, 'dischargingTime', { get: () => 12345, configurable: true });

    window.BatteryManager = BatteryManager;
    window.navigator.getBattery = () => Promise.resolve(new BatteryManager());

    Object.defineProperty(window.Navigator.prototype, 'deviceMemory', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Navigator.prototype, 'hardwareConcurrency', { get: () => 12345, configurable: true });

    Object.defineProperty(window.Screen.prototype, 'availTop', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Screen.prototype, 'availLeft', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Screen.prototype, 'availWidth', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Screen.prototype, 'availHeight', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Screen.prototype, 'colorDepth', { get: () => 12345, configurable: true });
    Object.defineProperty(window.Screen.prototype, 'pixelDepth', { get: () => 12345, configurable: true });

    if (!window.navigator.webkitTemporaryStorage) {
        window.navigator.webkitTemporaryStorage = {};
    }

    window.navigator.webkitTemporaryStorage.queryUsageAndQuota = function queryUsageAndQuota(callback, _) {
        callback(0, 9999999999);
    };

    window.DeviceOrientationEvent = window.Event; // we only need the constructor in tests
    window.DeviceMotionEvent = window.Event; // we only need the constructor in tests
    window.Permissions = class {
        query() {
            return Promise.resolve({ state: 'granted' });
        }
    }
    window.navigator.permissions = new window.Permissions();

    class SensorMock extends EventTarget {
        start() {}
    }
    if (!window.Sensor) window.Sensor = SensorMock;
    class ConcreteSensorMock extends window.Sensor {}
    if (!window.AbsoluteOrientationSensor) window.AbsoluteOrientationSensor = ConcreteSensorMock;
    if (!window.Accelerometer) window.Accelerometer = ConcreteSensorMock;
    if (!window.GravitySensor) window.GravitySensor = ConcreteSensorMock;
    if (!window.Gyroscope) window.Gyroscope = ConcreteSensorMock;
    if (!window.LinearAccelerationSensor) window.LinearAccelerationSensor = ConcreteSensorMock;
    if (!window.RelativeOrientationSensor) window.RelativeOrientationSensor = ConcreteSensorMock;

    if (!window.NavigatorUAData) {
        window.NavigatorUAData = class {
            async getHighEntropyValues() {
                return { platform: 'Win32' };
            }
        }
        window.navigator.userAgentData = new window.NavigatorUAData();
    }

    // freeze the base return value for getHighEntropyValues to not depend on the actual browser
    window.NavigatorUAData.prototype.getHighEntropyValues = function() {
        return Promise.resolve({
            "architecture": "arm",
            "bitness": "64",
            "brands": [
                {
                    "brand": "Not.A/Brand",
                    "version": "8"
                },
                {
                    "brand": "Chromium",
                    "version": "114"
                },
                {
                    "brand": "Google Chrome",
                    "version": "114"
                }
            ],
            "fullVersionList": [
                {
                    "brand": "Not.A/Brand",
                    "version": "8.0.0.0"
                },
                {
                    "brand": "Chromium",
                    "version": "114.1.5735.198"
                },
                {
                    "brand": "Google Chrome",
                    "version": "114.1.5735.198"
                }
            ],
            "mobile": false,
            "model": "some-real-model",
            "platform": "macOS",
            "platformVersion": "13.4.1",
            "uaFullVersion": "114.0.5735.198"
        });
    }

    if (!window.navigator.connection) {
        Object.getPrototypeOf(window.navigator).connection = {
            rtt: 12345,
            downlink: 12345,
            effectiveType: '4g'
        };
    }

    if (!window.navigator.getInstalledRelatedApps) {
        Object.getPrototypeOf(window.navigator).getInstalledRelatedApps = async function() {
            return ['some-returned-app'];
        }
    }

    if (!window.showOpenFilePicker) {
        window.showOpenFilePicker = () => 'mocked-showOpenFilePicker-result';
    }
    if (!window.showSaveFilePicker) {
        window.showSaveFilePicker = () => 'mocked-showSaveFilePicker-result';
    }
    if (!window.showDirectoryPicker) {
        window.showDirectoryPicker = () => 'mocked-showDirectoryPicker-result';
    }
    if (!window.DataTransferItem) {
        window.DataTransferItem = class {
            getAsFileSystemHandle() {
                return 'mocked-DataTransferItem-getAsFileSystemHandle-result';
            }
        }
    }

    if (typeof window.screen.isExtended === 'undefined') {
        Object.defineProperty(window.Screen.prototype, 'isExtended', { get: () => true, configurable: true });
    }

    if (!window.navigator.bluetooth) {
        window.Bluetooth = class {
            getAvailability() {
                return Promise.resolve(true);
            }
            requestDevice() {
                return Promise.resolve('mocked-Bluetooth-requestDevice-result');
            }
        }
        window.navigator.bluetooth = new window.Bluetooth();
    }

    if (!window.navigator.usb) {
        window.USB = class {
            requestDevice() {
                return Promise.resolve('mocked-USB-requestDevice-result');
            }
        }
        window.navigator.usb = new window.USB();
    }

    if (!window.navigator.serial) {
        window.Serial = class {
            requestPort() {
                return Promise.resolve(['mocked-Serial-requestPort-result']);
            }
        }
        window.navigator.serial = new window.Serial();
    }

    if (!window.navigator.hid) {
        window.HID = class {
            requestDevice() {
                return Promise.resolve(['mocked-HID-requestDevice-result']);
            }
        }
        window.navigator.hid = new window.HID();
    }

    if (!window.navigator.requestMIDIAccess) {
        Object.getPrototypeOf(window.navigator).requestMIDIAccess = () => Promise.resolve('mocked-requestMIDIAccess-result');
    }

    if (!window.IdleDetector) {
        window.IdleDetector = class {
            start() {}
        }
    }

    if (!window.NDEFReader) {
        window.NDEFReader = class {}
    }

    if (!window.NDEFMessage) {
        window.NDEFMessage = class {}
    }

    if (!window.NDEFRecord) {
        window.NDEFRecord = class {}
    }

    if (!window.navigator.storage) {
        window.StorageManager = class {
            async estimate() {
                return {
                    quota: 12345,
                    usage: 111
                };
            }
        }
        Object.getPrototypeOf(window.navigator).storage = new window.StorageManager();
    }
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = init
}