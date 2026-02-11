#!/usr/bin/env python3
"""
Extract expert framing labels from video clips for behavioral cloning.

Processes YouTube or local video files, detects persons via MediaPipe,
embeds detections in a virtual wide-shot canvas, and outputs JSONL
training data matching the Swift TrainingDataRecorder schema.

Usage:
    python extract_frames.py --source "https://youtube.com/watch?v=..."
    python extract_frames.py --source /path/to/clip.mp4 --max-frames 500
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from tqdm import tqdm

from canvas import CanvasState, embed_in_canvas
from detector import PersonDetector
from downloader import acquire_video
from schema import FrameObservation
from writer import SessionWriter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract expert framing labels from video clips for behavioral cloning.",
    )
    parser.add_argument(
        "--source",
        required=True,
        help="YouTube URL or path to a local video file",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=30,
        help="Target frames per second to process (default: 30)",
    )
    parser.add_argument(
        "--zoom-min",
        type=float,
        default=1.5,
        help="Minimum virtual zoom level (default: 1.5)",
    )
    parser.add_argument(
        "--zoom-max",
        type=float,
        default=3.0,
        help="Maximum virtual zoom level (default: 3.0)",
    )
    parser.add_argument(
        "--confidence",
        type=float,
        default=0.5,
        help="Detection confidence threshold (default: 0.5)",
    )
    parser.add_argument(
        "--model-complexity",
        type=int,
        choices=[0, 1, 2],
        default=1,
        help="MediaPipe model complexity: 0=lite, 1=full, 2=heavy (default: 1)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parent / "output",
        help="Base output directory (default: training/output)",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=None,
        help="Maximum frames to process (default: unlimited)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rng = np.random.default_rng(args.seed)
    zoom_range = (args.zoom_min, args.zoom_max)

    # Step 1: Acquire video
    print(f"Source: {args.source}")
    download_dir = args.output_dir / "_downloads"
    video_info = acquire_video(args.source, download_dir)

    # Step 2: Open video
    cap = cv2.VideoCapture(str(video_info.path))
    if not cap.isOpened():
        print(f"Error: Could not open video: {video_info.path}", file=sys.stderr)
        return 1

    source_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_source_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    print(f"Video: {video_info.title}")
    print(f"Resolution: {width}x{height} @ {source_fps:.1f} fps")
    print(f"Total source frames: {total_source_frames}")

    # Step 3: Frame skip for target FPS
    frame_skip = max(1, round(source_fps / args.fps))
    estimated_output = total_source_frames // frame_skip
    if args.max_frames:
        estimated_output = min(estimated_output, args.max_frames)
    print(f"Processing every {frame_skip} frame(s) -> ~{estimated_output} output frames")

    # Step 4: Initialize components
    detector = PersonDetector(args.confidence, args.model_complexity)
    writer = SessionWriter(
        base_dir=args.output_dir,
        video_title=video_info.title,
        fps=args.fps,
        resolution=(width, height),
        confidence_threshold=args.confidence,
        model_complexity=args.model_complexity,
    )

    print(f"Output: {writer.session_dir}")

    # Step 5: Process frames
    canvas_state: CanvasState | None = None
    frame_idx = 0
    output_idx = 0
    detections_count = 0

    try:
        with tqdm(total=estimated_output, unit="frames") as pbar:
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break

                if frame_idx % frame_skip != 0:
                    frame_idx += 1
                    continue

                # Detect person
                detection = detector.detect(frame)
                if detection.has_person:
                    detections_count += 1

                # Embed in canvas
                embedding = embed_in_canvas(
                    detection, canvas_state, rng, zoom_range,
                )
                canvas_state = embedding.state

                # Build observation
                timestamp = frame_idx / source_fps
                observation = FrameObservation(
                    t=round(timestamp, 3),
                    frame_idx=output_idx,
                    speaker=embedding.speaker,
                    keypoints=embedding.keypoints,
                    current_crop=embedding.crop,
                    ideal_crop=embedding.ideal_crop,
                    interpolating=False,
                )

                writer.write_frame(observation)
                output_idx += 1
                frame_idx += 1
                pbar.update(1)

                if args.max_frames and output_idx >= args.max_frames:
                    break

    except KeyboardInterrupt:
        print("\nInterrupted. Finalizing partial data...")

    # Step 6: Finalize
    duration = frame_idx / source_fps
    writer.finalize(total_frames=output_idx, duration=duration)
    cap.release()
    detector.close()

    detection_rate = (
        f"{detections_count / output_idx * 100:.1f}%"
        if output_idx > 0
        else "N/A"
    )
    print(f"\nDone! Wrote {output_idx} frames ({detection_rate} with detections)")
    print(f"Output: {writer.session_dir}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
