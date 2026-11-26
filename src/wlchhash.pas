unit wlchhash;
{$mode objfpc}{$H+}{$CODEPAGE UTF8}
interface
uses fpjson;

// Hash a list lifecycle record after dates have been rendered as UTC ISO strings.
function ListLifecycleHash(Row:TJSONObject):string;
function HistoryBoardKey(const Prefix,BoardId:string):string;
// WeKan's canonical() of a history value (models/lib/changeHistoryIntegrity.js):
// keys sorted, arrays in order, numbers as JSON.stringify writes them. Two
// rule snapshots are the same when their canonical texts are.
function CanonicalHistoryValue(Value:TJSONData):string;
// hashHistoryRow of any row: its protected keys, canonical, SHA-256.
function HistoryRowHash(Row:TJSONObject):string;
function ListReservationHash(Row:TJSONObject):string;
procedure ReservationHashes(const Document:string;out RowHash,PendingHash:string;
  const LegacyHash:string='';const ExpectedPendingHash:string='');

implementation
uses SysUtils,Classes,Math,StrUtils,base64,wlcrypt,wlcfjson,wlsjson;

const ProtectedKeys:array[0..15] of string=(
  'batchId','boardId','cardId','changeType','createdAt','entityId','entityType',
  'group','listId','newContent','previousContent','previousHash','restoredByUserId',
  'restoredFromId','swimlaneId','userId');

function JsonString(const Value:string):string;
var i:Integer;C:Char;
begin
  Result:='"';
  for i:=1 to Length(Value) do
  begin
    C:=Value[i];
    case C of
      '"','\': Result:=Result+'\'+C;
      #8: Result:=Result+'\b';
      #9: Result:=Result+'\t';
      #10: Result:=Result+'\n';
      #12: Result:=Result+'\f';
      #13: Result:=Result+'\r';
      #0..#7,#11,#14..#31: Result:=Result+'\u'+LowerCase(IntToHex(Ord(C),4));
      else Result:=Result+C;
    end;
  end;
  Result:=Result+'"';
end;

// JSON.stringify of a number: an integer as its digits, any other the
// shortest decimal that reads back as the same double, an exponent only from
// 1e21 up and below 1e-6.
function JsNumber(Value:TJSONData):string;
var D,Back:Double;P,E,Dot,ExpAt,I:Integer;Text,Digits,Mantissa,Full,Candidate:string;Neg:Boolean;
begin
  if TJSONNumber(Value).NumberType in [ntInteger,ntInt64,ntQWord] then Exit(Value.AsJSON);
  D:=Value.AsFloat;
  if IsNan(D) or IsInfinite(D) then raise Exception.Create('history contains a non-finite number');
  if D=0 then Exit('0');
  if (Frac(D)=0) and (Abs(D)<1e21) then Exit(FormatFloat('0',D));
  // The shortest form that reads back as the same double: the 17 digits
  // Str gives (FloatToStrF stops at 15), rounded to fewer while they still do.
  Str(Abs(D):25,Full);Full:=Trim(Full);
  ExpAt:=Pos('E',Full);E:=StrToInt(Copy(Full,ExpAt+1,MaxInt));
  Digits:=StringReplace(Copy(Full,1,ExpAt-1),'.','',[]);
  Text:=Copy(Digits,1,1)+'.'+Copy(Digits,2,MaxInt)+'E'+IntToStr(E);
  for P:=1 to Length(Digits) do
  begin
    Mantissa:=Copy(Digits,1,P);
    if (P<Length(Digits)) and (Digits[P+1]>='5') then
    begin
      // Rounded up, the carry through the nines.
      I:=P;
      while (I>=1) and (Mantissa[I]='9') do begin Mantissa[I]:='0';Dec(I);end;
      if I>=1 then Mantissa[I]:=Chr(Ord(Mantissa[I])+1) else Mantissa:='1'+Mantissa;
    end;
    if Length(Mantissa)>P then Candidate:=Copy(Mantissa,1,1)+'.'+Copy(Mantissa,2,MaxInt)+'E'+IntToStr(E+1)
    else Candidate:=Copy(Mantissa,1,1)+'.'+Copy(Mantissa,2,MaxInt)+'E'+IntToStr(E);
    if TryStrToFloat(Candidate,Back,DefaultFormatSettings) and (Back=Abs(D)) then begin Text:=Candidate;Break;end;
  end;
  if D<0 then Text:='-'+Text;
  // As digits and the exponent of the first of them: d.ddd x 10^E.
  Neg:=(Text<>'') and (Text[1]='-');
  if Neg then Delete(Text,1,1);
  ExpAt:=Pos('E',UpperCase(Text));E:=0;
  if ExpAt>0 then begin E:=StrToInt(Copy(Text,ExpAt+1,MaxInt));Text:=Copy(Text,1,ExpAt-1);end;
  Dot:=Pos('.',Text);
  if Dot=0 then Dot:=Length(Text)+1;
  Digits:=StringReplace(Text,'.','',[]);
  E:=E+Dot-2;
  I:=1;
  while (I<Length(Digits)) and (Digits[I]='0') do begin Inc(I);Dec(E);end;
  Digits:=Copy(Digits,I,MaxInt);
  while (Length(Digits)>1) and (Digits[Length(Digits)]='0') do Delete(Digits,Length(Digits),1);
  if (Abs(D)>=1e21) or (Abs(D)<1e-6) then
  begin
    Mantissa:=Copy(Digits,1,1);
    if Length(Digits)>1 then Mantissa:=Mantissa+'.'+Copy(Digits,2,MaxInt);
    if E>=0 then Result:=Mantissa+'e+'+IntToStr(E) else Result:=Mantissa+'e'+IntToStr(E);
  end
  else if E>=0 then
  begin
    while Length(Digits)<E+1 do Digits:=Digits+'0';
    Result:=Copy(Digits,1,E+1);
    if Length(Digits)>E+1 then Result:=Result+'.'+Copy(Digits,E+2,MaxInt);
  end
  else Result:='0.'+StringOfChar('0',-E-1)+Digits;
  if Neg then Result:='-'+Result;
