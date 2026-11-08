/** Suggestions for markets to seed with liquidity. Shared by the page and the API, which must build the same text. */

export type SuggestionKind = "new" | "market" | "fact";

export interface Suggestion {
  id: number;
  kind: SuggestionKind;
  /** The market or fact id, for "market" and "fact". */
  ref: number | null;
  text: string;
  author: string;
  at: number;
  votes: number;
  voted?: boolean;
}

export const SUGGEST_LIMITS = { minIdea: 10, maxText: 280 };

export const KIND_LABEL: Record<SuggestionKind, string> = {
  new: "New market",
  market: "Seed market",
  fact: "Seed fact",
};

/** What a wallet signs to post a suggestion. Signing is free and sends nothing onchain. */
export function createMessage(kind: SuggestionKind, ref: number | null, text: string, issuedAt: number) {
  return `Conditionals: suggest a market to seed\n\n${KIND_LABEL[kind]}${ref ? ` #${ref}` : ""}\n${text}\n\nTime: ${issuedAt}`;
}

/** What a wallet signs to back a suggestion. */
export function voteMessage(id: number, issuedAt: number) {
  return `Conditionals: back suggestion #${id}\n\nTime: ${issuedAt}`;
}
