{
	This file is part of the Mufasa Macro Library (MML)
	Copyright (c) 2009-2012 by Raymond van Venetië and Merlijn Wajer

    MML is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    MML is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with MML.  If not, see <http://www.gnu.org/licenses/>.

	See the file COPYING, included in this distribution,
	for details about the copyright.

    Fonts class for the Mufasa Macro Library
}

unit fontloader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,Graphics,bitmaps,
  ocrutil,lclintf; // contains the actual `loading'

{
  We will not give any access to actual indices.
}

type
  TMFont = class(TObject)
  public
    Name: String;
    Data: TOcrData;
    constructor Create;
    destructor Destroy; override;
    function Copy: TMFont;
  end;
  { TMFonts }

  TMFonts = class(TObject)
  private
    Fonts: TList;
    FPath: String;
    Client : TObject;
    function GetFontIndex(const Name: String): Integer;
    function GetFontByIndex(Index : integer): TMfont;
    procedure SetPath(const aPath: String);
    function GetPath: String;
  public
    constructor Create(Owner : TObject);
    destructor Destroy; override;
    function GetFont(const Name: String): TOcrData;
    function FreeFont(const Name: String): Boolean;
    function LoadFont(const Name: String; Shadow: Boolean): boolean;
    function LoadSystemFont(const SysFont : TFont; const FontName : string) : boolean;
    function Copy(Owner : TObject): TMFonts;
    function Count : integer;
    property Path : string read GetPath write SetPath;
    property Font[Index : integer]: TMfont read GetFontByIndex; default;
  end;

implementation

uses
  MufasaTypes, Client, strutils;


constructor TMFont.Create;
begin
  inherited;

  Name:='';
end;

destructor TMFont.Destroy;
begin
  Name:='';

  inherited;
end;

function TMFont.Copy: TMFont;
var
  i, l, ll:integer;
begin
  Result := TMFont.Create;
  Result.Name := Self.Name;
  Move(Self.Data.ascii[0], Result.Data.ascii[0], length(Self.Data.ascii) * SizeOf(TocrGlyphMetric));
  l := Length(Self.Data.Pos);
  SetLength(Result.Data.pos, l);
  for i := 0 to l - 1 do
  begin
    ll := length(Self.Data.Pos[i]);
    setlength(Result.Data.Pos[i], ll);
    Move(Self.Data.Pos[i][0], Result.Data.Pos[i][0], ll*SizeOf(Integer));
  end;

  SetLength(Result.Data.pos_adj,  length(Self.Data.pos_adj));
  Move(Self.Data.pos_adj[0], Result.Data.pos_adj[0], length(Self.Data.pos_adj) * SizeOf(real));

  l := Length(Self.Data.neg);
  SetLength(Result.Data.neg, l);
  for i := 0 to l - 1 do
  begin
    ll := length(Self.Data.neg[i]);
    setlength(Result.Data.neg[i], ll);
    Move(Self.Data.neg[i][0], Result.Data.neg[i][0], ll*SizeOf(Integer));
  end;

  SetLength(Result.Data.neg_adj,  length(Self.Data.neg_adj));
  Move(Self.Data.neg_adj[0], Result.Data.neg_adj[0], length(Self.Data.neg_adj) * SizeOf(real));

  SetLength(Result.Data.map,  length(Self.Data.map));
  Move(Self.Data.map[0], Result.Data.map[0], length(Self.Data.map) * SizeOf(char));

  Result.Data.Width := Self.Data.Width;
  Result.Data.Height := Self.Data.Height;
  Result.Data.inputs := Self.Data.inputs;
  Result.Data.outputs := Self.Data.outputs;
  Result.Data.max_height:= Self.Data.max_height;
  Result.Data.max_width:= Self.Data.max_width;
end;

function TMFonts.GetFontByIndex(Index : integer): TMfont;
begin
  // TODO: Check bounds?
  result := TMfont(Fonts.Items[index]);
end;

constructor TMFonts.Create(Owner : TObject);

begin
  inherited Create;
  Fonts := TList.Create;
  Client := Owner;
end;

destructor TMFonts.Destroy;
var
  i:integer;
begin
  for i := 0 to Fonts.Count - 1 do
    TMFont(Fonts.Items[i]).Free;
  Fonts.Free;

  inherited;
end;

procedure TMFonts.SetPath(const aPath: String);
begin
  FPath := aPath;
end;

