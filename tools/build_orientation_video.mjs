import { mkdir, readFile, rename } from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";

const root = process.cwd();
const [voicePath, outputPath] = process.argv.slice(2);
if (!voicePath || !outputPath) {
  throw new Error("Usage: node tools/build_orientation_video.mjs <voice.wav> <output.mp4>");
}

const manifest = JSON.parse(await readFile(path.join(root, "data", "video", "orientation_manifest.json"), "utf8"));
const cues = manifest.cues ?? [];
if (cues.length === 0) throw new Error("Orientation manifest has no cues.");

const outputDir = path.dirname(outputPath);
const frameDir = path.join(outputDir, "frames");
await mkdir(frameDir, { recursive: true });

const run = (command, args) => new Promise((resolve, reject) => {
  const child = spawn(command, args, { cwd: root, stdio: "inherit" });
  child.on("error", reject);
  child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`${command} exited with ${code}`)));
});

const scenePath = path.join(root, "scenes", "VideoOrientation.tscn");
const framePaths = [];
for (const cue of cues) {
  const id = String(cue.id ?? "");
  if (!id) throw new Error("Each orientation cue requires an id.");
  const framePath = path.join(frameDir, `${id}.png`);
  await run("godot", [
    "--path", root,
    scenePath,
    "--",
    `--orientation-cue=${id}`,
    `--orientation-output=${framePath}`,
  ]);
  framePaths.push(framePath);
}

const imageInputs = cues.flatMap((cue, index) => [
  "-loop", "1",
  "-framerate", "30",
  "-t", Number(cue.duration_sec).toFixed(3),
  "-i", framePaths[index],
]);
const concatInputs = cues.map((_, index) => `[${index}:v]`).join("");
const audioInputIndex = cues.length;
const temporaryOutput = path.join(outputDir, "robot_delegation_orientation.tmp.mp4");

await run("ffmpeg", [
  "-y",
  ...imageInputs,
  "-i", voicePath,
  "-filter_complex", `${concatInputs}concat=n=${cues.length}:v=1:a=0[video]`,
  "-map", "[video]",
  "-map", `${audioInputIndex}:a:0`,
  "-c:v", "libx264",
  "-crf", "18",
  "-pix_fmt", "yuv420p",
  "-c:a", "aac",
  "-b:a", "192k",
  "-shortest",
  temporaryOutput,
]);

await rename(temporaryOutput, outputPath);
