import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';

export const TEAM = 'team_AwRAFUzs20r9FodIKqY7KwJq';
export const SCOPE = 'my-life-graph-s-projects';
export const PROJECTS = [
  {name:'my-life-graph',id:'prj_TNZ5tOIyM3s2e43xLXRJlyrYfDzS'},
  {name:'mylifegraph-website',id:'prj_GEg0siR9ZQH7y4kyvOCSnK0ocQ6H'},
];
export const POLICY = {expiration:'1d',expirationProduction:'1w',expirationCanceled:'1d',expirationErrored:'1d'};
export const EXPECTED_DAYS = {expirationDays:1,expirationDaysProduction:7,expirationDaysCanceled:1,expirationDaysErrored:1};

export function assertProject(p) {
  if(!PROJECTS.some(x=>x.id===p.id&&x.name===p.name)||p.accountId!==TEAM)
    throw Error('Unexpected Vercel project/account');
}
export function policyMatches(p) {
  assertProject(p);
  return Object.entries(EXPECTED_DAYS).every(([k,v])=>p.deploymentExpiration?.[k]===v)
    && Number.isInteger(p.deploymentExpiration?.deploymentsToKeep)
    && p.deploymentExpiration.deploymentsToKeep>=3;
}
export function confirmation(plan) {return createHash('sha256').update(JSON.stringify(plan)).digest('hex');}