function TMFonts.GetPath: String;
begin
  Exit(FPath);
end;

function TMFonts.GetFontIndex(const Name: String): Integer;
var
  i: integer;
begin
  for i := 0 to Fonts.Count - 1 do
  begin
    if lowercase(Name) = lowercase(TMFont(Fonts.Items[i]).Name) then
      Exit(i);
  end;
  raise Exception.Create('Font [' + Name + '] not found.');
  Exit(-1);
end;

function TMFonts.GetFont(const Name: String): TOcrData;
var
  i: integer;
begin
  i := GetFontIndex(Name);
  Exit(TMFont(Fonts.Items[i]).Data);
end;

function TMFonts.FreeFont(const Name: String): boolean;
var
  i: integer;
begin
  i := GetFontIndex(Name);
  result := (i <> -1);
  if result then
  begin
    TMFont(Fonts.Items[i]).Free;
    Fonts.Delete(i);
  end;
end;

function TMFonts.LoadFont(const Name: String; Shadow: Boolean): boolean;
var
  f: TMFont;
  CanonicalName, fontPath: String;
begin
  Result := True;
  CanonicalName := '';
  fontPath := '';

  // TODO: Use UTF8 here?
  if not DirectoryExists(FPath + Name) then
  begin
     if not DirectoryExists(Name) then
      begin
        raise Exception.Create('LoadFont: Directory ' + FPath + Name + ' does not exist.');
        Exit(False);
      end
      else
      begin
        fontPath := Name;
        CanonicalName := ExtractFileDir(Name);
        CanonicalName := system.Copy(CanonicalName, 0, Length(CanonicalName) - rpos(DS, CanonicalName) + 1);
      end;

    // If we reached this place and CanonicalName is still '', then we found no
    // valid font path
    if CanonicalName <> '' then
    begin
      raise Exception.Create('LoadFont: Directory ' + FPath + Name + ' does not exist.');
      Exit(False);
    end;
  end else
  begin
    CanonicalName := Name;
    fontPath := FPath + Name;
  end;

  try
    // Hackety-hack
    if Shadow then
      Self.GetFontIndex(CanonicalName + '_s')
    else
      Self.GetFontIndex(CanonicalName)
  except
    raise Exception.Create('LoadFont: Font with same name ' + CanonicalName + 'is already loaded: ' + Name);
  end;

  f := TMFont.Create;
  f.Name := CanonicalName;
  if Shadow then
    F.Name := F.Name + '_s';
  f.Data := InitOCR(LoadGlyphMasks(fontPath + DS, Shadow));
  Fonts.Add(f);
  TClient(Client).Writeln('Loaded Font ' + f.Name);
end;

function TMFonts.LoadSystemFont(const SysFont: TFont; const FontName: string): boolean;
var
  Masks : TocrGlyphMaskArray;
  i,c : integer;
  w,h : integer;
  Bmp : TBitmap;
  NewFont : TMFont;
  MBmp : TMufasaBitmap;
begin
  SetLength(Masks,255);
  MBmp := TMufasaBitmap.Create;
  Bmp := TBitmap.Create;
  c := 0;
  with Bmp.canvas do
  begin
    Font := SysFont;
    Font.Color:= clWhite;
    Font.Quality:=   fqNonAntialiased;
    Brush.Color:= clBlack;
    Pen.Style:= psClear;
    for i := 1 to 255 do
    begin
      GetTextSize(chr(i),w,h);
      if (w<=0) or (h<=0) then
        Continue;
      Bmp.SetSize(w,h);
      TextOut(0,0,chr(i));
      MBmp.LoadFromTBitmap(bmp);
      Masks[c] := LoadGlyphMask(MBmp,false,chr(i));
      inc(c);
    end;
  end;
  setlength(masks,c);
  if c > 0 then
  begin
    NewFont := TMFont.Create;
    NewFont.Name:= FontName;
    NewFont.Data := InitOCR(masks);
    Fonts.Add(NewFont);
    result := true;
  end;
  bmp.free;
  MBmp.free;

end;

function TMFonts.Copy(Owner : TObject): TMFonts;

var
  i:integer;
begin
  Result := TMFonts.Create(Owner);
  Result.Path := FPath;
  for i := 0 to Self.Fonts.Count -1 do
    Result.Fonts.Add(TMFont(Self.Fonts.Items[i]).Copy());
end;

function TMFonts.Count: integer;
begin
  result := Fonts.Count;
end;

end.

