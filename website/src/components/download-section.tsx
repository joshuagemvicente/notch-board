"use client";

import { Apple, Terminal } from "lucide-react";
import { motion } from "motion/react";
import { buttonVariants } from "@/components/ui/button";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

const steps = [
  "Download the latest zip from GitHub Releases",
  "Move NotchBoard.app into Applications",
  "Open once (right-click → Open if Gatekeeper asks)",
] as const;

export function DownloadSection() {
  return (
    <section id="download" className="relative px-6 pb-24 md:px-8 md:pb-32">
      <motion.div
        className="relative mx-auto w-full max-w-6xl overflow-hidden rounded-[2rem] border border-ink/8 bg-ink px-6 py-12 text-white shadow-[0_40px_80px_-40px_rgb(16_20_28/55%)] sm:px-10 sm:py-14 md:px-14"
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-80px" }}
        transition={{ duration: 0.6 }}
      >
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(700px_320px_at_85%_0%,rgb(15_107_92/35%),transparent_60%)]"
        />

        <div className="relative grid gap-10 lg:grid-cols-[1.1fr_0.9fr] lg:items-end">
          <div>
            <p className="text-[13px] font-semibold uppercase tracking-[0.16em] text-teal-300/90">
              Get the app
            </p>
            <h2 className="mt-3 max-w-lg text-balance text-3xl font-semibold tracking-tight sm:text-4xl md:text-5xl">
              Download NotchBoard for Mac.
            </h2>
            <p className="mt-4 max-w-md text-pretty text-base leading-relaxed text-white/65">
              Free and open source. Built for {site.requirements}. First launch
              may need a right-click Open until notarized builds arrive.
            </p>

            <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
              <a
                href={site.downloadUrl}
                className={cn(
                  buttonVariants({ size: "lg" }),
                  "h-12 gap-2 rounded-xl bg-white px-6 text-[15px] text-ink hover:bg-white/90",
                )}
              >
                <Apple data-icon="inline-start" className="size-4" />
                Download for macOS
              </a>
              <a
                href={`${site.githubUrl}#build--run`}
                className={cn(
                  buttonVariants({ variant: "ghost", size: "lg" }),
                  "h-12 gap-2 rounded-xl px-4 text-[15px] text-white/80 hover:bg-white/10 hover:text-white",
                )}
                target="_blank"
                rel="noreferrer"
              >
                <Terminal data-icon="inline-start" className="size-4" />
                Build from source
              </a>
            </div>
          </div>

          <ol className="space-y-4 border-t border-white/10 pt-6 lg:border-l lg:border-t-0 lg:pl-10 lg:pt-0">
            {steps.map((step, i) => (
              <li key={step} className="flex gap-4">
                <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg bg-white/10 text-[12px] font-semibold tabular-nums text-teal-200">
                  {i + 1}
                </span>
                <p className="text-[15px] leading-relaxed text-white/75">{step}</p>
              </li>
            ))}
          </ol>
        </div>
      </motion.div>
    </section>
  );
}
