# Training Guide: Cinematic Framing Model

Train an RL agent to frame a speaker like a professional camera operator, using YouTube clips and local videos as expert demonstrations.

## Prerequisites

```bash
cd training

# Create virtual environment (if not done already)
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Install yt-dlp for YouTube downloads
pip install yt-dlp
# or: brew install yt-dlp

# Download MediaPipe pose model (one-time)
curl -L -o pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
```

## Step 1: Collect Training Data

Extract expert framing labels from videos where a professional camera operator has already framed the speaker well. The pipeline detects the speaker's pose in each frame and records the framing as training data.

### From YouTube

```bash
# Single-speaker talk (TED talk, lecture, keynote)
python extract_frames.py --source "https://www.youtube.com/watch?v=VIDEO_ID"

# Limit frames for a quick test
python extract_frames.py --source "https://www.youtube.com/watch?v=VIDEO_ID" --max-frames 200

# Adjust zoom range (default: 1.5-3.0)
python extract_frames.py --source "https://www.youtube.com/watch?v=VIDEO_ID" \
  --zoom-min 1.2 --zoom-max 2.5
```

### From Local Video Files

```bash
python extract_frames.py --source /path/to/video.mp4
python extract_frames.py --source ~/Videos/presentation.mov --fps 15
```

### What Gets Created

Each video produces a session directory:

```
output/
  session_youtube_2026-02-17_14-32-45/
    frames.jsonl      # One JSON observation per frame
    metadata.json     # Session info (fps, resolution, duration)
```

### Loader validation

New Python writer sessions append a UUID to the timestamped directory name and exclusively create frames and final metadata; existing sessions are preserved on collisions. Legacy timestamp-only directories remain readable.

`scan_sessions` validates observations and metadata before returning a session. Invalid FPS, non-object rows, nonfinite numeric labels and inconsistent provided session IDs or completed row counts raise `ValueError`; repair or explicitly replace the source corpus rather than treating rejected input as training evidence. A completed `total_frames` counts persisted rows, not the highest source frame index. Missing optional legacy metadata retains the existing fallback behavior.

Frame-index strides from subsampling and dropped frames remain accepted. By default, framing replay retains the legacy assumption that adjacent stored rows are fixed-rate control steps: speaker velocity is position change times metadata FPS, and expert crop actions are fixed increments per step. Environment `info` and dataset `timing_info` explicitly label timing and continuity as assumed; a missing timestamp does not become measured elapsed time. Metadata FPS is the declared stored-row rate, not proof of source-frame adjacency.

For a study with verified timestamp semantics, opt in to `TimestampTiming(continuity=...)` through `CinematicFramingEnv`, `ExpertDataset`, `train_bc` or `train_ppo`. Every row must supply finite numeric `t` in seconds, and the required caller callback must return a Boolean for every adjacent stored pair. `True` declares a continuous edge with strictly positive finite elapsed time; `False` starts a new partition and permits a clock reset. The implementation supplies no gap threshold, expected index stride, timestamp tolerance or FPS-based timestamp fallback. For example, this **synthetic three-row study** explicitly declares `(0, 10)` to be its missing interval and all other edges continuous:

```python
from replay_timing import TimestampTiming

timing = TimestampTiming(
    continuity=lambda previous, current:
        (previous["frame_idx"], current["frame_idx"]) != (0, 10)
)
# Supply the same reviewed study contract as timing= to dataset and environment.
```

Timestamp mode computes speaker velocity as position change divided by actual elapsed seconds. BC excludes boundary-spanning pairs; replay episodes stay within a declared partition, reset history at its start, and clear speaker-velocity history after a missing detection. Partitions with fewer than two rows provide no transitions. Timestamp replay chooses uniformly among eligible partitions, then uses the existing random slice selection inside that partition; this is not elapsed-time weighting or a guarantee of equal session exposure. Review sampling with the study contract. Timestamp episodes truncate upon reaching the last real row; legacy terminal behavior is preserved. Crop actions and the jitter reward retain their existing per-control-step units, including on any longer edge the caller explicitly accepts as continuous. No action is divided or multiplied by elapsed time.

The command-line trainers retain their legacy default; an explicit study contract is supplied through the Python APIs. The live Swift inference path still uses its existing show-rate velocity and fixed crop increments, so these replay tests establish neither training-to-live timing parity nor model quality. Run `python -m unittest test_replay_timing test_replay_consumers` from `training/` for synthetic timing and shared NumPy checks plus actual Gym/Torch adapter tests when those dependencies are available. No full training run, export or model promotion follows from passing these checks.

### Recommended Videos

For best results, collect **5-10 diverse clips** with:
- **Single speaker** clearly visible (the model trains on one-person framing)
- **Professional camerawork** — well-framed talks, not shaky handheld footage
- **Varied movement** — speaker walks, gestures, turns (not just standing still)
- **Different zoom levels** — mix of close-ups and medium shots

Good sources: TED talks, conference keynotes, interview-style content, lecture recordings.

### CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--source` | required | YouTube URL or local file path |
| `--fps` | 30 | Frames per second to process |
| `--zoom-min` | 1.5 | Minimum virtual zoom level |
| `--zoom-max` | 3.0 | Maximum virtual zoom level |
| `--confidence` | 0.5 | Pose detection confidence threshold |
| `--max-frames` | unlimited | Cap on frames (useful for testing) |
| `--output-dir` | `output` | Where to write session data |

---

## Step 2: Behavioral Cloning (Phase 1)

BC trains the policy to **imitate the expert framing** from your collected videos. It learns the "taste" of professional camera operators — rule of thirds, smooth pans, anticipatory movement.

