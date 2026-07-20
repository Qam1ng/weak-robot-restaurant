#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const admin = require("../functions/node_modules/firebase-admin");
const PROJECT_ID = "weak-robot-restaurant-web";

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: PROJECT_ID,
  });
}

const db = admin.firestore();

async function main() {
  const sessionId = process.argv[2];
  if (!sessionId) {
    console.error("Usage: node scripts/export_runtime_debug_events.js <session_id> [output_path]");
    process.exit(1);
  }

  const outputPath = process.argv[3] || path.join(process.cwd(), `${sessionId}_runtime_debug_events.json`);

  const snapshot = await db
      .collection("runtime_debug_events")
      .where("session_id", "==", sessionId)
      .get();

  const rows = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })).sort((a, b) => {
    const ta = Number(a.timestamp_ms || 0);
    const tb = Number(b.timestamp_ms || 0);
    return ta - tb;
  });

  fs.writeFileSync(outputPath, JSON.stringify(rows, null, 2), "utf8");
  console.log(`Exported ${rows.length} runtime_debug_events to ${outputPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
