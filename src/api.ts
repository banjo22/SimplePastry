import {createClient} from '@supabase/supabase-js';
import {reduce,seed,type Data,type Command} from './model';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const supabase=url&&key?createClient(url,key):null;
export const demo=!supabase;
const storageKey='smart-pantry-demo-v1';
export async function read():Promise<Data>{if(supabase){const {data,error}=await supabase.rpc('pantry_snapshot');if(error)throw error;return data;}const raw=localStorage.getItem(storageKey);if(raw)return JSON.parse(raw);const data=seed();localStorage.setItem(storageKey,JSON.stringify(data));return data;}
export async function command(c:Command,requestId:string=crypto.randomUUID()):Promise<Data>{
 if(supabase){if(!navigator.onLine)throw Error('Du bist offline. Bitte verbinde dich mit dem Internet.');const {error}=c.op==='reorder_product'?await supabase.rpc('pantry_reorder_product',{request_id:requestId,product_id:c.id,direction:c.direction}):c.op==='move_product'?await supabase.rpc('pantry_move_product',{request_id:requestId,product_id:c.id,before_product_id:c.before_id??null}):c.op==='move_shopping'?await supabase.rpc('pantry_move_shopping',{request_id:requestId,shopping_id:c.id,before_shopping_id:c.before_id??null}):await supabase.rpc('pantry_command',{request_id:requestId,command:c});if(error)throw error;return read();}
 const run=async()=>{const data=reduce(await read(),c);localStorage.setItem(storageKey,JSON.stringify(data));return data;};
 return navigator.locks?navigator.locks.request(storageKey,run):run();
}
