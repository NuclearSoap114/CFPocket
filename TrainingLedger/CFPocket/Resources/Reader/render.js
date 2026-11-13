'use strict';
if (typeof renderMathInElement === 'function') {
  renderMathInElement(document.body, {delimiters:[{left:'$$$',right:'$$$',display:false},{left:'$$',right:'$$',display:true},{left:'\\(',right:'\\)',display:false},{left:'\\[',right:'\\]',display:true},{left:'$',right:'$',display:false}],throwOnError:false,trust:false,maxExpand:1000,maxSize:10});
}
PocketCode.decorate(document, text=>window.webkit?.messageHandlers?.readerCopy?.postMessage(text));
PocketCode.images(document);
let lastHeight=0;
const report=()=>{const height=Math.ceil(document.body.getBoundingClientRect().height);if(height>0 && Math.abs(height-lastHeight)>1){lastHeight=height;window.webkit?.messageHandlers?.readerHeight?.postMessage(height);}};
new ResizeObserver(report).observe(document.body);
window.addEventListener('load',report);
document.fonts?.ready.then(report);
report();
