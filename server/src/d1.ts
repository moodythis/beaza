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

export type Env = { DB: D1Like };
