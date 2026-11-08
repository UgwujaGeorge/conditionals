import type { Metadata } from "next";

import { WikiPage } from "@/components/wiki/Wiki";

export async function generateMetadata({ params }: PageProps<"/wiki/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const name = slug.replace(/-/g, " ");
  return {
    title: `${name.charAt(0).toUpperCase()}${name.slice(1)} · Conditionals Encyclopedia`,
    description: `What the Conditionals markets hold to be true about ${name}, judged by the IMD swarm.`,
  };
}

export default async function Page({ params }: PageProps<"/wiki/[slug]">) {
  const { slug } = await params;
  return <WikiPage slug={slug} />;
}
