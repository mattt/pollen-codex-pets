import { readFileSync } from "node:fs";
import { defineConfig } from "astro/config";
import linkCheck from "./integrations/link-check.ts";

// The Space's owner and name live in space.json, the one place to change them.
// A static Space serves its files at the root of <owner>-<name>.static.hf.space.
const space = JSON.parse(readFileSync(new URL("./space.json", import.meta.url), "utf8")) as {
  owner: string;
  name: string;
};
const host = `${space.owner}-${space.name}`.toLowerCase().replace(/[^a-z0-9-]/g, "-");

// Static output with one URL form for every page: / is index.html, and every
// internal link ends in a slash. The link check fails the build on a link that
// doesn't, or that names a file the build didn't write.
export default defineConfig({
  site: `https://${host}.static.hf.space`,
  output: "static",
  trailingSlash: "always",
  build: { format: "directory" },
  integrations: [linkCheck()],
});
