import type { Metadata } from "next";

import { AirdropPage } from "@/components/Airdrop";

export const metadata: Metadata = {
  title: "Airdrop Friends of the Swarm · Conditionals",
  description: "IMD airdropped to CONDITION holders, in proportion to their holdings.",
};

export default function Page() {
  return <AirdropPage />;
}
