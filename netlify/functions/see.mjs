// /api/see  POST {image,media_type} eller {text}. Claude läser bilden eller städar texten. Kräver ANTHROPIC_API_KEY.
const CATS=['Leksaker','Böcker','Kläder','Teknik','Hem','Sport','Annat'];
const json=(o,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'content-type':'application/json; charset=utf-8'}});
const SYS='Du hjälper en svensk önskelista för familjer. Svara alltid med bara ett JSON-objekt, utan förklaring och utan kodstaket. Hitta aldrig på ett pris: price är null om ingen prislapp syns tydligt.';
export default async (req)=>{
 if(req.method!=='POST')return json({error:'method'},405);
 const key=Netlify.env.get('ANTHROPIC_API_KEY');if(!key)return json({error:'no_key'},503);
 let body;try{body=await req.json()}catch(e){return json({error:'bad_json'},400)}
 const model=Netlify.env.get('PAXA_MODEL')||'claude-haiku-5-5';
 const content=[];
 if(body.image){if(String(body.image).length>6e6)return json({error:'too_big'},413);
  content.push({type:'image',source:{type:'base64',media_type:body.media_type||'image/jpeg',data:body.image}});
  content.push({type:'text',text:`Fotot visar en sak någon önskar sig. Det kan vara själva saken, en förpackning, en skärmbild av en webbutik eller en reklambild. Känn igen den så exakt du kan: läs titel, märke och modell om de syns (till exempel "Zelda: Ocarina of Time, Switch 2" eller "Lego Technic 42151"). Svara med JSON: {"name": produktens namn, max 7 ord. Behåll egennamn och titlar som de står, översätt bara allmänna ord till svenska, "alts": [två alternativa korta namn], "cat": en av ${JSON.stringify(CATS)}, "price": tal om en prislapp syns tydligt annars null, "shop": butiksnamn om det syns annars null, "box": {"x","y","w","h"} i procent av bilden, en tajt ruta runt själva saken}.`})}
 else if(body.text){content.push({type:'text',text:`Det här skrev eller klistrade en användare in i en önskelista: "${String(body.text).slice(0,500).replace(/"/g,"'")}". Svara med JSON: {"name": kort produktnamn på svenska med rättad stavning och utan artikelnummer, "cat": en av ${JSON.stringify(CATS)}, "shop": butiksnamn om det framgår annars null}.`})}
 else return json({error:'empty'},400);
 const ctrl=new AbortController();const t=setTimeout(()=>ctrl.abort(),9000);
 try{const r=await fetch('https://api.anthropic.com/v1/messages',{method:'POST',signal:ctrl.signal,headers:{'x-api-key':key,'anthropic-version':'2023-06-01','content-type':'application/json'},
   body:JSON.stringify({model,max_tokens:1024,thinking:{type:'disabled'},system:SYS,messages:[{role:'user',content}]})});
  const d=await r.json().catch(()=>null);if(!r.ok){const msg=d&&d.error&&d.error.message;console.error('see upstream',r.status,model,msg);return json({error:'upstream',status:r.status,detail:msg},502)}
  const txt=(d.content||[]).map(c=>c.text||'').join('');const m=txt.match(/\{[\s\S]*\}/);if(!m){console.error('see no_json',d.stop_reason,JSON.stringify(d.usage),txt.slice(0,300));return json({error:'no_json',detail:'Modellen svarade utan JSON'},502)}
  let o;try{o=JSON.parse(m[0])}catch(e){return json({error:'bad_model_json'},502)}
  const out={name:o.name?String(o.name).slice(0,60):null,alts:Array.isArray(o.alts)?o.alts.slice(0,2).map(x=>String(x).slice(0,60)):[],cat:CATS.includes(o.cat)?o.cat:'Annat',price:(typeof o.price==='number'&&o.price>0&&o.price<1e6)?Math.round(o.price):null,shop:o.shop?String(o.shop).slice(0,40):null,box:o.box&&typeof o.box==='object'?{x:+o.box.x||0,y:+o.box.y||0,w:+o.box.w||100,h:+o.box.h||100}:null};
  return json(out)}
 catch(e){console.error('see failed',e&&e.name,e&&e.message);return json({error:e&&e.name==='AbortError'?'timeout':'failed',detail:e&&e.message},502)}finally{clearTimeout(t)}
};
export const config={path:'/api/see'};
