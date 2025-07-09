/**
 * @import { ProtectionsData } from "../../../types/new-tab";
 * @type {Record<string, ProtectionsData>}
 */
export const protectionsMocks = {
    empty: {
        totalCount: 0,
    },
    few: {
        totalCount: 86,
    },
    many: {
        totalCount: 1_000_020,
    },
};
