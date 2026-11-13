    if(location.origin!=='https://codeforces.com')return {error:'WRONG_ORIGIN'};
    const saved=JSON.parse(sessionStorage.getItem('cfpocket-'+input.nonce)||'null');
    if(!saved || !Array.isArray(saved.ids))return {pending:true};
    const r=await fetch('/api/user.status?handle='+encodeURIComponent(input.handle)+'&from=1&count=100',{credentials:'omit'});
    if(!r.ok)return {pending:true};
    const data=await r.json();if(data.status!=='OK' || !Array.isArray(data.result))return {pending:true};
    const rows=data.result.filter(x=>!saved.ids.includes(x.id) && x.creationTimeSeconds>=input.since && x.problem?.contestId===input.contest && x.problem?.index===input.index && x.author?.members?.some(m=>m.handle.toLowerCase()===input.handle.toLowerCase()));
    const verified=[];
    const normalize=s=>s.replace(/\r\n/g,'\n').trimEnd();
    for(const row of rows.slice(0,5)){
      const response=await fetch('/contest/'+input.contest+'/submission/'+row.id,{credentials:'include'});
      if(!response.ok)continue;
      const html=await response.text();if(html.length>4*1024*1024)continue;
      const doc=new DOMParser().parseFromString(html,'text/html');
      const source=doc.querySelector('#program-source-text');
      if(source && normalize(source.textContent)===normalize(input.source))verified.push(row.id);
    }
    return verified.length===1 ? {id:verified[0],sourceVerified:true} : {pending:true,ambiguous:verified.length>1};
