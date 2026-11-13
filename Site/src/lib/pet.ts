// The files of a downloaded pet: pet.json and the license notice.
import { art } from "./art";

export const DEFAULT_NAME = "My Microduck";
/** The ChatGPT app's limit for a pet's name in Settings. */
export const NAME_LIMIT = 80;

/**
 * pet.json for a pet in `folder`, named from its appearance. The visitor's name is
 * only the display name, so it can't change the folder or collide with another pet's.
 */
export function petManifest(name: string, folder: string) {
  return {
    id: folder,
    displayName: name.trim().slice(0, NAME_LIMIT) || DEFAULT_NAME,
    description: art.appearance.petDescription,
    spriteVersionNumber: 2,
    spritesheetPath: "spritesheet.png",
  };
}

/** The license notice in every download, from Art/microduck/pet-LICENSE.txt. */
export const LICENSE_NOTICE = art.license;
