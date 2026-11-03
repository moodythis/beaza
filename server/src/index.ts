import { handle } from './app.ts';
import type { D1Like, Env } from './d1.ts';
import { MIGRATE_PATH, migrate } from './migrate.ts';

export default {
  async fetch(request: Request, env: Env & { OLD_DB?: D1Like }): Promise<Response> {
    // TEMPORARY: one-time copy to the EU database (see migrate.ts).
    if (request.method === 'POST' && new URL(request.url).pathname === MIGRATE_PATH) {
      return Response.json(await migrate(env), { headers: { 'cache-control': 'no-store' } });
    }
    return handle(request, env);
  },
};
