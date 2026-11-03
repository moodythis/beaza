// Runs the real server code (src/app.ts) on a local port, with Node's
// built-in SQLite standing in for D1 (in memory, empty at start). Used by CI
// so the real phone code can talk to the real server code over HTTP.
//   node scripts/serve-local.ts 8787
import { createServer } from 'node:http';
import { handle } from '../src/app.ts';
import { TestD1 } from '../test/harness.ts';

const port = Number(process.argv[2] ?? 8787);
const env = { DB: new TestD1() };

createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    if (typeof value === 'string') headers.set(name, value);
  }
  const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
  const request = new Request(`http://127.0.0.1:${port}${req.url}`, {
    method: req.method,
    headers,
    body: hasBody ? Buffer.concat(chunks) : undefined,
  });
  const response = await handle(request, env, { log: () => {} });
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(port, '127.0.0.1', () => console.log(`listening ${port}`));
