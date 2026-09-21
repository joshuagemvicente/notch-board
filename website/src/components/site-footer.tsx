import { site } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="border-t border-ink/8 bg-white/40 px-6 py-10 backdrop-blur-sm md:px-8">
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-sm font-semibold tracking-tight text-ink">{site.name}</p>
          <p className="mt-1 text-sm text-muted-foreground">
            MIT licensed. Built for the Mac menu bar.
          </p>
        </div>
        <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted-foreground">
          <a
            href={site.downloadUrl}
            className="transition-colors hover:text-ink"
          >
            Releases
          </a>
          <a
            href={site.githubUrl}
            className="transition-colors hover:text-ink"
            target="_blank"
            rel="noreferrer"
          >
            GitHub
          </a>
          <a
            href={`${site.githubUrl}/blob/main/LICENSE`}
            className="transition-colors hover:text-ink"
            target="_blank"
            rel="noreferrer"
          >
            License
          </a>
        </div>
      </div>
    </footer>
  );
}
