#!/usr/bin/env python3
"""Render captioned walkthroughs from privacy-safe Post Demo window captures."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent.parent
frames = root / 'docs/demo-frames'
media = root / 'docs/media'
clips = root / '.build/demo-clips'
media.mkdir(parents=True, exist_ok=True)
clips.mkdir(parents=True, exist_ok=True)
font = '/System/Library/Fonts/SFNS.ttf'

def run(args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args], check=True)

def video(name, scenes):
    paths = []
    for index, (frame, caption) in enumerate(scenes):
        image = Image.open(frames / frame).convert('RGB')
        image = image.crop((0, 56, image.width, image.height))
        image.thumbnail((1440, 840), Image.Resampling.LANCZOS)
        canvas = Image.new('RGB', (1440, 900), '#111820')
        canvas.paste(image, ((1440-image.width)//2, 0))
        draw = ImageDraw.Draw(canvas)
        face = ImageFont.truetype(font, 23)
        draw.text((720, 872), caption, font=face, fill='white', anchor='mm')
        scene = clips / f'{name}-{index}.png'
        canvas.save(scene)
        output = clips / f'{name}-{index}.mp4'
        run(['-loop', '1', '-i', str(scene), '-t', '4', '-r', '24',
             '-c:v', 'libx264', '-crf', '22', '-pix_fmt', 'yuv420p', '-threads', '2', str(output)])
        paths.append(output)
    manifest = clips / f'{name}.txt'
    manifest.write_text(''.join("file '" + str(p).replace("'", "'\\''") + "'\n" for p in paths))
    run(['-f', 'concat', '-safe', '0', '-i', str(manifest), '-c', 'copy', '-movflags', '+faststart', str(media / f'{name}.mp4')])

video('mailbox-demo', [
    ('01-inbox.png', 'Post: labels and a focused inbox. Fictional sample mail.'),
    ('02-thread.png', 'Open a message to read the whole conversation.'),
    ('03-thread-latest.png', 'Scroll through incoming mail and your replies in one preview.'),
    ('04-reply.png', 'Command + R opens a reply with the cursor in the message body.'),
])
video('dark-mode-demo', [
    ('05-dark.png', 'Light, Dark, or System appearance in Settings.'),
    ('06-bulk.png', 'Collapse the sidebar. Shift + arrows selects a range without checkboxes.'),
    ('07-drafts.png', 'Saved drafts open in the preview pane. Escape offers Save or Discard.'),
])
for source, target in [('02-thread.png', 'light.png'), ('05-dark.png', 'dark.png')]:
    image = Image.open(frames / source).convert('RGBA')
    image = image.crop((0, 56, image.width, image.height))
    image.thumbnail((1440, 2000), Image.Resampling.LANCZOS)
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=18, fill=255)
    image.putalpha(mask)
    image.save(media / target)
