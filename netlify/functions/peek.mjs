// /api/peek?url=  Läser titel, bild, pris och butik ur en produktsida. Svarar med det som hittas, aldrig påhittat.
const UA='Mozilla/5.0 (Linux; Android 14; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
import {lookup} from 'node:dns/promises';
import net from 'node:net';
// SSRF-skydd: varje steg (även omdirigeringar) slås upp i DNS och får inte peka på interna adresser.
function badIp(ip){if(net.isIPv4(ip)){const [a,b]=ip.split('.').map(Number);
  return a===0||a===10||a===127||(a===169&&b===254)||(a===172&&b>=16&&b<=31)||(a===192&&b===168)||(a===100&&b>=64&&b<=127)||a>=224}
 const x=ip.toLowerCase();if(x.startsWith('::ffff:'))return badIp(x.slice(7));
 return x==='::'||x==='::1'||/^f[cd]/.test(x)||/^fe[89ab]/.test(x)||x.startsWith('ff')}
async function safeUrl(u){if(!/^https?:$/.test(u.protocol)||u.username||u.password)return false;if(u.port&&!['80','443'].includes(u.port))return false;
 const h=u.hostname.replace(/^\[|\]$/g,'');if(net.isIP(h))return !badIp(h);if(!h.includes('.')||/\.(local|internal|localhost)$/i.test(h))return false;
 try{const all=await lookup(h,{all:true});return all.length>0&&all.every(a=>!badIp(a.address))}catch(e){return false}}
async function safeFetch(url,opt){let u=url;for(let i=0;i<4;i++){if(!(await safeUrl(u)))throw new Error('blocked');
  const r=await fetch(u,{...opt,redirect:'manual'});if(r.status>=300&&r.status<400&&r.headers.get('location')){u=new URL(r.headers.get('location'),u);continue}return r}
 throw new Error('too_many_redirects')}
const json=(o,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'content-type':'application/json; charset=utf-8','cache-control':'public, max-age=600'}});
const dec=s=>String(s||'').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&nbsp;/g,' ').replace(/&#(\d+);/g,(_,n)=>String.fromCharCode(+n)).trim();
function meta(html,keys){for(const k of keys){const re=new RegExp(`<meta[^>]+(?:property|name|itemprop)=["']${k}["'][^>]*content=["']([^"']+)["']`,'i');let m=html.match(re);if(!m){const re2=new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name|itemprop)=["']${k}["']`,'i');m=html.match(re2)}if(m)return dec(m[1])}return null}
function num(v){if(v==null)return null;const s=String(v).replace(/\s|&nbsp;/g,'').replace(/[^\d.,]/g,'');if(!s)return null;let n;if(/,\d{1,2}$/.test(s))n=parseFloat(s.replace(/\./g,'').replace(',','.'));else n=parseFloat(s.replace(/,/g,''));return isFinite(n)&&n>0&&n<1e6?Math.round(n):null}
function ld(html){const out={};const re=/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;let m;
 while((m=re.exec(html))){let d;try{d=JSON.parse(m[1].trim())}catch(e){continue}const arr=Array.isArray(d)?d:(d['@graph']||[d]);
  for(const o of arr){if(!o||typeof o!=='object')continue;const t=String(o['@type']||'').toLowerCase();
   if(t.includes('product')){out.name=out.name||o.name;const im=Array.isArray(o.image)?o.image[0]:o.image;out.image=out.image||(typeof im==='string'?im:im&&im.url);const of=Array.isArray(o.offers)?o.offers[0]:o.offers;
    if(of){out.cur=out.cur||of.priceCurrency||(of.priceSpecification&&of.priceSpecification.priceCurrency);out.price=out.price||num(of.price||of.lowPrice||(of.priceSpecification&&of.priceSpecification.price));out.shop=out.shop||(of.seller&&of.seller.name)}}
   if(t==='organization'||t==='webSite'.toLowerCase())out.shop=out.shop||o.name}}return out}
export default async (req)=>{
 const u=new URL(req.url).searchParams.get('url');let target;
 try{target=new URL(u);if(!(await safeUrl(target)))throw 0}catch(e){return json({error:'bad_url'},400)}
 const ctrl=new AbortController();const t=setTimeout(()=>ctrl.abort(),7000);
 let html='';try{const r=await safeFetch(target,{headers:{'user-agent':UA,'accept':'text/html,*/*;q=0.8','accept-language':'sv-SE,sv;q=0.9,en;q=0.7'},signal:ctrl.signal});
  const ct=r.headers.get('content-type')||'';if(!/html|xml/.test(ct))return json({partial:true,shop:target.hostname.replace(/^www\./,'')});
  const reader=r.body.getReader();const chunks=[];let got=0;while(true){const {done,value}=await reader.read();if(done)break;chunks.push(value);got+=value.length;if(got>1500000)break}
  html=new TextDecoder('utf-8').decode(Buffer.concat(chunks.map(c=>Buffer.from(c))))}catch(e){return json({partial:true,shop:target.hostname.replace(/^www\./,''),error:'fetch_failed'})}finally{clearTimeout(t)}
 const L=ld(html);
 let name=L.name||meta(html,['og:title','twitter:title']);if(!name){const m=html.match(/<title[^>]*>([^<]+)<\/title>/i);name=m?dec(m[1]):null}
 if(name)name=name.split(/\s[|–-]\s/)[0].trim().slice(0,80);
 let image=L.image||meta(html,['og:image','og:image:secure_url','twitter:image']);if(image){try{image=new URL(image,target).href}catch(e){image=null}}
 let price=L.price||num(meta(html,['product:price:amount','og:price:amount','price','twitter:data1']));
 if(price==null){const m=html.match(/(?:"price"|'price'|data-price|itemprop="price"[^>]*content)\s*[:=]\s*["']?([\d\s.,]{2,12})/i);if(m)price=num(m[1])}
 const cur=String(L.cur||meta(html,['product:price:currency','og:price:currency'])||'SEK').toUpperCase();if(cur!=='SEK')price=null;
 const shop=(L.shop&&String(L.shop).slice(0,40))||meta(html,['og:site_name'])||target.hostname.replace(/^www\./,'').split('.')[0].replace(/^./,c=>c.toUpperCase());
 return json({name:name||null,image:image||null,price:price??null,currency:cur,shop:shop||null,partial:!(name&&price!=null)});
};
export const config={path:'/api/peek'};
