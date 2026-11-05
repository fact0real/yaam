'use strict';
document.documentElement.classList.add('js-enabled');

// Navigation is enhanced progressively: links and feature details work without JavaScript.
const menuButton = document.querySelector('.menu-toggle');
const nav = document.querySelector('#main-nav');
menuButton.hidden = false;
menuButton.addEventListener('click', () => {
  const open = menuButton.getAttribute('aria-expanded') !== 'true';
  menuButton.setAttribute('aria-expanded', String(open));
  nav.classList.toggle('is-open', open);
});
nav.addEventListener('click', event => {
  if (!event.target.closest('a')) return;
  nav.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
});
document.addEventListener('keydown', event => {
  if (event.key !== 'Escape' || !nav.classList.contains('is-open')) return;
  nav.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
  menuButton.focus();
});

const galleryData = {
  globe: ['Globe & Grids', 'Explore worked and confirmed stations, Maidenhead squares and great-circle paths.'],
  log_table: ['Logbook', 'Search, filter and inspect contact records with band, mode, station and confirmation context.'],
  statistics: ['Statistics', 'Review confirmation sources, country-band coverage and follow-up opportunities.'],
  contest: ['Contest Operations', 'Keep contest sessions, exchanges and operating context together at the desk.'],
  rover_mode: ['Rover', 'Bring changing location and grid context into your portable operating workflow.'],
  sync_center: ['Sync Center', 'Configure log sources, online service connections and synchronization workflows.']
};
const galleryImage = document.querySelector('#gallery-image');
const galleryDescription = document.querySelector('#gallery-description');
const galleryTabs = [...document.querySelectorAll('[data-gallery]')];
let currentGallery = 'globe';
function selectGallery(tab, focus = false) {
  currentGallery = tab.dataset.gallery;
  const [title, description] = galleryData[currentGallery];
  galleryTabs.forEach(item => {
    const active = item === tab;
    item.setAttribute('aria-selected', String(active));
    item.tabIndex = active ? 0 : -1;
  });
  galleryImage.src = `/assets/${currentGallery}.webp`;
  galleryImage.alt = `YAAM ${title} application screenshot. ${description}`;
  document.querySelector('#gallery-title').textContent = title;
  galleryDescription.textContent = description;
  galleryDescription.setAttribute('aria-labelledby', tab.id);
  document.querySelector('#gallery-enlarge').setAttribute('aria-label', `Enlarge ${title} screenshot`);
  if (focus) tab.focus();
}
galleryTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectGallery(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % galleryTabs.length;
    if (event.key === 'ArrowLeft') next = (index + galleryTabs.length - 1) % galleryTabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = galleryTabs.length - 1;
    if (next === undefined) return;
    event.preventDefault();
    selectGallery(galleryTabs[next], true);
  });
});
const screenshotDialog = document.querySelector('#screenshot-dialog');
document.querySelector('#gallery-enlarge').addEventListener('click', () => {
  const image = document.querySelector('#dialog-image');
  image.src = galleryImage.src;
  image.alt = galleryImage.alt;
  document.querySelector('#dialog-title').textContent = galleryData[currentGallery][0];
  screenshotDialog.showModal();
});
document.querySelector('#close-dialog').addEventListener('click', () => screenshotDialog.close());
screenshotDialog.addEventListener('click', event => {
  if (event.target !== screenshotDialog) return;
  const box = screenshotDialog.getBoundingClientRect();
  if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) screenshotDialog.close();
});

