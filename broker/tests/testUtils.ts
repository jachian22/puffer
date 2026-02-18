import { db } from "../src/db/client";
import { migrate } from "../src/db/migrate";

export function ensureMigrated(): void {
  migrate();
}

export function resetDb(): void {
  const database = db();
  database.exec("DELETE FROM completion_manifests;");
  database.exec("DELETE FROM pending_requests;");
}

export const TEST_AGENT_TOKEN = "test_broker_api_token";
export const TEST_PHONE_TOKEN = "test_phone_api_token";
