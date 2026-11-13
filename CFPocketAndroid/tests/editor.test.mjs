import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import vm from 'node:vm';
const scope={};vm.runInNewContext(fs.readFileSync(new URL('../tools/editor-core.js',import.meta.url),'utf8'),scope);const E=scope.PocketEditing;
const apply=(s,e)=>e?s.slice(0,e.start)+e.text+s.slice(e.end):s;
test('pairs, selected wrapping, duplicate closer, paired backspace and emoji UTF16 offsets',()=>{
 for(const [a,b] of [['(',')'],['[',']'],['{','}'],['"','"'],["'","'"]]){const e=E.edit('',0,0,a);assert.equal(apply('',e),a+b);assert.equal(e.selectionStart,1);assert.equal(apply(a+b,E.edit(a+b,0,1,'',false,true)),'');}
 const wrapped=E.edit('你好🙂value',4,9,'(');assert.equal(apply('你好🙂value',wrapped),'你好🙂(value)');assert.equal(wrapped.selectionStart,5);assert.equal(wrapped.selectionEnd,10);
 const skip=E.edit('foo()',4,4,')');assert.equal(apply('foo()',skip),'foo()');assert.equal(skip.selectionStart,5);
 assert.equal(E.edit('a',1,1,'<'),null);assert.equal(E.edit('',0,0,'() pasted'),null);
});
test('comments, strings, escapes, C++ raw strings and numeric separators remain literal',()=>{
 for(const s of ['// comment ','/* comment ','"abc ',"'x",'R"xx(raw { text '])assert.equal(E.edit(s,s.length,s.length,'('),null);
 assert.equal(E.edit('# comment ',10,10,'(',true),null);
 assert.equal(E.edit('"abc\\"',5,5,'"'),null);
 assert.equal(E.context('auto x = 1\'000; ',16,false),'code');
 assert.equal(E.edit('123',3,3,"'"),null);
 assert.equal(E.suggest('/* vec',6,6).length,0);assert.equal(E.suggest('"vec',4,4).length,0);
});
test('newline keeps indentation and opens a block with a correctly aligned closing brace',()=>{
 const s='    if (ok) {}',at=s.indexOf('}') ,e=E.edit(s,at,at,'\n');
 assert.equal(apply(s,e),'    if (ok) {\n        \n    }');assert.equal(e.selectionStart,s.indexOf('}')+9);
 const py='    if ok:';assert.equal(apply(py,E.edit(py,py.length,py.length,'\n',true)),'    if ok:\n        ');
 assert.equal(apply('    // {',E.edit('    // {',8,8,'\n')),'    // {\n    ');
});
test('multi-line indent and outdent preserve selection and do not affect the next unselected line',()=>{
 let s='one\n  two\nthree',e=E.indent(s,0,10);assert.equal(apply(s,e),'    one\n      two\nthree');assert.equal(e.selectionEnd,18);
 s='    one\n\ttwo\nthree';e=E.indent(s,0,13,true);assert.equal(apply(s,e),'one\ntwo\nthree');
 assert.equal(apply('ab',E.indent('ab',2,2)),'ab  ');
});
test('completion replaces the whole token, offers local identifiers, and aligns inserted blocks',()=>{
 let list=E.suggest('vecTor',3,3),item=list.find(x=>x.id==='vector');assert.equal(apply('vecTor',item.edit),'vector<>');assert.equal(item.edit.selectionStart,7);
 list=E.suggest('int maximumValue = 1;\nmaxi',25,25);assert.ok(list.some(x=>x.id==='maximumValue'));
 item=E.suggest('    fo',6,6).find(x=>x.id==='for');assert.equal(apply('    fo',item.edit),'    for (int i = 0; i < ; ++i) {\n        \n    }');
 assert.equal(E.suggest('for',0,3).length,0);
});
test('single/multiple templates position caret in solve and contain no unresolved marker',()=>{
 for(const python of [false,true])for(const multi of [false,true]){const e=E.template('old code',python,multi);assert.equal(e.start,0);assert.equal(e.end,8);assert.ok(!e.text.includes('$0'));assert.ok(e.selectionStart>0&&e.selectionStart<e.text.length);assert.ok(e.text.includes(python?'def solve():':'void solve()'));if(multi)assert.ok(e.text.includes(python?'range(t)':'while (t--)'));}
});
test('shipped iOS and Android editing engines match the tested source byte-for-byte',()=>{
 const source=fs.readFileSync(new URL('../tools/editor-core.js',import.meta.url));
 for(const target of ['../app/src/main/assets/Reader/editor-core.js','../../TrainingLedger/CFPocket/Resources/Reader/editor-core.js'])assert.equal(Buffer.compare(source,fs.readFileSync(new URL(target,import.meta.url))),0);
});

import {createHistory} from '../app/src/main/assets/web/editor-ui.mjs';
test('toolbar edits, template replacement, typing, undo and redo form bounded distinct history entries',()=>{
 const h=createHistory(),a={text:'x',start:1,end:1},b={text:'x()',start:2,end:2},c={text:'x(value)',start:7,end:7},t={text:'template',start:3,end:3};
 h.record(a,b,'pair',1);h.record(b,c,'completion',2);h.record(c,t,'template',3);
 assert.deepEqual(h.undo(t),c);assert.deepEqual(h.undo(c),b);assert.deepEqual(h.redo(b),c);
 h.record(c,{text:'changed',start:7,end:7},'typing',4);assert.equal(h.canRedo,false);
});

test('member completion favors common container methods instead of statement snippets',()=>{
 const list=E.suggest('values.',7,7);assert.ok(list.some(x=>x.id==='push_back'));assert.ok(list.some(x=>x.id==='size'));assert.ok(!list.some(x=>x.id==='for'));
});
import {validateImport} from '../app/src/main/assets/web/core.mjs';
test('personal templates migrate with backups but malformed or oversized imports are rejected',()=>{
 const backup=templates=>({format:'CFPocket.AndroidBackup',version:1,state:{workspaces:{},templates}});
 assert.equal(validateImport(backup({'C++':'int main() {}'})).state.templates['C++'],'int main() {}');
 for(const value of [null,[],{'C++':42},{'C++':'x'.repeat(262145)},{Java:'class A{}'}])assert.throws(()=>validateImport(backup(value)));
});
