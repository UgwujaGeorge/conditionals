import type { Metadata } from "next";

import { WikiIndex } from "@/components/wiki/Wiki";

export const metadata: Metadata = {
  title: "Encyclopedia · Conditionals",
  description: "An encyclopedia where every fact is a prediction market, judged by the IMD swarm and written up by AI from the odds.",
};

export default function Page() {
  return <WikiIndex />;
}
