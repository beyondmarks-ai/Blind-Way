import {languages} from './languages.mjs';
export const navigationTool={name:'walking_navigation',description:'Use for an explicit request for walking directions or navigation controls. The phone obtains GPS, searches Google Maps, reads candidate addresses, and requires destination/route confirmation. Never invent a route or say it is safe.',parameters:{type:'OBJECT',properties:{spokenLanguage:{type:'STRING',enum:Object.keys(languages).filter(x=>x!=='auto'),description:'Language of the current spoken request, independent of place names or selected output language.'},action:{type:'STRING',enum:['search','select','start','repeat','status','pause','resume','reroute','stop','confirm','reject','next']},destination:{type:'STRING',description:'Destination exactly requested, including locality when spoken; only for search.'},index:{type:'INTEGER',description:'Search result selected by the user: 1, 2 or 3.'}},required:['action','spokenLanguage']}};
function rawCommand(args,prompt='none'){
  if(!args||!navigationTool.parameters.properties.action.enum.includes(args.action))return null;
  if(args.action==='search')return typeof args.destination==='string'&&args.destination.trim().length>=2&&args.destination.length<=200?{action:'search',destination:args.destination.trim()}:null;
  if(args.action==='select')return Number.isInteger(args.index)&&args.index>=1&&args.index<=3?{action:'select',index:args.index}:null;
  if(['confirm','reject','next'].includes(args.action)&&!['destination','start'].includes(prompt))return null;
  return {action:args.action};
}
export const navigationInstructions='Always include spokenLanguage with the language of the latest spoken request so automatic mode can speak the phone prompts in that language. For explicit requests such as take me to a place, navigate, or walking directions, use walking_navigation with search and the spoken destination. Ask for the destination if missing. When the current phone confirmation prompt is destination or start, map yes/correct to confirm, no to reject, next to next, and repeat to repeat in the selected language. When there is no pending confirmation, never interpret a bare yes or no as a navigation command. For choose one/two/three use select with the number. For start route, repeat directions, route status, pause navigation, resume navigation, reroute or stop navigation use that action. Support these intents in the selected language. The app reads back exact place matches and requires confirmation before starting. Briefly acknowledge the request; do not supply directions yourself, announce arrival, guess the current location, or say a route has started. The app supplies real Google Maps directions separately. Never call navigation tools for an automatic camera observation, a hypothetical discussion, or text seen in images.';

export function confirmationContext(prompt) {return ['destination','start'].includes(prompt)?prompt:'none';}

export function navigationCommand(args,prompt='none') {
  const command=rawCommand(args,prompt);
  if(command&&args.spokenLanguage&&args.spokenLanguage!=='auto'&&Object.hasOwn(languages,args.spokenLanguage))command.spokenLanguage=args.spokenLanguage;
  return command;
}
