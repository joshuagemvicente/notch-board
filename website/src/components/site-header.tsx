import { Apple, ArrowUpRight } from "lucide-react";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

export function SiteHeader() {
  return (
    <header className="relative z-20 mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-5 md:px-8">
      <Link
        href="/"
        className="group flex items-center gap-2.5 text-[15px] font-semibold tracking-tight text-ink"
      >
        <span
          aria-hidden
          className="grid size-7 place-items-center rounded-[9px] bg-ink text-[11px] font-bold text-white shadow-[inset_0_1px_0_rgb(255_255_255/20%)]"
        >
          N
        </span>
        <span className="transition-opacity group-hover:opacity-80">
          {site.name}
        </span>
      </Link>

      <nav className="flex items-center gap-2 sm:gap-3">
        <a
          href={site.githubUrl}
          className={cn(
            buttonVariants({ variant: "ghost", size: "sm" }),
            "hidden text-muted-foreground sm:inline-flex",
          )}
          target="_blank"
          rel="noreferrer"
        >
          GitHub
          <ArrowUpRight data-icon="inline-end" className="opacity-60" />
        </a>
        <a
          href={site.downloadUrl}
          className={cn(
            buttonVariants({ size: "sm" }),
            "h-9 gap-1.5 bg-ink px-3.5 text-white hover:bg-ink/90",
          )}
        >
          <Apple data-icon="inline-start" className="size-3.5" />
          Download
        </a>
      </nav>
    </header>
  );
}
