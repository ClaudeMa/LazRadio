unit RadioModule;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, UComplex;

const
  // ParamH: TRadioDataStream
  // ParamL: index of data
  // Note: call TRadioDataStream.Release after processed
  RM_DATA            = 0;
  RM_DATA_DONE       = 1;

  // ParamH: Frequency   (0)    ParamL: in Hz
  // ParamH: Sample rate (1)    ParamL: in samples per second
  // ParamH: Bandwidth   (2)    ParamL: in Hz
  RM_SET_FEATURE     = 2;

  // ParamH: RUN   (0)    ParamL: ignore
  // ParamH: PAUSE (1)    ParamL: ignore
  // ParamH: RESET (2)    ParamL: ignore
  RM_CONTROL         = 3;

  // ParamH: timer id    ParamL: timer interval
  RM_TIMER           = 4;

  // ParamH: error   (0)    ParamL: code
  // ParamH: warning (1)    ParamL: code
  // ParamH: info    (2)    ParamL: code
  // ParamH: debug   (3)    ParamL: code
  RM_REPORT          = 5;

  RM_USER            = 10000;

type

  TDataStreamRec = record
    Counter: Integer;
    Allocated: Boolean;
    Data: array of Complex;
  end;

  TRadioModule = class;

  { TRadioDataStream }

  TRadioDataStream = class
  private
    FName: string;
    FBlockSize: Integer;
    FFreeFlag: Boolean;
    FBuffers: array [0..1] of TDataStreamRec;
    FModule: TRadioModule;
    function GetBuffer(const Index: Integer): PComplex;
    function GetBufferSize(const Index: Integer): Integer;
  public
    constructor Create(Module: TRadioModule; const AName: string; const BlockSize: Integer);
    destructor Destroy; override;
    procedure SafeFree;

    procedure Lock;
    procedure Unlock;

    function Alloc(out Index: Integer): PComplex;
    procedure Broadcast(const Index: Integer; Listeners: TList);
    procedure Release(const Index: Integer); // Listeners call this to release buffer

    property Name: string read FName;
    property Buffer[const Index: Integer]: PComplex read GetBuffer;
    property BufferSize[const Index: Integer]: Integer read GetBufferSize;
  end;

  { TStreamRegulator }

  TStreamRegulator = class
  public
    constructor Create(const Size: Integer);
  end;

  TRadioMessageId      = 0..31;
  TRadioMessageIdSet   = Cardinal;

  { TRadioMessage }

  TRadioMessage = record
    Sender: TRadioModule;
    Id: Integer;
    ParamH: PtrUInt;
    ParamL: PtrUInt;
  end;

  PRadioMessageNode = ^TRadioMessageNode;
  TRadioMessageNode = record
    Next: PRadioMessageNode;
    Msg: TRadioMessage;
  end;

  TRadioMessageQueue = class;
  TRadioRunQueue = class;
  PRadioThreadNode = ^TRadioThreadNode;

  { TRadioThread }

  TRadioThread = class(TThread)
  private
    FJob: TRadioMessageQueue;
    FNode: PRadioThreadNode;
    FRunQueue: TRadioRunQueue;
    FJobScheduled: PRTLEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property Job: TRadioMessageQueue read FJob write FJob;
    property Node: PRadioThreadNode read FNode write FNode;
  end;

  TRadioThreadNode = record
    Next: PRadioThreadNode;
    Thread: TRadioThread;
  end;

  PMessageQueueNode = ^TMessageQueueNode;
  TMessageQueueNode = record
    Next: PMessageQueueNode;
    Queue: TRadioMessageQueue;
  end;

  { TRadioRunQueue }

  TRadioRunQueue = class
  private
    FFirstJob: TMessageQueueNode;
    FIdleNode: TRadioThreadNode;
  private
    procedure Schedule;
    procedure Lock;
    procedure UnLock;
    procedure WorkerIdle(Worker: TRadioThread);
  public
    constructor Create(const SMP: Integer = 4);
    procedure Request(Job: TRadioMessageQueue);
  end;

  TProcessingType = (ptBackground, ptForeground);

  { TRadioMessageQueue }

  TRadioMessageQueue = class
  private
    FExecuting: Boolean;
    FFirstExecMsg: TRadioMessageNode;
    FLastExecMsg: PRadioMessageNode;
    FFirstMsg: TRadioMessageNode;
    FLastMsg: PRadioMessageNode;
    FMessageFilter: TRadioMessageIdSet;
    function GetNotEmpty: Boolean;
    procedure SetMessageFilter(AValue: TRadioMessageIdSet);
    procedure RequestSchudule;
  protected
    procedure MessageExceute;      // execute one message in a single call
    procedure ProccessMessage(const Msg: TRadioMessage; var Ret: PtrInt); virtual; abstract;
  public
    procedure Lock;
    procedure UnLock;

    procedure StoreMessage(const Msg: TRadioMessage);
    procedure MessageQueueReset;

    property NotEmpty: Boolean read GetNotEmpty;
    property MessageFilter: TRadioMessageIdSet read FMessageFilter write SetMessageFilter;
    property Executing: Boolean read FExecuting;
  end;

  { TRadioModule }

  TRadioModule = class(TRadioMessageQueue)
  private
    FDataListeners: TList;
    FDefOutput: TRadioDataStream;
    FFeatureListeners: TList;
    FName: string;
    FRunning: Boolean;
    FRunQueue: TRadioRunQueue;
    procedure SetName(AValue: string);
  protected
    procedure SetRunning(AValue: Boolean); virtual;

    procedure ProccessMessage(const Msg: TRadioMessage; var Ret: Integer); override;

    procedure RMControl(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMData(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMSetFeature(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMReport(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMTimer(const Msg: TRadioMessage; var Ret: Integer); virtual;

    procedure DoReset; virtual;
  public
    constructor Create(RunQueue: TRadioRunQueue); virtual;
    destructor Destroy; override;

    procedure PostMessage(const Id: Integer; const ParamH, ParamL: PtrInt);
    procedure PostMessage(const Msg: TRadioMessage); virtual;

    procedure Configure; virtual;
    procedure Draw(ACanvas: TCanvas; ARect: TRect); virtual;

    procedure AddDataListener(Listener: TRadioModule);
    procedure AddFeatureListener(Listener: TRadioModule);
    procedure RemoveDataListener(Listener: TRadioModule);
    procedure RemoveFeatureListener(Listener: TRadioModule);
    procedure ClearDataListeners;
    procedure ClearFeatureListeners;

    procedure ReceiveData(const P: PComplex; const Len: Integer); virtual;

    property DefOutput: TRadioDataStream read FDefOutput;
    property Running: Boolean read FRunning write SetRunning;
    property Name: string read FName write SetName;
  end;

  TRadioModuleClass = class of TRadioModule;

  { TGenericRadioThread }

  TGenericRadioThread = class(TThread)
  private
    FParam: Pointer;
    FRemoteRun: TNotifyEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    property RemoteRun: TNotifyEvent read FRemoteRun write FRemoteRun;
    property Param: Pointer read FParam write FParam;
  end;

  { TBackgroundRadioModule }

  TBackgroundRadioModule = class(TRadioModule)
  private
    FThread: TGenericRadioThread;
  protected
    procedure ThreadFun(Thread: TGenericRadioThread); virtual;
    procedure SetRunning(AValue: Boolean); override;
  public
    constructor Create(RunQueue: TRadioRunQueue); override;
    destructor Destroy; override;
  end;

// I don't like to creae too many CriticalSections
procedure RadioGlobalLock;
procedure RadioGlobalUnlock;

procedure RadioPostMessage(const M: TRadioMessage; Receiver: TRadioModule);

implementation

var
  RadioGlobalCS: TRTLCriticalSection;

procedure RadioGlobalLock;
begin
  EnterCriticalsection(RadioGlobalCS);
end;

procedure RadioGlobalUnlock;
begin
  LeaveCriticalsection(RadioGlobalCS);
end;

procedure RadioPostMessage(const M: TRadioMessage; Receiver: TRadioModule);
begin
  //
end;

{ TRadioMessageQueue }

function TRadioMessageQueue.GetNotEmpty: Boolean;
begin
  Result := Assigned(FFirstExecMsg.Next);
end;

procedure TRadioMessageQueue.SetMessageFilter(AValue: TRadioMessageIdSet);
var
  P: PRadioMessageNode;
  T: PRadioMessageNode;
  F: Boolean = False;
begin
  if FMessageFilter = AValue then Exit;
  FMessageFilter := AValue;
  P := @FFirstMsg;
  if not Assigned(P^.Next) then Exit;

  Lock;
  while Assigned(P^.Next) do
  begin
    T := P^.Next;
    if (FMessageFilter and (1 shl T^.Msg.Id)) > 0 then
    begin
      P^.Next := T^.Next;
      FLastExecMsg^.Next := T;
      T^.Next := nil;
      FLastExecMsg := T;
      F := True;
      if not Assigned(P^.Next) then
      begin
        FLastMsg := P;
        Break;
      end;
    end
    else
      P := T;
  end;
  UnLock;

  if F then RequestSchudule;
end;

procedure TRadioMessageQueue.RequestSchudule;
begin

end;

procedure TRadioMessageQueue.MessageExceute;
var
  Msg: TRadioMessage;
  Ret: Integer = 0;
  P: PRadioMessageNode;
begin
  if not Assigned(FFirstExecMsg.Next) then Exit;
  Lock;
  P := FFirstExecMsg.Next;
  Msg := P^.Msg;
  FFirstExecMsg.Next := P^.Next;
  if not Assigned(FFirstExecMsg.Next) then
    FLastExecMsg := @FFirstExecMsg;
  UnLock;
  Dispose(P);
  ProccessMessage(Msg, Ret);
end;

procedure TRadioMessageQueue.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioMessageQueue.UnLock;
begin
  RadioGlobalUnlock;
end;

procedure TRadioMessageQueue.StoreMessage(const Msg: TRadioMessage);
var
  P: PRadioMessageNode;
begin
  New(P);
  P^.Msg := Msg;
  P^.Next := nil;
  if (MessageFilter and (1 shl Msg.Id)) > 0 then
  begin
    Lock;
    FLastExecMsg^.Next := P;
    FLastExecMsg := P;
    UnLock;
    if not Executing then RequestSchudule;
  end
  else begin
    Lock;
    FLastMsg^.Next := P;
    FLastMsg := P;
    UnLock;
  end;
end;

procedure TRadioMessageQueue.MessageQueueReset;
  procedure FreeList(P: PRadioMessageNode);
  var
    T: PRadioMessageNode;
  begin
    while Assigned(P) do
    begin
      T := P^.Next;
      Dispose(P);
      P := T;
    end;
  end;

begin
  Lock;
  FreeList(FFirstMsg.Next);
  FreeList(FFirstExecMsg.Next);
  FFirstMsg.Next := nil;
  FLastMsg := @FFirstMsg;
  FFirstExecMsg.Next := nil;
  FLastExecMsg := @FFirstExecMsg;
  UnLock;
end;

{ TBackgroundRadioModule }

procedure TBackgroundRadioModule.ThreadFun(Thread: TGenericRadioThread);
begin

end;

procedure TBackgroundRadioModule.SetRunning(AValue: Boolean);
begin
  inherited;
  FThread.Suspended := not AValue;
end;

constructor TBackgroundRadioModule.Create(RunQueue: TRadioRunQueue);
begin
  inherited;
  FThread := TGenericRadioThread.Create;
  FThread.RemoteRun := TNotifyEvent(@ThreadFun);
end;

destructor TBackgroundRadioModule.Destroy;
begin
  inherited Destroy;
  FThread.Free;
end;

{ TGenericRadioThread }

procedure TGenericRadioThread.Execute;
begin
  while not Terminated do
    if Assigned(RemoteRun) then RemoteRun(Self);
end;

constructor TGenericRadioThread.Create;
begin
  inherited Create(True);
end;

{ TRadioRunQueue }

procedure TRadioRunQueue.Schedule;
var
  T: PRadioThreadNode;
  P: PMessageQueueNode;
begin
  if not Assigned(FFirstJob.Next) then Exit;
  if not Assigned(FIdleNode.Next) then Exit;
  Lock;
  T := FIdleNode.Next;
  FIdleNode.Next := T^.Next;
  P := FFirstJob.Next;
  FFirstJob.Next := P^.Next;
  UnLock;

  T^.Thread.Job := P^.Queue;
  Dispose(P);
  RTLEventSetEvent(T^.Thread.FJobScheduled);
end;

procedure TRadioRunQueue.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioRunQueue.UnLock;
begin
  RadioGlobalUnlock;
end;

procedure TRadioRunQueue.WorkerIdle(Worker: TRadioThread);
begin
  Lock;
  Worker.Node^.Next := FIdleNode.Next;
  FIdleNode.Next := Worker.Node;
  Unlock;
end;

constructor TRadioRunQueue.Create(const SMP: Integer);
var
  I: Integer;
  P: PRadioThreadNode;
begin
  for I := 1 to SMP do
  begin
    New(P);
    P^.Thread := TRadioThread.Create;
    P^.Thread.Node := P;
    P^.Thread.FRunQueue := Self;
    P^.Next := FIdleNode.Next;
    FIdleNode.Next := P;
  end;
end;

procedure TRadioRunQueue.Request(Job: TRadioMessageQueue);
var
  T: PRadioThreadNode;
  P: PMessageQueueNode;
begin
  if Assigned(FIdleNode.Next) then
  begin
    Lock;
    T := FIdleNode.Next;
    FIdleNode.Next := T^.Next;
    UnLock;

    T^.Thread.Job := Job;
    RTLEventSetEvent(T^.Thread.FJobScheduled);

    Exit;
  end;

  New(P);
  P^.Queue := Job;

  Lock;
  P^.Next := FFirstJob.Next;
  FFirstJob.Next := P;
  Unlock;

  Schedule;
end;

{ TRadioThread }

procedure TRadioThread.Execute;
begin
  while not Terminated do
  begin
    RTLEventWaitFor(FJobScheduled);
    RTLEventResetEvent(FJobScheduled);

    if not Assigned(FJob) then Break;
    while FJob.NotEmpty do FJob.MessageExceute;
    FJob := nil;
    FRunQueue.WorkerIdle(Self);
  end;
end;

constructor TRadioThread.Create;
begin
  FJobScheduled := RTLEventCreate;
  inherited Create(False);
end;

destructor TRadioThread.Destroy;
begin
  RTLEventDestroy(FJobScheduled);
  inherited Destroy;
end;

{ TStreamRegulator }

constructor TStreamRegulator.Create(const Size: Integer);
begin

end;

{ TRadioDataStream }

function TRadioDataStream.GetBuffer(const Index: Integer): PComplex;
begin
  Result := @FBuffers[Index].Data[0];
end;

function TRadioDataStream.GetBufferSize(const Index: Integer): Integer;
begin
  Result := FBlockSize;
end;

constructor TRadioDataStream.Create(Module: TRadioModule; const AName: string;
  const BlockSize: Integer);
begin
  FName := AName;
  FBlockSize := BlockSize;
  FModule := Module;
end;

destructor TRadioDataStream.Destroy;
begin
  inherited Destroy;
end;

procedure TRadioDataStream.SafeFree;
var
  I: Integer;
begin
  Lock;
  FFreeFlag := False;
  for I := Low(FBuffers) to High(FBuffers) do
  begin
    if FBuffers[I].Allocated then
    begin
      FFreeFlag := True;
      Break;
    end;
  end;
  if not FFreeFlag then Free;
  Unlock;
end;

procedure TRadioDataStream.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioDataStream.Unlock;
begin
  RadioGlobalUnlock;
end;

function TRadioDataStream.Alloc(out Index: Integer): PComplex;
var
  I: Integer;
begin
  Result := nil;

  Lock;
  for I := Low(FBuffers) to High(FBuffers) do
  begin
    if not FBuffers[I].Allocated then
    begin
      Result := @FBuffers[I].Data[0];
      FBuffers[I].Allocated := True;
      Index := I;
      Break;
    end;
  end;
  Unlock;
end;

procedure TRadioDataStream.Broadcast(const Index: Integer; Listeners: TList);
var
  M: TRadioMessage;
  P: Pointer;
begin
  Lock;
  FBuffers[Index].Counter := Listeners.Count;
  if FBuffers[Index].Counter < 1 then
    FBuffers[Index].Allocated := False;
  Unlock;

  with M do
  begin
    Id := RM_DATA;
    Sender := FModule;
    ParamH := PtrInt(Self);
    ParamL := Index;
  end;

  if FBuffers[Index].Allocated then
  begin
    for P in Listeners do
      TRadioModule(P).PostMessage(M);
  end
  else begin
    M.Id := RM_DATA_DONE;
    FModule.PostMessage(M);
  end;
end;

procedure TRadioDataStream.Release(const Index: Integer);
var
  M: TRadioMessage;
begin
  Lock;
  Dec(FBuffers[Index].Counter);
  if FBuffers[Index].Counter < 1 then
    FBuffers[Index].Allocated := False;
  Unlock;

  if not FBuffers[Index].Allocated then
  begin
    with M do
    begin
      Id := RM_DATA_DONE;
      Sender := FModule;
      ParamH := PtrInt(Self);
      ParamL := Index;
    end;
    FModule.PostMessage(M);
  end;
end;

{ TRadioModule }

procedure TRadioModule.SetName(AValue: string);
begin
  if FName = AValue then Exit;
  FName := AValue;
end;

procedure TRadioModule.SetRunning(AValue: Boolean);
begin
  if FRunning = AValue then Exit;
  FRunning := AValue;
end;

procedure TRadioModule.PostMessage(const Msg: TRadioMessage);
begin
  if (not Running) and (Msg.Id <> RM_CONTROL) then Exit;
  StoreMessage(Msg);
end;

procedure TRadioModule.ProccessMessage(const Msg: TRadioMessage;
  var Ret: Integer);
begin
  case Msg.Id of
    RM_Control: RMControl(Msg, Ret);
    RM_DATA     : RMData(Msg, Ret);
    RM_REPORT   : RMReport(Msg, Ret);
    RM_SET_FEATURE: RMSetFeature(Msg, Ret);
    RM_TIMER      : RMTimer(Msg, Ret);
  else
  end;
end;

procedure TRadioModule.RMControl(const Msg: TRadioMessage; var Ret: Integer);
begin
  case Msg.ParamH of
    0: Running := True;
    1: Running := False;
    2: DoReset;
  end;
end;

procedure TRadioModule.RMData(const Msg: TRadioMessage; var Ret: Integer);
var
  B: TRadioDataStream;
begin
  B := TRadioDataStream(Pointer(Msg.ParamH));
  ReceiveData(B.Buffer[Msg.ParamL], B.BufferSize[Msg.ParamL]);
  B.Release(Msg.ParamL);
end;

procedure TRadioModule.RMSetFeature(const Msg: TRadioMessage; var Ret: Integer);
begin

end;

procedure TRadioModule.RMReport(const Msg: TRadioMessage; var Ret: Integer);
begin

end;

procedure TRadioModule.RMTimer(const Msg: TRadioMessage; var Ret: Integer);
begin

end;

procedure TRadioModule.DoReset;
begin
  MessageQueueReset;
end;

constructor TRadioModule.Create(RunQueue: TRadioRunQueue);
begin
  inherited Create;
  FDataListeners := TList.Create;
  FFeatureListeners := TList.Create;
  FDefOutput := TRadioDataStream.Create(Self, 'output',1024);
  FRunQueue := RunQueue;
  FLastMsg := @FFirstMsg;
end;

destructor TRadioModule.Destroy;
begin
  // reset, then pause
  PostMessage(RM_CONTROL, 2, 0);
  PostMessage(RM_CONTROL, 1, 0);
  while Running do Sleep(10);
  FDefOutput.SafeFree;
  FDataListeners.Free;
  FFeatureListeners.Free;
  inherited Destroy;
end;

procedure TRadioModule.PostMessage(const Id: Integer; const ParamH,
  ParamL: PtrInt);
var
  M: TRadioMessage;
begin
  M.Id := Id;
  M.ParamH := ParamH;
  M.ParamL := ParamL;
  PostMessage(M);
end;

procedure TRadioModule.Configure;
begin

end;

procedure TRadioModule.Draw(ACanvas: TCanvas; ARect: TRect);
begin

end;

procedure TRadioModule.AddDataListener(Listener: TRadioModule);
begin
  with FDataListeners do
    if IndexOf(Listener) < 0 then Add(Listener);
end;

procedure TRadioModule.AddFeatureListener(Listener: TRadioModule);
begin
  with FFeatureListeners do
    if IndexOf(Listener) < 0 then Add(Listener);
end;

procedure TRadioModule.RemoveDataListener(Listener: TRadioModule);
begin
  FDataListeners.Remove(Listener);
end;

procedure TRadioModule.RemoveFeatureListener(Listener: TRadioModule);
begin
  FFeatureListeners.Remove(Listener);
end;

procedure TRadioModule.ClearDataListeners;
begin
  FDataListeners.Clear;
end;

procedure TRadioModule.ClearFeatureListeners;
begin
  FFeatureListeners.Clear;
end;

procedure TRadioModule.ReceiveData(const P: PComplex; const Len: Integer);
begin

end;

initialization

  InitCriticalSection(RadioGlobalCS);

finalization

  DoneCriticalsection(RadioGlobalCS);

end.
