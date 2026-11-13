import type { APIRoute } from "astro";
import { headMark } from "../lib/mark";

export const GET: APIRoute = () =>
  new Response(headMark(), { headers: { "Content-Type": "image/svg+xml; charset=utf-8" } });
