// The small part of Cloudflare D1 that the server uses. Kept here so the
// same code runs on Workers and, in tests, on Node's built-in SQLite.

export type Value = string | number | null;

export interface D1Statement {
  bind(...values: Value[]): D1Statement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<unknown>;
}

export interface D1Like {
  prepare(sql: string): D1Statement;
  /** Runs the statements in one transaction. */
  batch(statements: D1Statement[]): Promise<unknown[]>;
}

export type Env = {
  DB: D1Like;
  /** Optional contact shown on the privacy page (a Worker variable). */
  PRIVACY_CONTACT?: string;
  /** The Web OAuth client id that Google ID tokens must be issued for.
   * Unset turns Google sign-in off (503 google_disabled). */
  GOOGLE_CLIENT_ID?: string;
  /** Workers AI binding for the savings plan. Unset turns it off (503). */
  AI?: import('./coach.ts').AiLike;
  /** Google Gemini key (a Worker secret). Set: Gemini answers first and
   * Workers AI only when Gemini fails. Never in the app or the code. */
  GEMINI_API_KEY?: string;
  /** Gemini model id; default gemini-2.5-flash. */
  GEMINI_MODEL?: string;
};