end;

function LifecycleValue(Value:TJSONData;const Key:string):string;
var Keys:TStringList;I:Integer;Obj:TJSONObject;
begin
  if Value=nil then Exit('{"$undefined":true}');
  case Value.JSONType of
    jtNull,jtBoolean: Result:=Value.AsJSON;
    jtNumber: Result:=JsNumber(Value);
    jtArray:
    begin
      Result:='[';
      for I:=0 to Value.Count-1 do
      begin
        if I<>0 then Result:=Result+',';
        Result:=Result+LifecycleValue(Value.Items[I],'');
      end;
      Result:=Result+']';
    end;
    jtString:
      if (Key='createdAt') or (Key='deletedAt') then
        Result:='{"$date":'+JsonString(Value.AsString)+'}'
      else Result:=JsonString(Value.AsString);
    jtObject:
    begin
      Obj:=TJSONObject(Value);
      Keys:=TStringList.Create;
      try
        Keys.CaseSensitive:=True;Keys.Sorted:=True;
        for I:=0 to Obj.Count-1 do Keys.Add(Obj.Names[I]);
        Result:='{';
        for I:=0 to Keys.Count-1 do
        begin
          if I<>0 then Result:=Result+',';
          Result:=Result+JsonString(Keys[I])+':'+LifecycleValue(Obj.Find(Keys[I]),Keys[I]);
        end;
        Result:=Result+'}';
      finally Keys.Free;end;
    end;
    else raise Exception.Create('Unsupported list lifecycle value');
  end;
end;

function ListLifecycleHash(Row:TJSONObject):string;
var I:Integer;Body:string;
begin
  Body:='{';
  for I:=Low(ProtectedKeys) to High(ProtectedKeys) do
  begin
    if I<>Low(ProtectedKeys) then Body:=Body+',';
    Body:=Body+JsonString(ProtectedKeys[I])+':'+LifecycleValue(Row.Find(ProtectedKeys[I]),ProtectedKeys[I]);
  end;
  Result:=Sha256Hex(Body+'}');
end;

function CanonicalHistoryValue(Value:TJSONData):string;
begin
  Result:=LifecycleValue(Value,'');
end;

function HistoryRowHash(Row:TJSONObject):string;
begin
  Result:=ListLifecycleHash(Row);
end;

function ListReservationHash(Row:TJSONObject):string;
begin
  Result:=Sha256Hex(LifecycleValue(Row,''));
end;

function CompareJsonKeys(Keys:TStringList;Left,Right:Integer):Integer;
var A,B:UnicodeString;I:Integer;
begin
  A:=UTF8Decode(Keys[Left]);B:=UTF8Decode(Keys[Right]);
  for I:=1 to Length(A) do
  begin
    if I>Length(B) then Exit(1);
    if A[I]<>B[I] then Exit(Ord(A[I])-Ord(B[I]));
  end;
  Result:=Length(A)-Length(B);