export function makePlan(entries,aliases,activeRefs) {
  if(!Array.isArray(aliases)||!Array.isArray(activeRefs))throw Error('Incomplete alias/PR inventory');
  if(entries.length!==PROJECTS.length||new Set(entries.map(e=>e.project.id)).size!==PROJECTS.length)
    throw Error('Incomplete project inventory');
  return entries.map(({project:p,deployments})=>{
    assertProject(p);
    if(!Array.isArray(deployments)||new Set(deployments.map(d=>d.uid)).size!==deployments.length)
      throw Error('Invalid deployment inventory');
    const all=[...deployments].sort((a,b)=>b.created-a.created);
    const live=p.targets?.production?.id,liveRow=all.find(d=>d.uid===live);
    if(!liveRow||liveRow.state!=='READY'||liveRow.target!=='production')throw Error('Live deployment not READY');
    for(const d of all)if(!/^dpl_[A-Za-z0-9]+$/.test(d.uid)||!Number.isSafeInteger(d.created))throw Error('Invalid deployment identity');
    const protectedIds=new Map(),protect=(id,reason)=>{
      if(id)protectedIds.set(id,[...(protectedIds.get(id)??[]),reason]);
    };
    protect(live,'live');
    const seen=new Set([liveRow.meta?.githubCommitSha]);let rollbacks=0;
    for(const d of all) {
      const sha=d.meta?.githubCommitSha;
      if(d.target!=='production'||d.state!=='READY'||!/^[a-f0-9]{40}$/.test(sha??'')||seen.has(sha))continue;
      protect(d.uid,'rollback');seen.add(sha);if(++rollbacks===2)break;
    }
    // Too little trustworthy history is not permission to discard any output.
    if(rollbacks<2)for(const d of all)protect(d.uid,'insufficient rollback history');
    for(const target of Object.values(p.targets??{})) {
      if(target?.id&&!all.some(d=>d.uid===target.id))throw Error('Project target missing from inventory');
      protect(target?.id,'project target');
    }
    for(const d of all.slice(0,3))protect(d.uid,'recent3');
    for(const d of all) {
      if(!['READY','ERROR','CANCELED'].includes(d.state))protect(d.uid,'nonterminal');
      if(!/^[a-f0-9]{40}$/.test(d.meta?.githubCommitSha??''))protect(d.uid,'unknown source');
      const ref=d.meta?.githubCommitRef;
      if(activeRefs.includes(ref)&&all.find(x=>x.meta?.githubCommitRef===ref)?.uid===d.uid)protect(d.uid,'open PR');
    }
    for(const a of aliases) {
      const id=a.deploymentId??a.deployment?.id;
      if(a.alias&&!a.alias.endsWith('.vercel.app')&&all.some(d=>d.uid===id))protect(id,'custom domain');
    }
    const compact=d=>({id:d.uid,state:d.state,target:d.target??null,sha:d.meta?.githubCommitSha??null,created:d.created});
    return {id:p.id,name:p.name,live,retention:p.deploymentExpiration,
      kept:all.filter(d=>protectedIds.has(d.uid)).map(d=>({...compact(d),reasons:protectedIds.get(d.uid)})),
      remove:all.filter(d=>!protectedIds.has(d.uid)).map(compact)};
  });
}
export function assertDeletable(plan,candidate,detail) {
  if(plan.kept.some(d=>d.id===candidate.id)||!plan.remove.some(d=>d.id===candidate.id))throw Error('Protected/unknown deployment');
  if(detail.id!==candidate.id||detail.projectId!==plan.id||
      (detail.ownerId!==TEAM&&detail.team?.id!==TEAM)||detail.readyState!==candidate.state||
      detail.meta?.githubCommitSha!==candidate.sha)throw Error('Deployment drift');
  if(!Array.isArray(detail.alias)||detail.alias.some(a=>typeof a!=='string'||!a.endsWith('.vercel.app')))
    throw Error('Custom/unknown alias protection');
}
export function executePlan(plan,{snapshot,request,log=()=>{}}) {
  if(confirmation(snapshot())!==confirmation(plan))throw Error('Plan drift; preview again');
  const removed=[];
  for(const p of plan) {
    for(const d of p.remove) {
      // Recompute all protections, including newly opened PRs/aliases, before each deletion.
      const fresh=snapshot().find(x=>x.id===p.id);
      if(fresh?.live!==p.live||!fresh.remove.some(x=>x.id===d.id&&x.sha===d.sha))throw Error('Protection changed');
      assertDeletable(fresh,d,request(`/v13/deployments/${d.id}`));
      const latest=request(`/v9/projects/${p.id}`);assertProject(latest);
      if(latest.targets?.production?.id!==p.live||Object.values(latest.targets??{}).some(t=>t?.id===d.id))
        throw Error('Live/preview target changed before deletion');
      const r=request(`/v13/deployments/${d.id}`,'DELETE');
      if(r.state!=='DELETED'||r.uid!==d.id)throw Error('Deletion not confirmed; reconcile before retry');
      removed.push({project:p.name,id:d.id});log({deleted:d.id,project:p.name});
    }
    const current=request(`/v9/projects/${p.id}`);assertProject(current);
    if(current.targets?.production?.id!==p.live)throw Error('Live target changed');
    if(!Number.isInteger(current.deploymentExpiration?.deploymentsToKeep)||current.deploymentExpiration.deploymentsToKeep<3)
      throw Error('Rollback retention minimum unavailable');
    if(!policyMatches(current))request(`/v9/projects/${p.id}/deployment-expiration`,'PATCH',POLICY);
    const after=request(`/v9/projects/${p.id}`);
    if(!policyMatches(after)||after.targets?.production?.id!==p.live||
        after.deploymentExpiration.deploymentsToKeep!==current.deploymentExpiration.deploymentsToKeep)
      throw Error('Native policy verification failed');
  }
  return {removed,removedCount:removed.length};
}

