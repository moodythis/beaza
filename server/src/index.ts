import { handle } from './app.ts';
import type { Env } from './d1.ts';

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
};
