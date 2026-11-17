const http=require('node:http');const assert=require('node:assert/strict');
const base=new URL(process.argv[2]);const agent=new http.Agent({keepAlive:true,maxSockets:1});
function call(method,path,body='') {
  return new Promise((resolve,reject)=>{
    const request=http.request({hostname:base.hostname,port:base.port,path,method,agent,
      headers:{Host:'localhost','User-Agent':'Conn-test','Content-Type':'application/x-www-form-urlencoded','Content-Length':Buffer.byteLength(body)}},response=>{
      response.on('error',reject);response.resume();response.on('end',()=>{
        try {assert.equal(response.headers.connection,'close');assert([200,429].includes(response.statusCode));resolve();}catch(error){reject(error);}
      });
    });request.on('error',reject);request.end(body);
  });
}
(async()=>{
  try {for(let i=0;i<40;i++){await call('GET','/robots.txt');await call('POST','/sign-in','username=missing&password=invalid');}
    console.log('PASS: pooled HTTP/1.1 GET/POST clients reconnect after advertised close without resets');
  } finally {agent.destroy();}
})().catch(error=>{console.error(error);process.exit(1);});
