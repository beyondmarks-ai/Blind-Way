import {AzureOpenAI} from 'openai';
import {DefaultAzureCredential,getBearerTokenProvider} from '@azure/identity';
import {config} from './config.js';
import {navigationIntent} from './navigation.js';
let client:AzureOpenAI|undefined;
export async function classifyNavigation(question:string,prompt='none') {
  const direct=navigationIntent(question,prompt);if(direct)return direct;
  // The fast local parser handles common English commands. Other languages and
  // conversational navigation requests use a bounded structured classifier.
  if(prompt==='none'&&!/[^\u0000-\u007f]|\b(navigat\w*|directions?|route|go|guide|destination|choose|select)\b/i.test(question)||!config.AZURE_OPENAI_ENDPOINT)return undefined;
  client??=new AzureOpenAI({endpoint:config.AZURE_OPENAI_ENDPOINT,deployment:config.AZURE_OPENAI_DEPLOYMENT,apiVersion:'2025-04-01-preview',azureADTokenProvider:getBearerTokenProvider(new DefaultAzureCredential(),'https://cognitiveservices.azure.com/.default'),timeout:10000,maxRetries:0});
  const actions=['none','search','select','start','repeat','status','pause','resume','reroute','stop','confirm','reject','next'];
  const response=await client.responses.create({model:config.AZURE_OPENAI_DEPLOYMENT,store:false,max_output_tokens:180,
    instructions:`Current phone confirmation prompt: ${prompt}. Only when this is destination or start, map an explicit affirmative reply to confirm, negative reply to reject, next match to next, and repeat to repeat, in any language. An affirmative does not itself choose a different destination. With no pending prompt, yes/no/next alone are none. Classify an explicit walking-navigation request in any language. For a request to go to a place, use search and copy the spoken destination/locality without inventing an address. For an explicit numbered choice, select 1 to 3. Start only for an explicit request to start the route. Map route controls to the matching action. Ordinary camera questions, emergency requests, hypothetical discussions, and unclear requests are none. Do not invent a destination or select a place without the user choosing. Return the requested schema only.`,
    input:question,text:{format:{type:'json_schema',name:'walking_intent',strict:true,schema:{type:'object',properties:{action:{type:'string',enum:actions},destination:{type:['string','null']},index:{type:['integer','null']}},required:['action','destination','index'],additionalProperties:false}}}});
  const result=JSON.parse(response.output_text);
  if(!actions.includes(result.action)||result.action==='none')return undefined;
  if(result.action==='search')return typeof result.destination==='string'&&result.destination.length>=2&&result.destination.length<=200?{action:'search',destination:result.destination}:undefined;
  if(result.action==='select')return Number.isInteger(result.index)&&result.index>=1&&result.index<=3?{action:'select',index:result.index}:undefined;
  if(['confirm','reject','next'].includes(result.action)&&!['destination','start'].includes(prompt))return undefined;
  return {action:result.action};
}
