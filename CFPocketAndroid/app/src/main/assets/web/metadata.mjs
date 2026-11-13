import {problemID} from './core.mjs';
// Current Codeforces rank-color bands; numeric problem ratings are shown without rank titles.
export function cfColor(rating) {
  if (!Number.isInteger(rating) || rating <= 0 || rating < 1200) return '#808080';
  return rating < 1400 ? '#008000' : rating < 1600 ? '#03A89E' : rating < 1900 ? '#0000FF' : rating < 2100 ? '#AA00AA' : rating < 2400 ? '#FF8C00' : '#FF0000';
}
// Luogu /_lfe/config ProblemDifficulty IDs captured 2026-11-13, including cyan 提高.
export function luoguColor(id) { return ['#BFBFBF','#FE4C61','#F39C11','#FFC116','#52C41A','#13C2C2','#3498DB','#9D3DCF','#0E1D69'][id] || '#BFBFBF'; }
export function parseCFProblems(result) {
  if (!Array.isArray(result?.problems) || !result.problems.length) throw Error('题库结果异常，保留上次数据。');
  const seen = new Set();
  const rows = result.problems.filter(p => p.contestId !== undefined).map(p => {
    if (!Number.isInteger(p.contestId) || p.contestId <= 0 || !/^([A-Z][0-9]{0,2}|[0-9]{2})$/.test(p.index) || typeof p.name !== 'string' || !p.name.trim() || (p.rating !== undefined && (!Number.isInteger(p.rating) || p.rating <= 0)) || !Array.isArray(p.tags) || p.tags.some(t => typeof t !== 'string' || !t.trim())) throw Error('CF 题目信息不完整，保留上次题库。');
    const {id} = problemID(p.contestId,p.index);
    if (seen.has(id)) throw Error('CF 题库出现重复题号，保留上次数据。');
    seen.add(id);
    return {id,contest:p.contestId,index:p.index,name:p.name,rating:p.rating ?? null,tags:[...new Set(p.tags)]};
  });
  if (!rows.length) throw Error('题库结果异常，保留上次数据。');
  return rows.sort((a,b)=>(a.rating??9999)-(b.rating??9999)||b.contest-a.contest);
}
