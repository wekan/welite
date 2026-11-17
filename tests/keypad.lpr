program keypad;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wlmove,wlauth;
var P:TStringList;S:TWLSession;Body,Before:string;
procedure Check(Ok:Boolean;const Name:string);
begin if not Ok then raise Exception.Create(Name);end;
procedure Reject(const First,Second:string);
begin
  P.Clear;P.Add(First);if Second<>'' then P.Add(Second);Before:=P.Text;
  Check(not NormalizeMoveSubmit(P),'Accepted conflict: '+Before);
  Check(P.Text=Before,'Changed invalid input');
end;
begin
  P:=TStringList.Create;
  try
    Check(not NormalizeMoveSubmit(nil),'Accepted nil');
    Check(NormalizeMoveSubmit(P),'Rejected empty');
    P.Add('move_right=left');Check(NormalizeMoveSubmit(P),'Rejected native arrow');
    Check(P.Values['dir']='right','Used caption as direction');
    P.Clear;P.Add('move_left=');Check(NormalizeMoveSubmit(P),'Rejected empty caption');
    Check(P.Values['dir']='left','Wrong empty-caption direction');
    P.Clear;P.Add('dir=drop');Before:=P.Text;
    Check(NormalizeMoveSubmit(P) and (P.Text=Before),'Changed legacy drag');
    P.Clear;P.Add('action=export');Before:=P.Text;
    Check(NormalizeMoveSubmit(P) and (P.Text=Before),'Changed legacy action');
    Reject('move_left=x','move_right=x');Reject('move_up=x','move_up=y');
    Reject('move_down=x','dir=drop');Reject('move_left=x','action=export');
    Reject('move_left=x','action=');Reject('move_far=x','');
    Body:=MoveKeypad(Default(TWLSession),0,0,0);
    Check(Pos('name="move_left" value="&lt;" dir="ltr"',Body)>0,'Missing left arrow');
    Check(Pos('name="move_right" value="&gt;" dir="ltr"',Body)>0,'Missing right arrow');
    Check(Pos('name="move_up" value="^" dir="ltr"',Body)>0,'Missing up arrow');
    Check(Pos('name="move_down" value="v" dir="ltr"',Body)>0,'Missing down arrow');
    Check(Pos('name="move_left"',Body)<Pos('name="move_down"',Body),'Wrong left/down order');
    Check(Pos('name="move_down"',Body)<Pos('name="move_right"',Body),'Wrong down/right order');
    Check(Pos('name="dir"',Body)=0,'Emitted caption-bound direction');
    Writeln('PASS: caption-independent ASCII arrows, physical order, legacy commands and atomic ambiguous-submit refusal');
  finally P.Free;end;
end.
