import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vite-plus/test";
import { crc32, zip } from "./zip";

test("crc32 matches the standard check value", () => {
  expect(crc32(new TextEncoder().encode("123456789"))).toBe(0xcbf43926);
});

test("unzip reads the archive and its files", () => {
  const text = new TextEncoder().encode("hello\n");
  const archive = zip([
    { path: "pet/pet.json", data: new TextEncoder().encode("{}") },
    { path: "pet/LICENSE.txt", data: text },
  ]);
  const dir = mkdtempSync(join(tmpdir(), "zip-test-"));
  const file = join(dir, "pet.zip");
  writeFileSync(file, archive);
  expect(execFileSync("unzip", ["-t", file], { encoding: "utf8" })).toContain("No errors detected");
  expect(execFileSync("unzip", ["-p", file, "pet/LICENSE.txt"], { encoding: "utf8" })).toBe("hello\n");
});
