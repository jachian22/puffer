import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

import { db } from "./client";
import { nowIso } from "../util/time";

function migrationDir(): string {
  return resolve(import.meta.dir, "../../migrations");
}

export function migrate(): void {
  const database = db();

  database.exec(
    "CREATE TABLE IF NOT EXISTS schema_migrations (id TEXT PRIMARY KEY, applied_at TEXT NOT NULL);"
  );

  const files = readdirSync(migrationDir())
    .filter((f) => f.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const applied = database
      .query("SELECT id FROM schema_migrations WHERE id = ? LIMIT 1;")
      .get(file) as { id: string } | null;

    if (applied) continue;

    const sql = readFileSync(join(migrationDir(), file), "utf8");
    database.transaction(() => {
      database.exec(sql);
      database
        .query("INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?);")
        .run(file, nowIso());
    })();
  }
}

if (import.meta.main) {
  migrate();
  process.stdout.write("migrations applied\n");
}
