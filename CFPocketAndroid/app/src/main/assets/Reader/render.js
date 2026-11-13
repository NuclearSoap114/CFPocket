'use strict';
if (typeof renderMathInElement === 'function') {
  renderMathInElement(document.body, {delimiters:[{left:'$$$',right:'$$$',display:false},{left:'$$',right:'$$',display:true},{left:'\\(',right:'\\)',display:false},{left:'\\[',right:'\\]',display:true},{left:'$',right:'$',display:false}],throwOnError:false,trust:false,maxExpand:1000,maxSize:10});
}
for (const pre of document.querySelectorAll('pre')) {
  const code = pre.querySelector('code') || pre;
  const language = [...code.classList].find(x => x.startsWith('language-'))?.slice(9) || 'CODE';
  const bar = document.createElement('div'); bar.className='code-tools';
  const label = document.createElement('span'); label.textContent=language.toUpperCase();
  const button=document.createElement('button'); button.type='button'; button.textContent='复制代码'; button.setAttribute('aria-label','复制代码');
  button.addEventListener('click',event=>{if(!event.isTrusted)return;window.webkit?.messageHandlers?.readerCopy?.postMessage(code.textContent);button.textContent='已复制';setTimeout(()=>button.textContent='复制代码',1400);});
  bar.append(label,button);pre.before(bar);
}
let lastHeight=0;
const report=()=>{const height=Math.ceil(document.body.getBoundingClientRect().height);if(height>0 && Math.abs(height-lastHeight)>1){lastHeight=height;window.webkit?.messageHandlers?.readerHeight?.postMessage(height);}};
new ResizeObserver(report).observe(document.body);
window.addEventListener('load',report);
document.fonts?.ready.then(report);
report();
