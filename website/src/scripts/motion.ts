import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { CustomEase } from 'gsap/CustomEase';

gsap.registerPlugin(ScrollTrigger, CustomEase);
// Emil Kowalski's strong ease-out and ease-in-out; GSAP owns scroll orchestration.
CustomEase.create('ui-out', '0.23,1,0.32,1');
CustomEase.create('ui-move', '0.77,0,0.175,1');
const video = document.querySelector<HTMLVideoElement>('#demo-video')!;
const play = document.querySelector<HTMLButtonElement>('#play-demo')!;
const label = play.querySelector('small')!;
const error = document.querySelector<HTMLElement>('.video-error')!;
play.addEventListener('click', async () => {
  play.disabled = true;
  label.textContent = 'Loading the film…';
  try { await video.play(); } catch { error.hidden = false; }
  finally { play.disabled = false; }
});
video.addEventListener('play', () => { play.hidden = true; });
video.addEventListener('pause', () => { play.hidden = false; });
video.addEventListener('playing', () => { play.disabled = false; });
video.addEventListener('waiting', () => { label.textContent = 'Loading the film…'; });
video.addEventListener('canplay', () => { label.textContent = '00:31 · Sound optional'; });
video.addEventListener('ended', () => { play.hidden = false; });
video.addEventListener('error', () => { error.hidden = false; play.disabled = false; });
const copy = document.querySelector<HTMLButtonElement>('#copy-install')!;
copy.addEventListener('click', async () => {
  const status = document.querySelector('#copy-status')!;
  try {
    await navigator.clipboard.writeText(document.querySelector('#install-code')!.textContent!);
    status.textContent = 'Commands copied.';
    copy.classList.add('is-copied');
  } catch { status.textContent = 'Copy isn’t available here. Select the commands above to copy them.'; }
});
// Native disclosures retain keyboard behavior; the browser animates their content.
// Text and controls are stable; the scroll story owns the motion.
async function initMotion() {
  await document.fonts.ready;
  const mm = gsap.matchMedia();
  const story = document.querySelector<HTMLVideoElement>('#story-video')!;
  const source = story.querySelector('source')!;
  let wantedTime = 0;
  const seek = () => {
    if (story.readyState >= 2 && !story.seeking && Math.abs(story.currentTime - wantedTime) > .08) {
      story.currentTime = wantedTime;
    }
  };
  story.addEventListener('seeked', seek);
  story.addEventListener('loadeddata', seek);
  const loadStory = () => {
    if (!source.src) {source.src = source.dataset.src!;story.load();}
  };
  mm.add('(prefers-reduced-motion: no-preference)', () => {
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry=>entry.isIntersecting)) {loadStory();observer.disconnect();}
    }, {rootMargin:'1000px'});
    observer.observe(document.querySelector('.workflow')!);
    gsap.to('.reading-progress',{scaleX:1,transformOrigin:'left',ease:'none',scrollTrigger:{start:0,end:'max',scrub:true}});
    gsap.from('.take-rule',{scaleX:0,ease:'none',scrollTrigger:{trigger:'.statement',start:'top 75%',end:'bottom 60%',scrub:.6}});
    return () => observer.disconnect();
  });

  mm.add({desktop:'(min-width: 900px) and (min-height: 720px)',mobile:'(max-width:899px), (max-height:719px)',motion:'(prefers-reduced-motion: no-preference)'}, (context) => {
    if (!context.conditions?.motion) return;
    const desktop = context.conditions.desktop;
    const workflow = document.querySelector('.workflow')!;
    const steps = [...document.querySelectorAll<HTMLElement>('.step')];
    const status = document.querySelector('#stage-status-text')!;
    const filename = document.querySelector('.stage-file')!;
    const shotNote = document.querySelector('.shot-note span')!;
    const time = document.querySelector('#story-time')!;
    const progress = {value:0};
    const selectStep = (index:number) => {
      steps.forEach((step,i)=>step.classList.toggle('active',i===index));
      status.textContent=['A few directions','The camera follows','Finding the rhythm','That’s a wrap'][index];
      filename.textContent=['shots.yaml','Chrome / recording','timeline.yaml','blog-tour.mp4'][index];
    };
    const update = () => {
      const p=progress.value;
      selectStep(p<.18?0:p<.57?1:p<.84?2:3);
      wantedTime=gsap.utils.clamp(0,27,((p-.18)/.39)*27);
      seek();
      shotNote.textContent=wantedTime<8?'Click. The camera follows.':wantedTime<17?'Scroll. Keep the reader with you.':'Every little interaction, in frame.';
      time.textContent=`00:${String(Math.round(p*31)).padStart(2,'0')}`;
    };
    if(desktop) workflow.classList.add('is-animated');
    const tl=gsap.timeline({scrollTrigger:desktop
      ? {trigger:'.workflow',start:'top top',end:'+=2400',pin:true,scrub:.35,invalidateOnRefresh:true}
      : {trigger:'.process-stage',start:'top 85%',end:'bottom 10%',scrub:.25}});
    tl.to(progress,{value:1,duration:10,ease:'none',onUpdate:update},0)
      .from('.code-scene .code-key',{opacity:.5,stagger:.08,duration:.3},0)
      .to('.code-scene',{clipPath:'inset(0 100% 0 0)',duration:1,ease:'ui-move'},1.1)
      .fromTo('.capture-scene',{autoAlpha:0,clipPath:'inset(0 0 0 100%)'},{autoAlpha:1,clipPath:'inset(0 0 0 0)',duration:1,ease:'ui-move'},1.1)
      .from('.shot-note',{y:-12,opacity:0,duration:.45,ease:'ui-out'},2)
      .to('.shot-note',{autoAlpha:0,y:-8,duration:.3},5.2)
      .to('.capture-scene',{scale:.78,y:-36,autoAlpha:0,duration:.8,ease:'ui-move'},5.4)
      .fromTo('.edit-scene',{autoAlpha:0},{autoAlpha:1,duration:.25},5.6)
      .from('.edit-monitor',{scale:1.22,y:38,opacity:0,duration:.65,ease:'ui-move'},5.7)
      .from('.film-clip',{y:52,rotation:5,opacity:0,stagger:.15,duration:.6,ease:'ui-out'},6)
      .from('.title-track span',{scaleX:0,transformOrigin:'left',stagger:.18,duration:.5,ease:'ui-out'},6.7)
      .from('.edit-caption',{opacity:0,y:8,duration:.4,ease:'ui-out'},6.9)
      .from('.music-track',{scaleX:0,duration:.8,ease:'ui-move'},7.1)
      .to('.edit-scene',{clipPath:'inset(0 0 100% 0)',duration:.7,ease:'ui-move'},8.1)
      .fromTo('.render-scene',{autoAlpha:0,clipPath:'inset(100% 0 0 0)'},{autoAlpha:1,clipPath:'inset(0 0 0 0)',duration:.7,ease:'ui-move'},8.1)
      .from('.export-badge',{y:20,opacity:0,duration:.55,ease:'ui-out'},8.7)
      .from('.export-badge svg',{scale:.92,opacity:0,duration:.3,ease:'ui-out'},9.1);
    tl.fromTo('.story-progress>div',{scaleX:0},{scaleX:1,duration:10,ease:'none'},0)
      .to('.story-progress>b',{x:()=>document.querySelector('.story-progress')!.clientWidth,duration:10,ease:'none'},0);
    return () => {workflow.classList.remove('is-animated');selectStep(0);time.textContent='00:00';};
  });
  mm.add('(prefers-reduced-motion: no-preference)',()=>{
    gsap.utils.toArray<HTMLElement>('.detail-list article').forEach(article=>{
      gsap.from(article.querySelector('.detail-rule'),{scaleX:0,ease:'none',scrollTrigger:{trigger:article,start:'top 85%',end:'top 60%',scrub:.5}});
    });
  });
  ScrollTrigger.refresh();
  window.addEventListener('pagehide',()=>mm.revert(),{once:true});
}
initMotion();
