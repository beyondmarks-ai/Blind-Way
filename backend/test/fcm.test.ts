import {describe,it,expect,vi} from 'vitest';
import {FcmSender,pushMessage} from '../src/fcm.js';
import {MemoryRepository} from '../src/repository.js';

describe('keyless Firebase notifications',()=>{
  it('exchanges the Azure identity, scopes the service token and caches it; validation never delivers',async()=>{
    const request=vi.fn()
      .mockResolvedValueOnce(Response.json({access_token:'federated'}))
      .mockResolvedValueOnce(Response.json({accessToken:'scoped',expireTime:new Date(Date.now()+3600000).toISOString()}))
      .mockImplementation(async()=>Response.json({name:'validated'}));
    const azure=vi.fn(async()=> 'azure-identity');
    const sender=new FcmSender({project:'test-project',provider:'projects/123/locations/global/workloadIdentityPools/p/providers/a',serviceAccount:'push@example.iam.gserviceaccount.com'},azure,request);
    const message=pushMessage('test-device','Test','Test only',{type:'test'});
    await sender.send(message,true);
    await sender.send(message,true);
    expect(azure).toHaveBeenCalledTimes(1);
    expect(request).toHaveBeenCalledTimes(4);
    const body=(n:number)=>JSON.parse(request.mock.calls[n][1].body);
    expect(body(0)).toMatchObject({subjectToken:'azure-identity',subjectTokenType:'urn:ietf:params:oauth:token-type:jwt'});
    expect(body(1)).toEqual({scope:['https://www.googleapis.com/auth/firebase.messaging'],lifetime:'3600s'});
    expect(body(2)).toMatchObject({validate_only:true,message:{token:'test-device',android:{priority:'high',notification:{channel_id:'emergency_alerts'}}}});
    expect(request.mock.calls[2][1].headers.Authorization).toBe('Bearer scoped');
  });
  it('fails closed without configuration and never sends with a failed identity exchange',async()=>{
    const request=vi.fn(async()=>Response.json({error:{status:'PERMISSION_DENIED'}},{status:403}));
    await expect(new FcmSender({},async()=> 'identity',request).send({})).rejects.toThrow('not configured');
    expect(request).not.toHaveBeenCalled();
    const sender=new FcmSender({project:'p',provider:'provider',serviceAccount:'sa'},async()=> 'identity',request);
    await expect(sender.send({})).rejects.toThrow('403');
    expect(request).toHaveBeenCalledTimes(1);
  });
  it('moves an installation token when its account changes',async()=>{
    const store=new MemoryRepository();
    const device={id:'old-device',type:'device' as const,platform:'android' as const,ownerId:'old-owner',pushToken:'installation',updatedAt:new Date().toISOString()};
    await store.saveDevice(device);
    await store.saveDevice({...device,id:'new-device',ownerId:'new-owner'});
    expect(await store.devices(['old-owner'])).toEqual([]);
    expect(await store.devices(['new-owner'])).toHaveLength(1);
  });
});
