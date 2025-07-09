export interface MessageTypes {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    requests?: Record<string, any>;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    notifications?: Record<string, any>;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    subscriptions?: Record<string, any>;
}

/**
 * This is a helper-type used by code-generated files. It adds strong types
 * to any Messaging instance
 */
export interface MessagingBase<T extends MessageTypes = MessageTypes> {
    notify<
        Method extends T['notifications'] extends { method: string } ? T['notifications']['method'] : never,
        Msg = Extract<T['notifications'], { method: Method }>,
    >(
        ...args: Msg extends { params: infer Params } ? [Method, Params] : [Method]
    ): void;
    request<
        Method extends T['requests'] extends { method: string } ? T['requests']['method'] : never,
        Msg = Extract<T['requests'], { method: Method }>,
        Return = Msg extends { result: infer Result } ? Result : void,
    >(
        ...args: Msg extends { params: infer Params } ? [Method, Params] : [Method]
    ): Promise<Return>;
    subscribe<
        Method extends T['subscriptions'] extends { subscriptionEvent: string } ? T['subscriptions']['subscriptionEvent'] : never,
        Msg = Extract<T['subscriptions'], { subscriptionEvent: Method }>,
        Callback = Msg extends { params: infer Params } ? (params: Params) => void : (a: never) => void,
    >(
        subscriptionEvent: Method,
        cb: Callback,
    ): () => void;
}