```bash
# Standard training (50 epochs, ~2 minutes for 10k samples)
python train_bc.py --data-dir output --epochs 50

# Faster learning rate or larger batches
python train_bc.py --data-dir output --epochs 100 --lr 1e-3 --batch-size 512
```

### What to Look For

BC requires a finite `val_split` strictly between zero and one and at least one derived sample in each partition. It retains the existing validation-count rounding and refuses an empty partition before constructing a model; this is a structural check, not a minimum study-size claim.

The script prints training and validation loss every few epochs:

```
Expert dataset: 8547 samples
Train: 7692, Val: 855
Epoch  5/50 | train_loss: 0.042351 | val_loss: 0.038912
Epoch 10/50 | train_loss: 0.021847 | val_loss: 0.024103
...
Epoch 50/50 | train_loss: 0.005231 | val_loss: 0.007842

Saved BC model to models/bc_pretrained
Best val loss: 0.006103
```

**Good signs:** Val loss decreasing steadily, final val loss < 0.01.
**Bad signs:** Val loss increasing (overfitting) — try fewer epochs or more data.

**Output:** `models/bc_pretrained.zip`

---

## Step 3: PPO Fine-Tuning (Phase 2)

PPO takes the BC-pretrained policy and **improves it using a reward signal** — the agent plays through recorded sessions, receives rewards for good framing and penalties for jitter/head cutoffs, and learns to do better than simple imitation.

```bash
# Fine-tune from BC weights (recommended)
python train_ppo.py --bc-model models/bc_pretrained.zip --total-steps 500000

# Train from scratch (slower, needs more steps)
python train_ppo.py --from-scratch --total-steps 1000000

# Custom hyperparameters
python train_ppo.py --bc-model models/bc_pretrained.zip \
  --total-steps 500000 --lr 1e-4 --batch-size 64
```

### Monitor with TensorBoard

```bash
tensorboard --logdir models/tb_logs
# Open http://localhost:6006 in your browser
```

Key metrics to watch:
- **`rollout/ep_rew_mean`** — average episode reward (should increase)
- **`train/loss`** — PPO loss (should generally decrease)
- **`train/entropy_loss`** — exploration entropy (slow decrease is healthy)

### Checkpoints

Models are saved every 50k steps to `models/checkpoints/`. If training looks good at 200k steps but degrades later, you can use an earlier checkpoint.

**Output:** `models/ppo_final.zip`

---

## Step 4: Export to CoreML

Convert the trained model to a `.mlpackage` for use in the macOS app.

```bash
python export_coreml.py --model models/ppo_final.zip

# Custom output path
python export_coreml.py --model models/ppo_final.zip \
  --output models/CinematicFraming.mlpackage
```

The exported model:
- **Input:** 18-dim float32 observation vector
- **Output:** 3-dim float32 action vector (pan, tilt, zoom velocities in [-1, 1])
- **Target:** macOS 14+, Float32 precision

Export supports the standard SB3 `ActorCriticPolicy` with unsquashed diagonal Gaussian actions, a float32 `(18,)` Box observation space, and a float32 `(3,)` Box action space bounded by `[-1, 1]`, as produced by this framing pipeline. The actor wrapper clips its raw deterministic actions exactly as SB3 prediction does; it does not add an extra `tanh`. Unsupported policy, distribution or space configurations raise `ValueError`. Inference-only parity tests do not establish CoreML conversion or model quality.

**Output:** `models/CinematicFraming.mlpackage`

---

## Adding More Training Data

You can always add more videos and retrain:

```bash
# Process additional clips (they accumulate in output/)
python extract_frames.py --source "https://youtube.com/watch?v=NEW_VIDEO_1"
python extract_frames.py --source "https://youtube.com/watch?v=NEW_VIDEO_2"
python extract_frames.py --source /path/to/local_clip.mp4

# Re-run the full training pipeline
python train_bc.py --data-dir output --epochs 50
python train_ppo.py --bc-model models/bc_pretrained.zip --total-steps 500000
python export_coreml.py --model models/ppo_final.zip
```

Each `extract_frames.py` run creates a new `session_*` directory. The training scripts automatically pick up all sessions in the `output/` directory.

---

## Quick Reference

```bash
# Full pipeline from scratch
source venv/bin/activate

# 1. Collect data (repeat for each video)
python extract_frames.py --source "https://youtube.com/watch?v=VIDEO_ID"

# 2. Train BC
python train_bc.py --data-dir output --epochs 50

# 3. Train PPO
python train_ppo.py --bc-model models/bc_pretrained.zip --total-steps 500000

# 4. Export
python export_coreml.py --model models/ppo_final.zip

# Run tests
python test_env.py          # Environment tests
python test_training.py     # Training pipeline tests
```

---

## Troubleshooting

**"No valid sessions found"**
- Check that `output/` contains `session_*/frames.jsonl` files
- Run `extract_frames.py` first to generate training data

**"No expert demonstrations found"**
- BC training requires sessions with `ideal_crop` data (from YouTube/video extraction)
- Live capture sessions (from the macOS app) don't have `ideal_crop` and are used only for PPO

**Low detection rate during extraction**
- Try `--confidence 0.3` for a lower detection threshold
- Ensure the video has a clearly visible person (not too far away)
- Videos with multiple people may confuse the single-person detector

**yt-dlp errors**
- Update yt-dlp: `pip install --upgrade yt-dlp`
- Some videos may be region-locked or require authentication

**BC validation loss not decreasing**
- Need more training data — process additional video clips
- Try a lower learning rate: `--lr 1e-4`

**PPO reward not improving**
- Ensure you have enough training sessions (5+ recommended)
- Try more timesteps: `--total-steps 1000000`
- Check TensorBoard for diagnostics
