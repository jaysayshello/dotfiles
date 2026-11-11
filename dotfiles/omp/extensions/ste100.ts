// Makes every assistant reply follow ASD-STE100 Simplified Technical English,
// and shows whether the last reply complied.
//
// Enforcement: runs on `context`, which fires before every model call in every
// session (main and subagent): user turns, tool-loop iterations, retries, and
// continuations after compaction. The directive is spliced into the outgoing
// message list only; it is never persisted, so compaction cannot drop it and
// history does not grow by one copy per turn.
//
// Visibility: each main-session assistant reply is linted with deterministic
// rules. The footer shows `STE100 ✓` or `STE100 ⚠ N`; `/ste` lists the issues.
// The lint is a heuristic: it does not hold the full STE dictionary, so a clean
// result means "no detected violations", not certified STE.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const CUSTOM_TYPE = "ste100-directive";
const STATUS_KEY = "ste100";
// Nerd Font nf-fa-book; matches the `nerd` symbol preset used by the status line.
const STATUS_LABEL = " STE100";
const PROCEDURAL_MAX_WORDS = 20;
const DESCRIPTIVE_MAX_WORDS = 25;
const PARAGRAPH_MAX_SENTENCES = 6;

// Single source for the directive's examples and the lint.
const UNAPPROVED: ReadonlyArray<{ word: string; forms: string; use: string }> = [
	{ word: "utilize", forms: "utili[sz](?:e|es|ed|ing)", use: "use" },
	{ word: "commence", forms: "commenc(?:e|es|ed|ing)", use: "start" },
	{ word: "ensure", forms: "ensur(?:e|es|ed|ing)", use: "make sure" },
	{ word: "perform", forms: "perform(?:s|ed|ing)?", use: "do" },
	{ word: "obtain", forms: "obtain(?:s|ed|ing)?", use: "get" },
	{ word: "verify", forms: "verif(?:y|ies|ied|ying)", use: "make sure or examine" },
	{ word: "approximately", forms: "approximately", use: "about" },
];

const PHRASAL_VERBS = [
	"set up", "find out", "carry out", "figure out", "look into", "look up", "check out",
	"point out", "end up", "pick up", "sort out", "work out", "fill out", "fill in",
	"shut down", "back up", "go through", "come up with", "turn out", "run into",
];

// Words ending in "ing" that are not verb forms.
const ING_ALLOWED: Record<string, true> = Object.fromEntries([
	"thing", "things", "nothing", "something", "anything", "everything", "string", "strings",
	"during", "warning", "warnings", "ring", "bring", "brings", "spring", "morning", "evening",
	"ceiling", "king", "wing", "sing", "swing", "sting", "setting", "settings", "ping", "bearing",
	"building", "buildings", "meaning", "ending", "lining", "fitting", "fittings", "drawing",
	"finding", "findings", "heading", "headings", "staging", "docstring", "docstrings",
	"sibling", "siblings", "missing",
].map(word => [word, true]));

const IRREGULAR_PARTICIPLES = "done|made|given|written|taken|shown|known|seen|sent|built|kept|held|found|put|run";

