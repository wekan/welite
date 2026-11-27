program keypad;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wlmove,wlauth,wlcolors;
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
    P.Clear;P.Add('action_export=delete');Check(NormalizeMoveSubmit(P),'Rejected native export');
    Check(P.Values['action']='export','Used action caption as command');
    Reject('action_edit=x','action_clone=y');Reject('action_delete=x','action_delete=y');
    Reject('action_clear=x','move_right=y');Reject('action_export=x','dir=left');
    Reject('action_clone=x','action=clear');Reject('action_unknown=x','');
    P.Clear;P.Add('action_save=delete');Check(NormalizeMoveSubmit(P),'Rejected native save');
    Check(P.Values['action']='save','Used save caption as command');
    Reject('action_save=x','action=save');Reject('action_save=x','move_right=x');
    P.Clear;P.Add('action_confirm-delete=clear');Check(NormalizeMoveSubmit(P),'Rejected native confirmation');
    Check(P.Values['action']='confirm-delete','Used confirmation caption as command');
    Reject('action_confirm-delete=x','action=confirm-delete');Reject('action_confirm-delete=x','move_up=x');
    Reject('action_confirm-delete=x','action_confirm-delete=y');
    Check(Pos('(hex, e.g. ffee22)',RenderColorInput('color','red','hex'))>0,'Changed default color hint');
    Check(Pos('(hex,',RenderColorInput('color','red','hex',False))=0,'Could not hide English color hint');
    Body:=MoveKeypad(Default(TWLSession),0,0,0);
    Check(Pos('name="move_left" value="&lt;" dir="ltr"',Body)>0,'Missing left arrow');
    Check(Pos('name="move_right" value="&gt;" dir="ltr"',Body)>0,'Missing right arrow');
    Check(Pos('name="move_up" value="^" dir="ltr"',Body)>0,'Missing up arrow');
    Check(Pos('name="move_down" value="v" dir="ltr"',Body)>0,'Missing down arrow');
    Check(Pos('<table class="board-joystick" dir="ltr"',Body)>0,'Missing physical table direction');
    Check(Pos('name="move_up"',Body)<Pos('name="move_left"',Body),'Missing upper row');
    Check(Pos('name="move_left"',Body)<Pos('name="move_right"',Body),'Reversed horizontal controls');
    Check(Pos('name="move_right"',Body)<Pos('name="move_down"',Body),'Missing lower row');
    Check(Pos('name="dir"',Body)=0,'Emitted caption-bound direction');
    Check(Pos('name="action_edit"',Body)>0,'Missing native edit');
    Check(Pos('name="action_clone"',Body)>0,'Missing native clone');
    Check(Pos('name="action"',Body)=0,'Emitted caption-bound action');
    Writeln('PASS: caption-independent ASCII arrows, physical order, legacy commands and atomic ambiguous-submit refusal');
  finally P.Free;end;
end.
