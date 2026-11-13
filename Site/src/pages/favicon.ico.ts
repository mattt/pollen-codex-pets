import type { APIRoute } from "astro";
import { encodeIco } from "../lib/ico";
import { iconSvg } from "../lib/icons";
import { headMark } from "../lib/mark";
import { imageResponse, transformImage } from "../lib/raster";

// Browsers, feed readers, and crawlers request /favicon.ico without reading
// the page's icon links.
export const GET: APIRoute = async ({ logger }) => {
  const pngs = await Promise.all(
    [16, 32, 48].map((size) => transformImage(iconSvg(headMark(), size), { format: "png" }, logger)),
  );
  return imageResponse(encodeIco(pngs), "image/x-icon");
};
