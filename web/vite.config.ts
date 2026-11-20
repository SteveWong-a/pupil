import fs from "node:fs";
import path from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

const MIME: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".js": "application/javascript; charset=utf-8",
  ".webp": "image/webp",
};

function serveDocsAssetsInDev(): Plugin {
  const docsRoot = path.resolve(import.meta.dirname, "../docs");
  return {
    name: "serve-docs-assets-dev",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const cleanUrl = (req.url ?? "").split("?")[0];
        if (!cleanUrl.startsWith("/assets/") && cleanUrl !== "/sw.js") {
          return next();
        }
        const filePath = path.join(docsRoot, cleanUrl);
        if (!filePath.startsWith(docsRoot) || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
          return next();
        }
        const ext = path.extname(filePath).toLowerCase();
        if (MIME[ext]) res.setHeader("Content-Type", MIME[ext]);
        fs.createReadStream(filePath).pipe(res);
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), serveDocsAssetsInDev()],
  base: "./",
  publicDir: false,
  build: {
    outDir: "../docs",
    emptyOutDir: false,
    target: "es2022",
    chunkSizeWarningLimit: 1200,
  },
});
