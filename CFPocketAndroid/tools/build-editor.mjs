import {readFile,writeFile} from 'node:fs/promises';
const source=await readFile(new URL('./editor-core.js',import.meta.url));
for(const target of ['../app/src/main/assets/Reader/editor-core.js','../../TrainingLedger/CFPocket/Resources/Reader/editor-core.js'])await writeFile(new URL(target,import.meta.url),source);
console.log('Copied identical offline editing rules to iOS and Android.');
