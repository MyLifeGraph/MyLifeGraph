import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {TEAM,PROJECTS,POLICY,EXPECTED_DAYS,makePlan,confirmation,executePlan,assertDeletable,policyMatches,childEnvironment} from './vercel_deployment_retention.mjs';
function fixture() {
  return PROJECTS.map((p,i)=>({project:{...p,accountId:TEAM,targets:{production:{id:`dpl_P${i}0`}},
    deploymentExpiration:{...EXPECTED_DAYS,deploymentsToKeep:10}},deployments:Array.from({length:6},(_,j)=>
      ({uid:`dpl_P${i}${j}`,created:100-j,state:'READY',target:'production',
        meta:{githubCommitSha:String(j+1).repeat(40),githubCommitRef:'main'}}))}));
}
const planOf=(entries=fixture(),aliases=[],refs=[])=>makePlan(entries,aliases,refs);
test('preserves live and two distinct READY production rollback sources',()=>{
  const plan=planOf();assert.deepEqual(plan.map(p=>p.kept.length),[3,3]);
  for(const p of plan)assert.equal(p.kept.filter(k=>k.reasons.includes('rollback')).length,2);
});
test('current preview and most recent open-PR preview remain protected',()=>{
  const e=fixture();e[0].deployments[3].target=null;e[0].deployments[3].meta.githubCommitRef='open';
  e[0].deployments[4].target=null;e[0].project.targets.preview={id:e[0].deployments[4].uid};
  const p=planOf(e,[],['open'])[0];assert(p.kept.some(d=>d.id===e[0].deployments[3].uid));
  assert(p.kept.some(d=>d.id===e[0].deployments[4].uid));
});
test('unknown source, in-flight deployment and custom domain are protected',()=>{
  const e=fixture();delete e[0].deployments[3].meta.githubCommitSha;e[0].deployments[4].state='BUILDING';
  const p=planOf(e,[{alias:'preview.example.org',deploymentId:e[0].deployments[5].uid}])[0];
  assert.equal(p.remove.length,0);
});
test('insufficient rollback history removes nothing',()=>{
  const e=fixture();for(const d of e[0].deployments)d.meta.githubCommitSha='a'.repeat(40);
  assert.equal(planOf(e)[0].remove.length,0);
});
test('malformed source cannot qualify as a trustworthy rollback',()=>{
  const e=fixture();for(const d of e[0].deployments)d.meta.githubCommitSha='a'.repeat(40);
  e[0].deployments[1].meta.githubCommitSha='_'.repeat(40);e[0].deployments[2].meta.githubCommitSha='b'.repeat(40);
  assert.equal(planOf(e)[0].remove.length,0);
});
test('foreign account, missing project and duplicate ids fail closed',()=>{
  const e=fixture();e[0].project.accountId='foreign';assert.throws(()=>planOf(e),/Unexpected/);
  assert.throws(()=>planOf(fixture().slice(0,1)),/Incomplete project/);
  const dup=fixture();dup[0].deployments[1].uid=dup[0].deployments[0].uid;assert.throws(()=>planOf(dup),/Invalid deployment/);
});
test('missing/non-READY live or missing target fails closed',()=>{
  const e=fixture();e[0].deployments[0].state='BUILDING';assert.throws(()=>planOf(e),/Live/);
  const f=fixture();f[0].project.targets.preview={id:'dpl_missing'};assert.throws(()=>planOf(f),/target missing/);
});
test('confirmation binds exact ids, protected sources and retention',()=>{
  const p=planOf();const copy=structuredClone(p);copy[0].kept[0].sha='f'.repeat(40);
  assert.notEqual(confirmation(p),confirmation(copy));
  copy[0].retention.expirationDays=7;assert.notEqual(confirmation(p),confirmation(copy));
});
function detail(p,d){return {id:d.id,projectId:p.id,ownerId:TEAM,readyState:d.state,meta:{githubCommitSha:d.sha},alias:[]};}
test('deletion guards reject protected, foreign, changed state/source and custom aliases',()=>{
  const p=planOf()[0],d=p.remove[0],valid=detail(p,d);assertDeletable(p,d,valid);
  assert.throws(()=>assertDeletable(p,p.kept[0],valid),/Protected/);
  for(const change of [{projectId:'foreign'},{ownerId:'foreign'},{readyState:'BUILDING'},
    {meta:{githubCommitSha:'f'.repeat(40)}},{alias:['live.example.org']},{alias:undefined}])
    assert.throws(()=>assertDeletable(p,d,{...valid,...change}));
});
test('native policy requires all durations and rollback floor',()=>{
  const p=fixture()[0].project;assert(policyMatches(p));
  for(const k of Object.keys(EXPECTED_DAYS))assert(!policyMatches({...p,deploymentExpiration:{...p.deploymentExpiration,[k]:30}}));
  assert(!policyMatches({...p,deploymentExpiration:{...p.deploymentExpiration,deploymentsToKeep:2}}));
});
test('native loader environment casing survives while application secrets are excluded',()=>{
  assert.deepEqual(childEnvironment({Path:'bin',SystemRoot:'win',windir:'win',ComSpec:'cmd',
    SUPABASE_SERVICE_ROLE_KEY:'secret',OPENAI_API_KEY:'secret',ANDROID_KEYSTORE_PASSWORD:'secret',GH_TOKEN:'secret'}),
    {Path:'bin',SystemRoot:'win',windir:'win',ComSpec:'cmd'});
  assert.deepEqual(childEnvironment({GH_TOKEN:'scoped'},true),{GH_TOKEN:'scoped'});
});
function harness(e=fixture()) {
  const calls=[];let aliases=[];
  const snapshot=()=>planOf(e,aliases,[]);
  const request=(path,method='GET',body)=>{
    calls.push({path,method,body});
    const entry=e.find(x=>path===`/v9/projects/${x.project.id}`||path===`/v9/projects/${x.project.id}/deployment-expiration`);
    if(entry){if(method==='PATCH'){assert.deepEqual(body,POLICY);Object.assign(entry.project.deploymentExpiration,EXPECTED_DAYS);}return structuredClone(entry.project);}
    const row=e.flatMap(x=>x.deployments.map(d=>({entry:x,row:d}))).find(x=>path===`/v13/deployments/${x.row.uid}`);
    if(!row)throw Error('Unknown fake endpoint');
    if(method==='DELETE'){row.entry.deployments=row.entry.deployments.filter(x=>x.uid!==row.row.uid);return {state:'DELETED',uid:row.row.uid};}
    return detail({id:row.entry.project.id},{id:row.row.uid,state:row.row.state,sha:row.row.meta.githubCommitSha});
  };
  return {snapshot,request,calls,setAliases:a=>aliases=a};
}
test('exact plan applies once and repetition is a no-op',()=>{
  const h=harness();assert.equal(executePlan(h.snapshot(),h).removedCount,6);
  const n=h.calls.filter(c=>c.method==='DELETE').length;assert.equal(executePlan(h.snapshot(),h).removedCount,0);
  assert.equal(h.calls.filter(c=>c.method==='DELETE').length,n);
});
test('plan drift prevents all writes',()=>{
  const h=harness(),p=h.snapshot();h.setAliases([{alias:'new.example.org',deploymentId:p[0].remove[0].id}]);
  assert.throws(()=>executePlan(p,h),/Plan drift/);assert.equal(h.calls.length,0);
});
test('new protection during apply stops subsequent deletions',()=>{
  const h=harness(),plan=h.snapshot(),original=h.snapshot;let calls=0;
  h.snapshot=()=>{if(++calls>1)h.setAliases([{alias:'new.example.org',deploymentId:plan[0].remove[0].id}]);return original();};
  assert.throws(()=>executePlan(plan,h),/Protection changed/);assert(!h.calls.some(c=>c.method==='DELETE'));
});
test('promotion after inventory is rechecked immediately before deletion',()=>{
  const e=fixture(),h=harness(e),p=h.snapshot(),request=h.request;
  h.request=(path,method,body)=>{
    const value=request(path,method,body);
    if(path===`/v13/deployments/${p[0].remove[0].id}`&&method===undefined)
      e[0].project.targets.production.id=p[0].remove[0].id;
    return value;
  };
  assert.throws(()=>executePlan(p,h),/target changed/);assert(!h.calls.some(c=>c.method==='DELETE'));
});
test('native retention update uses its dedicated endpoint and preserves minimum',()=>{
  const e=fixture();for(const x of e)Object.assign(x.project.deploymentExpiration,{expirationDays:30,expirationDaysProduction:30});
  const h=harness(e);executePlan(h.snapshot(),h);
  assert.equal(h.calls.filter(c=>c.method==='PATCH').length,2);
  for(const x of e){assert(policyMatches(x.project));assert.equal(x.project.deploymentExpiration.deploymentsToKeep,10);}
});
test('unconfirmed delete stops without claiming success',()=>{
  const h=harness(),request=h.request;h.request=(path,method,body)=>method==='DELETE'?{state:'ERROR'}:request(path,method,body);
  assert.throws(()=>executePlan(h.snapshot(),h),/not confirmed/);
});
test('source gate and mandatory publication workflow include retention checks',()=>{
  assert.match(readFileSync(new URL('../AGENTS.md',import.meta.url),'utf8'),/vercel:cleanup:auto/);
  const pkg=JSON.parse(readFileSync(new URL('../package.json',import.meta.url),'utf8'));
  assert(pkg.scripts['vercel:cleanup:auto']);assert.match(pkg.scripts['verify:vercel-release'],/vercel_deployment_retention\.test\.mjs/);
  assert.match(readFileSync(new URL('./verify_source.sh',import.meta.url),'utf8'),/node --test scripts\/vercel_deployment_retention\.test\.mjs/);
});
