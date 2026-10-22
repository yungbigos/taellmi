// Serve the website folder on 127.0.0.1 without browser caching, for previewing while editing.
// No dependencies: Node 23.6+ runs TypeScript directly (`npm run dev`, or `node serve.ts [port]`).
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.argv[2] ?? 4173);
const url = `http://localhost:${port}/study/`;

const types: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

async function resolve(path: string): Promise<string | null> {
  const file = normalize(join(root, decodeURIComponent(path)));
  if (!file.startsWith(root)) return null;
  try {
    const s = await stat(file);
    return s.isDirectory() ? join(file, 'index.html') : file;
  } catch {
    return null;
  }
}

const server = createServer(async (req, res) => {
  const path = new URL(req.url ?? '/', 'http://localhost').pathname;
  if (path.endsWith('/') === false && !extname(path)) {
    res.writeHead(301, { Location: path + '/' }).end();
    return;
  }
  const file = await resolve(path);
  const body = file && (await readFile(file).catch(() => null));
  // there is no site yet, only the study
  if (path === '/' && !body) {
    res.writeHead(302, { Location: '/study/' }).end();
    return;
  }
  if (!file || !body) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('not found.');
    return;
  }
  res.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' }).end(body);
});

server.on('error', (e: NodeJS.ErrnoException) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`port ${port} is already in use, probably by a server that is already running. open ${url}, or pass another port: npm run dev -- ${port + 1}`);
    process.exit(1);
  }
  throw e;
});

server.listen(port, '127.0.0.1', () => console.log(`serving ${root.split(sep).slice(-2).join('/')} at ${url}`));
