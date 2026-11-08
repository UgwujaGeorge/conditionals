import { slugify } from "@/lib/facts";
import { loadFacts, publicFact } from "@/lib/server/facts";

const CORS = { "access-control-allow-origin": "*", "cache-control": "public, s-maxage=30, stale-while-revalidate=60" };

/**
 * The encyclopedia's facts for anyone to use, other prediction markets included: each claim, the market's
 * probability that it is true, and the IMD swarm's latest verdict. `?topic=bitcoin` filters to one page.
 */
export async function GET(req: Request) {
  const topic = new URL(req.url).searchParams.get("topic");
  try {
    const { source, facts } = await loadFacts();
    const list = topic ? facts.filter((f) => slugify(f.topic) === slugify(topic)) : facts;
    return Response.json({ source, count: list.length, facts: list.map(publicFact) }, { headers: CORS });
  } catch {
    return Response.json({ error: "Could not read the facts. Try again." }, { status: 502, headers: CORS });
  }
}