end;

type TDecimal=record
  Digits:string;
  Exponent:Integer;
end;

function Decimal(Coefficient:QWord;Power:Integer):TDecimal;
const Base=1000000000;
// A binary64 midpoint has fewer than 810 decimal digits.
var Limbs:array[0..89] of LongWord;
  Exponent,DigitCount,Step,Chunk,Index:Integer;
  Factor,Multiplier,Carry:QWord;
  Digits:string;
begin
  Result.Exponent:=0;
  Factor:=2;
  Chunk:=29;
  if Power<0 then
  begin
    Result.Exponent:=Power;
    Factor:=5;
    Chunk:=12;
  end;
  DigitCount:=0;
  repeat
    Limbs[DigitCount]:=Coefficient mod Base;
    Inc(DigitCount);
    Coefficient:=Coefficient div Base;
  until Coefficient=0;
  Exponent:=Abs(Power);
  while Exponent>0 do
  begin
    Step:=Min(Exponent,Chunk);
    Dec(Exponent,Step);
    Multiplier:=1;
    for Index:=1 to Step do Multiplier:=Multiplier*Factor;
    Carry:=0;
    for Index:=0 to DigitCount-1 do
    begin
      Inc(Carry,QWord(Limbs[Index])*Multiplier);
      Limbs[Index]:=Carry mod Base;
      Carry:=Carry div Base;
    end;
    if Carry<>0 then
    begin
      Limbs[DigitCount]:=Carry;
      Inc(DigitCount);
    end;
  end;
  Result.Digits:=UIntToStr(Limbs[DigitCount-1]);
  for Index:=DigitCount-2 downto 0 do
  begin
    Digits:=UIntToStr(Limbs[Index]);
    Result.Digits:=Result.Digits+StringOfChar('0',9-Length(Digits))+Digits;
  end;
end;

function Compare(const A,B:TDecimal):Integer;
var Index:Integer;Left,Right:Char;
begin
  Result:=Length(A.Digits)+A.Exponent-Length(B.Digits)-B.Exponent;
  if Result<>0 then Exit;
  for Index:=1 to Max(Length(A.Digits),Length(B.Digits)) do
  begin
    Left:='0';Right:='0';
    if Index<=Length(A.Digits) then Left:=A.Digits[Index];
    if Index<=Length(B.Digits) then Right:=B.Digits[Index];
    if Left<>Right then Exit(Ord(Left)-Ord(Right));
  end;
end;

// Render the correctly rounded binary64 from its SJSON decimal token.
function CanonicalDouble(Value:Double;Literal:string):string;
var Bits,Significand,Prefix:QWord;BinaryExponent,StoredExponent,LengthLimit,I,Position,Attempts:Integer;
  Exact,Lower,Upper,Candidate,Input:TDecimal;Even,Negative,RoundUp:Boolean;Digits:string;

  procedure ReadLiteral;
  var Index,Point:Integer;
  begin
    if Literal[1]='-' then Delete(Literal,1,1);
    Index:=Pos('e',LowerCase(Literal));
    Input.Exponent:=0;
    if Index>0 then
    begin
      Input.Exponent:=StrToInt(Copy(Literal,Index+1,MaxInt));
      SetLength(Literal,Index-1);
    end;
    Point:=Pos('.',Literal);
    if Point>0 then
    begin
      Dec(Input.Exponent,Length(Literal)-Point);
      Delete(Literal,Point,1);
    end;
    Index:=1;
    while (Index<Length(Literal)) and (Literal[Index]='0') do Inc(Index);
    Input.Digits:=Copy(Literal,Index,MaxInt);
  end;

  procedure DecodeBounds;
  begin
    StoredExponent:=(Bits shr 52) and $7ff;
    Significand:=Bits and QWord($fffffffffffff);
    if StoredExponent=$7ff then raise Exception.Create('Invalid history reservation number');
    if StoredExponent=0 then BinaryExponent:=-1074
    else
    begin
      Significand:=Significand or QWord($10000000000000);
      BinaryExponent:=StoredExponent-1075;
    end;
    Even:=not Odd(Significand);
    Upper:=Decimal(2*Significand+1,BinaryExponent-1);
    if Significand=0 then Lower:=Upper
    else if (StoredExponent>1) and (Significand=QWord($10000000000000)) then
      Lower:=Decimal(4*Significand-1,BinaryExponent-2)
    else Lower:=Decimal(2*Significand-1,BinaryExponent-1);
  end;

  function Fits(Coefficient:QWord;Exponent:Integer):Boolean;
  var LowSide,HighSide:Integer;
  begin
    Candidate.Digits:=UIntToStr(Coefficient);
    Candidate.Exponent:=Exponent;
    LowSide:=Compare(Candidate,Lower);
    HighSide:=Compare(Candidate,Upper);
    Result:=((LowSide>0) or ((LowSide=0) and Even)) and
      ((HighSide<0) or ((HighSide=0) and Even));
  end;

