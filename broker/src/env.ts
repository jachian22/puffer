import { resolve } from "node:path";

export type Env = {
  BROKER_HOST: string;
  BROKER_PORT: number;
  BROKER_DB_PATH: string;
  BROKER_API_TOKEN: string;
  PHONE_API_TOKEN: string;
  BROKER_PHONE_SHARED_SECRET: string;
  TELEGRAM_BOT_TOKEN: string;
  TELEGRAM_PHONE_CHAT_ID: string;
  ICLOUD_INBOX_PATH: string;
  NODE_ENV: string;
};

function required(name: string): string {
  const v = process.env[name];
  if (v && v.trim()) return v.trim();

  const nodeEnv = process.env.NODE_ENV ?? "development";
  if (nodeEnv === "test") {
    return `test_${name.toLowerCase()}`;
  }

  throw new Error(`${name} is required`);
}

function optional(name: string, fallback = ""): string {
  const v = process.env[name];
  if (!v) return fallback;
  return v.trim();
}

function int(name: string, fallback: number): number {
  const raw = optional(name, String(fallback));
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

export const env: Env = {
  BROKER_HOST: optional("BROKER_HOST", "127.0.0.1"),
  BROKER_PORT: int("BROKER_PORT", 8765),
  BROKER_DB_PATH: resolve(optional("BROKER_DB_PATH", "./data/broker.sqlite3")),
  BROKER_API_TOKEN: required("BROKER_API_TOKEN"),
  PHONE_API_TOKEN: required("PHONE_API_TOKEN"),
  BROKER_PHONE_SHARED_SECRET: required("BROKER_PHONE_SHARED_SECRET"),
  TELEGRAM_BOT_TOKEN: optional("TELEGRAM_BOT_TOKEN"),
  TELEGRAM_PHONE_CHAT_ID: optional("TELEGRAM_PHONE_CHAT_ID"),
  ICLOUD_INBOX_PATH: optional("ICLOUD_INBOX_PATH"),
  NODE_ENV: optional("NODE_ENV", "development"),
};
