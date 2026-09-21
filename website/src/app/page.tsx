import { DownloadSection } from "@/components/download-section";
import { Features } from "@/components/features";
import { Hero } from "@/components/hero";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export default function Home() {
  return (
    <>
      <SiteHeader />
      <main className="flex-1">
        <Hero />
        <Features />
        <DownloadSection />
      </main>
      <SiteFooter />
    </>
  );
}
