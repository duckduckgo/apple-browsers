import { snippets } from './eval-snippets';
import { ContentScriptMessage } from './messages';
import { getRandomID } from './random';

class Deferred<T> {
    id: string;
    promise: Promise<T>;
    resolve: (value?: T) => void;
    reject: (reason?: any) => void;
    timer: number;

    constructor(id: string, timeout = 1000) {
        this.id = id;
        this.promise = new Promise((resolve, reject) => {
            this.resolve = resolve;
            this.reject = reject;
        });
        this.timer = window.setTimeout(() => {
            this.reject(new Error('timeout'));
        }, timeout);
    }
}

type EvalState = {
    pending: Map<string, Deferred<boolean>>;
    sendContentMessage: (message: ContentScriptMessage) => void;
};

export const evalState: EvalState = {
    pending: new Map(),
    sendContentMessage: null,
};

export function requestEval(code: string, snippetId?: keyof typeof snippets): Promise<boolean> {
    const id = getRandomID();
    evalState.sendContentMessage({
        type: 'eval',
        id,
        code,
        snippetId,
    });
    const deferred = new Deferred<boolean>(id);
    evalState.pending.set(deferred.id, deferred);
    return deferred.promise;
}

export function resolveEval(id: string, value: boolean) {
    const deferred = evalState.pending.get(id);
    if (deferred) {
        evalState.pending.delete(id);
        deferred.timer && window.clearTimeout(deferred.timer);
        deferred.resolve(value);
    } else {
        console.warn('no eval #', id);
    }
}
