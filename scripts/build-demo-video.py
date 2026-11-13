#!/usr/bin/env python3
"""Encode synthetic native UI frames. Requires local ffmpeg; no downloads."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FRAMES = ROOT / ".build/demo-video"
OUTPUT = ROOT / "docs/media"


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def timestamp(seconds):
    milliseconds = round(seconds * 1000)
    return f"{milliseconds // 3600000:02}:{milliseconds // 60000 % 60:02}:{milliseconds // 1000 % 60:02}.{milliseconds % 1000:03}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--encode-only", action="store_true", help="encode existing fixture frames instead of regenerating them")
    args = parser.parse_args()
    for binary in ("ffmpeg", "ffprobe"):
        if not shutil.which(binary):
            parser.error(f"{binary} is required locally for media authoring, not for building CopySaver")
    if not args.encode_only:
        import os
        environment = dict(os.environ, COPY_SAVER_DEMO="1")
        subprocess.run(["./scripts/swift.sh", "test", "--disable-xctest", "--filter", "exportDemoVideoFrames"], cwd=ROOT, env=environment, check=True)
    shots = json.loads((FRAMES / "shots.json").read_text())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    concat, cues, transcript = [], ["WEBVTT\n"], ["# CopySaver feature-tour transcript\n", "Scripted native UI with fictional records and injected website metadata. No audio. This demonstrates interface workflows, not OS integration or encryption verification.\n"]
    elapsed = 0.0
    previous = None
    for shot in shots:
        name, duration = shot["file"], shot["seconds"]
        if Path(name).name != name or not name.endswith(".png") or not 0 < duration <= 10:
            raise ValueError("Unexpected demo frame or duration")
        if not (FRAMES / name).is_file():
            raise ValueError("Missing frame")
        concat.extend([f"file '{name}'", f"duration {duration:.3f}"])
        cues.append(f"{timestamp(elapsed)} --> {timestamp(elapsed + duration)}\n{shot['title']}\n{shot['subtitle']}\n")
        title = shot["title"]
        if title != previous:
            transcript.append(f"- {timestamp(elapsed)[:-4]}: **{title}** {shot['subtitle']}")
        previous = title
        elapsed += duration
    concat.append(f"file '{shots[-1]['file']}'")
    (FRAMES / "frames.ffconcat").write_text("\n".join(concat) + "\n")
    (OUTPUT / "copysaver-demo.vtt").write_text("\n".join(cues))
    (OUTPUT / "transcript.md").write_text("\n".join(transcript) + "\n")
    video = OUTPUT / "copysaver-demo.mp4"
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "1", "-i", str(FRAMES / "frames.ffconcat"), "-t", str(elapsed), "-vf", "scale=1280:960:flags=lanczos,fps=24,format=yuv420p", "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-movflags", "+faststart", "-an", "-map_metadata", "-1", str(video))
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(video), "-filter_complex", "fps=8,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle", "-loop", "0", str(OUTPUT / "copysaver-demo.gif"))
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(video), "-frames:v", "1", str(OUTPUT / "poster.png"))
    probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(video)]))
    stream = probe["streams"][0]
    assert len(probe["streams"]) == 1 and stream["codec_name"] == "h264"
    assert (stream["width"], stream["height"], stream["pix_fmt"]) == (1280, 960, "yuv420p")
    assert abs(float(probe["format"]["duration"]) - elapsed) < 0.15
    for asset in (video, OUTPUT / "copysaver-demo.gif"):
        assert asset.stat().st_size < 10_000_000, f"Media exceeds 10 MB budget: {asset.name}"
        print(f"{asset.relative_to(ROOT)}: {asset.stat().st_size:,} bytes")
    print(f"Verified {elapsed:.2f}s H.264 feature tour, animated preview, poster, captions and transcript.")


if __name__ == "__main__":
    main()
