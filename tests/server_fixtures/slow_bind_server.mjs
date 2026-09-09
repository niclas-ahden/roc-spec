// Like working_server.mjs, but it waits before binding.
//
// A server that conflicts on its port only fails once it reaches `listen`,
// and on a loaded machine that is a long way from `spawn`. This fixture
// makes that delay explicit so the readiness guard in `Server` is tested
// against it on every machine, not only slow ones.
import http from "node:http";

const port = Number(process.env.PORT ?? "8000");
const delay = Number(process.env.SLOW_BIND_MS ?? "300");

setTimeout(() => {
  http
    .createServer((_req, res) => {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("OK");
    })
    .listen(port);
}, delay);
