"use client";

import { motion } from "motion/react";
import { providers } from "@/lib/site";

const features = [
  {
    title: "Ranked for right now",
    body: "Pinned boards first, then overdue and due-soon work, recent activity, and the GitHub project for the repo you’re in — Terminal, iTerm2, or VS Code.",
  },
  {
    title: "One click to the board",
    body: "No inline kanban clutter. NotchBoard surfaces the shortlist in the notch; open a board and you’re in the browser where the real work lives.",
  },
  {
    title: "Tokens stay on your Mac",
    body: "API keys live in the Keychain. Connect Trello, GitHub, Linear, Jira, or Azure DevOps with personal tokens or OAuth — nothing is sold as telemetry.",
  },
] as const;

export function Features() {
  return (
    <section className="relative px-6 py-20 md:px-8 md:py-28">
      <div className="mx-auto w-full max-w-6xl">
        <motion.div
          className="max-w-2xl"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-80px" }}
          transition={{ duration: 0.55 }}
        >
          <p className="text-[13px] font-semibold uppercase tracking-[0.16em] text-accent">
            Why it exists
          </p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight text-ink sm:text-4xl">
            Context over clutter.
          </h2>
          <p className="mt-4 max-w-xl text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg">
            Your boards already live in five tools. NotchBoard doesn’t replace
            them — it brings the right one to the front of the Mac.
          </p>
        </motion.div>

        <div className="mt-14 grid gap-10 border-t border-ink/8 pt-12 md:grid-cols-3 md:gap-8">
          {features.map((feature, i) => (
            <motion.article
              key={feature.title}
              initial={{ opacity: 0, y: 18 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={{ duration: 0.5, delay: i * 0.08 }}
            >
              <p className="text-[12px] font-semibold tabular-nums text-accent/80">
                0{i + 1}
              </p>
              <h3 className="mt-3 text-xl font-semibold tracking-tight text-ink">
                {feature.title}
              </h3>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                {feature.body}
              </p>
            </motion.article>
          ))}
        </div>

        <motion.div
          className="mt-16 flex flex-col gap-5 border-t border-ink/8 pt-10 sm:flex-row sm:items-center sm:justify-between"
          initial={{ opacity: 0, y: 14 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          <p className="text-sm font-medium text-ink">Works with the tools you already use</p>
          <ul className="flex flex-wrap items-center gap-x-5 gap-y-3">
            {providers.map((provider) => (
              <li
                key={provider.name}
                className="flex items-center gap-2 text-sm text-muted-foreground"
              >
                <span
                  className="size-2 rounded-full"
                  style={{ backgroundColor: provider.color }}
                  aria-hidden
                />
                {provider.name}
              </li>
            ))}
          </ul>
        </motion.div>
      </div>
    </section>
  );
}
