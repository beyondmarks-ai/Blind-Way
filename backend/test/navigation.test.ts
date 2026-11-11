import {describe,it,expect,vi} from 'vitest';
import {MapsNavigation,navigationIntent,mapsLanguage} from '../src/navigation.js';
describe('Google walking navigation',()=>{
  it('interprets yes/no/next only when the phone is waiting for confirmation',()=>{
    for(const [text,action] of [['yes','confirm'],['No thanks','reject'],['next one','next'],['say that again','repeat']]) {
      expect(navigationIntent(text)).toBeUndefined();
      expect(navigationIntent(text,'destination')).toEqual({action});
      expect(navigationIntent(text,'start')).toEqual({action});
    }
    expect(navigationIntent('yes but not that address','destination')).toBeUndefined();
  });
  it('searches near GPS and uses a narrow field mask',async()=>{
    const fetcher=vi.fn(async()=>Response.json({places:[{id:'place-one',displayName:{text:'Park'},formattedAddress:'Main Road',location:{latitude:12,longitude:77}}]}));
    const maps=new MapsNavigation('test-key',fetcher);
    expect(await maps.search('Park',{latitude:12,longitude:77},'kn-IN')).toMatchObject([{id:'place-one',name:'Park'}]);
    const options=fetcher.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(options.body as string)).toMatchObject({languageCode:'kn',pageSize:3,locationBias:{circle:{center:{latitude:12,longitude:77}}}});
    expect(options.headers).toMatchObject({'X-Goog-Api-Key':'test-key'});
  });
  it('requests walking only and preserves provider directions and warnings',async()=>{
    const fetcher=vi.fn(async()=>Response.json({routes:[{distanceMeters:130,duration:'100s',polyline:{encodedPolyline:'abc'},warnings:['No sidewalk'],legs:[{steps:[{distanceMeters:130,startLocation:{latLng:{latitude:12,longitude:77}},endLocation:{latLng:{latitude:12.001,longitude:77}},navigationInstruction:{instructions:'Turn left onto <b>Main Road</b>',maneuver:'TURN_LEFT'}}]}]}]}));
    const result=await new MapsNavigation('test-key',fetcher).route({latitude:12,longitude:77},'selected-place','en-IN');
    expect(JSON.parse((fetcher.mock.calls[0][1] as RequestInit).body as string)).toMatchObject({travelMode:'WALK',destination:{placeId:'selected-place'}});
    expect(result.steps[0].instruction).toBe('Turn left onto Main Road');
    expect(result.warnings).toContain('No sidewalk');
  });
  it('fails closed when no route or cloud access exists',async()=>{
    await expect(new MapsNavigation('test',async()=>Response.json({routes:[]})).route({latitude:1,longitude:1},'place','en-IN')).rejects.toMatchObject({status:404});
    await expect(new MapsNavigation('test',async()=>Response.json({},{status:403})).search('Park',{latitude:1,longitude:1},'en-IN')).rejects.toMatchObject({status:502});
  });
  it('extracts destinations and controls without confusing a scene question or emergency',()=>{
    expect(navigationIntent('Take me to Cubbon Park')).toEqual({action:'search',destination:'Cubbon Park'});
    expect(navigationIntent('Choose two')).toEqual({action:'select',index:2});
    expect(navigationIntent('Stop navigation')).toEqual({action:'stop'});
    expect(navigationIntent('What is in front of me?')).toBeUndefined();
    expect(navigationIntent('Help')).toBeUndefined();
    expect(mapsLanguage('od-IN')).toBe('en');
  });
});
