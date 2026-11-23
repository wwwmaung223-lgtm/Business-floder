// Read-only diagnostic: checks whether Vercel's server runtime can reach this
// project's Supabase Auth health endpoint. No credentials or user data are used.
module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.setHeader("Content-Type", "application/json; charset=utf-8");

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }

  const startedAt = Date.now();
  try {
    const upstream = await fetch(
      "https://esoekjjwsbtuyjkrbnam.supabase.co/auth/v1/health",
      { method: "GET", signal: AbortSignal.timeout(8000) }
    );
    const body = await upstream.text();
    return res.status(200).json({
      ok: upstream.ok,
      service: "supabase-auth",
      reachable: true,
      upstreamStatus: upstream.status,
      elapsedMs: Date.now() - startedAt,
      responsePreview: body.slice(0, 160)
    });
  } catch (error) {
    return res.status(200).json({
      ok: false,
      service: "supabase-auth",
      reachable: false,
      elapsedMs: Date.now() - startedAt,
      errorName: error && error.name ? String(error.name) : "FetchError",
      errorMessage: error && error.message ? String(error.message).slice(0, 180) : "Upstream request failed"
    });
  }
};
