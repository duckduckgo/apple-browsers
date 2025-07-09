/* global Bluetooth, Geolocation, HID, Serial, USB */
import { DDGProxy, DDGReflect } from '../utils';
import ContentFeature from '../content-feature';

export default class WindowsPermissionUsage extends ContentFeature {
    init() {
        const Permission = {
            Geolocation: 'geolocation',
            Camera: 'camera',
            Microphone: 'microphone',
        };

        const Status = {
            Inactive: 'inactive',
            Accessed: 'accessed',
            Active: 'active',
            Paused: 'paused',
        };

        const isFrameInsideFrame = window.self !== window.top && window.parent !== window.top;

        function windowsPostMessage(name, data) {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            windowsInteropPostMessage({
                Feature: 'Permissions',
                Name: name,
                Data: data,
            });
        }

        function signalPermissionStatus(permission, status) {
            windowsPostMessage('PermissionStatusMessage', { permission, status });
            console.debug(`Permission '${permission}' is ${status}`);
        }

        let pauseWatchedPositions = false;
        const watchedPositions = new Set();
        // proxy for navigator.geolocation.watchPosition -> show red geolocation indicator
        const watchPositionProxy = new DDGProxy(this, Geolocation.prototype, 'watchPosition', {
            apply(target, thisArg, args) {
                if (isFrameInsideFrame) {
                    // we can't communicate with iframes inside iframes -> deny permission instead of putting users at risk
                    throw new DOMException('Permission denied');
                }

                const successHandler = args[0];
                args[0] = function (position) {
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
            },
        });
        watchPositionProxy.overload();

        // proxy for navigator.geolocation.clearWatch -> clear red geolocation indicator
        const clearWatchProxy = new DDGProxy(this, Geolocation.prototype, 'clearWatch', {
            apply(target, thisArg, args) {
                DDGReflect.apply(target, thisArg, args);
                if (args[0] && watchedPositions.delete(args[0]) && watchedPositions.size === 0) {
                    signalPermissionStatus(Permission.Geolocation, Status.Inactive);
                }
            },
        });
        clearWatchProxy.overload();

        // proxy for navigator.geolocation.getCurrentPosition -> normal geolocation indicator
        const getCurrentPositionProxy = new DDGProxy(this, Geolocation.prototype, 'getCurrentPosition', {
            apply(target, thisArg, args) {
                const successHandler = args[0];
                args[0] = function (position) {
                    signalPermissionStatus(Permission.Geolocation, Status.Accessed);
                    successHandler?.(position);
                };
                return DDGReflect.apply(target, thisArg, args);
            },
        });
        getCurrentPositionProxy.overload();

        const userMediaStreams = new Set();
        const videoTracks = new Set();
        const audioTracks = new Set();

        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
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
            if (track.readyState === 'ended') return;

            if (track.kind === 'video' && !videoTracks.has(track)) {
                console.debug(`New video stream track ${track.id}`);
                track.addEventListener('ended', videoTrackEnded);
                track.addEventListener('mute', signalVideoTracksState);
                track.addEventListener('unmute', signalVideoTracksState);
                videoTracks.add(track);
            } else if (track.kind === 'audio' && !audioTracks.has(track)) {
                console.debug(`New audio stream track ${track.id}`);
                track.addEventListener('ended', audioTrackEnded);
                track.addEventListener('mute', signalAudioTracksState);
                track.addEventListener('unmute', signalAudioTracksState);
                audioTracks.add(track);
            }
        }

        function handleTrackEnded(track) {
            if (track.kind === 'video' && videoTracks.has(track)) {
                console.debug(`Video stream track ${track.id} ended`);
                track.removeEventListener('ended', videoTrackEnded);
                track.removeEventListener('mute', signalVideoTracksState);
                track.removeEventListener('unmute', signalVideoTracksState);
                videoTracks.delete(track);
                signalVideoTracksState();
            } else if (track.kind === 'audio' && audioTracks.has(track)) {
                console.debug(`Audio stream track ${track.id} ended`);
                track.removeEventListener('ended', audioTrackEnded);
                track.removeEventListener('mute', signalAudioTracksState);
                track.removeEventListener('unmute', signalAudioTracksState);
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

        // proxy for track.stop -> clear camera/mic indicator manually here because no ended event raised this way
        const stopTrackProxy = new DDGProxy(this, MediaStreamTrack.prototype, 'stop', {
            apply(target, thisArg, args) {
                handleTrackEnded(thisArg);
                return DDGReflect.apply(target, thisArg, args);
            },
        });
        stopTrackProxy.overload();

        // proxy for track.clone -> monitor the cloned track
        const cloneTrackProxy = new DDGProxy(this, MediaStreamTrack.prototype, 'clone', {
            apply(target, thisArg, args) {
                const clonedTrack = DDGReflect.apply(target, thisArg, args);
                if (clonedTrack && (videoTracks.has(thisArg) || audioTracks.has(thisArg))) {
                    // @ts-expect-error - thisArg is possibly undefined
                    console.debug(`Media stream track ${thisArg.id} has been cloned to track ${clonedTrack.id}`);
                    monitorTrack(clonedTrack);
                }
                return clonedTrack;
            },
        });
        cloneTrackProxy.overload();

        // override MediaStreamTrack.enabled -> update active/paused status when enabled is set
        const trackEnabledPropertyDescriptor = Object.getOwnPropertyDescriptor(MediaStreamTrack.prototype, 'enabled');
        this.defineProperty(MediaStreamTrack.prototype, 'enabled', {
            // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
            configurable: trackEnabledPropertyDescriptor.configurable,
            // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
            enumerable: trackEnabledPropertyDescriptor.enumerable,
            get: function () {
                // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
                return trackEnabledPropertyDescriptor.get.bind(this)();
            },
            set: function () {
                // @ts-expect-error - trackEnabledPropertyDescriptor is possibly undefined
                const result = trackEnabledPropertyDescriptor.set.bind(this)(...arguments);
                if (videoTracks.has(this)) {
                    signalVideoTracksState();
                } else if (audioTracks.has(this)) {
                    signalAudioTracksState();
                }
                return result;
            },
        });

        // proxy for get*Tracks methods -> needed to monitor tracks returned by saved media stream coming for MediaDevices.getUserMedia
        const getTracksMethodNames = ['getTracks', 'getAudioTracks', 'getVideoTracks'];
        for (const methodName of getTracksMethodNames) {
            const getTracksProxy = new DDGProxy(this, MediaStream.prototype, methodName, {
                apply(target, thisArg, args) {
                    const tracks = DDGReflect.apply(target, thisArg, args);
                    if (userMediaStreams.has(thisArg)) {
                        tracks.forEach(monitorTrack);
                    }
                    return tracks;
                },
            });
            getTracksProxy.overload();
        }

        // proxy for MediaStream.clone -> needed to monitor cloned MediaDevices.getUserMedia streams
        const cloneMediaStreamProxy = new DDGProxy(this, MediaStream.prototype, 'clone', {
            apply(target, thisArg, args) {
                const clonedStream = DDGReflect.apply(target, thisArg, args);
                if (userMediaStreams.has(thisArg)) {
                    // @ts-expect-error - thisArg is possibly 'undefined' here
                    console.debug(`User stream ${thisArg.id} has been cloned to stream ${clonedStream.id}`);
                    userMediaStreams.add(clonedStream);
                }
                return clonedStream;
            },
        });
        cloneMediaStreamProxy.overload();

        // proxy for navigator.mediaDevices.getUserMedia -> show red camera/mic indicators
        if (window.MediaDevices) {
            const getUserMediaProxy = new DDGProxy(this, MediaDevices.prototype, 'getUserMedia', {
                apply(target, thisArg, args) {
                    if (isFrameInsideFrame) {
                        // we can't communicate with iframes inside iframes -> deny permission instead of putting users at risk
                        return Promise.reject(new DOMException('Permission denied'));
                    }

                    const videoRequested = args[0]?.video;
                    const audioRequested = args[0]?.audio;

                    if (videoRequested && (videoRequested.pan || videoRequested.tilt || videoRequested.zoom)) {
                        // WebView2 doesn't support acquiring pan-tilt-zoom from its API at the moment
                        return Promise.reject(new DOMException('Pan-tilt-zoom is not supported'));
                    }

                    // eslint-disable-next-line promise/prefer-await-to-then
                    return DDGReflect.apply(target, thisArg, args).then(function (stream) {
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
                },
            });
            getUserMediaProxy.overload();
        }

        function performAction(action, permission) {
            if (action && permission) {
                switch (action) {
                    case 'pause':
                        pause(permission);
                        break;
                    case 'resume':
                        resume(permission);
                        break;
                    case 'stop':
                        stop(permission);
                        break;
                }
            }
        }

        // handle actions from browser
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        windowsInteropAddEventListener('message', function ({ data }) {
            if (data?.action && data?.permission) {
                performAction(data?.action, data?.permission);
            }
        });

        // these permissions cannot be disabled using WebView2 or DevTools protocol
        const permissionsToDisable = [
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            { name: 'Bluetooth', prototype: () => Bluetooth.prototype, method: 'requestDevice', isPromise: true },
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            { name: 'USB', prototype: () => USB.prototype, method: 'requestDevice', isPromise: true },
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            { name: 'Serial', prototype: () => Serial.prototype, method: 'requestPort', isPromise: true },
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            { name: 'HID', prototype: () => HID.prototype, method: 'requestDevice', isPromise: true },
            { name: 'Protocol handler', prototype: () => Navigator.prototype, method: 'registerProtocolHandler', isPromise: false },
            { name: 'MIDI', prototype: () => Navigator.prototype, method: 'requestMIDIAccess', isPromise: true },
        ];
        for (const { name, prototype, method, isPromise } of permissionsToDisable) {
            try {
                const protoObj = prototype();
                if (!protoObj || !(method in protoObj)) continue;
                const proxy = new DDGProxy(this, protoObj, method, {
                    apply() {
                        if (isPromise) {
                            return Promise.reject(new DOMException('Permission denied'));
                        } else {
                            throw new DOMException('Permission denied');
                        }
                    },
                });
                proxy.overload();
            } catch (error) {
                console.info(`Could not disable access to ${name} because of error`, error);
            }
        }

        // these permissions can be disabled using DevTools protocol but it's not reliable and can throw exception sometimes
        const permissionsToDelete = [
            { name: 'Idle detection', permission: 'IdleDetector' },
            { name: 'NFC', permission: 'NDEFReader' },
            { name: 'Orientation', permission: 'ondeviceorientation' },
            { name: 'Motion', permission: 'ondevicemotion' },
        ];
        for (const { permission } of permissionsToDelete) {
            if (permission in window) {
                Reflect.deleteProperty(window, permission);
            }
        }
    }
}
