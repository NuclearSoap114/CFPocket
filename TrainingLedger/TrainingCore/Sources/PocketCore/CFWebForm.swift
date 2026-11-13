import Foundation

/// Scripts run only in the user's Codeforces WebKit session. No password or cookie leaves WebKit.
public enum CFWebForm {
  public static func failureMessage(_ code: String) -> String {
    switch code {
    case "LOGIN_REQUIRED": return "官网登录已失效，请重新登录 Codeforces。"
    case "VERIFICATION_REQUIRED": return "官网要求完成验证，请打开官网检查；已登录账号会保留。"
    case "ACCOUNT_CHANGED": return "官网账号已变化，请确认账号后重新准备提交。"
    case "ALREADY_SENT": return "这张网页已有提交正在处理，请先核对记录，避免重复发送。"
    case "BASELINE_UNAVAILABLE": return "暂时无法读取官网提交记录，代码未发送。请稍后重试，无需重新登录。"
    case "WRONG_PROBLEM": return "官网表单的题号与当前题目不一致，请重新准备提交。"
    case "FORM_ACTION_UNSUPPORTED": return "当前官网提交地址未被识别，请重新准备提交；登录状态不受影响。"
    case "TOKEN_MISSING": return "提交页面的校验信息尚未加载，请重新准备提交。"
    case "LANGUAGE_UNAVAILABLE": return "官网当前不提供所选编译器，请重新选择提交语言。"
    case "EDITOR_NOT_READY": return "官网代码编辑器尚未加载完成，请稍后重试或打开官网检查。"
    case "SUBMIT_UNAVAILABLE": return "官网暂未开放提交按钮，请打开官网查看限制说明。"
    case "FORM_INVALID": return "官网仍有未满足的提交条件，请打开官网检查。"
    case "FORM_VALUES_CHANGED": return "官网表单在准备时发生变化，代码未发送，请重试。"
    case "STORAGE_UNAVAILABLE": return "无法保存这次提交的核对记录，代码未发送，请重新准备提交。"
    case "FORM_LOADING": return "提交页面正在加载，请稍候。"
    case "WRONG_ORIGIN": return "当前页面不是 Codeforces 官方提交页面，请重新准备提交。"
    case "FORM_MISSING": return "当前官网页面没有提交表单，请重新准备提交。"
    case "FORM_FIELDS_MISSING": return "官网提交字段尚未完整加载，请重新准备提交或打开官网检查。"
    default: return "暂时无法准备官网提交，代码未发送。请重新准备提交或打开官网检查。"
    }
  }
  // Shared by the readiness UI and dispatch. Android assets are generated from these exact bodies.
  public static let formHelpers = #"""

