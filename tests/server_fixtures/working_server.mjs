// Minimal HTTP server used by the Server.* integration tests.
// (The old fixture was a basic-webserver Roc app; there is no
// basic-webserver for the new compiler yet, so node stands in.)
import http from "node:http";

const port = Number(process.env.PORT ?? "8000");
http
  .createServer((_req, res) => {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end("OK");
  })
  .listen(port);