const searchInput = document.querySelector('#feature-search');
const featureGroups = [...document.querySelectorAll('.feature-group')];
const status = document.querySelector('#feature-status');
const expandButton = document.querySelector('#expand-features');
const featureCount = document.querySelectorAll('.feature-item').length;
expandButton.hidden = false;
status.textContent = `${featureCount} capabilities · ${featureGroups.length} categories`;
let savedOpenState = null;
function updateExpandButton() {
  const visible = featureGroups.filter(group => !group.hidden);
  const allOpen = visible.length > 0 && visible.every(group => group.open);
  expandButton.setAttribute('aria-expanded', String(allOpen));
  expandButton.innerHTML = `${allOpen ? 'Collapse all' : 'Expand all'} <span aria-hidden="true">${allOpen ? '−' : '+'}</span>`;
}
searchInput.addEventListener('input', () => {
  const terms = searchInput.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const searching = terms.length > 0;
  if (searching && savedOpenState === null) savedOpenState = featureGroups.map(group => group.open);
  let matched = 0;
  featureGroups.forEach((group, index) => {
    const groupTitle = group.querySelector('summary').textContent.toLocaleLowerCase();
    let shown = 0;
    group.querySelectorAll('.feature-item').forEach(item => {
      const haystack = `${groupTitle} ${item.textContent}`.toLocaleLowerCase();
      item.hidden = !terms.every(term => haystack.includes(term));
      if (!item.hidden) shown++;
    });
    group.hidden = shown === 0;
    if (searching) group.open = shown > 0;
    else if (savedOpenState) group.open = savedOpenState[index];
    matched += shown;
  });
  if (!searching) savedOpenState = null;
  document.querySelector('#no-features').hidden = matched !== 0;
  status.textContent = searching ? `${matched} matching ${matched === 1 ? 'capability' : 'capabilities'}` : `${featureCount} capabilities · ${featureGroups.length} categories`;
  expandButton.disabled = matched === 0;
  updateExpandButton();
});
expandButton.addEventListener('click', () => {
  const open = expandButton.getAttribute('aria-expanded') !== 'true';
  featureGroups.filter(group => !group.hidden).forEach(group => { group.open = open; });
  updateExpandButton();
});
featureGroups.forEach(group => group.addEventListener('toggle', updateExpandButton));
function openFeatureHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  if (!id.startsWith('feature-') && id !== 'mode-support') return;
  const target = document.getElementById(id);
  if (!(target instanceof HTMLDetailsElement)) return;
  if (searchInput.value) {
    searchInput.value = '';
    searchInput.dispatchEvent(new Event('input'));
  }
  target.open = true;
  requestAnimationFrame(() => target.scrollIntoView({ block: 'start' }));
}
window.addEventListener('hashchange', openFeatureHash);
document.querySelectorAll('.feature-jump').forEach(link => link.addEventListener('click', () => {
  const target = document.getElementById(link.hash.slice(1));
  if (target) target.open = true;
}));
openFeatureHash();

// Comparison uses documented workflows; highlighting is an integration filter, not a ranking.
const comparisonButtons = [...document.querySelectorAll('[data-comparison]')];
comparisonButtons.forEach(button => button.addEventListener('click', () => {
  const advantages = button.dataset.comparison === 'advantages';
  comparisonButtons.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  document.querySelectorAll('.comparison-table tbody tr').forEach(row => {
    row.hidden = advantages && !row.classList.contains('yaam-edge');
  });
  document.querySelector('#comparison-status').textContent = advantages
    ? '7 integrated advantages · see scope and sources below'
    : '23 workflows compared · scroll to explore';
}));

// Motion respects both the system preference and an explicit, in-memory visitor setting.
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const motionButton = document.querySelector('#motion-toggle');
let motionPaused = reducedMotion.matches;
motionButton.hidden = false;
function updateMotion() {
  motionButton.textContent = motionPaused ? 'Enable motion' : 'Pause motion';
  motionButton.setAttribute('aria-pressed', String(motionPaused));
  document.documentElement.classList.toggle('motion-paused', motionPaused);
}
motionButton.addEventListener('click', () => { motionPaused = !motionPaused; updateMotion(); restartGlobe(); });
reducedMotion.addEventListener('change', event => { motionPaused = event.matches; updateMotion(); restartGlobe(); });
updateMotion();

