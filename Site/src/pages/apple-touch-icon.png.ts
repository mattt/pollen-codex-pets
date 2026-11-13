import type { APIRoute } from "astro";
import { iconSvg } from "../lib/icons";
import { headMark } from "../lib/mark";
import { imageResponse, transformImage } from "../lib/raster";
import { PAGE_BACKGROUND } from "../lib/site";

// iOS fills transparent pixels with black and rounds the corners, so the mark
// sits on the page's background inside a margin.
export const GET: APIRoute = async ({ logger }) =>
  imageResponse(
    await transformImage(iconSvg(headMark(), 180, 0.125), { format: "png", background: PAGE_BACKGROUND }, logger),
    "image/png",
  );
