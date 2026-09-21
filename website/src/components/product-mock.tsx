"use client";

import { motion } from "motion/react";

const boards = [
  {
    title: "Shipping · Sprint 12",
    meta: "3 due soon · active repo",
    tone: "focus" as const,
  },
  {
    title: "Design system",
    meta: "Pinned",
    tone: "pin" as const,
  },
  {
    title: "Customer onboarding",
    meta: "1 overdue",
    tone: "warn" as const,
  },
  {
    title: "Infra backlog",
    meta: "Updated yesterday",
    tone: "muted" as const,
  },
];

export function ProductMock() {
  return (
    <div className="relative mx-auto w-full max-w-5xl">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-8 -bottom-6 top-1/3 rounded-[40%] bg-[radial-gradient(ellipse_at_center,rgb(15_107_92/18%),transparent_70%)] blur-2xl animate-soft-pulse"
      />

      <motion.div
        className="animate-float relative overflow-hidden rounded-t-[1.75rem] border border-white/70 bg-[#1c1f26] shadow-[0_40px_80px_-30px_rgb(16_20_28/55%),0_0_0_1px_rgb(255_255_255/6%)_inset]"
        initial={{ opacity: 0, y: 28, scale: 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.85, delay: 0.25, ease: [0.22, 1, 0.36, 1] }}
      >
        {/* Mac top chrome + notch */}
        <div className="relative flex h-11 items-center justify-center bg-gradient-to-b from-[#2a2e38] to-[#1c1f26]">
          <div className="absolute left-1/2 top-0 h-[22px] w-[148px] -translate-x-1/2 rounded-b-[14px] bg-black shadow-[inset_0_-1px_0_rgb(255_255_255/8%)]" />
          <div className="absolute right-5 top-1/2 flex -translate-y-1/2 items-center gap-2 text-[11px] font-medium tracking-wide text-white/70">
            <span className="rounded-md bg-white/10 px-2 py-0.5 text-white/90">
              12:42
            </span>
            <span className="size-1.5 rounded-full bg-emerald-400/90" />
            <span>NotchBoard</span>
          </div>
        </div>

        {/* Desktop wallpaper + popover */}
        <div className="relative min-h-[340px] bg-[radial-gradient(900px_420px_at_50%_0%,#3d4f63_0%,#1a2230_55%,#12171f_100%)] px-4 pb-10 pt-3 sm:min-h-[400px] sm:px-8">
          <div
            aria-hidden
            className="pointer-events-none absolute inset-0 opacity-40"
            style={{
              backgroundImage:
                "linear-gradient(rgb(255 255 255 / 4%) 1px, transparent 1px), linear-gradient(90deg, rgb(255 255 255 / 4%) 1px, transparent 1px)",
              backgroundSize: "48px 48px",
            }}
          />

          <div className="relative mx-auto mt-2 w-full max-w-md overflow-hidden rounded-2xl border border-white/12 bg-[#0f131a]/88 p-3 shadow-[0_24px_60px_-20px_rgb(0_0_0/70%)] backdrop-blur-xl sm:mt-4 sm:p-4">
            <div className="mb-3 flex items-end justify-between px-1">
              <div>
                <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-white/45">
                  Focus
                </p>
                <p className="mt-0.5 text-[15px] font-semibold text-white">
                  Boards for right now
                </p>
              </div>
              <p className="text-[11px] text-teal-300/90">joshuagem / NotchBoard</p>
            </div>

            <ul className="space-y-1.5">
              {boards.map((board, i) => (
                <motion.li
                  key={board.title}
                  initial={{ opacity: 0, x: 8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.55 + i * 0.08, duration: 0.4 }}
                  className="flex items-center gap-3 rounded-xl px-2.5 py-2.5 transition-colors hover:bg-white/6"
                >
                  <span
                    className={
                      board.tone === "focus"
                        ? "size-2 shrink-0 rounded-full bg-teal-400"
                        : board.tone === "pin"
                          ? "size-2 shrink-0 rounded-full bg-sky-300"
                          : board.tone === "warn"
                            ? "size-2 shrink-0 rounded-full bg-amber-400"
                            : "size-2 shrink-0 rounded-full bg-white/25"
                    }
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[13px] font-medium text-white/95">
                      {board.title}
                    </p>
                    <p className="truncate text-[11px] text-white/45">{board.meta}</p>
                  </div>
                  {board.tone === "focus" ? (
                    <span className="rounded-md bg-teal-400/15 px-1.5 py-0.5 text-[10px] font-semibold text-teal-200">
                      Open
                    </span>
                  ) : null}
                </motion.li>
              ))}
            </ul>
          </div>
        </div>
      </motion.div>

      {/* Desk / base shadow plane */}
      <div
        aria-hidden
        className="mx-auto h-3 w-[72%] rounded-[100%] bg-ink/20 blur-md"
      />
    </div>
  );
}
