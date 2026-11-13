'use strict';
let worker=null, timer=null, active=null, currentPhase=null, messageCount=0;
const CAP=65536, encoder=new TextEncoder();
const phaseOrder={setup:0,compile:1,link:2,run:3};
function send(message) {
  if (window.webkit?.messageHandlers?.runtime) window.webkit.messageHandlers.runtime.postMessage(message);
  if (window.cfpocketProbe) window.cfpocketProbe(message);
}
function end(status,detail) {
  if (!active) return;
  const elapsed=performance.now()-active.start;
  worker?.terminate();worker=null;clearTimeout(timer);timer=null;
  send({type:'result',jobID:active.id,status,stdout:'',stderr:String(detail).slice(0,4096),durationMS:elapsed,environment:'Worker terminated'});active=null;
}
function arm(ms,status,detail) { clearTimeout(timer);timer=setTimeout(()=>end(status,detail),ms); }
window.startJob=function(job) {
  if(active) return send({type:'rejected',reason:'已有运行任务，请先停止。'});
  active={id:job.id,start:performance.now()};currentPhase='setup';messageCount=0;
  worker=new Worker('runner-worker.js');
  worker.onmessage=({data})=>{
    if(!active)return;
    // Python JS interop can post arbitrary objects. No extra fields cross the native bridge.
    if(++messageCount>64){end('message-limit','运行任务发送过多控制消息，底层 Worker 已终止。');return;}
    if(!data || typeof data!=='object')return;
    if(data.type==='output-limit'){end('output-limit','输出超过 64 KB，底层 Worker 已终止。');return;}
    if(data.type==='phase'){
      if(typeof data.phase!=='string')return;
      const rank=phaseOrder[data.phase];
      // Monotonic phases: a user program cannot restart deadlines with forged/repeated phase events.
      if(!Number.isInteger(rank) || rank<=phaseOrder[currentPhase])return;
      if(data.phase==='run')arm(job.timeoutMS||2000,'timeout','执行超过时限，底层 Worker 已终止。');
      else if(data.phase==='compile' && currentPhase==='setup')arm(30000,'compile-timeout','本地编译超过 30 秒，Worker 已终止。');
      currentPhase=data.phase;send({type:'phase',phase:currentPhase,jobID:active.id});return;
    }
    if(data.type!=='result')return;
    const stdout=typeof data.stdout==='string'?data.stdout:'';
    const stderr=typeof data.stderr==='string'?data.stderr:'';
    if(stdout.length+stderr.length>CAP || encoder.encode(stdout).length+encoder.encode(stderr).length>CAP){end('output-limit','运行结果超过 64 KB，底层 Worker 已终止。');return;}
    const status=['ok','compile-error','runtime-error','setup-error','unsupported-feature','output-limit'].includes(data.status)?data.status:'runtime-error';
    const environment=typeof data.environment==='string'?data.environment.slice(0,256):'WebKit Worker';
    const result={type:'result',jobID:active.id,status,stdout,stderr,durationMS:performance.now()-active.start,environment};
    worker.terminate();worker=null;clearTimeout(timer);timer=null;active=null;send(result);
  };
  worker.onerror=(e)=>end('runtime-error','运行环境错误：'+String(e.message).slice(0,4096));
  arm(60000,'setup-timeout','运行环境初始化超过 60 秒，Worker 已终止。');
  worker.postMessage(job);
};
window.stopJob=function(reason){end('stopped',reason||'你已停止运行；底层 Worker 已终止。');};
send({type:'ready'});