begin
  Negative:=Literal[1]='-';
  ReadLiteral;
  if Input.Digits='0' then Exit('0');
  Move(Value,Bits,SizeOf(Bits));
  Bits:=Bits and QWord($7fffffffffffffff);
  // Some FPC targets parse decimal JSON through an intermediate rounding.
  // Check the original token against exact midpoints before formatting.
  for Attempts:=0 to 16 do
  begin
    DecodeBounds;
    Position:=Compare(Input,Upper);
    if (Position>0) or ((Position=0) and not Even) then Inc(Bits)
    else
    begin
      if Significand=0 then Exit('0');
      Position:=Compare(Input,Lower);
      if (Position<0) or ((Position=0) and not Even) then Dec(Bits)
      else Break;
    end;
    if Attempts=16 then raise Exception.Create('Cannot round history reservation number');
  end;
  Exact:=Decimal(Significand,BinaryExponent);
  LengthLimit:=Min(17,Length(Exact.Digits));
  Prefix:=0;
  for I:=1 to LengthLimit do
  begin
    Prefix:=Prefix*10+Ord(Exact.Digits[I])-Ord('0');
    Position:=Length(Exact.Digits)-I;
    if Position=0 then
    begin
      Fits(Prefix,Exact.Exponent);
      Break;
    end;
    RoundUp:=(Exact.Digits[I+1]>'5') or ((Exact.Digits[I+1]='5') and
      (Odd(Prefix) or (TrimRightSet(Copy(Exact.Digits,I+2,MaxInt),['0'])<>'')));
    if Fits(Prefix+Ord(RoundUp),Exact.Exponent+Position) or
      Fits(Prefix+Ord(not RoundUp),Exact.Exponent+Position) then Break;
    if I=LengthLimit then raise Exception.Create('Cannot format history reservation number');
  end;
  Digits:=TrimRightSet(Candidate.Digits,['0']);
  Position:=Length(Candidate.Digits)+Candidate.Exponent;
  if (Position>0) and (Position<=21) then
  begin
    if Position>=Length(Digits) then Result:=Digits+StringOfChar('0',Position-Length(Digits))
    else Result:=Copy(Digits,1,Position)+'.'+Copy(Digits,Position+1,MaxInt);
  end
  else if (Position<=0) and (Position> -6) then
    Result:='0.'+StringOfChar('0',-Position)+Digits
  else
  begin
    Result:=Digits[1];
    if Length(Digits)>1 then Result:=Result+'.'+Copy(Digits,2,MaxInt);
    Result:=Result+'e';
    if Position>0 then Result:=Result+'+';
    Result:=Result+IntToStr(Position-1);
  end;
  if Negative then Result:='-'+Result;
end;

function ReservationValue(Value,Schema:TJSONData):string;forward;

function ReservationObject(Obj,Props:TJSONObject;Other:TJSONObject=nil):string;
var Keys:TStringList;I:Integer;Key:string;
begin
  Keys:=TStringList.Create;
  try
    if Props<>nil then
      for I:=0 to Props.Count-1 do Keys.Add(Props.Names[I]);
    if Other<>nil then
      for I:=0 to Other.Count-1 do
      begin
        Key:=Other.Names[I];
        // WeKan uses JavaScript's in operator against a normal object.
        if (Obj.Find(Key)=nil) and not MatchStr(Key,[
          '__proto__','constructor','hasOwnProperty','isPrototypeOf','propertyIsEnumerable',
          'toLocaleString','toString','valueOf','__defineGetter__','__defineSetter__',
          '__lookupGetter__','__lookupSetter__']) then Keys.Add(Key);
      end;
    Keys.CustomSort(@CompareJsonKeys);
    Result:='{';
    for I:=0 to Keys.Count-1 do
    begin
      if I<>0 then Result:=Result+',';
      Key:=Keys[I];
      Result:=Result+JsonString(Key)+':';
      if Obj.Find(Key)=nil then Result:=Result+'{"$undefined":true}'
      else Result:=Result+ReservationValue(Obj.Find(Key),Props.Find(Key));
    end;
    Result:=Result+'}';
  finally Keys.Free;end;
