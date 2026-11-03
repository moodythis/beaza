// TEMPORARY. Starts the one-time copy to the EU database on the live server
// and prints its report (counts and "same" flags only). Retries until the
// new version of the server is live. Removed together with migrate.ts.
//   node scripts/call-migrate.ts https://beaza-sync.moodythis.workers.dev
import { MIGRATE_PATH } from '../src/migrate.ts';

const url = new URL(MIGRATE_PATH, process.argv[2]);
for (let attempt = 1; attempt <= 80; attempt++) {
  let response: Response;
  try {
    response = await fetch(url, { method: 'POST' });
  } catch (error) {
    console.log(`attempt ${attempt}: ${error instanceof Error ? error.message : 'no answer'}, waiting`);
    await new Promise((resolve) => setTimeout(resolve, 15_000));
    continue;
  }
  if (response.ok) {
    const report = (await response.json()) as Record<string, { rows: number; copied: number; same: boolean }>;
    console.log(JSON.stringify(report, null, 2));
    const ok = Object.values(report).every((t) => t.same && t.rows === t.copied);
    console.log(ok ? 'MIGRATION OK' : 'MIGRATION MISMATCH');
    process.exit(ok ? 0 : 1);
  }
  console.log(`attempt ${attempt}: server answered ${response.status}, waiting for the new version`);
  await new Promise((resolve) => setTimeout(resolve, 15_000));
}
console.log('gave up: the new version did not come up');
process.exit(1);
