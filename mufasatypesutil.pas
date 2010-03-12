unit mufasatypesutil;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,mufasatypes;

function ConvArr(Arr: array of TPoint): TPointArray; overload;
function ConvArr(Arr: array of TPointArray): T2DPointArray; overload;
function ConvArr(Arr: array of Integer): TIntegerArray; overload;
function ConvArr(Arr: array of String): TStringArray; overload;

function ConvTPAArr(Arr: array of TPoint): TPointArray; overload;


implementation

function ConvArr(Arr: array of TPoint): TPointArray; overload;
var
  Len : Integer;
begin;
  Len := Length(Arr);
  SetLength(Result, Len);
  Move(Arr[Low(Arr)], Result[0], Len*SizeOf(TPoint));
end;

function ConvTPAArr(Arr: array of TPoint): TPointArray; overload;
var
  Len : Integer;
begin;
  Len := Length(Arr);
  SetLength(Result, Len);
  Move(Arr[Low(Arr)], Result[0], Len*SizeOf(TPoint));
end;


function ConvArr(Arr: array of TPointArray): T2DPointArray; overload;
var
  Len,Len2 : Integer;
  i : integer;
begin;
  Len := Length(Arr);
  SetLength(Result, Len);
  for i := Len - 1 downto 0 do
  begin
    Len2 := Length(Arr[i]);
    SetLength(result[i],len2);
    Move(Arr[i][0],Result[i][0],Len2*SizeOf(TPoint));
  end;
end;

function ConvArr(Arr: array of Integer): TIntegerArray; overload;
var
  Len : Integer;
begin;
  Len := Length(Arr);
  SetLength(Result, Len);
  Move(Arr[Low(Arr)], Result[0], Len*SizeOf(Integer));
end;

function ConvArr(Arr: array of String): TStringArray; overload;
var
  Len : Integer;
  I : integer;
begin;
  Len := Length(Arr);
  SetLength(Result, Len);
  for i := 0 to Len - 1 do
    result[i] := arr[i];
end;

end.

