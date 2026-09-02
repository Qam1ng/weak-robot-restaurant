import { access, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";

const root = process.cwd();
const outputPath = process.argv[2];
if (!outputPath) throw new Error("Usage: node tools/build_orientation_audio.mjs <output.wav>");

const manifest = JSON.parse(await readFile(path.join(root, "data", "video", "orientation_manifest.json"), "utf8"));
const cues = manifest.cues ?? [];
const audioPaths = cues.map((cue) => path.join(root, "assets", "audio", "orientation", `${cue.id}.mp3`));

for (const audioPath of audioPaths) await access(audioPath);
await mkdir(path.dirname(outputPath), { recursive: true });

const inputs = audioPaths.flatMap((audioPath) => ["-i", audioPath]);
const paddedTracks = cues.map((cue, index) => `[${index}:a]apad=whole_dur=${Number(cue.duration_sec).toFixed(3)}[a${index}]`);
const concatInputs = cues.map((_, index) => `[a${index}]`).join("");
const filter = `${paddedTracks.join(";")};${concatInputs}concat=n=${cues.length}:v=0:a=1[voice]`;
const args = ["-y", ...inputs, "-filter_complex", filter, "-map", "[voice]", "-c:a", "pcm_s16le", outputPath];

await new Promise((resolve, reject) => {
  const child = spawn("ffmpeg", args, { stdio: "inherit" });
  child.on("error", reject);
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`)));
});