    const account = () => {
      const p = document.querySelector('.lang-chooser a[href^="/profile/"]');
      if (!document.querySelector('a[href*="/logout"]') || !p) return '';
      try { return decodeURIComponent(new URL(p.href).pathname.slice(9)); } catch { return ''; }
    };
    const enabled = node => !!node && !node.matches(':disabled');
    const options = node => [...(node?.options || [])].filter(x => x.value && enabled(x));
    const route = url => {
      if (url.origin !== 'https://codeforces.com' || url.username || url.password) return null;
      const contest = url.pathname.match(/^\/contest\/([1-9]\d*)\/submit(?:\/([A-Za-z0-9]+))?\/?$/);
      if (contest) return {contest:Number(contest[1]), index:contest[2] || null};
      const problemset = url.pathname.match(/^\/problemset\/submit(?:\/([1-9]\d*)\/([A-Za-z0-9]+))?\/?$/);
      return problemset ? {contest:problemset[1] ? Number(problemset[1]) : null, index:problemset[2] || null} : null;
    };
    const inspectForm = expected => {
      const handle = account();
      const areas = [...document.querySelectorAll('textarea[name="source"]')];
      // Prefer the full submit page over a sidebar's quick-submit form.
      const forms = areas.map(area => ({area, form:area.form || area.closest('form')})).filter(x => x.form);
      forms.sort((a,b) => Number(!!b.form.querySelector('[name="programTypeId"]')) - Number(!!a.form.querySelector('[name="programTypeId"]')));
      const base = {handle, formPresent:forms.length > 0};
      const fail = error => ({...base,error});
      if (location.origin !== 'https://codeforces.com') return fail('WRONG_ORIGIN');
      if (!handle) return fail(document.querySelector('#challenge-form,.cf-turnstile,.g-recaptcha') ? 'VERIFICATION_REQUIRED' : 'LOGIN_REQUIRED');
      if (!forms.length) return fail(document.querySelector('#challenge-form,.cf-turnstile,.g-recaptcha') ? 'VERIFICATION_REQUIRED' : 'FORM_MISSING');
      let last = fail('FORM_FIELDS_MISSING');
      for (const {area,form} of forms) {
        const button = [...form.querySelectorAll('input[type="submit"],button[type="submit"],button:not([type])')].find(enabled);
        let action;
        try { action = new URL(button?.getAttribute('formaction') || form.getAttribute('action') || location.href, document.baseURI); } catch { last=fail('FORM_ACTION_UNSUPPORTED'); continue; }
        const target = route(action);
        const method = (button?.getAttribute('formmethod') || form.method).toLowerCase();
        if (!target || method !== 'post') { last=fail('FORM_ACTION_UNSUPPORTED'); continue; }
        const field = form.querySelector('[name="submittedProblemCode"],[name="submittedProblemIndex"]');
        const lang = form.querySelector('select[name="programTypeId"]');
        const contest = form.querySelector('[name="contestId"]');
        if (!enabled(area) || !enabled(field) || !enabled(lang) || !options(lang).length) { last=fail('FORM_FIELDS_MISSING'); continue; }
        if (expected) {
          if ((target.contest && target.contest !== expected.contest) || (target.index && target.index !== expected.index) || (contest?.value && Number(contest.value) !== expected.contest)) { last=fail('WRONG_PROBLEM'); continue; }
          if (field.name === 'submittedProblemIndex' && target.contest !== expected.contest && Number(contest?.value) !== expected.contest) { last=fail('WRONG_PROBLEM'); continue; }
          const value = field.name === 'submittedProblemCode' ? String(expected.contest)+expected.index : expected.index;
          if (field.tagName === 'SELECT' && !options(field).some(x => x.value === value)) { last=fail('WRONG_PROBLEM'); continue; }
        }
        const csrf = form.querySelector('[name="csrf_token"]');
        if (!(enabled(csrf) && csrf.value) && !action.searchParams.get('csrf_token')) { last=fail('TOKEN_MISSING'); continue; }
        const challenge = [...form.querySelectorAll('[name="cf-turnstile-response"],[name="g-recaptcha-response"],[name="h-captcha-response"]')];
        if (challenge.some(x => !x.value.trim())) { last=fail('VERIFICATION_REQUIRED'); continue; }
        if (!button) { last=fail('SUBMIT_UNAVAILABLE'); continue; }
        const aceNode = form.querySelector('.ace_editor'), ace = aceNode?.env?.editor;
        const cmNode = form.querySelector('.CodeMirror'), cm = cmNode?.CodeMirror;
        if ((aceNode && (!ace?.setValue || !ace?.getValue)) || (cmNode && (!cm?.setValue || !cm?.getValue))) { last=fail('EDITOR_NOT_READY'); continue; }
        return {...base,form,area,field,lang,button,ace,cm};
      }
      return last;
    };
  """#

  public static let snapshotBody = #"""

    const state = inspectForm(typeof input === 'object' ? input : null);
    return {handle:state.handle, form:!state.error, formPresent:state.formPresent, readinessError:state.error || null,
      languages:state.lang ? options(state.lang).map(x => ({id:x.value,name:x.textContent.trim()})) : [],
      errors:[...document.querySelectorAll('.error')].filter(x=>x.getClientRects().length).map(x=>x.textContent.trim()).filter(Boolean).slice(0,4).join(' · ')};
  """#
  public static let snapshot = "(() => {\n" + formHelpers + snapshotBody + "\n})()"
  public static func snapshot(problem: ProblemID?) -> String {
    guard let problem else { return snapshot }
    return "(() => {const input={contest:\(problem.contest),index:\(String(data:try! JSONEncoder().encode(problem.index),encoding:.utf8)!)};\n" + formHelpers + snapshotBody + "\n})()"
  }
  public static func submit(problem: ProblemID, source: String, languageID: String, handle: String, nonce: UUID) throws -> String {
    let data: [String: Any] = ["contest":problem.contest,"index":problem.index,"id":"\(problem.contest)\(problem.index)","source":source,"language":languageID,"handle":handle,"nonce":nonce.uuidString]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self)
    return "const input = \(json);\n" + dispatchBody
  }
  public static let dispatchBody = formHelpers + dispatchOperation
  public static let dispatchOperation = #"""

