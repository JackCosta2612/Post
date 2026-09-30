#!/usr/bin/env python3
"""Frame a real Post Demo recording and overlay timed cursor and keyboard cues.

Requires FFmpeg and Pillow. Input timeline records actual action times; no UI
states are generated. Idle holds may be trimmed, but typing and transitions stay.
"""
import argparse, json, math, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

parser=argparse.ArgumentParser()
parser.add_argument('recording',type=Path)
parser.add_argument('timeline',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
data=json.loads(args.timeline.read_text())
events=data['events']
for e in events: e['source']=e['at']-data['start']
start=max(0,events[0]['source']-2.2)
end=events[-1]['source']+3
cuts=[]
for a,b in zip(events,events[1:]):
    if b['source']-a['source']>6 and a['kind']!='typing':
        cuts.append((a['source']+2.8,b['source']-1.2))
def mapped(t):
    return t-start-sum(max(0,min(t,b)-a) for a,b in cuts if t>a)
for e in events: e['time']=mapped(e['source'])
W,H=1710,980
w,h=1670,920
ox,oy=20,30
fps=60
bg=Image.new('RGB',(W,H),'#f7f7ed')
shadow=Image.new('RGBA',(W,H))
ImageDraw.Draw(shadow).rounded_rectangle((ox,oy+8,ox+w,oy+h+8),radius=15,fill=(0,0,0,90))
shadow=shadow.filter(ImageFilter.GaussianBlur(12))
bg=Image.alpha_composite(bg.convert('RGBA'),shadow).convert('RGB')
mask=Image.new('L',(w,h)); ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1),radius=15,fill=255)
font=ImageFont.truetype('/System/Library/Fonts/SFNS.ttf',17)
# A small black cursor with a white outline, drawn at 3x for clean edges.
cur=Image.new('RGBA',(75,99))
d=ImageDraw.Draw(cur)
d.polygon([(6,3),(6,78),(25,59),(40,93),(52,87),(37,55),(65,55)],fill='#111820',outline='white',width=5)
cur=cur.resize((25,33),Image.Resampling.LANCZOS)
pointer=[e for e in events if e['point']]
keys=[e for e in events if e['kind']=='key']
typing=[e for e in events if e['kind']=='typing'][0]['time']
typing_end=[e for e in events if e['kind']=='typingEnd'][0]['time']

def position(t):
    prev=(1120,600)
    prev_t=-10
    for e in pointer:
        target=(e['point'][0]/2,e['point'][1]/2)
        duration=min(.75,max(.25,(e['time']-prev_t)*.25))
        if t<e['time']-duration: return prev
        if t<e['time']:
            u=(t-e['time']+duration)/duration
            u=u*u*(3-2*u)
            return (prev[0]+(target[0]-prev[0])*u,prev[1]+(target[1]-prev[1])*u)
        prev,prev_t=target,e['time']
    return prev

def render(frame,t):
    # Cover the computer-use control in the otherwise decorative titlebar area.
    # Sample the current sidebar color so sheets and both appearances match.
    color=frame.getpixel((110,12))
    dr=ImageDraw.Draw(frame)
    dr.rectangle((0,0,90,28),fill=color)
    modal=65 < sum(color)/3 < 215
    for x,c in zip((16,38,60),('#ff6057','#ffbd2e','#28c840')):
        dr.ellipse((x-6,10,x+6,22),fill='#aeb2b5' if modal else c)
    canvas=bg.copy(); canvas.paste(frame,(ox,oy),mask)
    overlay=Image.new('RGBA',canvas.size); draw=ImageDraw.Draw(overlay)
    for e in pointer:
        age=t-e['time']
        if e['kind']=='click' and 0<=age<.48:
            x,y=e['point'][0]/2+ox,e['point'][1]/2+oy
            r=10+age*25
            draw.ellipse((x-r,y-r,x+r,y+r),outline=(58,119,184,int(180*(1-age/.48))),width=2)
    label=''
    for e in keys:
        if 0<=t-e['time']<1.7: label=e['label']
    if typing<=t<=typing_end: label='Typing'
    if label:
        box=draw.textbbox((0,0),label,font=font)
        bw=box[2]-box[0]+32
        x,y=(W-bw)/2,H-73
        draw.rounded_rectangle((x,y,x+bw,y+38),radius=8,fill=(24,34,46,225))
        draw.text((W/2,y+19),label,font=font,anchor='mm',fill='white')
    x,y=position(t)
    overlay.alpha_composite(cur,(round(x+ox),round(y+oy)))
    return Image.alpha_composite(canvas.convert('RGBA'),overlay).convert('RGB')

args.output.parent.mkdir(parents=True,exist_ok=True)
dec=subprocess.Popen(['ffmpeg','-v','error','-ss',str(start),'-i',str(args.recording),'-t',str(end-start),'-vf',f'scale={w}:{h}:flags=lanczos,fps={fps}','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],stdout=subprocess.PIPE)
enc=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(fps),'-i','pipe:0','-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(args.output)],stdin=subprocess.PIPE)
count=0; output_frames=0
try:
    while True:
        raw=dec.stdout.read(w*h*3)
        if len(raw)!=w*h*3: break
        source=start+count/fps; count+=1
        if any(a<=source<b for a,b in cuts): continue
        image=Image.frombytes('RGB',(w,h),raw)
        enc.stdin.write(render(image,mapped(source)).tobytes())
        output_frames+=1
        if output_frames%(fps*10)==0: print(f'Edited {output_frames/fps:.0f}s',flush=True)
finally:
    dec.stdout.close(); enc.stdin.close()
if dec.wait()!=0 or enc.wait()!=0: raise SystemExit('FFmpeg failed')
manifest={'duration':output_frames/fps,'events':events,'source_start':start,'idle_cuts':cuts,'output':str(args.output)}
args.output.with_suffix('.timing.json').write_text(json.dumps(manifest,indent=2))
print(f'Finished {output_frames/fps:.1f}s',flush=True)
