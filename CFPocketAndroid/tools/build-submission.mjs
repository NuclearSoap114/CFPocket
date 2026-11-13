import {readFile,writeFile} from 'node:fs/promises';
const source=await readFile(new URL('../../TrainingLedger/TrainingCore/Sources/PocketCore/CFWebForm.swift',import.meta.url),'utf8');
function body(name){const m=source.match(new RegExp('public static let '+name+' = #"""\\n([\\s\\S]*?)\\n  """#'));if(!m)throw Error('Missing Swift script: '+name);return m[1];}
const helpers=body('formHelpers');
for(const [name,value] of Object.entries({'cf-snapshot.js':'(() => {\n'+helpers+'\n'+body('snapshotBody')+'\n})()','cf-dispatch.js':helpers+'\n'+body('dispatchOperation'),'cf-receipt.js':body('receiptBody')}))await writeFile(new URL('../app/src/main/assets/web/'+name,import.meta.url),value+'\n');
const messages=Object.fromEntries([...source.matchAll(/case "([A-Z_]+)": return "([^"]+)"/g)].map(m=>[m[1],m[2]]));
await writeFile(new URL('../app/src/main/assets/web/cf-feedback.mjs',import.meta.url),'// Generated from CFWebForm.swift; run npm run build:submission.\nconst messages='+JSON.stringify(messages,null,2)+';\nexport const submissionMessage=code=>messages[code]||"暂时无法准备官网提交，代码未发送。请重新准备提交或打开官网检查。";\n');
console.log('Generated shared submission checks and feedback for Android.');
