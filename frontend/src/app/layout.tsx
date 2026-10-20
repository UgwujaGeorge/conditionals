import type { Metadata, Viewport } from "next";
import { Instrument_Serif, Geist, Geist_Mono } from "next/font/google";
import { Providers } from "@/components/Providers";
import "./globals.css";

const display = Instrument_Serif({
  variable: "--font-display-face",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
});
const sans = Geist({ variable: "--font-sans-face", subsets: ["latin"] });
const mono = Geist_Mono({ variable: "--font-mono-face", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Conditionals · Trade the world where it happens",
  description:
    "Conditional prediction markets on IMD. Stake on what happens next in the world where an event occurs, and in the one where it doesn't. Settled by the IdentityMD oracle. Every fee burns IMD.",
  openGraph: {
    title: "Conditionals · Trade the world where it happens",
    description: "Two worlds. One outcome. Settled by IMD's oracle, on Robinhood Chain.",
  },
};

export const viewport: Viewport = {
  themeColor: "#060608",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${display.variable} ${sans.variable} ${mono.variable} antialiased`}>
      <body className="min-h-screen">
        <div className="grain" aria-hidden />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
