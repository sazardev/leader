// Astro config for {{name}}: static output with sitemap
// target: astro.config.mjs
import { defineConfig } from "astro/config";

// https://astro.build/config
export default defineConfig({
  site: "https://{{name}}.example.com",
  output: "static",
});
