import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { resolve } from "node:path";

// 패널(index.html)과 설정 창(settings.html) 두 페이지.
export default defineConfig({
  plugins: [svelte()],
  clearScreen: false,
  // src-tauri 는 cargo 가 본다. Vite 가 같이 보면 빌드 중 잠긴 파일 때문에 감시기가 죽는다 (EBUSY)
  server: { port: 1420, strictPort: true, watch: { ignored: ["**/src-tauri/**", "**/dist/**"] } },
  build: {
    target: "es2022",
    rollupOptions: {
      input: { main: resolve(__dirname, "index.html"), settings: resolve(__dirname, "settings.html") },
    },
  },
  test: { environment: "node", include: ["src/**/*.test.ts"] },
});