end;

// These are the enumerable properties of the BSON values returned by
// WeKan's Mongo driver with default promotions (bson 7.3.3).
function CanonicalBsonInteger(Bits:QWord;Unsigned:Boolean):string;
var LowBits,HighBits:LongWord;LowValue,HighValue:LongInt;
begin
  LowBits:=LongWord(Bits and $ffffffff);
  HighBits:=LongWord(Bits shr 32);
  Move(LowBits,LowValue,SizeOf(LowValue));
  Move(HighBits,HighValue,SizeOf(HighValue));
  Result:='{"high":'+IntToStr(HighValue)+',"low":'+IntToStr(LowValue)+',"unsigned":';
  if Unsigned then Result:=Result+'true}' else Result:=Result+'false}';
end;

function CanonicalBinary(const Encoded:string;Subtype:Integer):string;
var Bytes:string;Output:TStringStream;

  procedure WriteByte(Index:Integer);
  begin
    if Index<>0 then Output.WriteString(',');
    Output.WriteString('"'+IntToStr(Index)+'":'+IntToStr(Ord(Bytes[Index+1])));
  end;

  procedure WritePrefix(Index:Integer);
  var Digit:Integer;
  begin
    if Index>=Length(Bytes) then Exit;
    WriteByte(Index);
    for Digit:=0 to 9 do WritePrefix(Index*10+Digit);
  end;

var Digit:Integer;
begin
  Bytes:=DecodeStringBase64(Encoded,True);
  Output:=TStringStream.Create('{"buffer":{');
  try
    Output.Position:=Output.Size;
    if Length(Bytes)>0 then WriteByte(0);
    for Digit:=1 to 9 do WritePrefix(Digit);
    Output.WriteString('},"position":'+IntToStr(Length(Bytes))+',"sub_type":'+IntToStr(Subtype)+'}');
    Result:=Output.DataString;
  finally Output.Free;end;
end;

function ReservationValue(Value,Schema:TJSONData):string;
var Kind:string;Items,Date:TJSONData;Number:Int64;Bits:QWord;I:Integer;
begin
  if Value=nil then Exit('{"$undefined":true}');
  Kind:=TJSONObject(Schema).Get('t','');
  case Kind of
    'null','bool':Result:=Value.AsJSON;
    'string':Result:=JsonString(Value.AsString);
    'date':
      begin
        Date:=JsonDate(Value.AsInt64);
        try
          if Date.JSONType<>jtString then raise Exception.Create('Invalid history reservation date');
          Result:='{"$date":'+JsonString(Date.AsString)+'}';
        finally Date.Free;end;
      end;
    'double':
      begin
        if Value.JSONType<>jtNumber then raise Exception.Create('Invalid history reservation number');
        Result:=CanonicalDouble(Value.AsFloat,Value.AsJSON);
      end;
    'int','long':
      begin
        Number:=StrToInt64(Value.AsJSON);
        if (Number>= -9007199254740992) and (Number<=9007199254740992) then
          Result:=IntToStr(Number)
        else
        begin
          Move(Number,Bits,SizeOf(Bits));
          Result:=CanonicalBsonInteger(Bits,False);
        end;
      end;
    'timestamp':Result:=CanonicalBsonInteger(StrToQWord(Value.AsJSON),True);
    'objectId':
      begin
        Result:='{';
        for I:=0 to 3 do
        begin
          if I<>0 then Result:=Result+',';
          Result:=Result+'"i'+IntToStr(I)+'":'+IntToStr(StrToInt('$'+Copy(Value.AsString,1+I*6,6)));
        end;
        Result:=Result+'}';
      end;
    'binData':Result:=CanonicalBinary(Value.AsString,TJSONObject(Schema).Get('s',0));
    // WeKan's EJSON copy hashes the pattern and options, but the default
    // Mongo read exposes a RegExp with no enumerable properties. A digest
    // of that read cannot verify either the stored pattern or its options.
    'regex':raise Exception.Create('Cannot verify history reservation regular expression');
    'object':
      Result:=ReservationObject(TJSONObject(Value),TJSONObject(TJSONObject(Schema).Objects['$s'].Find('p')));
    'array':
      begin
        Items:=TJSONObject(Schema).Arrays['i'];
        Result:='[';
        for I:=0 to Value.Count-1 do
        begin
          if I<>0 then Result:=Result+',';
          Result:=Result+ReservationValue(Value.Items[I],Items.Items[I]);
        end;
        Result:=Result+']';
      end;
    else raise Exception.Create('Unsupported history reservation value');
  end;
