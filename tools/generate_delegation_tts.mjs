import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const [scope = "all"] = process.argv.slice(2);
const force = process.argv.includes("--force");
if (!["all", "strategy", "opener", "bridge"].includes(scope) && scope !== "trial") {
  console.error("Usage: node tools/generate_delegation_tts.mjs [all|strategy|opener|bridge|trial]");
  process.exit(1);
}

const root = process.cwd();
const keyPath = path.join(root, "secrets", "openai_api_key.txt");
const apiKey = (process.env.OPENAI_API_KEY || await readFile(keyPath, "utf8")).trim();
const source = await readFile(path.join(root, "scripts", "PersuasionEngine.gd"), "utf8");
const templatePattern = /"template_id": "([^"]+)",\s*"template_text": "([^"]+)"/g;
const allTemplates = [...source.matchAll(templatePattern)]
  .map((match) => ({ id: match[1], text: match[2] }));

const STRATEGIES = ["authority", "reciprocity", "liking", "commitment", "social_proof", "scarcity"];
const items = ["pizza", "hotdog", "sandwich"];
const isStrategy = (id) => STRATEGIES.some((strategy) => id.startsWith(`${strategy}_`));
const inScope = (id) => (
  scope === "all"
    ? isStrategy(id) || id.startsWith("opener_") || id.startsWith("bridge_") || id.startsWith("trial_")
    : scope === "strategy"
      ? isStrategy(id)
      : id.startsWith(`${scope}_`)
);
const templates = allTemplates.filter((template) => inScope(template.id));

if (templates.length === 0) {
  throw new Error(`No templates found for scope: ${scope}`);
}

for (const template of templates) {
  const variants = template.text.includes("{item}") ? items : [null];
  const category = isStrategy(template.id)
    ? "strategy"
    : template.id.startsWith("opener_")
      ? "opener"
      : template.id.startsWith("bridge_")
        ? "bridge"
        : "trial";
  const outputDir = path.join(root, "assets", "audio", "delegation", category);
  await mkdir(outputDir, { recursive: true });

  for (const variant of variants) {
    const suffix = variant ? `_${variant}` : "";
    const outputPath = path.join(outputDir, `${template.id}${suffix}.mp3`);
    if (!force) {
      try {
        await readFile(outputPath);
        console.log(`Skipped existing ${path.relative(root, outputPath)}`);
        continue;
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }

    const response = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini-tts",
        voice: "onyx",
        input: variant ? template.text.replace("{item}", variant) : template.text,
        instructions: "Speak in a clear, helpful, attentive service-robot voice. Sound proactive, positive, and warmly engaged when asking for assistance. Keep the delivery professional and consistent across all lines; avoid sounding monotone, gloomy, weary, overly excited, or sales-like.",
        response_format: "mp3",
        speed: 1.0,
      }),
    });

    if (!response.ok) {
      throw new Error(`TTS failed for ${template.id}: ${response.status} ${await response.text()}`);
    }

    await writeFile(outputPath, Buffer.from(await response.arrayBuffer()));
    console.log(`Generated ${path.relative(root, outputPath)}`);
  }
}
