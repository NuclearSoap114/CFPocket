import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCFProblems,cfColor,luoguColor} from '../app/src/main/assets/web/metadata.mjs';
import {problem,difficulties} from '../app/src/main/assets/web/luogu.mjs';
test('CF colors use the current 2100 master threshold and all boundary intervals',()=>{
  for(const [lo,hi,color] of [[1,1199,'#808080'],[1200,1399,'#008000'],[1400,1599,'#03A89E'],[1600,1899,'#0000FF'],[1900,2099,'#AA00AA'],[2100,2399,'#FF8C00'],[2400,4000,'#FF0000']]){assert.equal(cfColor(lo),color);assert.equal(cfColor(hi),color);}
  assert.equal(cfColor(null),'#808080');
});
test('CF API metadata survives parsing, including numeric indices and unrated problems',()=>{
  const rows=parseCFProblems({problems:[{contestId:4,index:'A',name:'Watermelon',rating:800,tags:['brute force','math']},{contestId:921,index:'01',name:'Test',tags:[]}]});
  assert.deepEqual(rows[0].tags,['brute force','math']);assert.equal(rows[0].rating,800);
  assert.equal(rows[1].id,'921-01');assert.equal(rows[1].rating,null);assert.deepEqual(rows[1].tags,[]);
});
test('Malformed/missing tags and duplicate IDs do not silently replace the cached library',()=>{
  const row={contestId:4,index:'A',name:'Watermelon',rating:800,tags:[]};
  for(const problems of [[],[row,row],[{...row,tags:undefined}],[{...row,rating:-1}],[{...row,tags:[12]}]])assert.throws(()=>parseCFProblems({problems}));
});
test('Current Luogu IDs include cyan level and the new maximum ID 8',()=>{
  const p=problem({status:200,template:'problem.show',data:{problem:{pid:'CF4A',name:'Fixture',difficulty:8}}},'CF4A');
  assert.equal(difficulties[p.difficulty],'NOI/NOI+/CTS');assert.equal(difficulties[5],'提高');
  assert.equal(luoguColor(5),'#13C2C2');assert.equal(luoguColor(6),'#3498DB');assert.equal(luoguColor(7),'#9D3DCF');assert.equal(luoguColor(8),'#0E1D69');
});
