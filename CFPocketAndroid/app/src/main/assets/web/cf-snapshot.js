(() => {

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

    const state = inspectForm(typeof input === 'object' ? input : null);
    return {handle:state.handle, form:!state.error, formPresent:state.formPresent, readinessError:state.error || null,
      languages:state.lang ? options(state.lang).map(x => ({id:x.value,name:x.textContent.trim()})) : [],
      errors:[...document.querySelectorAll('.error')].filter(x=>x.getClientRects().length).map(x=>x.textContent.trim()).filter(Boolean).slice(0,4).join(' · ')};
})()
