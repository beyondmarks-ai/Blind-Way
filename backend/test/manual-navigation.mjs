// Opt-in check of the app's navigation service using an explicitly supplied image.
import {readFile,writeFile} from 'node:fs/promises';
import {analyzeScene} from '../dist/services.js';
const started=performance.now();
const result=await analyzeScene(await readFile(process.argv[2]),'English');
const record={milliseconds:Math.round(performance.now()-started),result};
console.log(JSON.stringify(record));
if(process.argv[3]) await writeFile(process.argv[3],JSON.stringify(record,null,2));
