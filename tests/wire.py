"""Minimal local Mongo OP_MSG client for integration tests; no third-party driver."""
import socket
import struct
class Long(int):pass
class DateMs(int):pass
class Timestamp(int):pass
class ObjectId(bytes):pass
class Binary(bytes):
    def __new__(cls,data,subtype=0):
        value=super().__new__(cls,data);value.subtype=subtype;return value
class Regex:
    def __init__(self,pattern,options):self.pattern=pattern;self.options=options

def cstring(value):
    assert '\0' not in value
    return value.encode()+b'\0'
def encode(doc):
    body=b''
    for key,value in doc.items():
        name=cstring(key)
        if isinstance(value,bool):kind=8;data=bytes([value])
        elif value is None:kind=10;data=b''
        elif isinstance(value,DateMs):kind=9;data=struct.pack('<q',value)
        elif isinstance(value,Timestamp):kind=17;data=struct.pack('<Q',value)
        elif isinstance(value,Long):kind=18;data=struct.pack('<q',value)
        elif isinstance(value,int):
            kind=16 if -(2**31)<=value<2**31 else 18;data=struct.pack('<i' if kind==16 else '<q',value)
        elif isinstance(value,float):kind=1;data=struct.pack('<d',value)
        elif isinstance(value,str):
            kind=2;raw=value.encode();data=struct.pack('<i',len(raw)+1)+raw+b'\0'
        elif isinstance(value,dict):kind=3;data=encode(value)
        elif isinstance(value,list):kind=4;data=encode({str(i):v for i,v in enumerate(value)})
        elif isinstance(value,ObjectId):kind=7;data=bytes(value);assert len(data)==12
        elif isinstance(value,bytes):kind=5;data=struct.pack('<i',len(value))+bytes([getattr(value,'subtype',0)])+value
        elif isinstance(value,Regex):kind=11;data=cstring(value.pattern)+cstring(value.options)
        else:raise TypeError(type(value))
        body+=bytes([kind])+name+data
    return struct.pack('<i',len(body)+5)+body+b'\0'
def decode(raw,offset=0):
    end=offset+struct.unpack_from('<i',raw,offset)[0];at=offset+4;doc={}
    while at<end-1:
        kind=raw[at];at+=1;stop=raw.index(0,at);key=raw[at:stop].decode();at=stop+1
        if kind==1:value=struct.unpack_from('<d',raw,at)[0];at+=8
        elif kind==2:
            size=struct.unpack_from('<i',raw,at)[0];at+=4;value=raw[at:at+size-1].decode();at+=size
        elif kind in [3,4]:
            value,at=decode(raw,at)
            if kind==4:value=[value[str(i)] for i in range(len(value))]
        elif kind==5:
            size=struct.unpack_from('<i',raw,at)[0];at+=4;subtype=raw[at];at+=1;value=Binary(raw[at:at+size],subtype);at+=size
        elif kind==7:value=ObjectId(raw[at:at+12]);at+=12
        elif kind==8:value=bool(raw[at]);at+=1
        elif kind==9:value=DateMs(struct.unpack_from('<q',raw,at)[0]);at+=8
        elif kind==10:value=None
        elif kind==11:
            stop=raw.index(0,at);pattern=raw[at:stop].decode();at=stop+1;stop=raw.index(0,at);value=Regex(pattern,raw[at:stop].decode());at=stop+1
        elif kind==16:value=struct.unpack_from('<i',raw,at)[0];at+=4
        elif kind==17:value=Timestamp(struct.unpack_from('<Q',raw,at)[0]);at+=8
        elif kind==18:value=Long(struct.unpack_from('<q',raw,at)[0]);at+=8
        else:raise ValueError('Unsupported BSON response type '+str(kind))
        doc[key]=value
    assert at==end-1 and raw[at]==0
    return doc,end
class Client:
    def __init__(self,port):self.port=port
    def command(self,doc,database='wekan'):
        body=struct.pack('<i',0)+b'\0'+encode(dict(doc,**{'$db':database}))
        message=struct.pack('<iiii',len(body)+16,1,0,2013)+body
        with socket.create_connection(('127.0.0.1',self.port),timeout=10) as conn:
            conn.sendall(message)
            def read(count):
                result=b''
                while len(result)<count:
                    part=conn.recv(count-len(result))
                    if not part:raise EOFError('Mongo connection closed')
                    result+=part
                return result
            header=read(16);length,_,response,opcode=struct.unpack('<iiii',header)
            assert response==1 and opcode==2013,(response,opcode)
            data=read(length-16);assert data[4]==0
            result,_=decode(data,5)
            assert result.get('ok')==1,result
            return result
    def find(self,collection,identity):
        result=self.command({'find':collection,'filter':{'_id':identity},'batchSize':100})
        return result['cursor']['firstBatch']