    if (window.__pocketSent || window.__pocketSending) return {error:'ALREADY_SENT'};
    let state = inspectForm(input);
    if (state.error) return {error:state.error};
    if (state.handle.toLowerCase() !== input.handle.toLowerCase()) return {error:'ACCOUNT_CHANGED'};
    if (!options(state.lang).some(x => x.value === input.language)) return {error:'LANGUAGE_UNAVAILABLE'};
    window.__pocketSending = input.nonce;
    try {
      // Failure before clicking is definitely not sent. Never label an API timeout as an unknown POST.
      let baseline;
      const controller = new AbortController(), timer = setTimeout(() => controller.abort(),15000);
      try {
        const response = await fetch('/api/user.status?handle='+encodeURIComponent(input.handle)+'&from=1&count=100', {credentials:'omit',signal:controller.signal});
        if (!response.ok) return {error:'BASELINE_UNAVAILABLE'};
        baseline = await response.json();
        if (baseline.status !== 'OK' || !Array.isArray(baseline.result) || baseline.result.some(x => !Number.isSafeInteger(x.id) || x.id <= 0)) return {error:'BASELINE_UNAVAILABLE'};
      } catch { return {error:'BASELINE_UNAVAILABLE'}; } finally { clearTimeout(timer); }
      state = inspectForm(input);
      if (state.error) return {error:state.error};
      if (state.handle.toLowerCase() !== input.handle.toLowerCase()) return {error:'ACCOUNT_CHANGED'};
      if (window.__pocketSent) return {error:'ALREADY_SENT'};
      const {form,area,field,lang,button,ace,cm} = state;
      if (!options(lang).some(x => x.value === input.language)) return {error:'LANGUAGE_UNAVAILABLE'};
      const expected = field.name === 'submittedProblemCode' ? String(input.contest)+input.index : input.index;
      const set = (node,value) => { node.value=value; node.dispatchEvent(new Event('input',{bubbles:true})); node.dispatchEvent(new Event('change',{bubbles:true})); };
      set(field,expected); set(lang,input.language); set(area,input.source);
      if (cm) { cm.setValue(input.source); cm.save?.(); if(cm.getValue() !== input.source) return {error:'EDITOR_NOT_READY'}; }
      if (ace) { ace.setValue(input.source,-1); if(ace.getValue() !== input.source) return {error:'EDITOR_NOT_READY'}; }
      if (area.value !== input.source || lang.value !== input.language || field.value !== expected) return {error:'FORM_VALUES_CHANGED'};
      // Page listeners may rebuild the form or invalidate a challenge after changing fields.
      const final = inspectForm(input);
      if (final.error) return {error:final.error};
      if (final.handle.toLowerCase() !== input.handle.toLowerCase()) return {error:'ACCOUNT_CHANGED'};
      if (final.form !== form || final.button !== button) return {error:'FORM_VALUES_CHANGED'};
      if (!form.checkValidity()) return {error:'FORM_INVALID'};
      const ids = baseline.result.map(x=>x.id);
      try { sessionStorage.setItem('cfpocket-'+input.nonce,JSON.stringify({ids,at:Date.now()})); } catch { return {error:'STORAGE_UNAVAILABLE'}; }
      window.__pocketSent = input.nonce;
      button.click();
      return {dispatched:true,baseline:ids};
    } finally { window.__pocketSending = null; }
  """#

  public static func receipt(_ attempt: SubmissionAttempt) throws -> String {
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["contest":attempt.problem.contest,"index":attempt.problem.index,"handle":attempt.handle,"nonce":attempt.id.uuidString,"source":attempt.revision.source,"since":Int(attempt.createdAt.timeIntervalSince1970)-5]), as: UTF8.self)
    return "const input = \(json);\n" + receiptBody
  }
  public static let receiptBody = #"""
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
  """#
}
