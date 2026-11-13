// Shared, offline editing rules. Offsets are UTF-16 (UITextView / textarea).
// Deliberately lexical completion: no compiler, network, or AI requests.
var PocketEditing = (() => {
  const pairs = {'(':')','[':']','{':'}','"':'"',"'":"'"};
  const word = c => !!c && /[A-Za-z0-9_]/.test(c);
  function valid(s,a,b){return typeof s==='string'&&Number.isInteger(a)&&Number.isInteger(b)&&a>=0&&b>=a&&b<=s.length;}
  function result(start,end,text,selectionStart=start+text.length,selectionEnd=selectionStart){return {start,end,text,selectionStart,selectionEnd};}
  function context(s,end,python){
    let state='code',quote='',rawEnd='';
    for(let i=0;i<end;i++){
      const c=s[i],n=s[i+1];
      if(state==='line'){if(c==='\n')state='code';continue;}
      if(state==='block'){if(c==='*'&&n==='/'){state='code';i++;}continue;}
      if(state==='raw'){if(s.startsWith(rawEnd,i)){state='code';i+=rawEnd.length-1;}continue;}
      if(state==='string'){
        if(c==='\\'){i++;continue;}
        if(s.startsWith(quote,i)){state='code';i+=quote.length-1;}continue;
      }
      if(python&&c==='#'||!python&&c==='/'&&n==='/'){state='line';if(!python)i++;continue;}
      if(!python&&c==='/'&&n==='*'){state='block';i++;continue;}
      if(!python&&c==='R'&&n==='"'){
        const m=s.slice(i,end).match(/^R"([^\s()\\]{0,16})\(/);
        if(m){state='raw';rawEnd=')'+m[1]+'"';i+=m[0].length-1;continue;}
      }
      if(c==='"'||c==="'"){
        if(!python&&c==="'"&&/[0-9a-fA-F]/.test(s[i-1]||'')&&/[0-9a-fA-F]/.test(n||''))continue;
        quote=python&&s.startsWith(c.repeat(3),i)?c.repeat(3):c;state='string';i+=quote.length-1;
      }
    }
    return state;
  }
  function escaped(s,at){let n=0;while(at>0&&s[--at]==='\\')n++;return n%2===1;}
  function edit(s,a,b,input,python=false,backspace=false){
    if(!valid(s,a,b)||typeof input!=='string')return null;
    const state=context(s,a,python),next=s[b]||'',prev=s[a-1]||'';
    if(backspace&&input===''&&b-a===1&&pairs[s[a]]===next&&state==='code')return result(a,b+1,'',a);
    if(input==='\n'){
      const line=s.slice(s.lastIndexOf('\n',a-1)+1,a),base=line.match(/^[\t ]*/)[0];
      const left=line.trimEnd(),open=state==='code'&&(python?left.endsWith(':'):/[({[]$/.test(left));
      const extra=open?'    ':'';
      if(!base&&!extra)return null;
      const close=open&&pairs[left.at(-1)]===next;
      return result(a,b,'\n'+base+extra+(close?'\n'+base:''),a+1+base.length+extra.length);
    }
    if(input.length!==1)return null; // Paste, dictation and IME commits remain literal.
    if(a===b&&next===input&&')]}'.includes(input)&&state==='code')return result(a,b,'',a+1);
    if(a===b&&next===input&&(input==='"'||input==="'")&&state==='string'&&!escaped(s,a))return result(a,b,'',a+1);
    if(pairs[input]&&state==='code'){
      if(a!==b)return result(a,b,input+s.slice(a,b)+pairs[input],a+1,b+1);
      if((input==='"'||input==="'")&&(word(prev)||escaped(s,a)))return null;
      if(next&&!/[\s)\]}>,;:]/.test(next))return null;
      return result(a,b,input+pairs[input],a+1);
    }
    return null;
  }
  function indent(s,a,b,outdent=false){
    if(!valid(s,a,b))return null;
    if(a===b&&!outdent){const lineStart=s.lastIndexOf('\n',a-1)+1;const text=' '.repeat(4-((a-lineStart)%4));return result(a,b,text);}
    const start=s.lastIndexOf('\n',a-1)+1,finish=b>a&&s[b-1]==='\n'?b-1:b;
    let end=s.indexOf('\n',finish);if(end<0)end=s.length;
    const lines=s.slice(start,end).split('\n'),removed=[];
    const text=lines.map(line=>{const n=outdent?(line[0]==='\t'?1:Math.min(4,line.match(/^ */)[0].length)):-4;removed.push(n);return outdent?line.slice(n):'    '+line;}).join('\n');
    const shift=removed.reduce((n,v)=>n-v,0),first=-removed[0];
    return result(start,end,text,Math.max(start,a+first),a===b?Math.max(start,a+first):Math.max(start,b+shift));
  }
  const cpp=[
    ['for','for 循环','for (int i = 0; i < $0; ++i) {\n    \n}'],
    ['if','if 条件','if ($0) {\n    \n}'],['while','while 循环','while ($0) {\n    \n}'],
    ['vector','vector 容器','vector<$0>'],['pair','pair 类型','pair<$0>'],['map','map 容器','map<$0>'],['set','set 容器','set<$0>'],['queue','queue 容器','queue<$0>'],['priority_queue','priority_queue','priority_queue<$0>'],
    ['cin','cin 输入','cin >> $0;'],['cout','cout 输出',"cout << $0 << '\\n';"],['sort','sort 排序','sort($0);'],
    ['lower_bound','lower_bound','lower_bound($0)'],['push_back','push_back','push_back($0)'],['emplace_back','emplace_back','emplace_back($0)'],
    ['empty','empty()','empty()$0'],['clear','clear()','clear()$0'],['erase','erase()','erase($0)'],['find','find()','find($0)'],['size','size()','size()$0'],['begin','begin()','begin()$0'],['end','end()','end()$0'],['return','return','return $0;'],
  ];
  const py=[['for','for 循环','for i in range($0):\n    pass'],['if','if 条件','if $0:\n    pass'],['while','while 循环','while $0:\n    pass'],['def','def 函数','def $0():\n    pass'],['print','print 输出','print($0)'],['input','input()','input()$0'],['range','range()','range($0)'],['len','len()','len($0)'],['int','int()','int($0)'],['list','list()','list($0)'],['map','map()','map($0)'],['sorted','sorted()','sorted($0)'],['append','append()','append($0)'],['enumerate','enumerate()','enumerate($0)']];
  const keywordsCPP='int long double float bool char string auto const static void struct class public private template typename using namespace std include iostream algorithm vector array deque unordered_map unordered_set stack queue tuple make_pair max min abs gcd reverse unique next_permutation binary_search upper_bound lower_bound accumulate iota fill memset swap break continue else true false nullptr sizeof switch case'.split(' ');
  const keywordsPy='import from as sys collections heapq bisect itertools math deque defaultdict Counter set dict str float bool tuple return break continue else elif True False None in not and or lambda sum min max abs zip reversed'.split(' ');
  function snippetEdit(s,a,b,text){
    const base=s.slice(s.lastIndexOf('\n',a-1)+1,a).match(/^[\t ]*/)[0];
    text=text.replace(/\n/g,'\n'+base);const cursor=text.indexOf('$0');text=text.replace('$0','');
    return result(a,b,text,a+(cursor<0?text.length:cursor));
  }
  function suggest(s,a,b,python=false){
    if(!valid(s,a,b)||a!==b||context(s,a,python)!=='code')return [];
    let start=a,end=a;while(start>0&&word(s[start-1]))start--;while(end<s.length&&word(s[end]))end++;
    const prefix=s.slice(start,a);if(prefix&& !/^[A-Za-z_]/.test(prefix))return [];
    const member=s[start-1]==='.'||s.slice(Math.max(0,start-2),start)==='->',memberIDs=python?['append','count']:['push_back','emplace_back','size','begin','end','empty','clear','erase','find'];
    const snippets=(python?py:cpp).filter(x=>!member||memberIDs.includes(x[0])).sort((a,b)=>member?memberIDs.indexOf(a[0])-memberIDs.indexOf(b[0]):0),output=[],seen=new Set();
    const add=(id,label,text,kind)=>{if(seen.has(id)||output.length===6)return;seen.add(id);output.push({id,label,kind,edit:snippetEdit(s,start,end,text)});};
    for(const [id,label,text] of snippets)if(prefix?id.startsWith(prefix):member||['for','if',python?'def':'vector',python?'print':'cin'].includes(id))add(id,label,text,'片段');
    if(prefix){
      const identifiers=s.slice(Math.max(0,a-32768),Math.min(s.length,a+32768)).match(/[A-Za-z_][A-Za-z_0-9]{1,63}/g)||[];
      for(const id of [...new Set(identifiers)].filter(x=>x.startsWith(prefix)&&x!==prefix&&x!==s.slice(start,end)).sort((x,y)=>x.length-y.length||x.localeCompare(y)))add(id,id,id,'当前代码');
      for(const id of (python?keywordsPy:keywordsCPP))if(id.startsWith(prefix))add(id,id,id,'关键字');
    }
    return output;
  }
  function template(s,python=false,multiple=false){
    const text=python?'import sys\ninput = sys.stdin.readline\n\ndef solve():\n    $0pass\n\nif __name__ == "__main__":\n'+(multiple?'    t = int(input())\n    for _ in range(t):\n        solve()\n':'    solve()\n'):'#include <bits/stdc++.h>\nusing namespace std;\nusing ll = long long;\n\nvoid solve() {\n    $0\n}\n\nint main() {\n    ios::sync_with_stdio(false);\n    cin.tie(nullptr);\n'+(multiple?'    int t;\n    cin >> t;\n    while (t--) solve();\n':'    solve();\n')+'    return 0;\n}\n';
    const cursor=text.indexOf('$0');return result(0,s.length,text.replace('$0',''),cursor);
  }
  return {edit,indent,suggest,template,context,
    editJSON:(...args)=>JSON.stringify(edit(...args)),indentJSON:(...args)=>JSON.stringify(indent(...args)),suggestJSON:(...args)=>JSON.stringify(suggest(...args)),templateJSON:(...args)=>JSON.stringify(template(...args))};
})();
