/* CF Pocket worker: bundled compiler/interpreter, one process per job, no native secret bridge. */
'use strict';
const CAP = 65536;
let stage = 'setup', stdout = '', stderr = '', bytes = 0, outputOverflow = false;
const encoder = new TextEncoder();
function emit(text, fd = 1) {
  text = String(text); bytes += encoder.encode(text).length;
  if (bytes > CAP) { outputOverflow = true; postMessage({type:'output-limit',stdout,stderr}); const error = new Error('输出超过 64 KB，已终止本次运行'); error.name = 'OutputLimit'; throw error; }
  if (fd === 2) stderr += text; else stdout += text;
}
function phase(value) { stage = value; postMessage({type:'phase', phase:value}); }
async function buffer(name) {
  const response = await fetch(new URL(name, self.location.href));
  if (!response.ok) throw Error('本地运行资源缺失：' + name);
  return response.arrayBuffer();
}
const bitsHeader = `// CF Pocket compatibility aggregator for libc++; this is NOT GNU libstdc++.
#include <algorithm>
#include <array>
#include <bitset>
#include <cassert>
#include <cctype>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <list>
#include <map>
#include <numeric>
#include <optional>
#include <queue>
#include <random>
#include <ranges>
#include <set>
#include <span>
#include <sstream>
#include <stack>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>
`;
async function cpp(job) {
  if (/^\s*#\s*include\s*[<"](?:ext\/pb_ds\/|bits\/extc\+\+\.h)/m.test(job.source)) { const error = new Error('当前 libc++ / WASI 环境不包含 GNU PBDS；这不是对算法正确性的判断。'); error.name = 'UnsupportedFeature'; throw error; }
  importScripts('cpp/shared.js');
  const api = new self.CFPocketClang({
    readBuffer: n => buffer('cpp/' + n), compileStreaming: async n => WebAssembly.compile(await buffer('cpp/' + n)),
    hostWrite: (text, fd) => { if (fd !== undefined) emit(stage === 'run' ? text : text.replace(/\x1b\[[0-9;]*m/g, ''), stage === 'run' ? fd : 2); },
    clang:'clang22', lld:'lld22', sysroot:'sysroot22.tar', clangResourceInclude:'/lib/clang/22/include',
    clangExtraArgs:['-internal-isystem','/include/wasm32-wasip1/noeh/c++/v1','-internal-isystem','/include/wasm32-wasip1','-std=' + (job.standard === 'c++17' ? 'c++17' : 'c++20')],
    lldLibdir:'lib/wasm32-wasip1', lldFlags:['--export-dynamic','--max-memory=268435456'],
    lldLibs:['-lc','-lc++','-lc++abi','-lclang_rt.builtins']
  });
  await api.ready;
  api.memfs.addDirectory('include/bits'); api.memfs.addFile('include/bits/stdc++.h', bitsHeader);
  phase('compile');
  await api.compile({input:'main.cc',contents:job.source,obj:'main.o'});
  phase('link'); await api.link('main.o','main.wasm');
  const module = await WebAssembly.compile(api.memfs.getFileContents('main.wasm'));
  api.memfs.setStdinStr(job.stdin || '');
  phase('run');
  await api.run(module,'main.wasm');
  return 'Clang/LLD 22.1.8 · libc++ / WASI · ' + (job.standard || 'c++20');
}
async function python(job) {
  importScripts('python/pyodide.js');
  const py = await loadPyodide({indexURL:new URL('python/',self.location.href).href,stdout:s=>emit(s+'\n'),stderr:s=>emit(s+'\n',2),fullStdLib:false});
  // No downloaded packages. Every execution gets a new interpreter/FS. Network is bounded by the document CSP.
  const stdinBytes = encoder.encode(job.stdin || ''); let stdinAt = 0;
  py.setStdin({read: target => { const n = Math.min(target.length, stdinBytes.length - stdinAt); target.set(stdinBytes.subarray(stdinAt, stdinAt + n)); stdinAt += n; return n; }, isatty:false});
  py.setStdout({write: b=>{emit(new TextDecoder().decode(b));return b.length;}});
  py.setStderr({write: b=>{emit(new TextDecoder().decode(b),2);return b.length;}});
  const version = py.runPython('import sys; sys.version.split()[0]');
  phase('run');
  py.runPython(job.source, {filename:'main.py'});
  return 'CPython ' + version + ' · Pyodide 314.0.7 / WASM';
}
self.onmessage = async ({data:job}) => {
  const start=performance.now();
  try {
    if (encoder.encode(job.source||'').length>262144 || encoder.encode(job.stdin||'').length>65536) throw Error('源码或输入超过长度限制');
    const environment=job.language==='Python'?await python(job):await cpp(job);
    postMessage({type:'result',status:'ok',stdout,stderr,durationMS:performance.now()-start,environment});
  } catch(error) {
    let status=outputOverflow||error.name==='OutputLimit'?'output-limit':error.name==='UnsupportedFeature'?'unsupported-feature':stage==='compile'||stage==='link'?'compile-error':stage==='setup'?'setup-error':'runtime-error';
    postMessage({type:'result',status,stdout,stderr:stderr+'\n'+String(error.message||error),durationMS:performance.now()-start,environment:job.language==='Python'?'Pyodide 314.0.7':'Clang/LLD 22.1.8 / WASI'});
  }
};
