import { expect, test } from "vite-plus/test";
import { petManifest } from "./pet";

test("the manifest uses the folder as its ID and the name only for display", () => {
  expect(petManifest("  Sir Quacks-a-Lot!  ", "microduck-2aae1a7")).toMatchObject({
    id: "microduck-2aae1a7",
    displayName: "Sir Quacks-a-Lot!",
    spriteVersionNumber: 2,
    spritesheetPath: "spritesheet.png",
  });
});

test("an empty name falls back to the default, and long names are cut to the app's limit", () => {
  expect(petManifest("   ", "microduck-2aae1a7").displayName).toBe("My Microduck");
  expect(petManifest("x".repeat(100), "microduck-2aae1a7").displayName).toHaveLength(80);
});
