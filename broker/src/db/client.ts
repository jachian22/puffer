import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { Database } from "bun:sqlite";

import { env } from "../env";

let _db: Database | undefined;

export function db(): Database {
  if (_db) return _db;
  mkdirSync(dirname(env.BROKER_DB_PATH), { recursive: true });
  _db = new Database(env.BROKER_DB_PATH, { create: true });
  _db.exec("PRAGMA foreign_keys = ON;");
  return _db;
}