end;

procedure ReservationHashes(const Document:string;out RowHash,PendingHash:string;
  const LegacyHash,ExpectedPendingHash:string);
const CleanedFields:array[0..7] of string=('boardId','swimlaneId','listId','cardId',
  'group','batchId','restoredFromId','restoredByUserId');
var Row,Props:TJSONObject;Value,BeforeValue,AfterValue:TJSONData;
  Parts,LegacyParts:array[Low(ProtectedKeys)..High(ProtectedKeys)] of string;
  CleanedBits:array[Low(ProtectedKeys)..High(ProtectedKeys)] of Integer;
  I,Count,Mask:Integer;Key:string;HasLegacyContent:Boolean;

  function Hash(Mask:Integer;LegacyContent:Boolean):string;
  var J:Integer;Body:string;
  begin
    Body:='{';
    for J:=Low(ProtectedKeys) to High(ProtectedKeys) do
    begin
      if J<>Low(ProtectedKeys) then Body:=Body+',';
      Body:=Body+JsonString(ProtectedKeys[J])+':';
      if (Mask and CleanedBits[J])<>0 then Body:=Body+'""'
      else if LegacyContent then Body:=Body+LegacyParts[J]
      else Body:=Body+Parts[J];
    end;
    Result:=Sha256Hex(Body+'}');
  end;

  function PropertySchema(const Name:string):TJSONObject;
  begin
    Result:=TJSONObject(TJSONObject(Props.Find(Name)).Objects['$s'].Find('p'));
  end;

begin
  // Validate the complete FerretDB value and its corresponding BSON metadata.
  PlainDocument(Document);
  Row:=ExactObject(Document);
  try
    Props:=Row.Objects['$s'].Objects['p'];
    PendingHash:=Sha256Hex(ReservationObject(Row,Props));
    RowHash:='';
    if (ExpectedPendingHash<>'') and (PendingHash<>ExpectedPendingHash) then Exit;
    Count:=0;
    for I:=Low(ProtectedKeys) to High(ProtectedKeys) do
    begin
      Key:=ProtectedKeys[I];
      Value:=Row.Find(Key);
      Parts[I]:=ReservationValue(Value,Props.Find(Key));
      CleanedBits[I]:=0;
      if ((Value=nil) or (Value.JSONType=jtNull)) and MatchStr(Key,CleanedFields) then
      begin
        CleanedBits[I]:=1 shl Count;
        Inc(Count);
      end;
    end;
    RowHash:=Hash(0,False);
    if (LegacyHash='') or (RowHash=LegacyHash) then Exit;
    BeforeValue:=Row.Find('previousContent');
    AfterValue:=Row.Find('newContent');
    HasLegacyContent:=False;
    if (BeforeValue is TJSONObject) and (AfterValue is TJSONObject) then
    begin
      LegacyParts:=Parts;
      for I:=Low(ProtectedKeys) to High(ProtectedKeys) do
      begin
        Key:=ProtectedKeys[I];
        if Key='previousContent' then
          LegacyParts[I]:=ReservationObject(TJSONObject(BeforeValue),PropertySchema(Key),TJSONObject(AfterValue))
        else if Key='newContent' then
          LegacyParts[I]:=ReservationObject(TJSONObject(AfterValue),PropertySchema(Key),TJSONObject(BeforeValue));
        if Parts[I]<>LegacyParts[I] then HasLegacyContent:=True;
      end;
    end;
    for Mask:=0 to (1 shl Count)-1 do
      if ((Mask<>0) and (Hash(Mask,False)=LegacyHash)) or
        (HasLegacyContent and (Hash(Mask,True)=LegacyHash)) then
      begin
        RowHash:=LegacyHash;
        Exit;
      end;
  finally Row.Free;end;
end;

function HistoryBoardKey(const Prefix,BoardId:string):string;
begin
  Result:=Sha256Hex('['+JsonString(Prefix)+','+JsonString(BoardId)+']');
end;

end.