export function childEnvironment(environment=process.env,github=false) {
  const keys=['PATH','HOME','USERPROFILE','USERNAME','USERDOMAIN','HOMEDRIVE','HOMEPATH','USER','LOGNAME',
    'APPDATA','LOCALAPPDATA','SystemRoot','SystemDrive','windir','ComSpec','ProgramData','PATHEXT',
    'TEMP','TMP','LANG','SSH_AUTH_SOCK'];
  if(github)keys.push('GH_TOKEN','GITHUB_TOKEN');
  const allowed=new Set(keys.map(k=>k.toLowerCase()));
  // Preserve Windows' original environment-key casing for native executable loaders.
  return Object.fromEntries(Object.entries(environment).filter(([k])=>allowed.has(k.toLowerCase())));
}
function cliRequest(path,method='GET',body) {
  if(!/^\/[a-zA-Z0-9/?=&_.-]+$/.test(path))throw Error('Invalid endpoint');
  const host=process.env.MLG_VERCEL_SSH_HOST,cli=process.env.MLG_VERCEL_CLI??'vercel';
  const args=['api',path,'--scope',SCOPE,'--raw'];
  if(method!=='GET')args.push('-X',method);
  if(body)args.push('--input','-');
  if(method==='DELETE')args.push('--dangerously-skip-permissions');
  let executable=cli;
  if(host) {
    if(!/^[a-zA-Z0-9_.@-]+$/.test(host)||!/^[/a-zA-Z0-9_.-]+$/.test(cli))throw Error('Invalid SSH adapter');
    executable=process.env.MLG_SSH_CLI??(process.platform==='win32'?join(process.env.SystemRoot??'C:/Windows','System32','OpenSSH','ssh.exe'):'ssh');
    const remote=args.map(a=>`'${a}'`).join(' ');
    args.splice(0,args.length,'-o','BatchMode=yes','-o','ConnectTimeout=20',host,`${cli} ${remote}`);
  }
  return JSON.parse(execFileSync(executable,args,{encoding:'utf8',windowsHide:true,timeout:60000,
    maxBuffer:12000000,input:body?JSON.stringify(body):undefined,env:childEnvironment()}));
}
function paged(path,key) {
  const result=[],seen=new Set();let next;
  do {
    const r=cliRequest(path+(next?`&until=${next}`:''));
    if(!Array.isArray(r[key]))throw Error('Missing inventory page');result.push(...r[key]);
    next=r.pagination?.next;
    if(next&&(!Number.isSafeInteger(next)||seen.has(next)))throw Error('Invalid pagination');
    seen.add(next);if(result.length>2000)throw Error('Inventory limit exceeded');
  }while(next);
  return result;
}
function snapshot() {
  const refs=JSON.parse(execFileSync(process.env.MLG_GH_CLI??'gh',['pr','list','--repo','MyLifeGraph/MyLifeGraph',
    '--state','open','--limit','100','--json','headRefName'],{encoding:'utf8',windowsHide:true,timeout:30000,env:childEnvironment(process.env,true)}));
  if(!Array.isArray(refs)||refs.length>=100)throw Error('Incomplete PR inventory');
  return makePlan(PROJECTS.map(p=>({project:cliRequest(`/v9/projects/${p.id}`),
    deployments:paged(`/v6/deployments?projectId=${p.id}&limit=100`,'deployments')})),
    paged('/v4/aliases?limit=100','aliases'),refs.map(x=>x.headRefName));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  try {
    const origin=execFileSync('git',['remote','get-url','origin'],{encoding:'utf8',env:childEnvironment()}).trim();
    if(!['https://github.com/MyLifeGraph/MyLifeGraph.git','git@github.com:MyLifeGraph/MyLifeGraph.git'].includes(origin))throw Error('Foreign repository');
    const mode=process.argv[2]??'dry-run';
    if(!['dry-run','apply','auto'].includes(mode))throw Error('Unknown mode');
    const plan=snapshot(),hash=confirmation(plan);
    console.log(JSON.stringify({dryRun:true,confirmation:hash,plan},null,2));
    if(mode==='apply'&&process.argv[3]!==hash)throw Error('Exact preview confirmation required');
    if(mode!=='dry-run')console.log(JSON.stringify(executePlan(plan,{snapshot,request:cliRequest,log:r=>console.log(JSON.stringify(r))}),null,2));
  }catch(error){console.error(error.message);process.exitCode=1;}
}
