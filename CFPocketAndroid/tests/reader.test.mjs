import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {JSDOM} from 'jsdom';
import {imageURL} from '../app/src/main/assets/web/images.mjs';
const script=fs.readFileSync(new URL('../app/src/main/assets/Reader/code-highlight.js',import.meta.url),'utf8');
const context=vm.createContext({});vm.runInContext(script,context);const code=context.PocketCode;
test('public article images support other hosts, protocol-relative and legacy CDN links',()=>{
 assert.equal(imageURL('//i.loli.net/2020/12/04/a.png'),'https://i.loli.net/2020/12/04/a.png');
 assert.equal(imageURL('http://cdn.luogu.org/upload/pic/123.png'),'https://cdn.luogu.com.cn/upload/pic/123.png');
 assert.equal(imageURL('https://raw.githubusercontent.com/github/explore/main/topics/cpp/cpp.png'),'https://raw.githubusercontent.com/github/explore/main/topics/cpp/cpp.png');
 for(const url of ['javascript:alert(1)','file:///etc/passwd','data:image/svg+xml,bad','https://127.0.0.1/x','https://[::1]/x','https://router.local/x','https://localhost/x','https://user:secret@images.example.com/a','https://images.example.com:8080/a',''])assert.equal(imageURL(url),null,url);
});
test('C++ grammar retains raw source and recognizes functions, types, strings, comments and numbers',()=>{
 const source='#include <bits/stdc++.h>\nusing namespace std;\n// 中文 😀\nint main() {\n  string s = "// not a comment <script>\\n";\n  auto r = R"tag(raw \\" x)tag";\n  for (int i=0; i<42; ++i) cout << s;\n  return 0;\n}\n';
 const tokens=JSON.parse(code.tokensJSON(source,'cpp'));
 assert.equal(tokens.map(x=>x.text).join(''),source);
 for(const kind of ['keyword','control','function','string','number','comment'])assert.ok(tokens.some(x=>x.kind===kind),kind);
 assert.ok(tokens.some(x=>x.kind==='string'&&x.text.includes('// not a comment')));
 const dom=new JSDOM(`<pre><code>${code.html(source,'cpp')}</code></pre>`);assert.equal(dom.window.document.querySelector('code').textContent,source);assert.equal(dom.window.document.querySelectorAll('script').length,0);
});
test('Light+ and Dark+ are distinct, and unlabelled fences default to C++',()=>{
 assert.equal(code.language(), 'cpp');assert.equal(code.language('C++20'),'cpp');assert.equal(code.language('python'),'python');
 assert.equal(code.language('javascript'),'plaintext');assert.equal(code.language('java'),'plaintext');
 assert.equal(JSON.parse(code.paletteJSON(false)).background,'#FFFFFF');assert.equal(JSON.parse(code.paletteJSON(true)).background,'#1E1E1E');
 assert.equal(JSON.parse(code.paletteJSON(false)).keyword,'#0000FF');assert.equal(JSON.parse(code.paletteJSON(true)).keyword,'#569CD6');
});
test('reader decorates once, preserves code text, and exposes failed-image retry',()=>{
 const dom=new JSDOM('<article><pre><code>int main() { return 0; }\n</code></pre><img src="https://images.example.com/a.png"></article>',{runScripts:'outside-only'});
 dom.window.eval(script);const p=dom.window.PocketCode,d=dom.window.document;
 p.decorate(d);p.decorate(d);assert.equal(d.querySelectorAll('.code-tools').length,1);assert.equal(d.querySelector('pre').textContent,'int main() { return 0; }\n');assert.ok(d.querySelector('.tok-control'));
 p.images(d);d.querySelector('img').dispatchEvent(new dom.window.Event('error'));assert.equal(d.querySelector('.image-retry').hidden,false);
 d.querySelector('img').dispatchEvent(new dom.window.Event('load'));assert.equal(d.querySelector('.image-retry').hidden,true);
});
