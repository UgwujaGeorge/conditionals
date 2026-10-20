/** Proxies IMD's free oracle pre-check (POST /requests/check), which has no CORS. Nothing is paid or stored. */
export async function POST(req: Request) {
  let question = "";
  try {
    const body = (await req.json()) as { question?: unknown };
    question = typeof body.question === "string" ? body.question.slice(0, 2000) : "";
  } catch {}
  if (!question) return Response.json({ error: "question required" }, { status: 400 });

  try {
    const res = await fetch("https://api.imd.fun/requests/check", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "oracle.request",
        input: { question, chainId: 1, answerType: "bool", evidence: "panel", panelSize: 5 },
      }),
      cache: "no-store",
    });
    const data = (await res.json()) as {
      blockers?: { code: string; detail: string }[];
      suggestions?: { code: string; detail: string }[];
      online?: number;
      error?: string;
      detail?: string;
    };
    return Response.json({
      ok: res.ok && Array.isArray(data.blockers) && data.blockers.length === 0,
      blockers: data.blockers ?? [],
      suggestions: data.suggestions ?? [],
      online: data.online ?? null,
      error: data.error ? `${data.error}${data.detail ? `: ${data.detail}` : ""}` : null,
    });
  } catch {
    return Response.json({ error: "The IMD API did not answer. Try again." }, { status: 502 });
  }
}
