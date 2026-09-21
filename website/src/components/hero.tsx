"use client";

import { Apple, ArrowUpRight } from "lucide-react";
import { motion } from "motion/react";
import { buttonVariants } from "@/components/ui/button";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";
import { ProductMock } from "./product-mock";

export function Hero() {
  return (
    <section className="relative overflow-hidden px-6 pb-6 pt-10 md:px-8 md:pt-14">
      <div className="mx-auto flex w-full max-w-6xl flex-col items-center text-center">
        <motion.h1
          className="max-w-4xl text-balance text-5xl font-semibold leading-[0.98] tracking-tight text-ink sm:text-6xl md:text-7xl lg:text-[5.25rem]"
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.65, ease: [0.22, 1, 0.36, 1] }}
        >
          {site.name}
        </motion.h1>

        <motion.p
          className="mt-5 max-w-2xl text-balance text-xl font-medium tracking-tight text-ink/80 sm:text-2xl md:text-[1.75rem]"
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.08 }}
        >
          {site.tagline}
        </motion.p>

        <motion.p
          className="mt-4 max-w-xl text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg"
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.16 }}
        >
          {site.description}
        </motion.p>

        <motion.div
          className="mt-8 flex flex-col items-center gap-3 sm:flex-row"
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.55, delay: 0.24 }}
        >
          <a
            href={site.downloadUrl}
            className={cn(
              buttonVariants({ size: "lg" }),
              "h-12 gap-2 rounded-xl bg-ink px-6 text-[15px] text-white shadow-[0_12px_30px_-16px_rgb(16_20_28/70%)] hover:bg-ink/90",
            )}
          >
            <Apple data-icon="inline-start" className="size-4" />
            Download for macOS
          </a>
          <a
            href={site.githubUrl}
            className={cn(
              buttonVariants({ variant: "outline", size: "lg" }),
              "h-12 gap-2 rounded-xl border-ink/10 bg-white/55 px-5 text-[15px] text-ink backdrop-blur-sm hover:bg-white/80",
            )}
            target="_blank"
            rel="noreferrer"
          >
            View source
            <ArrowUpRight data-icon="inline-end" className="size-4 opacity-60" />
          </a>
        </motion.div>

        <motion.p
          className="mt-4 text-[13px] text-muted-foreground"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
        >
          {site.requirements} · {site.versionLabel}
        </motion.p>
      </div>

      <div className="mx-auto mt-12 w-full max-w-6xl md:mt-16">
        <ProductMock />
      </div>
    </section>
  );
}