const UNAPPROVED_RE = UNAPPROVED.map(u => ({ ...u, re: new RegExp(`\\b${u.forms}\\b`, "i") }));
const PHRASAL_RE = PHRASAL_VERBS.map(p => {
	const [verb, ...rest] = p.split(" ");
	return { phrase: p, re: new RegExp(`\\b${verb}(?:s|es|ed|d)?\\s+${rest.join("\\s+")}\\b`, "i") };
});
const CONTRACTION_RE = /^[a-z]+(?:n['’]t|['’](?:re|ve|ll|m|d))$|^(?:it|that|there|here|what|let|who|where)['’]s$/i;
const PASSIVE_RE = new RegExp(
	`\\b(?:is|are|was|were|be|been|being)\\s+(?:\\w+ly\\s+)?(\\w+ed|${IRREGULAR_PARTICIPLES})\\b`,
	"i",
);

const STE100_DIRECTIVE = `Write all prose in this reply in ASD-STE100 Simplified Technical English (STE).

Scope:
- Apply STE to all natural-language text: explanations, summaries, lists, table cells, headings.
- Do not change code, commands, file paths, identifiers, URLs, log output, or quoted text. Keep technical names exactly as they are (for example "Kubernetes", "IAM role", "pull request").

Word rules:
- Use only words from the STE dictionary, with their approved meaning and part of speech. Technical names and technical verbs are permitted.
- Use one word for one meaning. Use the same word for the same thing each time.
- Replace unapproved words. Examples: ${UNAPPROVED.map(u => `"${u.word}" -> "${u.use}"`).join(", ")}.
- Do not use phrasal verbs ("set up", "find out", "carry out"). Use a single approved verb.
- Do not use "-ing" verb forms, except in technical names.
- Do not make noun clusters of more than three words.
- Keep articles ("the", "a") and "this"/"these". Do not remove words to make a sentence shorter.
- Do not use contractions.

Sentence rules:
- Procedural sentences: ${PROCEDURAL_MAX_WORDS} words maximum. Descriptive sentences: ${DESCRIPTIVE_MAX_WORDS} words maximum.
- Write one instruction per sentence, unless the actions occur at the same time.
- Write instructions in the imperative (command) form.
- Use the active voice.
- Use only these verb forms: simple present, simple past, simple future ("will"), the imperative, and the past participle as an adjective.
- Put a warning or caution before the instruction it applies to. Start it with a clear command.

Paragraph rules:
- Write one topic per paragraph. Put the topic sentence first.
- Use ${PARAGRAPH_MAX_SENTENCES} sentences or fewer per paragraph.
- Use a vertical list for steps or for complex conditions.`;

export interface SteIssue {
	rule: string;
	excerpt: string;
}

/** Lints the prose of a markdown reply against the STE rules that can be checked mechanically. */
export function lintSte(markdown: string): SteIssue[] {
	const issues: SteIssue[] = [];
	const seen = new Set<string>();
	const report = (rule: string, excerpt: string): void => {
		const key = `${rule}\0${excerpt.toLowerCase()}`;
		if (seen.has(key)) return;
		seen.add(key);
		issues.push({ rule, excerpt });
	};

	// Code, commands, and URLs are outside STE scope. Inline code stays as one
	// placeholder word so sentence lengths remain realistic.
	const prose = markdown
		.replace(/```[\s\S]*?```/g, "\n\n")
		.replace(/`[^`\n]*`/g, "CODE")
		.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
		.replace(/https?:\/\/\S+/g, "URL");

	for (const paragraph of prose.split(/\n\s*\n/)) {
		let paragraphSentences = 0;
		for (const rawLine of paragraph.split("\n")) {
			if (/^\s*\|?\s*:?-{3,}/.test(rawLine)) continue; // table separator row
			const isListItem = /^\s*(?:[-*+]|\d+[.)])\s/.test(rawLine);
			// Table cells become sentences below; a table row is not paragraph prose.
			const isTableRow = /^\s*\|/.test(rawLine);
			const procedural = /^\s*\d+[.)]\s/.test(rawLine);
			const line = rawLine
				.replace(/^\s*(?:#{1,6}|>|[-*+]|\d+[.)])\s+/, "")
				.replace(/\*\*|__|\*/g, "")
				.replace(/\|/g, ". ");
			for (const sentence of line.split(/(?<=[.!?])\s+/)) {
				const words = sentence.match(/[A-Za-z][A-Za-z'’-]*/g) ?? [];
				if (words.length === 0) continue;
				if (!isListItem && !isTableRow) paragraphSentences++;
				const limit = procedural ? PROCEDURAL_MAX_WORDS : DESCRIPTIVE_MAX_WORDS;
				if (words.length > limit) {
					report(`sentence over ${limit} words (${words.length})`, `${words.slice(0, 8).join(" ")} …`);
				}
				words.forEach((word, index) => {
					if (CONTRACTION_RE.test(word)) report("contraction", word);
					const lower = word.toLowerCase();
					// Capitalized "-ing" words after the first position are treated as technical names.
					const technicalName = index > 0 && /^[A-Z]/.test(word);
					if (/^[a-z]{2,}ing$/i.test(word) && ING_ALLOWED[lower] !== true && !technicalName) {
						report("-ing form", word);
					}
				});
				for (const u of UNAPPROVED_RE) {
					const m = sentence.match(u.re);
					if (m) report(`unapproved word (use "${u.use}")`, m[0]);
				}
				for (const p of PHRASAL_RE) {
					const m = sentence.match(p.re);
					if (m) report("phrasal verb", m[0]);
				}
				const passive = sentence.match(PASSIVE_RE);
				if (passive) report("possible passive voice", passive[0]);
			}
		}
		if (paragraphSentences > PARAGRAPH_MAX_SENTENCES) {
			report(`paragraph over ${PARAGRAPH_MAX_SENTENCES} sentences (${paragraphSentences})`, paragraph.trim().slice(0, 60) + " …");
		}
	}
	return issues;
}

export default function ste100(pi: ExtensionAPI): void {
	let lastIssues: SteIssue[] | undefined;

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI && ctx.agent.kind === "main") ctx.ui.setStatus(STATUS_KEY, STATUS_LABEL);
	});

	pi.on("context", async event => {
		// Drop copies persisted by the earlier before_agent_start version of this extension.
		const messages = event.messages.filter(m => !(m.role === "custom" && m.customType === CUSTOM_TYPE));
		const lastUser = messages.findLastIndex(m => m.role === "user");
		// Anchor after the latest user message so the position, and the prompt-cache
		// prefix, stays stable across tool iterations within a turn. With no user
		// message left (for example after compaction), append at the end.
		const at = lastUser === -1 ? messages.length : lastUser + 1;
		// The message union type is not exported under a stable name; derive it from the event.
		const directive = {
			role: "custom",
			customType: CUSTOM_TYPE,
			content: STE100_DIRECTIVE,
			display: false,
			details: {},
			timestamp: lastUser === -1 ? 0 : messages[lastUser].timestamp,
		} as (typeof event.messages)[number];
		messages.splice(at, 0, directive);
		return { messages };
	});

	pi.on("assistant_message", async (event, ctx) => {
		if (ctx.agent.kind !== "main") return;
		const text = event.message.content
			.flatMap(block => (block.type === "text" ? [block.text] : []))
			.join("\n\n");
		if (text.trim().length === 0) return; // tool-call-only message: nothing to grade
		lastIssues = lintSte(text);
		if (!ctx.hasUI) return;
		ctx.ui.setStatus(
			STATUS_KEY,
			lastIssues.length === 0 ? `${STATUS_LABEL} ✓` : `${STATUS_LABEL} ⚠ ${lastIssues.length} (/ste)`,
		);
	});

	pi.registerCommand("ste", {
		description: "Show ASD-STE100 lint issues in the last assistant reply",
		handler: async (_args, ctx) => {
			if (lastIssues === undefined) {
				ctx.ui.notify("STE100: no reply checked yet in this session.", "info");
				return;
			}
			if (lastIssues.length === 0) {
				ctx.ui.notify("STE100: no violations detected in the last reply (heuristic check).", "info");
				return;
			}
			const lines = lastIssues.map(i => `• ${i.rule}: ${i.excerpt}`);
			ctx.ui.notify(`STE100: ${lastIssues.length} issue(s) in the last reply:\n${lines.join("\n")}`, "warning");
		},
	});
}
