// Same-origin relay for Supabase Auth requests. It forwards only to this
// project's fixed Supabase host and only under /auth/v1; the browser's public
// publishable key and the user's own access token remain subject to Supabase RLS.
module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store, max-age=0");
  const rawPath = typeof req.query.path === "string" ? req.query.path : "";
  if (!rawPath.startsWith("/auth/v1/") || rawPath.startsWith("//") || rawPath.includes("\\0")) {
    return res.status(400).json({ error: "Invalid Auth proxy path" });
  }

  let upstreamUrl;
  try {
    upstreamUrl = new URL(rawPath, "https://esoekjjwsbtuyjkrbnam.supabase.co");
  } catch {
    return res.status(400).json({ error: "Invalid Auth proxy path" });
  }
  if (upstreamUrl.origin !== "https://esoekjjwsbtuyjkrbnam.supabase.co" ||
      !upstreamUrl.pathname.startsWith("/auth/v1/")) {
    return res.status(400).json({ error: "Invalid Auth proxy destination" });
  }

  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    if (typeof value !== "string") continue;
    const lower = name.toLowerCase();
    if (["host", "connection", "content-length", "transfer-encoding", "origin", "referer"].includes(lower)) continue;
    headers.set(name, value);
  }

  try {
    let body;
    if (req.method !== "GET" && req.method !== "HEAD") {
      const chunks = [];
      for await (const chunk of req) chunks.push(Buffer.from(chunk));
      body = Buffer.concat(chunks);
    }

    const upstream = await fetch(upstreamUrl, {
      method: req.method,
      headers,
      body,
      redirect: "manual",
      signal: AbortSignal.timeout(20000)
    });

    res.statusCode = upstream.status;
    for (const [name, value] of upstream.headers) {
      const lower = name.toLowerCase();
      if (["connection", "transfer-encoding", "content-encoding", "content-length"].includes(lower)) continue;
      res.setHeader(name, value);
    }
    if (req.method === "HEAD" || upstream.status === 204 || upstream.status === 304) {
      return res.end();
    }
    const payload = Buffer.from(await upstream.arrayBuffer());
    return res.end(payload);
  } catch (error) {
    return res.status(502).json({
      error: "Supabase Auth upstream is unavailable",
      code: error && error.name ? String(error.name) : "UPSTREAM_ERROR"
    });
  }
};

module.exports.config = { api: { bodyParser: false } };
