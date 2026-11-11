import {config} from './config.js';
import {HttpError} from './auth.js';
export type Coordinates={latitude:number;longitude:number};
export const walkingWarning='Walking directions are in beta. Use caution - this route may be missing sidewalks or pedestrian paths. Use your usual mobility aid. The app cannot tell whether a crossing is safe.';
export function navigationIntent(question:string,prompt='none') {
  const text=question.trim().replace(/[.!?]+$/,'');
  if(['destination','start'].includes(prompt)) {
    if(/^(yes|yes please|yeah|correct|that is right|that is the place|confirm|okay|ok)$/i.test(text))return {action:'confirm'};
    if(/^(no|no thanks|no thank you|not this|wrong place)$/i.test(text))return {action:'reject'};
    if(/^(next|next one|next place|another one)$/i.test(text))return {action:'next'};
    if(/^(repeat|repeat address|say that again)$/i.test(text))return {action:'repeat'};
  }
  const search=text.match(/^(?:please\s+)?(?:navigate to|take me to|directions to|how do I get to|I want to go to|walk to|go to)\s+(.{2,180})$/i);
  if(search)return {action:'search',destination:search[1]};
  const select=text.match(/^(?:choose|select|option)\s+(one|two|three|[123])$/i);
  if(select)return {action:'select',index:({'one':1,'two':2,'three':3} as Record<string,number>)[select[1].toLowerCase()]??Number(select[1])};
  const actions:Record<string,string>={'start route':'start','start navigation':'start','stop navigation':'stop','stop route':'stop','repeat direction':'repeat','repeat directions':'repeat','pause navigation':'pause','resume navigation':'resume','reroute':'reroute','route status':'status'};
  return actions[text.toLowerCase()]?{action:actions[text.toLowerCase()]}:undefined;
}
export function mapsLanguage(value:string) {
  const code=value==='auto'?'en':value.split('-')[0];
  // Odia is translated by the authenticated language relay after route retrieval.
  return code==='od'?'en':code;
}
export class MapsNavigation {
  constructor(private key=config.GOOGLE_MAPS_SERVER_KEY,private request:typeof fetch=fetch){}
  private async post(url:string,body:unknown,fields:string) {
    if(!this.key)throw new HttpError(503,'Google Maps is not configured.');
    let response:Response;
    try {response=await this.request(url,{method:'POST',headers:{'Content-Type':'application/json','X-Goog-Api-Key':this.key,'X-Goog-FieldMask':fields},body:JSON.stringify(body),signal:AbortSignal.timeout(12000)});}
    catch {throw new HttpError(503,'Google Maps could not be reached. Check internet and try again.');}
    if(!response.ok)throw new HttpError(502,`Google Maps request failed (${response.status}). Please try again.`);
    return await response.json() as any;
  }
  async search(query:string,origin:Coordinates,language:string) {
    const data=await this.post('https://places.googleapis.com/v1/places:searchText',{
      textQuery:query,languageCode:mapsLanguage(language),pageSize:3,
      locationBias:{circle:{center:origin,radius:10000}},
    },'places.id,places.displayName,places.formattedAddress,places.location,places.attributions');
    return (data.places??[]).map((p:any)=>({id:p.id,name:p.displayName?.text??p.formattedAddress,address:p.formattedAddress??'',location:p.location,attributions:p.attributions??[]}));
  }
  async route(origin:Coordinates,placeId:string,language:string) {
    const data=await this.post('https://routes.googleapis.com/directions/v2:computeRoutes',{
      origin:{location:{latLng:origin}},destination:{placeId},travelMode:'WALK',
      languageCode:mapsLanguage(language),units:'METRIC',computeAlternativeRoutes:false,polylineQuality:'HIGH_QUALITY',
    },'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.warnings,routes.legs.steps.distanceMeters,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.startLocation,routes.legs.steps.endLocation,routes.legs.steps.navigationInstruction');
    const r=data.routes?.[0];
    if(!r)throw new HttpError(404,'No walking route was found. Choose another destination.');
    const steps=(r.legs??[]).flatMap((leg:any)=>leg.steps??[]).map((s:any)=>({
      distanceMeters:s.distanceMeters??0,start:s.startLocation.latLng,end:s.endLocation.latLng,
      instruction:String(s.navigationInstruction?.instructions??'Continue along the mapped walking route.').replace(/<[^>]*>/g,'').replace(/&amp;/g,'&'),
      maneuver:s.navigationInstruction?.maneuver??'MANEUVER_UNSPECIFIED',polyline:s.polyline?.encodedPolyline??'',
    }));
    if(!steps.length)throw new HttpError(404,'Google Maps returned no walking instructions.');
    return {distanceMeters:r.distanceMeters,durationSeconds:Math.round(parseFloat(r.duration)),polyline:r.polyline?.encodedPolyline??'',steps,warnings:[walkingWarning,...(r.warnings??[])],source:'Google Maps'};
  }
}
export const mapsNavigation=new MapsNavigation();
