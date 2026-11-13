// All mutations are local and share one bounded undo history, including toolbar edits.
export function createHistory(){
  const undo=[],redo=[];let lastKind='',lastAt=0;
  const equal=(a,b)=>a.text===b.text&&a.start===b.start&&a.end===b.end;
  return {
    record(before,after,kind='edit',now=Date.now()){
      if(before.text===after.text)return;
      const previous=undo.at(-1),merge=kind==='typing'&&lastKind===kind&&now-lastAt<700&&previous&&equal(previous.after,before)&&before.start===before.end;
      if(merge)previous.after=after;else undo.push({before,after});
      while(undo.length>60||undo.length>1&&undo.reduce((n,e)=>n+e.before.text.length+e.after.text.length,0)>2*1024*1024)undo.shift();
      redo.length=0;lastKind=kind;lastAt=now;
    },
    undo(current){const e=undo.pop();if(!e)return null;redo.push({before:e.before,after:current});lastKind='';return e.before;},
    redo(current){const e=redo.pop();if(!e)return null;undo.push({before:current,after:e.after});lastKind='';return e.after;},
    get canUndo(){return !!undo.length;},get canRedo(){return !!redo.length;}
  };
}
let session=null;
export function attachEditor(input,{key,python,highlight,warn}){
  const E=globalThis.PocketEditing,root=input.closest('main')||document;
  if(!session||session.key!==key||session.text!==input.value)session={key,text:input.value,history:createHistory()};
  const history=session.history;let before=null,inputKind="typing",applying=false,composing=false,composeBefore=null,numbers=false,disposed=false;
  const snapshot=()=>({text:input.value,start:input.selectionStart,end:input.selectionEnd});
  const suggestions=root.querySelector('#code-suggestions'),symbols=root.querySelector('#code-symbols');
  const shell=input.closest('.code-editor-shell'),tools=root.querySelector('.editor-tools');
  let visibilityFrame=0;
  function keepCaretVisible(){
    if(disposed||document.activeElement!==input||!tools||!shell)return;
    const viewport=globalThis.visualViewport,available=viewport?.height||globalThis.innerHeight;
    if(available){shell.style.height=Math.max(112,Math.min(620,available-tools.offsetHeight-92))+'px';}
    const rect=input.getBoundingClientRect(),toolbar=tools.getBoundingClientRect(),style=getComputedStyle(input),lineHeight=parseFloat(style.lineHeight)||24;
    const line=input.value.slice(0,input.selectionStart).split('\n').length-1;
    const caretTop=rect.top+(parseFloat(style.paddingTop)||0)+line*lineHeight-input.scrollTop;
    const safeTop=toolbar.bottom+8,bottom=(viewport?.offsetTop||0)+(available||10000)-12;
    if(caretTop<safeTop)globalThis.scrollBy?.(0,caretTop-safeTop);
    else if(caretTop+lineHeight>bottom)globalThis.scrollBy?.(0,caretTop+lineHeight-bottom);
  }
  function scheduleVisibility(){if(disposed)return;cancelAnimationFrame(visibilityFrame);visibilityFrame=requestAnimationFrame(()=>{visibilityFrame=requestAnimationFrame(keepCaretVisible);});}
  globalThis.visualViewport?.addEventListener('resize',scheduleVisibility);
  input.addEventListener('focus',scheduleVisibility);input.addEventListener('blur',()=>{if(shell)shell.style.height='';});
  function changed(){input.dispatchEvent(new Event('input',{bubbles:true}));}
  function update(){
    if(disposed)return;highlight();session.text=input.value;scheduleVisibility();
    const options=composing?[]:E.suggest(input.value,input.selectionStart,input.selectionEnd,python);
    if(suggestions){suggestions.replaceChildren();for(const item of options){const b=document.createElement('button');b.type='button';b.textContent=item.id;b.setAttribute('aria-label',`补全 ${item.label}，${item.kind}`);b.onpointerdown=e=>e.preventDefault();b.onclick=()=>{const current=E.suggest(input.value,input.selectionStart,input.selectionEnd,python).find(x=>x.id===item.id);if(current)apply(current.edit,'completion');};suggestions.append(b);}}
    root.querySelector('[data-editor=undo]')?.toggleAttribute('disabled',!history.canUndo);root.querySelector('[data-editor=redo]')?.toggleAttribute('disabled',!history.canRedo);
  }
  function apply(edit,kind='edit'){
    if(!edit||composing)return;
    const old=snapshot(),newLength=input.value.length-(edit.end-edit.start)+edit.text.length;
    if(edit.start<0||edit.end<edit.start||edit.end>input.value.length||newLength>262144){warn('代码最多支持 256K 字符。');return;}
    applying=true;input.focus({preventScroll:true});
    input.setRangeText(edit.text,edit.start,edit.end,'preserve');input.setSelectionRange(edit.selectionStart,edit.selectionEnd);
    history.record(old,snapshot(),kind);changed();applying=false;update();
  }
  function restore(value){if(!value)return;applying=true;input.value=value.text;input.focus({preventScroll:true});input.setSelectionRange(value.start,value.end);changed();applying=false;update();}
  function undo(){if(!composing)restore(history.undo(snapshot()));}
  function redo(){if(!composing)restore(history.redo(snapshot()));}
  function insert(text){const a=input.selectionStart,b=input.selectionEnd;apply(E.edit(input.value,a,b,text,python,false)||{start:a,end:b,text,selectionStart:a+text.length,selectionEnd:a+text.length},'symbol');}
  function indent(outdent=false){apply(E.indent(input.value,input.selectionStart,input.selectionEnd,outdent),'indent');}
  input.maxLength=262144;
  input.addEventListener('beforeinput',e=>{
    before=snapshot();inputKind=e.inputType==='insertFromPaste'?'paste':'typing';if(composing||e.isComposing)return;
    if(e.inputType==='historyUndo'||e.inputType==='historyRedo'){e.preventDefault();e.inputType==='historyUndo'?undo():redo();return;}
    let a=input.selectionStart,b=input.selectionEnd,text=e.data,backspace=false;
    if(e.inputType==='deleteContentBackward'){text='';if(a===b&&a>0){backspace=true;a-=input.value.codePointAt(a-2)>65535?2:1;}}
    else if(e.inputType==='insertLineBreak'||e.inputType==='insertParagraph')text='\n';
    else if(e.inputType!=='insertText')return;
    if(text==null)return;const edit=E.edit(input.value,a,b,text,python,backspace);
    if(edit&&e.cancelable){e.preventDefault();apply(edit,'assist');}
  });
  input.addEventListener('input',e=>{if(applying||composing||e.isComposing)return;history.record(before||snapshot(),snapshot(),inputKind);before=null;update();});
  input.addEventListener('compositionstart',()=>{composing=true;composeBefore=snapshot();update();});
  input.addEventListener('compositionend',()=>{composing=false;history.record(composeBefore||snapshot(),snapshot(),'composition');composeBefore=null;before=null;changed();update();});
  input.addEventListener('keydown',e=>{
    if(e.isComposing)return;
    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();e.shiftKey?redo():undo();}
    else if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='y'){e.preventDefault();redo();}
    else if(e.key==='Tab'){e.preventDefault();indent(e.shiftKey);}
  });
  input.addEventListener('select',()=>{if(!applying)update();});input.addEventListener('keyup',()=>{if(!composing)update();});input.addEventListener('click',update);
  input.addEventListener('scroll',highlight,{passive:true});
  function symbolRow(){
    symbols?.replaceChildren();const toggle=root.querySelector('[data-editor=numbers]');if(toggle)toggle.textContent=numbers?'符号':'123';
    for(const text of numbers?'1234567890.-'.split(''):['⇥','⇤','{','}','(',')','[',']',';','<<','>>','++','==','&&','||','<','>','=','+','-','*','/','%','&','|','!','"',"'",'_',',',':','#']){
      const b=document.createElement('button');b.type='button';b.textContent=text;b.setAttribute('aria-label',text==='⇥'?'缩进':text==='⇤'?'取消缩进':`输入 ${text}`);b.onpointerdown=e=>e.preventDefault();b.onclick=()=>text==='⇥'||text==='⇤'?indent(text==='⇤'):insert(text);symbols?.append(b);
    }
  }
  root.querySelectorAll('[data-editor]').forEach(b=>{
    b.onpointerdown=e=>e.preventDefault();b.onclick=()=>{
      const action=b.dataset.editor;
      if(action==='undo')undo();else if(action==='redo')redo();else if(action==='numbers'){numbers=!numbers;symbolRow();}
      else if(action==='done')input.blur();else if(action==='left'||action==='right'){
        let at=action==='left'?input.selectionStart:input.selectionEnd;
        if(action==='left'&&at>0)at-=input.value.codePointAt(at-2)>65535?2:1;
        if(action==='right'&&at<input.value.length)at+=input.value.codePointAt(at)>65535?2:1;
        input.focus({preventScroll:true});input.setSelectionRange(at,at);update();
      }
    };
  });
  symbolRow();update();
  return {apply,undo,redo,insert,indent,update,get isComposing(){return composing;},dispose(){disposed=true;cancelAnimationFrame(visibilityFrame);globalThis.visualViewport?.removeEventListener('resize',scheduleVisibility);}};
}
