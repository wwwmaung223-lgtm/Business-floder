// Cloudflare Pages Function equivalent of api/supabase-auth-proxy.js.
// Relays only Supabase Auth endpoints to the fixed project host.
const SUPABASE_ORIGIN = "https://esoekjjwsbtuyjkrbnam.supabase.co";

export async function onRequest({ request }) {
  const url = new URL(request.url);
  const rawPath = url.searchParams.get("path") || "";
  if (!rawPath.startsWith("/auth/v1/") || rawPath.startsWith("//") || rawPath.includes("\\0")) {
    return Response.json({ error: "Invalid Auth proxy path" }, { status: 400 });
  }

  let upstreamUrl;
  try {
    upstreamUrl = new URL(rawPath, SUPABASE_ORIGIN);
  } catch {
    return Response.json({ error: "Invalid Auth proxy path" }, { status: 400 });
  }
  if (upstreamUrl.origin !== SUPABASE_ORIGIN || !upstreamUrl.pathname.startsWith("/auth/v1/")) {
    return Response.json({ error: "Invalid Auth proxy destination" }, { status: 400 });
  }

  const headers = new Headers(request.headers);
  for (const name of ["host", "connection", "content-length", "transfer-encoding", "origin", "referer"]) {
    headers.delete(name);
  }

  try {
    const init = {
      method: request.method,
      headers,
      redirect: "manual"
    };
    if (request.method !== "GET" && request.method !== "HEAD") init.body = request.body;

    const upstream = await fetch(upstreamUrl.toString(), init);
    const responseHeaders = new Headers(upstream.headers);
    for (const name of ["connection", "transfer-encoding", "content-encoding", "content-length"]) {
      responseHeaders.delete(name);
    }
    responseHeaders.set("Cache-Control", "no-store, max-age=0");

    if (request.method === "HEAD" || upstream.status === 204 || upstream.status === 304) {
      return new Response(null, { status: upstream.status, headers: responseHeaders });
    }
    return new Response(upstream.body, { status: upstream.status, headers: responseHeaders });
  } catch (error) {
    return Response.json({
      error: "Supabase Auth upstream is unavailable",
      code: error && error.name ? String(error.name) : "UPSTREAM_ERROR"
    }, { status: 502, headers: { "Cache-Control": "no-store, max-age=0" } });
  }
}
