"""Renders the Part 1 soundtrack (drone, heartbeat, footsteps, dialogue blips, whisper) to WAV, matching the animation timeline."""
import numpy as np, wave, subprocess
SR=44100; T=92; n=SR*T; rng=np.random.default_rng(7)
t=np.arange(n)/SR; out=np.zeros(n)
def lowpass(x,fc):
    a=np.exp(-2*np.pi*fc/SR); y=np.empty_like(x); s=0.0
    for i in range(0,len(x)): pass
    return x
def onepole(x,fc):
    from numpy import cumsum
    a=1-np.exp(-2*np.pi*fc/SR); y=np.zeros_like(x); acc=0.0
    # vectorised via block loop (fast enough for short bursts)
    for i in range(len(x)): acc+=a*(x[i]-acc); y[i]=acc
    return y
def add(sig,at,vol=1):
    i=int(at*SR); j=min(n,i+len(sig)); out[i:j]+=sig[:j-i]*vol
# drone: detuned saws, slow filter wobble approximated by amplitude swell
for f,v in [(55,.05),(55.7,.05),(82.4,.04),(110.3,.015)]:
    saw=2*((t*f)%1)-1; out+=saw*v*(0.8+0.2*np.sin(2*np.pi*.12*t))
# crude lowpass of the drone
k=int(SR/180); out=np.convolve(out,np.ones(k)/k,mode='same')*2.2
out*=np.minimum(1,t/3)*np.minimum(1,(T-t)/3)
def env(L,dec): x=np.arange(L)/SR; return np.exp(-x/dec)
def blip(f,dur,vol,kind='square'):
    L=int(dur*SR); x=np.arange(L)/SR; ph=(x*f)%1
    s=np.sign(np.sin(2*np.pi*ph)) if kind=='square' else (2*ph-1) if kind=='saw' else np.sin(2*np.pi*f*x)
    return s*vol*env(L,dur/3)
def step(vol):
    L=int(.12*SR); w=rng.standard_normal(L); w=np.convolve(w,np.ones(40)/40,mode='same')
    return w*env(L,.03)*vol*6
def thump(at): add(blip(48,.25,.35,'sine'),at); add(blip(44,.25,.3,'sine'),at+.18)
# heartbeat accents
thump(26.7); thump(74.0)
for tt in np.arange(80,90,1.4): thump(tt)
# whisper
L=int(1.5*SR); w=rng.standard_normal(L); w=w-np.convolve(w,np.ones(18)/18,mode='same'); sh=np.minimum(np.arange(L)/(.4*SR),1)*np.minimum(1,(L-np.arange(L))/(.1*SR)); add(w*sh*.12,73.5)
# footsteps: Gwen 5-12, Miles 11-16, both 28-49
def steps(a,b,period,vol):
    for tt in np.arange(a,b,period): add(step(vol),tt)
steps(5,12,.62,.05); steps(11,16,.45,.05); steps(28,41,.38,.04); steps(28.2,41,.4,.035); steps(41,49,.45,.04); steps(44.2,49,.47,.035)
# dialogue blips (30 chars/sec typewriter, every 2nd char)
SUBS=[(15,18.4,'M','Hey… you lost? You’re new, right?'),(18.5,22,'G','Is it that obvious? …Gwen. Gwen Stacy.'),(22,25.2,'M','Miles. Miles Morales. Homeroom’s this way.'),(25.2,27.6,'G','Lead the way, Miles.'),(30,33,'M','Fair warning: Mr. Alvarez loves pop quizzes.'),(33.2,36.5,'G','Back home, I’m always the one with the drumsticks.'),(36.8,40,'M','Wait. You play drums?'),(40.2,43.4,'G','Wait. You noticed?'),(51,55,'M','Okay… so, gravity. Force equals mass times acceleration.'),(55.2,59.2,'G','Or: the reason you keep falling for my bad jokes.'),(59.4,62.6,'M','…That one was actually good.'),(63,67,'G','Share your notes? I promise I’ll… swing by with snacks.'),(67.2,70.5,'M','Deal. I’ve got a weird feeling you’re gonna fit in here.'),(74,78.5,'S','( …they don’t know someone is watching… )')]
for a,b,w,txt in SUBS:
    for i in range(0,min(len(txt),int((b-a)*30)),2):
        f={'G':640,'M':330,'S':90}[w]; add(blip(f*(1+.04*((i*7)%5)),.04,.07 if w!='S' else .05,'saw' if w=='S' else 'square'),a+i/30)
out=np.tanh(out*1.4)*.85
pcm=(out*32767).astype('<i2')
with wave.open('/tmp/p1.wav','wb') as wf: wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(SR); wf.writeframes(pcm.tobytes())
subprocess.run(['ffmpeg','-y','-loglevel','error','-i','/tmp/p1.wav','-b:a','192k','across-the-doors-part1.mp3'],check=True)