// Orthographic globe. Natural Earth public-domain land geometry, rendered locally.
const canvas = document.querySelector('#station-globe');
const ctx = canvas.getContext('2d');
let land = [];
let width = 0;
let height = 0;
let radius = 0;
let frameId = 0;
let inView = true;
let rotation = -50 * Math.PI / 180;
let lastFrame = 0;
let phase = 0;
const rad = Math.PI / 180;
function sphere(lon, lat) {
  return [Math.cos(lat * rad) * Math.sin(lon * rad), Math.sin(lat * rad), Math.cos(lat * rad) * Math.cos(lon * rad)];
}
function project(vector, scale = 1) {
  const [x, y, z] = vector;
  const tx = x * Math.cos(rotation) + z * Math.sin(rotation);
  const tz = z * Math.cos(rotation) - x * Math.sin(rotation);
  const tilt = .18;
  const ty = y * Math.cos(tilt) - tz * Math.sin(tilt);
  return [width / 2 + tx * radius * scale, height / 2 - ty * radius * scale, tz * Math.cos(tilt) + y * Math.sin(tilt)];
}
const arcs = [[-72,42], [139,35], [24,-28], [151,-33], [0,52], [-45,-20], [77,28]].map(([lon,lat]) => {
  const from = sphere(53,34), to = sphere(lon,lat);
  const angle = Math.acos(Math.min(1, Math.max(-1, from.reduce((sum, v, i) => sum + v * to[i], 0))));
  return Array.from({length:61}, (_, i) => {
    const t = i / 60;
    const a = Math.sin((1 - t) * angle) / Math.sin(angle);
    const b = Math.sin(t * angle) / Math.sin(angle);
    return [from.map((v,j) => v * a + to[j] * b), 1 + Math.sin(t * Math.PI) * .19];
  });
});
function strokeCoordinates(vectors, color, lineWidth = .5) {
  ctx.beginPath();
  let pen = false;
  vectors.forEach(vector => {
    const p = project(vector);
    if (p[2] < 0) { pen = false; return; }
    if (pen) ctx.lineTo(p[0],p[1]); else ctx.moveTo(p[0],p[1]);
    pen = true;
  });
  ctx.strokeStyle = color;
  ctx.lineWidth = lineWidth;
  ctx.stroke();
}
function drawGlobe() {
  if (!ctx || !width || !height) return;
  ctx.clearRect(0,0,width,height);
  const cx = width / 2, cy = height / 2;
  // Outer scale and orbital plane.
  ctx.strokeStyle = '#80b5bf24'; ctx.lineWidth = .6;
  ctx.beginPath(); ctx.arc(cx,cy,radius*1.2,0,Math.PI*2); ctx.stroke();
  for (let i=0;i<72;i++) {
    const a = i*Math.PI/36;
    const inner = radius*(i%6===0?1.18:1.195);
    ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*inner,cy+Math.sin(a)*inner);ctx.lineTo(cx+Math.cos(a)*radius*1.21,cy+Math.sin(a)*radius*1.21);ctx.stroke();
  }
  ctx.setLineDash([3,7]);
  ctx.beginPath();ctx.ellipse(cx,cy,radius*1.35,radius*.38,-.36,0,Math.PI*2);ctx.strokeStyle='#daab5a46';ctx.stroke();ctx.setLineDash([]);
  const glow = ctx.createRadialGradient(cx-radius*.3,cy-radius*.4,0,cx,cy,radius*1.1);
  glow.addColorStop(0,'#1b3e49');glow.addColorStop(.7,'#112d36');glow.addColorStop(1,'#10232b');
  ctx.fillStyle=glow;ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.fill();
  ctx.save();ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.clip();
  for (let latitude=-60;latitude<=60;latitude+=20) strokeCoordinates(Array.from({length:121},(_,i)=>sphere(i*3-180,latitude)),'#68b5c72b');
  for (let longitude=-180;longitude<180;longitude+=20) strokeCoordinates(Array.from({length:91},(_,i)=>sphere(longitude,i*2-90)),'#68b5c725');
  land.forEach(ring => {
    const visible = ring.map(p=>project(p));
    ctx.beginPath();let pen=false;
    visible.forEach(p=>{if(p[2]<0){pen=false;return;}if(pen)ctx.lineTo(p[0],p[1]);else ctx.moveTo(p[0],p[1]);pen=true;});
    ctx.strokeStyle='#57c1d377';ctx.lineWidth=.8;ctx.stroke();
    if (visible.every(p=>p[2]>=0)) {ctx.closePath();ctx.fillStyle='#2b768b20';ctx.fill();}
  });
  // Land vertices provide a restrained point texture rather than invented live data.
  ctx.fillStyle='#79d0df73';
  land.forEach(ring=>ring.forEach((point,index)=>{if(index%5)return;const p=project(point);if(p[2]>.08){ctx.beginPath();ctx.arc(p[0],p[1],.6,0,Math.PI*2);ctx.fill();}}));
  ctx.restore();
  ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.strokeStyle='#69bdd25e';ctx.lineWidth=1;ctx.shadowColor='#18a4d1';ctx.shadowBlur=16;ctx.stroke();ctx.shadowBlur=0;
  arcs.forEach((arc,index)=>{
    ctx.beginPath();let pen=false;
    arc.forEach(([vector,scale])=>{const p=project(vector,scale);if(p[2]<0){pen=false;return;}if(pen)ctx.lineTo(p[0],p[1]);else ctx.moveTo(p[0],p[1]);pen=true;});
    ctx.strokeStyle=index%2?'#f9a22972':'#f9a229b3';ctx.lineWidth=.85;ctx.stroke();
    const particle=arc[Math.floor(((phase*.06+index*.14)%1)*60)];
    const p=project(particle[0],particle[1]);
    if(p[2]>0){ctx.beginPath();ctx.arc(p[0],p[1],1.7,0,Math.PI*2);ctx.fillStyle='#ffc878';ctx.shadowColor='#f9a229';ctx.shadowBlur=8;ctx.fill();ctx.shadowBlur=0;}
    const end=project(arc[60][0]);
    if(end[2]>0){ctx.beginPath();ctx.arc(end[0],end[1],2,0,Math.PI*2);ctx.fillStyle='#f9b34d';ctx.fill();ctx.beginPath();ctx.arc(end[0],end[1],5,0,Math.PI*2);ctx.strokeStyle='#f9a22970';ctx.lineWidth=.5;ctx.stroke();}
  });
  const origin=project(sphere(53,34));
  if(origin[2]>0){ctx.beginPath();ctx.arc(origin[0],origin[1],4,0,Math.PI*2);ctx.fillStyle='#b0eeff';ctx.shadowColor='#18a4d1';ctx.shadowBlur=15;ctx.fill();ctx.shadowBlur=0;ctx.beginPath();ctx.arc(origin[0],origin[1],10,0,Math.PI*2);ctx.strokeStyle='#85dcf0aa';ctx.lineWidth=.6;ctx.stroke();}
}
function animateGlobe(now) {
  frameId = 0;
  if (!inView || document.hidden || motionPaused) {lastFrame=0;return;}
  if (now-lastFrame >= 32) {
    const elapsed=lastFrame ? Math.min(now-lastFrame,100) : 0;
    rotation+=elapsed*.000015;
    phase+=elapsed*.001;
    drawGlobe();
    lastFrame=now;
  }
  frameId=requestAnimationFrame(animateGlobe);
}
function restartGlobe() {
  if(frameId)cancelAnimationFrame(frameId);
  frameId=0;lastFrame=0;
  drawGlobe();
  if(!motionPaused && !document.hidden && inView)frameId=requestAnimationFrame(animateGlobe);
}
function resizeGlobe() {
  const bounds=canvas.getBoundingClientRect();
  width=bounds.width;height=bounds.height;
  const dpr=Math.min(devicePixelRatio||1,2);
  canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);
  if(ctx)ctx.setTransform(dpr,0,0,dpr,0,0);
  radius=Math.min(width*.35,height*.35);
  restartGlobe();
}
if(ctx){
  new ResizeObserver(resizeGlobe).observe(canvas);
  new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;restartGlobe();},{rootMargin:'40px'}).observe(canvas);
  document.addEventListener('visibilitychange',restartGlobe);
  fetch('/assets/land.json').then(response=>{if(!response.ok)throw Error('Geometry unavailable');return response.json();}).then(data=>{land=data.map(ring=>ring.map(([lon,lat])=>sphere(lon,lat)));drawGlobe();}).catch(()=>{});
}

// Reveal only content that is already below the initial viewport.
if (!reducedMotion.matches && 'IntersectionObserver' in window) {
  const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{
    if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target);}
  }),{threshold:.06});
  document.querySelectorAll('.workflow-row,.intro-columns article,.beyond-grid article,.engineering-grid article').forEach(element=>{
    if(element.getBoundingClientRect().top>innerHeight){element.classList.add('reveal');observer.observe(element);}
  });
  document.documentElement.classList.add('page-ready');
}
