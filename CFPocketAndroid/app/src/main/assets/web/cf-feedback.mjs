// Generated from CFWebForm.swift; run npm run build:submission.
const messages={
  "LOGIN_REQUIRED": "官网登录已失效，请重新登录 Codeforces。",
  "VERIFICATION_REQUIRED": "官网要求完成验证，请打开官网检查；已登录账号会保留。",
  "ACCOUNT_CHANGED": "官网账号已变化，请确认账号后重新准备提交。",
  "ALREADY_SENT": "这张网页已有提交正在处理，请先核对记录，避免重复发送。",
  "BASELINE_UNAVAILABLE": "暂时无法读取官网提交记录，代码未发送。请稍后重试，无需重新登录。",
  "WRONG_PROBLEM": "官网表单的题号与当前题目不一致，请重新准备提交。",
  "FORM_ACTION_UNSUPPORTED": "当前官网提交地址未被识别，请重新准备提交；登录状态不受影响。",
  "TOKEN_MISSING": "提交页面的校验信息尚未加载，请重新准备提交。",
  "LANGUAGE_UNAVAILABLE": "官网当前不提供所选编译器，请重新选择提交语言。",
  "EDITOR_NOT_READY": "官网代码编辑器尚未加载完成，请稍后重试或打开官网检查。",
  "SUBMIT_UNAVAILABLE": "官网暂未开放提交按钮，请打开官网查看限制说明。",
  "FORM_INVALID": "官网仍有未满足的提交条件，请打开官网检查。",
  "FORM_VALUES_CHANGED": "官网表单在准备时发生变化，代码未发送，请重试。",
  "STORAGE_UNAVAILABLE": "无法保存这次提交的核对记录，代码未发送，请重新准备提交。",
  "FORM_LOADING": "提交页面正在加载，请稍候。",
  "WRONG_ORIGIN": "当前页面不是 Codeforces 官方提交页面，请重新准备提交。",
  "FORM_MISSING": "当前官网页面没有提交表单，请重新准备提交。",
  "FORM_FIELDS_MISSING": "官网提交字段尚未完整加载，请重新准备提交或打开官网检查。"
};
export const submissionMessage=code=>messages[code]||"暂时无法准备官网提交，代码未发送。请重新准备提交或打开官网检查。";
