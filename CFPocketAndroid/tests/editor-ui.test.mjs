import test from 'node:test';import assert from 'node:assert/strict';import {JSDOM} from 'jsdom';import fs from 'node:fs';import vm from 'node:vm';import {attachEditor} from '../app/src/main/assets/web/editor-ui.mjs';
const core={};vm.runInNewContext(fs.readFileSync(new URL('../tools/editor-core.js',import.meta.url),'utf8'),core);
function setup(text=''){
 const dom=new JSDOM('<main><button data-editor="undo"></button><button data-editor="redo"></button><div class="editor-tools"><div id="code-suggestions"></div><button data-editor="numbers">123</button><div id="code-symbols"></div></div><div class="code-editor-shell"><textarea id="source"></textarea></div></main>',{pretendToBeVisual:true});
 Object.assign(globalThis,{document:dom.window.document,Event:dom.window.Event,PocketEditing:core.PocketEditing,requestAnimationFrame:()=>0,cancelAnimationFrame:()=>{},getComputedStyle:dom.window.getComputedStyle.bind(dom.window)});
 const input=document.querySelector('textarea');input.value=text;input.focus();input.setSelectionRange(text.length,text.length);
 const ui=attachEditor(input,{key:Math.random().toString(),python:false,highlight:()=>{},warn:message=>{throw Error(message);}});
 return {dom,input,ui};
}
test('real textarea mutations: pairs and completion are reversible without duplicate history entries',()=>{
 const {dom,input,ui}=setup();
 const e=new dom.window.InputEvent('beforeinput',{data:'(',inputType:'insertText',bubbles:true,cancelable:true});input.dispatchEvent(e);
 assert.ok(e.defaultPrevented);assert.equal(input.value,'()');assert.equal(input.selectionStart,1);
 ui.insert('7');assert.equal(input.value,'(7)');ui.undo();assert.equal(input.value,'()');ui.redo();assert.equal(input.value,'(7)');
 ui.apply({start:0,end:3,text:'vec',selectionStart:3,selectionEnd:3},'fixture');
 document.querySelector('[aria-label^="补全 vector"]').click();assert.equal(input.value,'vector<>');assert.equal(input.selectionStart,7);
 ui.undo();assert.equal(input.value,'vec');ui.redo();assert.equal(input.value,'vector<>');ui.dispose();dom.window.close();
});
test('composing text is not paired or autocompleted and commits as one undo operation',()=>{
 const {dom,input,ui}=setup('old');
 input.dispatchEvent(new dom.window.CompositionEvent('compositionstart',{bubbles:true}));
 input.dispatchEvent(new dom.window.InputEvent('beforeinput',{data:'你',inputType:'insertCompositionText',isComposing:true,bubbles:true,cancelable:true}));
 input.value='old你';input.setSelectionRange(4,4);input.dispatchEvent(new dom.window.InputEvent('input',{data:'你',isComposing:true,bubbles:true}));
 assert.equal(document.querySelector('#code-suggestions').childElementCount,0);
 input.dispatchEvent(new dom.window.CompositionEvent('compositionend',{data:'你',bubbles:true}));
 ui.undo();assert.equal(input.value,'old');ui.redo();assert.equal(input.value,'old你');ui.dispose();dom.window.close();
});
test('template replacement and language/file switches do not mix undo histories',()=>{
 const first=setup('int keep = 7;');first.ui.apply(core.PocketEditing.template(first.input.value,false,true),'template');first.ui.undo();assert.equal(first.input.value,'int keep = 7;');first.ui.dispose();first.dom.window.close();
 const second=setup('print(1)');second.ui.undo();assert.equal(second.input.value,'print(1)');second.ui.dispose();second.dom.window.close();
});
