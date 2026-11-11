import {DefaultAzureCredential} from '@azure/identity';
import {config} from './config.js';

type FcmSettings = {project?:string;provider?:string;serviceAccount?:string};
const scope='https://www.googleapis.com/auth/firebase.messaging';
export class FcmSender {
  private cached?:{token:string;expires:number};
  private refreshing?:Promise<string>;
  constructor(private settings:FcmSettings,
    private azureToken:()=>Promise<string> = async()=>{
      const token=await new DefaultAzureCredential().getToken('https://management.azure.com/.default');
      if(!token)throw Error('Azure service identity unavailable');return token.token;
    }, private request:typeof fetch=fetch) {}
  get configured() {return Boolean(this.settings.project&&this.settings.provider&&this.settings.serviceAccount);}
  private async json(url:string,headers:Record<string,string>,body:unknown) {
    const response=await this.request(url,{method:'POST',headers:{...headers,'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
    const data=await response.json() as any;
    if(!response.ok) {
      const code=typeof data.error==='string'?data.error:(data.error?.status??'unavailable');
      const detail=String(data.error_description??'').replace(/eyJ[A-Za-z0-9_.-]+/g,'[redacted]').slice(0,400);
      const error=new Error(`Push service ${new URL(url).hostname} failed (${response.status}, ${code}). ${detail}`.trim());
      Object.assign(error,{fcmCode:data.error?.details?.find((x:any)=>x.errorCode)?.errorCode});throw error;
    }
    return data;
  }
  async accessToken():Promise<string> {
    if(!this.configured)throw Error('Guardian push is not configured');
    if(this.cached && this.cached.expires>Date.now()+120000)return this.cached.token;
    if(this.refreshing)return this.refreshing;
    this.refreshing=(async()=>{
      const exchanged=await this.json('https://sts.googleapis.com/v1/token',{}, {
        grantType:'urn:ietf:params:oauth:grant-type:token-exchange',
        audience:`//iam.googleapis.com/${this.settings.provider}`,
        requestedTokenType:'urn:ietf:params:oauth:token-type:access_token',
        subjectTokenType:'urn:ietf:params:oauth:token-type:jwt',
        subjectToken:await this.azureToken(),scope:'https://www.googleapis.com/auth/cloud-platform',
      });
      const generated=await this.json(`https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${this.settings.serviceAccount}:generateAccessToken`,
        {Authorization:`Bearer ${exchanged.access_token}`},{scope:[scope],lifetime:'3600s'});
      this.cached={token:generated.accessToken,expires:Date.parse(generated.expireTime)};
      return this.cached.token;
    })();
    try{return await this.refreshing;}finally{this.refreshing=undefined;}
  }
  async send(message:Record<string,unknown>,validateOnly=false) {
    return this.json(`https://fcm.googleapis.com/v1/projects/${this.settings.project}/messages:send`,
      {Authorization:`Bearer ${await this.accessToken()}`},{validate_only:validateOnly,message});
  }
}
export const fcm=new FcmSender({project:config.FIREBASE_PROJECT_ID,provider:config.FCM_WIF_PROVIDER,serviceAccount:config.FCM_SERVICE_ACCOUNT});
export function pushMessage(token:string,title:string,body:string,data:Record<string,string>) {
  return {token,notification:{title,body},data,android:{priority:'high',ttl:'300s',notification:{channel_id:'emergency_alerts',sound:'default',tag:data.alertId??'blindway-test'}}};
}
