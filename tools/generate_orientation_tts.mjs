import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const apiKey = (process.env.OPENAI_API_KEY || await readFile(path.join(root, "secrets", "openai_api_key.txt"), "utf8")).trim();
const manifest = JSON.parse(await readFile(path.join(root, "data", "video", "orientation_manifest.json"), "utf8"));
const outputDir = path.join(root, "assets", "audio", "orientation");
await mkdir(outputDir, { recursive: true });

for (const cue of manifest.cues ?? []) {
  const id = String(cue.id ?? "").trim();
  const input = String(cue.text ?? "").trim();
  if (!id || !input) throw new Error("Each orientation cue requires id and text.");
  const outputPath = path.join(outputDir, `${id}.mp3`);
  try {
    await readFile(outputPath);
    console.log(`Skipped existing ${path.relative(root, outputPath)}`);
    continue;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: "gpt-4o-mini-tts",
      voice: "onyx",
      input,
      instructions: "Speak in a calm, clear, professional service-robot voice. Keep the delivery neutral and do not add emotional emphasis beyond the wording.",
      response_format: "mp3",
      speed: 1.0,
    }),
  });
  if (!response.ok) throw new Error(`TTS failed for ${id}: ${response.status} ${await response.text()}`);
  await writeFile(outputPath, Buffer.from(await response.arrayBuffer()));
  console.log(`Generated ${path.relative(root, outputPath)}`);
}
