# Pose files

Custom poses live in the same folder as War Journalist's settings:
`%APPDATA%\Arrowhead\Helldivers2\`. Each pose is one text file named
`wj-pose-01.txt` through `wj-pose-99.txt`.

## In Photo Mode

Freeze Action, open the Subject tab and use **Pose editor** to turn bones with
the Bend, Swing and Twist sliders or the drag row. **Saved poses** below it
lists every pose file:

- **Save as new pose** writes the pose you see to the lowest free number.
- **Load pose** puts the selected file on your Helldiver. Edits then start from it.
- **Overwrite selected** replaces the file's pose and keeps its name.
- **Delete selected** removes the file.
- **Rescan pose files** picks up files you copied in by hand.

Saving while nothing is posed saves the frozen moment as a snapshot, so you can
freeze mid-dive, save it, and load it again later.

## Sharing

Send someone your `wj-pose-NN.txt`. They drop it into their settings folder
under any free number, press Rescan, and it shows up in the list. Renaming
the pose in the list means editing the `label=` line at the top of the file
in a text editor; the file name must stay in the `wj-pose-NN.txt` pattern.

## Limits

- Poses are for Helldivers only, and apply while Freeze Action holds.
- A file from a different rig or a damaged file is refused with a message
  in the Saved poses status line; nothing else is touched.
- Up to 99 files. When all numbers are taken, delete one before saving.

## Convert an emote replacement

Unpack the mod ZIP, then run the converter with Python and Lupa installed.
Give it the mod's patch file or an extracted animation .bin. For example:

    python tools/convert_emote.py emote.patch_0 wj-pose-01.txt --time 0.58 --label "Wave"

Time is in seconds. If the patch contains several animations, the converter lists
their resource hashes. Add `--resource HASH` to choose one. This samples one frame
from a stock 90-channel Helldiver animation. The output must be a new file.
Copy it to a free pose slot in the settings folder and choose Rescan pose files.
