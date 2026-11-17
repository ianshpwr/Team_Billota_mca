# Recording Checklist (five-minute prototype video)

The team must record the video. Tick each item; do not mark the video as done until the file exists and the link is in
`video/prototype_video_link.md`.

## Before recording
- [ ] All five members confirmed roles for their segment; names and statements are true
- [ ] `docs/individual_contributions.md` filled in so the spoken contributions match it
- [ ] Fresh clone (or clean tree) compiles: `make clean && make phase1` shows `ALL TESTS PASSED`
- [ ] `build/vec4.vvp` prepared (command in `video/demo_script.md`) for the optional live waveform regeneration
- [ ] Waveform images ready: `results/waveforms/*.png` (state that they are Surfer screenshots, not GTKWave)
- [ ] Terminal font large, dark/light theme readable, notifications off, no secrets or personal data on screen
- [ ] Screen recorder tested (resolution >= 1080p, microphone level checked, mono is fine)
- [ ] Script rehearsed with a stopwatch; total <= 4:45 to leave margin

## During recording
- [ ] 0:00-0:30 title + all five members introduced (placeholders replaced by real names)
- [ ] 0:30-1:15 architecture, direct mapping, tag/index/offset with the 0x0004 / 0x0044 example
- [ ] 1:15-2:15 Verilog modules and the FSM diagram
- [ ] 2:15-4:15 live: compile, cold miss, hit, conflict miss, refill, write-through (real output)
- [ ] 4:15-5:00 actual results, limitations stated, conclusion
- [ ] Never exceed 5:00 (the limit is hard)

## After recording
- [ ] Watch the full video once; confirm audio, readable text, no private information
- [ ] Upload (unlisted/private link as required by the course), record the link in `video/prototype_video_link.md`, `README.md`, the report
- [ ] Keep a local copy of the file; do not commit large video files to git
- [ ] Record the date and the names of the people in the recording
