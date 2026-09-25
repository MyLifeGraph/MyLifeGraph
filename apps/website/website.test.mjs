import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {german,demoCopy,tourCopy,signals,chartPoints} from './public/content.js';
import {appearances,normalizeAppearance,appearanceIcon} from './public/appearance.js';
const html=await readFile(new URL('./public/index.html',import.meta.url),'utf8');
const script=await readFile(new URL('./public/app.js',import.meta.url),'utf8');
const config=JSON.parse(await readFile(new URL('./vercel.json',import.meta.url),'utf8'));

test('every visible and accessible page label has a German translation',()=>{
  const keys=[...html.matchAll(/data-(?:copy|aria)="([^"]+)"/g)].map(m=>m[1]);
  assert(keys.length>65);
  for(const key of keys)assert.equal(typeof german[key],'string',key);
  assert.deepEqual(new Set(keys),new Set(Object.keys(german)));
});
test('both demo languages cover identical controls and content',()=>{
  assert.deepEqual(Object.keys(tourCopy.en).sort(),Object.keys(tourCopy.de).sort());
  assert.deepEqual(Object.keys(demoCopy.en).sort(),Object.keys(demoCopy.de).sort());
  for(const c of Object.values(demoCopy)){
    assert.equal(c.days.length,7);assert.equal(c.events.length,7);
    assert.equal(c.taskNames.length,3);assert.equal(c.prompts.length,2);assert.equal(c.answers.length,2);
    assert.equal(c.events[6].length,0);
  }
});
test('four distinct theme icons, safe saved-value fallback and Liquid Glass default',()=>{
  assert.equal(appearances.length,4);
  assert.equal(new Set(appearances.map(t=>appearanceIcon(t.id))).size,4);
  for(const theme of appearances)assert.equal(normalizeAppearance(theme.id),theme.id);
  for(const invalid of [null,undefined,'','system','<script>'])assert.equal(normalizeAppearance(invalid),'liquid-glass');
  assert.match(html,/data-theme="liquid-glass"/);
  assert.match(script,/mylifegraph\.website\.appearance/);
  assert.match(script,/closeAppearance\(true\)/);
  assert.match(script,/event.key==='Escape'/);
});
test('example charts are finite, in bounds and use seven values in both periods',()=>{
  for(const s of Object.values(signals))for(const values of [s.recent,s.previous]){
    assert.equal(values.length,7);
    const points=chartPoints(values,s.min,s.max).split(' ').map(p=>p.split(',').map(Number));
    for(const [x,y]of points){assert(x>=20&&x<=500);assert(y>=25&&y<=150);}
  }
});
test('demo cannot call a backend or collect account data',()=>{
  const csp=config.headers[0].headers.find(h=>h.key==='Content-Security-Policy').value;
  assert.match(csp,/connect-src 'none'/);assert.match(csp,/form-action 'none'/);
  assert.doesNotMatch(html,/<(?:iframe|form|input)\b/i);
  assert.doesNotMatch(script,/\b(?:fetch|XMLHttpRequest|WebSocket|sendBeacon)\b/);
  assert.doesNotMatch(script,/navigator\.(?:mediaDevices|geolocation)/);
  assert.match(script,/let language='en'/);
  assert.match(script,/mylifegraph\.website\.language/);
  assert.equal(config.outputDirectory,'public');
});
test('public assets are local, CTA targets are only the existing app and repository',()=>{
  for(const match of html.matchAll(/(?:src|href)="([^"]+)"/g)){
    const url=match[1];
    assert(url.startsWith('/')||url.startsWith('#')||url.startsWith('https://my-life-graph-my-life-graph-s-projects.vercel.app/')||url.startsWith('https://github.com/MyLifeGraph/MyLifeGraph'),url);
  }
  assert.match(html,/role="tablist"/);assert.match(html,/role="tabpanel"/);
  assert.match(script,/ArrowRight/);assert.match(script,/ArrowLeft/);
});

test('product scene is decorative and independent of scrolling',async()=>{
  const css=await readFile(new URL('./public/product-scene.css',import.meta.url),'utf8');
  assert.doesNotMatch(html,/<video|tour\.mp4|film-section/);
  assert.match(html,/class="product-scene" aria-hidden="true"/);
  assert.doesNotMatch(css,/animation-timeline|view-timeline/);
  assert.match(css,/prefers-reduced-motion:reduce/);
  assert.match(css,/pointer-events:none/);
  assert(html.indexOf('class="product-scene"')<html.indexOf('id="demo"'));
});

test('phone loop is subtle, visibility-paused and respects motion preferences',async()=>{
  const css=await readFile(new URL('./public/product-scene.css',import.meta.url),'utf8');
  const motion=await readFile(new URL('./public/product-motion.js',import.meta.url),'utf8');
  assert.match(html,/class="product-float"><div class="product-phone"/);
  assert.match(css,/product-float 8s ease-in-out infinite/);
  assert.match(css,/translateY\(-5px\)/);
  assert.match(css,/animation-play-state:paused/);
  assert.match(css,/data-moving=true/);
  assert.match(css,/@media\(prefers-reduced-motion:no-preference\)/);
  assert.match(css,/@media\(hover:hover\) and \(pointer:fine\)/);
  assert.match(css,/\.product-float:hover\{rotate:y 6deg\}/);
  assert.match(motion,/IntersectionObserver/);assert.match(motion,/visibilitychange/);
  assert.match(motion,/visible&&!document.hidden/);
});
