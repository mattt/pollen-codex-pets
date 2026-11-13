import type { APIRoute } from "astro";
import { shareSvg } from "../lib/mark";
import { imageResponse, transformImage } from "../lib/raster";
import { PAGE_BACKGROUND, SHARE_IMAGE } from "../lib/site";

// The share image is the site's own art, which is CC BY-NC-SA 4.0 with credit
// to Pollen Robotics on the page that it previews.
export const GET: APIRoute = async ({ logger }) =>
  imageResponse(
    await transformImage(shareSvg(SHARE_IMAGE.width, SHARE_IMAGE.height, PAGE_BACKGROUND), { format: "png" }, logger),
    SHARE_IMAGE.type,
  );
