import { slugify } from "@/lib/facts";
import { loadFacts, publicFact } from "@/lib/server/facts";
import { articleFor } from "@/lib/server/writer";

const CORS = { "access-control-allow-origin": "*", "cache-control": "public, s-maxage=60, stale-while-revalidate=300" };

/** One encyclopedia page: the article written from the current odds, and the facts it was written from. */
export async function GET(_req: Request, ctx: RouteContext<"/api/wiki/[slug]">) {
  const { slug } = await ctx.params;
  try {
    const { source, facts } = await loadFacts();
    const list = facts.filter((f) => slugify(f.topic) === slugify(slug));
    if (!list.length) return Response.json({ error: "No page with that name yet." }, { status: 404, headers: CORS });
    const article = await articleFor(list[0].topic, list);
    return Response.json({ source, article, facts: list.map(publicFact) }, { headers: CORS });
  } catch {
    return Response.json({ error: "Could not build the page. Try again." }, { status: 502, headers: CORS });
  }
}
