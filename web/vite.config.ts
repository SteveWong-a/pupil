import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  base: "./",
  publicDir: false,
  build: {
    outDir: "../docs",
    emptyOutDir: false,
    target: "es2022",
    chunkSizeWarningLimit: 1200,
  },
});
