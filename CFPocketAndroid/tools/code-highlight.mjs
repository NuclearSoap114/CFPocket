import hljs from 'highlight.js/lib/core';
import cpp from 'highlight.js/lib/languages/cpp';
import python from 'highlight.js/lib/languages/python';
hljs.registerLanguage('cpp', cpp);
hljs.registerLanguage('python', python);

// VS Code's MIT-licensed Light+ / Dark+ token colors. Shared by WebView and UIKit.
const light={background:'#FFFFFF',foreground:'#000000',keyword:'#0000FF',control:'#AF00DB',type:'#267F99',function:'#795E26',string:'#A31515',number:'#098658',comment:'#008000',meta:'#0000FF',variable:'#001080',punctuation:'#000000',line:'#E5E5E5'};
const dark={background:'#1E1E1E',foreground:'#D4D4D4',keyword:'#569CD6',control:'#C586C0',type:'#4EC9B0',function:'#DCDCAA',string:'#CE9178',number:'#B5CEA8',comment:'#6A9955',meta:'#569CD6',variable:'#9CDCFE',punctuation:'#D4D4D4',line:'#3C3C3C'};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#x27;'}[c]));
const decode=s=>s.replace(/&(amp|lt|gt|quot|#x27|#39);/g,(_,k)=>({amp:'&',lt:'<',gt:'>',quot:'"','#x27':"'",'#39':"'"}[k]));
function language(value='cpp'){value=String(value).trim();return /^(py|python|python3)$/i.test(value)?'python':!value||/^(cpp|c|cxx|cc|c\+\+\d*|gnu\+\+\d*)$/i.test(value)?'cpp':'plaintext';}
function tokens(text,lang='cpp'){
  text=String(text);const selected=language(lang);
  if(selected==='plaintext'||text.length>262144)return [{text,kind:'foreground'}];
  const html=hljs.highlight(text,{language:selected,ignoreIllegals:true}).value;
  const stack=[],result=[];
  for(const part of html.match(/<span class="[^"]*">|<\/span>|[^<]+/g)||[]){
    if(part.startsWith('<span')){stack.push(part.match(/class="([^"]*)"/)[1]);continue;}
    if(part==='</span>'){stack.pop();continue;}
    const value=decode(part),scope=stack.join(' ');let kind='foreground';
    if(/comment/.test(scope))kind='comment';else if(/string|char|regexp/.test(scope))kind='string';else if(/number|literal/.test(scope))kind='number';
    else if((/function/.test(scope)&&/title/.test(scope)||/built_in/.test(scope)))kind='function';else if((/type/.test(scope)||/title/.test(scope)&&/class/.test(scope)))kind='type';
    else if(/keyword/.test(scope))kind=/^(return|if|else|for|while|do|break|continue|switch|case|default|throw|try|catch|co_return|co_yield|yield|elif|except|raise|finally|with)$/.test(value)?'control':'keyword';
    else if(/meta/.test(scope))kind='meta';else if(/variable|params/.test(scope))kind='variable';
    result.push({text:value,kind});
  }
  // Rendering must never change source bytes, especially string escapes and copied code.
  return result.map(x=>x.text).join('')===text?result:[{text,kind:'foreground'}];
}
function html(text,lang){return tokens(text,lang).map(t=>t.kind==='foreground'?esc(t.text):`<span class="tok-${t.kind}">${esc(t.text)}</span>`).join('');}
function decorate(root=document,copy){
  root.querySelectorAll('pre').forEach(pre=>{
    if(pre.closest('.sample-test,.input,.output')&&!pre.dataset.codeLanguage||pre.dataset.highlighted)return;
    let code=pre.querySelector('code');if(!code){code=document.createElement('code');code.textContent=pre.textContent;pre.replaceChildren(code);}
    const raw=code.textContent,declared=pre.dataset.codeLanguage||[...code.classList].find(c=>c.startsWith('language-'))?.slice(9),lang=language(declared);
    code.innerHTML=html(raw,lang);pre.dataset.highlighted='true';pre.classList.add('pocket-code');
    const tools=document.createElement('div');tools.className='code-tools';
    const label=document.createElement('span');label.textContent=lang==='cpp'?'C++':lang==='python'?'Python':String(declared||'文本').slice(0,24);
    const button=document.createElement('button');button.type='button';button.textContent='复制代码';
    button.addEventListener('click',async e=>{if(!e.isTrusted)return;try{await copy?.(raw);button.textContent='已复制';setTimeout(()=>button.textContent='复制代码',1400);}catch{button.textContent='复制失败，重试';}});
    tools.append(label,button);pre.before(tools);
  });
}
function images(root=document){root.querySelectorAll('img').forEach(img=>{
  if(img.dataset.readerImage)return;img.dataset.readerImage='true';
  const status=document.createElement('button');status.type='button';status.className='image-retry';status.textContent='图片未能加载 · 点此重试';status.hidden=true;img.after(status);
  img.addEventListener('load',()=>{status.hidden=true;img.hidden=false;});img.addEventListener('error',()=>{status.hidden=false;img.hidden=true;});
  status.addEventListener('click',()=>{status.hidden=true;img.hidden=false;const src=img.src;img.removeAttribute('src');img.src=src;});
  if(img.complete&&!img.naturalWidth)img.dispatchEvent(new Event('error'));
});}
globalThis.PocketCode={language,html,tokensJSON:(text,lang)=>JSON.stringify(tokens(text,lang)),paletteJSON:isDark=>JSON.stringify(isDark?dark:light),decorate,images};
