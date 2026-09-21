import { Manrope } from "next/font/google";
import type { Metadata } from "next";
import "./globals.css";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata: Metadata = {
  title: "NotchBoard — Boards at the notch",
  description:
    "A macOS menu bar app that ranks your Trello, GitHub, Linear, Jira, and Azure boards by what you’re working on right now.",
  openGraph: {
    title: "NotchBoard",
    description:
      "Kanban boards one click from the notch — ranked by focus, due work, and the repo you’re in.",
    type: "website",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${manrope.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col font-sans text-foreground">
        {children}
      </body>
    </html>
  );
}
