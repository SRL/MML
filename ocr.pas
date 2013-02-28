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

    OCR class for the Mufasa Macro Library
}

unit ocr;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, MufasaTypes,MufasaBase, bitmaps, math, ocrutil, fontloader,
  {Begin To-Remove units. Replace ReadBmp with TMufasaBitmap stuff later.}
  graphtype, intfgraphics,graphics;
  {End To-Remove unit}

(*
.. _mmlref-ocr:

TMOCR Class
===========

The TMOCR class uses the powerful ``ocrutil`` unit to create some default but
useful functions that can be used to create and identify text. It also contains
some functions used in special cases to filter noise. Specifically, these are
all the ``Filter*`` functions.

*)

type
    { TMOCR }

  TMOCR = class(TObject)
  private
    Client: TObject;
    FFonts: TMFonts;
    filterdata: TOCRFilterDataArray;
    function  GetFonts:TMFonts;
    procedure SetFonts(const NewFonts: TMFonts);
  public
    constructor Create(Owner: TObject);
    destructor Destroy; override;
    function InitTOCR(const path: string): boolean;
    function getTextPointsIn(sx, sy, w, h: Integer; shadow: boolean;
           var _chars, _shadows: T2DPointArray): Boolean;
    function GetUpTextAtEx(atX, atY: integer; shadow: boolean): string;
    function GetUpTextAt(atX, atY: integer; shadow: boolean): string;

    procedure CreateDefaultFilter;
    procedure SetFilter(filter: TOCRFilterDataArray);
    procedure ResetFilter;
    procedure FilterUpTextByColour(bmp: TMufasaBitmap);
    procedure FilterUpTextByCharacteristics(bmp: TMufasaBitmap);
    procedure FilterUpTextByColourMatches(bmp: TMufasaBitmap);
    procedure FilterShadowBitmap(bmp: TMufasaBitmap);
    procedure FilterCharsBitmap(bmp: TMufasaBitmap);

    function GetTextAt(atX, atY, minvspacing, maxvspacing, hspacing,
                    color, tol, len: integer; font: string): string;overload;
    function GetTextAt(xs, ys, xe, ye, minvspacing, maxvspacing, hspacing,
      color, tol: integer; font: string): string;overload;
    function GetTextATPA(const ATPA: T2DPointArray; const maxvspacing: integer; font: string): string;
    function TextToFontTPA(Text, font: String; out w, h: integer): TPointArray;
    function TextToFontBitmap(Text, font: String): TMufasaBitmap;
    function TextToMask(Text, font: String): TMask;
    property Fonts : TMFonts read GetFonts write SetFonts;
    {$IFDEF OCRDEBUG}
    procedure DebugToBmp(bmp: TMufasaBitmap; hmod,h: integer);
    public
       debugbmp: TMufasaBitmap;
    {$ENDIF}
  end;

  {$IFDEF OCRDEBUG}
    {$IFDEF LINUX}
      const OCRDebugPath = '/tmp/';
    {$ELSE}
      const OCRDebugPath = '';
    {$ENDIF}
  {$ENDIF}

implementation

uses
  colour_conv, client,  files, tpa, mufasatypesutil, iomanager;

const
    { Very rough limits for R, G, B }
    ocr_Limit_High = 190;
    ocr_Limit_Med = 130;
    ocr_Limit_Low = 65;


    { `base' Colours of the Uptext }

    { White }
    ocr_White = 16777215;

    { Level < Your Level }
    ocr_Green = 65280;

    { Level > Your Level }
    ocr_Red = 255;

    { Interact or Level = Your Level }
    ocr_Yellow = 65535;

    { Object }
    ocr_Blue = 16776960;

    { Item }
    ocr_ItemC = 16744447;

    { Item }
    ocr_ItemC2 = clRed or clGreen;

    { Shadow }
    ocr_Purple = 8388736;

const
    OF_LN = 256;
    OF_HN = -1;


{ Constructor }
constructor TMOCR.Create(Owner: TObject);
begin
  inherited Create;
  Self.Client := Owner;
  Self.FFonts := TMFonts.Create(Owner);

  CreateDefaultFilter;
end;

{ Destructor }
destructor TMOCR.Destroy;
begin
  SetLength(filterdata, 0);

  Self.FFonts.Free;
  inherited Destroy;
end;

(*
InitTOCR
~~~~~~~~

.. code-block:: pascal

    function TMOCR.InitTOCR(const path: string): boolean;

InitTOCR loads all fonts in path
We don't do this in the constructor because we may not yet have the path.

*)
function TMOCR.InitTOCR(const path: string): boolean;
var
   dirs: array of string;
   i: longint;
   {$IFDEF FONTDEBUG}
   fonts_loaded: String = '';
   {$ENDIF}
begin
  // We're going to load all fonts now
  FFonts.Path := path;
  dirs := GetDirectories(path);
  Result := false;
  for i := 0 to high(dirs) do
  begin
    {$IFDEF FONTDEBUG}
    // REMOVING THIS WILL CAUSE FONTS_LOADED NOT BE ADDED SOMEHOW?
    writeln('Loading: ' + dirs[i]);
    {$ENDIF}
    if FFonts.LoadFont(dirs[i], false) then
    begin
      {$IFDEF FONTDEBUG}
      fonts_loaded := fonts_loaded + dirs[i] + ', ';
      {$ENDIF}
      result := true;
    end;
  end;
  {$IFDEF FONTDEBUG}
  if length(fonts_loaded) > 2 then
  begin
    writeln(fonts_loaded);
    setlength(fonts_loaded,length(fonts_loaded)-2);
    TClient(Self.Client).WriteLn('Loaded fonts: ' + fonts_loaded);
  end;
  {$ENDIF}
  { TODO FIXME CHANGE TO NEW CHARS? }
  If DirectoryExists(path + 'UpChars') then
    FFonts.LoadFont('UpChars', true); // shadow
end;

{ Get the current pointer to our list of Fonts }
function TMOCR.GetFonts:TMFonts;
begin
  Result := Self.FFonts;
end;

{ Set new Fonts. We set it to a Copy of NewFonts }
procedure TMOCR.SetFonts(const NewFonts: TMFonts);
begin
  if (Self.FFonts <> nil) then
    Self.FFonts.Free;

  Self.FFonts := NewFonts.Copy(Self.Client);
end;


{
  Filter UpText by a very rough colour comparison / range check.
  We first convert the colour to RGB, and if it falls into the following
  defined ranges, it may be part of the uptext. Also get the possible
  shadows.

  We have large ranges because we rather have extra (fake) pixels than less
  uptext pixels... This because we can filter most of the noise out easily.

  Non optimised. We can make it use direct data instead of fastgetpixel and
  fastsetpixel, but speed isn't really an issue. The entire algorithm is still
  fast enough.

  There are some issues with this method; since later on the algorithm
  (if I recall correctly) throws aways some pixels if a character isn't just
  one colour)

  We will match shadow as well; we need it later on.
}

      {
    We're going to filter the bitmap solely on colours first.
    If we found one, we set it to it's `normal' colour.

    Note that these values aren't randomly chosen, but I didn't spent too
    much time on finding the exact values either.

    We will iterate over each pixel in the bitmap, and if it matches any of the
    ``rules'' for the colour; we will set it to a constant colour which
    represents this colour (and corresponding rule). Usually the ``base''
    colour.

    If it doesn't match any rule, we can safely make the pixel black.

    To my knowledge this algorithm doesn't remove any valid points. It does
    not remove *all* invalid points either; but that is simply not possible
    based purely on the colour. (If someone has a good idea, let me know)
  }

  (*
  FilterUpTextByColour
  ~~~~~~~~~~~~~~~~~~~~

  .. code-block:: pascal

      procedure TMOCR.FilterUpTextByColour(bmp: TMufasaBitmap);

  *)

procedure TMOCR.CreateDefaultFilter;
  function load0(r_low,r_high,g_low,g_high,b_low,b_high,set_col: integer;
      is_text_color: boolean): tocrfilterdata;
  begin
    result.r_low := r_low;
    result.r_high := r_high;
    result.g_low := g_low;
    result.g_high := g_high;
    result.b_low := b_low;
    result.b_high := b_high;
    result.set_col := set_col;
    result._type := 0;
    result.is_text_color:= is_text_color;
  end;

begin
  setlength(filterdata, 9);

  filterdata[0] := load0(65, OF_HN, OF_LN, 190, OF_LN, 190, ocr_Blue, True); // blue
  filterdata[1] := load0(65, OF_HN, OF_LN, 190, 65, OF_HN, ocr_Green, True); // green
  filterdata[2] := load0(OF_LN, 190, 220, 100, 127, 40, ocr_ItemC, True); // itemC
  filterdata[3] := load0(OF_LN, 190, OF_LN, 190, 65, OF_HN, ocr_Yellow, True); // yellow
  filterdata[4] := load0(OF_LN, 190, 65, OF_HN, 65, OF_HN, ocr_Red, True); // red
  filterdata[5] := load0(OF_LN, 190, OF_LN, 65, 65, OF_HN, ocr_Red, True); // red 2
  filterdata[6] := load0(190 + 10, 130, OF_LN, 65 - 10, 20, OF_HN, ocr_Green, True); // green 2
  filterdata[7] := load0(190, 140, 210, 150, 200, 160, ocr_ItemC2, True); // item2, temp item_c
  filterdata[8] := load0(65, OF_HN, 65, OF_HN, 65, OF_HN, ocr_Purple, False); // shadow
end;

procedure TMOCR.SetFilter(filter: TOCRFilterDataArray);

begin
  SetLength(filterdata, 0);
  filterdata := copy(filter);
end;

procedure TMOCR.ResetFilter;

begin
  SetLength(filterdata, 0);
  CreateDefaultFilter;
end;

procedure TMOCR.FilterUpTextByColour(bmp: TMufasaBitmap);

var
   x, y,r, g, b, i: Integer;
   found: Boolean;

begin
  for y := 0 to bmp.Height - 1 do
    for x := 0 to bmp.Width - 1 do
    begin
      colortorgb(bmp.fastgetpixel(x,y),r,g,b);

      { white, need this for now since it cannot be expressed in filterocrdata  }
      if (r > ocr_Limit_High) and (g > ocr_Limit_High) and (b > ocr_Limit_High)
         and (abs(r-g) + abs(r-b) + abs(g-b) < 55) then
      begin
        bmp.fastsetpixel(x,y,ocr_White);
        continue;
      end;


      found := False;
      for i := 0 to high(filterdata) do
      begin
        if filterdata[i]._type = 0 then
            if (r < filterdata[i].r_low) and (r > filterdata[i].r_high) and (g < filterdata[i].g_low)
            and (g > filterdata[i].g_high) and (b < filterdata[i].b_low) and (b > filterdata[i].b_high) then
            begin
              bmp.fastsetpixel(x, y, filterdata[i].set_col);
              found := True;
              break;
            end;
        { else if type = 1 }
        { XXX TODO ^ }
      end;
      if found then
        continue;

      // Black if no match
      bmp.fastsetpixel(x, y ,0);
    end;

    {
      Make outline black for shadow characteristics filter
      First and last horiz line = 0. This makes using the shadow algo easier.
      We don't really throw away information either since we already took the
      bitmap a bit larger than required.
    }
    for x := 0 to bmp.width -1 do
      bmp.fastsetpixel(x,0,0);
    for x := 0 to bmp.width -1 do
      bmp.fastsetpixel(x,bmp.height-1,0);

    // Same for vertical lines
    for y := 0 to bmp.Height -1 do
      bmp.fastsetpixel(0, y, 0);
    for y := 0 to bmp.Height -1 do
      bmp.fastsetpixel(bmp.Width-1, y, 0);
end;


{
  This filter assumes the previous colour filter has been applied first.
  I like to call this the `characteristics' filter because we really only filter
  on characteristics.

  For the uptext, a few things apply...

  *** Remove False Shadow ***
      if shadow[x,y] then not shadow[x-1,y-1]
  If there is a shadow at x,y then there should not be a shadow at x-1, y-1; if
  there is one, then shadow[x, y] is not a shadow.

    (One could also say, if shadow[x,y] and shadow[x+1,y+1] then shadow[x+1,y+1]
     is no shadow; because it essentially means the same. However, a smart mind
     will soon see that this algorithm will be a *lot* more efficient if we
     start at the right bottom, instead of the left top. Which means we should
     work with x-1 and y-1, rather than x+1,y+1
    )

  *** UpText chars identity 1 and 2 ***
      if UpTextChar[x,y] then (UpTextChar[x+1,y+1] or shadow[x+1,y+1])
    If this is not true, then UpTextChar[x,y] cannot be part of uptext - it
    has no shadow, and it doesn't have a `friend' (at x+1,y+1) either.
    We don't need to do this from the right bottom to left top.
}

(*
FilterUpTextByCharacteristics
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: pascal

    procedure TMOCR.FilterUpTextByCharacteristics(bmp: TMufasaBitmap; w,h: integer);
*)

procedure TMOCR.FilterUpTextByCharacteristics(bmp: TMufasaBitmap);
var
   x,y: Integer;
begin
  { Filter 2
    This performs a `simple' filter.
    What we are doing here is simple checking that if Colour[x,y] is part
    of the uptext, then so must Colour[x+1,y+1], or Colour[x+1,y+1] is a shadow.
    if it is neither, we can safely remove it.

    XXX: This causes the previously mentioned fuckup.
  }
 for y := 0 to bmp.Height - 2 do
   for x := 0 to bmp.Width - 2 do
   begin
     if bmp.fastgetpixel(x,y) = clPurple then
       continue;
     if bmp.fastgetpixel(x,y) = clBlack then
       continue;
     if (bmp.fastgetpixel(x,y) <> bmp.fastgetpixel(x+1,y+1)) and
          (bmp.fastgetpixel(x+1,y+1) <> clpurple) then
       bmp.fastsetpixel(x,y,{clAqua}0);
   end;

  {
    Remove false shadow. (A shadow isn't larger than 1 pixel. So if x, y is
    shadow, thex x+1, y+1 can't be shadow. If it is, we can safely remove it.
    (As well as x+2, y+2, etc).

    The tricky part of the algorithm is that it starts at the bottom,
    removing shadow point x,y if x-1,y-1 is also shadow.
  }

 for y := bmp.Height - 1 downto 1 do
   for x := bmp.Width - 1 downto 1 do
   begin
     if bmp.fastgetpixel(x,y) <> clPurple then
       continue;
     if bmp.fastgetpixel(x,y) = bmp.fastgetpixel(x-1,y-1) then
     begin
       bmp.fastsetpixel(x,y,clSilver);
       continue;
     end;
     if bmp.fastgetpixel(x-1,y-1) = 0 then
       bmp.fastsetpixel(x,y,clSilver);
   end;

  // Now we do another filter, with uptext chars identity 1 and 2.
  for y := bmp.Height - 2 downto 0 do
    for x := bmp.Width - 2 downto 0 do
    begin
      if bmp.fastgetpixel(x,y) = clPurple then
        continue;
      if bmp.fastgetpixel(x,y) = clBlack then
        continue;

      // identity 1
      if (bmp.fastgetpixel(x,y) = bmp.fastgetpixel(x+1,y+1) ) then
        continue;

      // identity 2
      if bmp.fastgetpixel(x+1,y+1) <> clPurple then
      begin
        bmp.fastsetpixel(x,y,clOlive);
        continue;
      end;

     // If we make it to here, it means the pixel is part of the uptext.
   end;
end;

{$IFDEF OCRDEBUG}
{ Write to our debugbmp }
procedure TMOCR.DebugToBmp(bmp: TMufasaBitmap; hmod, h: integer);
var
   x,y: integer;
begin
 for y := 0 to bmp.height - 1 do
   for x := 0 to bmp.width - 1 do
     debugbmp.fastsetpixel(x,y + hmod *h,bmp.fastgetpixel(x,y));
end;
{$ENDIF}

{
  Return the shadows of the points in charpoint on bitmap shadowsbmp.

  Pseudo:
    if shadow[charpoint[i].x+1, charpoint[i].y+1] then addtoResult;
}
function getshadows(shadowsbmp:TMufasaBitmap; charpoint: tpointarray): tpointarray;
var
   i,c:integer;
begin
  setlength(result,length(charpoint));
  c:=0;
  for i := 0 to high(charpoint) do
  begin
    if shadowsbmp.fastgetpixel(charpoint[i].x+1,charpoint[i].y+1) = clPurple then
    begin
      result[c]:=point(charpoint[i].x+1, charpoint[i].y+1);
      inc(c);
    end;
  end;
  setlength(result,c);
end;


procedure TMOCR.FilterUpTextByColourMatches(bmp: TMufasaBitmap);

var
   TPA: TPointArray;
   ATPA: T2DPointArray;
   OldTarget: Integer;
   c, i, j, k: Integer;
begin
  TClient(Client).IOManager.GetImageTarget(OldTarget);
  TClient(Client).IOManager.SetTarget(bmp);

  for i := 0 to high(filterdata) do
  begin
    if not filterdata[i].is_text_color then
      continue;
    c := filterdata[i].set_col;

    TClient(Client).MFinder.FindColors(TPA, c, 0, 0, bmp.width - 1, bmp.height - 1);

    ATPA := SplitTPAEx(TPA, 2, 6);

    for j := 0 to high(atpa) do
    begin
      if length(ATPA[j]) > 70 then
        for k := 0 to high(ATPA[j]) do
          bmp.FastSetPixel(ATPA[j][k].x, ATPA[j][k].y, 0);

      if length(ATPA[j]) < 4 then
        for k := 0 to high(ATPA[j]) do
          bmp.FastSetPixel(ATPA[j][k].x, ATPA[j][k].y, 0);
    end;

  end;


  TClient(Client).IOManager.SetImageTarget(OldTarget);
end;

(*
FilterShadowBitmap
~~~~~~~~~~~~~~~~~~

.. code-block:: pascal

    procedure TMOCR.FilterShadowBitmap(bmp: TMufasaBitmap);

Remove anything but the shadows on the bitmap (Shadow = clPurple)
*)

procedure TMOCR.FilterShadowBitmap(bmp: TMufasaBitmap);
var
   x,y:integer;
begin
  for y := 0 to bmp.Height - 1 do
    for x := 0 to bmp.Width - 1 do
    begin
      if bmp.fastgetpixel(x,y) <> clPurple then
      begin
        bmp.FastSetPixel(x,y,0);
        continue;
      end;
    end;
end;

(*

FilterCharsBitmap
~~~~~~~~~~~~~~~~~

.. code-block:: pascal

    procedure TMOCR.FilterCharsBitmap(bmp: TMufasaBitmap);

Remove all but uptext colours clWhite,clGreen, etc.

This assumes that the bitmap only consists of colour 0, and the other
constants founds above the functions
*)
procedure TMOCR.FilterCharsBitmap(bmp: TMufasaBitmap);
var
   x,y: integer;
begin
  begin
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        if bmp.fastgetpixel(x,y) = clPurple then
        begin
          bmp.FastSetPixel(x,y,0);
          continue;
        end;
        if bmp.fastgetpixel(x,y) = clOlive then
        begin
          bmp.FastSetPixel(x,y,0);
          continue;
        end;
        if bmp.fastgetpixel(x,y) = clSilver then
        begin
          bmp.FastSetPixel(x,y,0);
          continue;
        end;
      end;
  end;
end;


{
}
(*
getTextPointsIn
~~~~~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.getTextPointsIn(sx, sy, w, h: Integer; shadow: boolean;
                               var _chars, _shadows: T2DPointArray): Boolean;

This uses the two filters, and performs a split on the bitmap.
A split per character, that is. So we can more easily identify it.

TODO:
  *
    Remove more noise after we have split, it should be possible to identify
    noise; weird positions or boxes compared to the rest, etc.
  *
    Split each colours seperately, and combine only later, after removing noise.
*)

function TMOCR.getTextPointsIn(sx, sy, w, h: Integer; shadow: boolean;
                               var _chars, _shadows: T2DPointArray): Boolean;
var
   bmp, shadowsbmp, charsbmp: TMufasaBitmap;
   x,y: integer;
   {$IFDEF OCRDEBUG}
   dx,dy: integer;
   {$ENDIF}
   shadows: T2DPointArray;
   helpershadow: TPointArray;
   chars: TPointArray;
   charscount: integer;
   chars_2d, chars_2d_b, finalchars: T2DPointArray;
   pc: integer;
   bb: Tbox;

begin
  bmp := TMufasaBitmap.Create;
  { Increase to create a black horizonal line at the top and at the bottom }
  { This so the crappy algo can do it's work correctly. }
  bmp.SetSize(w + 2, h + 2);

  // Copy the client to out working bitmap.
  bmp.CopyClientToBitmap(TClient(Client).IOManager, False, 1{0},1, sx, sy, sx + w - 1, sy + h - 1);

  {$IFDEF OCRSAVEBITMAP}
  bmp.SaveToFile(OCRDebugPath + 'ocrinit.bmp');
  {$ENDIF}

  {$IFDEF OCRDEBUG}
    debugbmp := TMufasaBitmap.Create;
    debugbmp.SetSize(w + 2, (h + 2) * 8);
    debugbmp.FastDrawClear(clBlack);
  {$ENDIF}
  {$IFDEF OCRDEBUG}
    DebugToBmp(bmp,0,h);
  {$ENDIF}

  {
    Filter 1, remove most colours we don't want.
  }
  FilterUpTextByColour(bmp);
  {$IFDEF OCRSAVEBITMAP}
  bmp.SaveToFile(OCRDebugPath + 'ocrcol.bmp');
  {$ENDIF}

  {$IFDEF OCRDEBUG}
    DebugToBmp(bmp,1,h);
  {$ENDIF}

  // new filter
  FilterUpTextByColourMatches(bmp);
  {$IFDEF OCRSAVEBITMAP}
  bmp.SaveToFile(OCRDebugPath + 'ocrcolourmatches.bmp');
  {$ENDIF}
  {$IFDEF OCRDEBUG}
    DebugToBmp(bmp,2,h);
  {$ENDIF}

  {
    Filter 2, remove all false shadow points and points that have no shadow
    after false shadow is removed.
  }
  // Filter 2
  FilterUpTextByCharacteristics(bmp);

  {$IFDEF OCRSAVEBITMAP}
  bmp.SaveToFile(OCRDebugPath + 'ocrdebug.bmp');
  {$ENDIF}
  {$IFDEF OCRDEBUG}
    DebugToBmp(bmp,3,h);
  {$ENDIF}

  {
    We've now passed the two filters.
    We need to extract the characters and return a TPA of each character
  }

  { Create a bitmap with only the shadows on it }
  shadowsbmp := bmp.copy;
  FilterShadowBitmap(shadowsbmp);
  {$IFDEF OCRDEBUG}
  DebugToBmp(shadowsbmp,4,h);
  {$ENDIF}

  { create a bitmap with only the chars on it }
  charsbmp := bmp.copy;
  FilterCharsBitmap(charsbmp);
  {$IFDEF OCRDEBUG}
    DebugToBmp(charsbmp,5,h);
  {$ENDIF}

  { Now actually extract the characters }

  // TODO XXX FIXME:
  // We should make a different TPA
  // for each colour, rather than put them all in one. Noise can be of a
  // different colour.

  SetLength(chars, charsbmp.height * charsbmp.width);
  charscount := 0;

  for y := 0 to charsbmp.height - 1 do
    for x := 0 to charsbmp.width - 1 do
    begin
      { If the colour > 0, it is a valid point of a character }
      if charsbmp.fastgetpixel(x,y) > 0 then
      begin
        { Add the point }
        chars[charscount] := point(x,y);
        inc(charscount);
      end;
    end;
  setlength(chars,charscount);
  { Limit to charpoint amount of points }

  { Now that the points of all the characters are in array ``chars'', split }
  chars_2d := SplitTPAEx(chars,1,charsbmp.height);

  { Each char now has its own TPA in chars_2d[n] }

  { TODO: This only sorts the points in every TPA }
  SortATPAFrom(chars_2d, point(0,0));

  {$IFDEF OCRDEBUG}
  for x := 0 to high(chars_2d) do
  begin
    pc := random(clWhite);
    for y := 0 to high(chars_2d[x]) do
      charsbmp.FastSetPixel(chars_2d[x][y].x, chars_2d[x][y].y, pc);
  end;
  DebugToBmp(charsbmp,6,h);
  {$ENDIF}

  for y := 0 to high(chars_2d) do
  begin
    { bb is the bounding box of one character }
    bb:=gettpabounds(chars_2d[y]);

    { Character is way too large }
    if (bb.x2 - bb.x1 > 10) or (length(chars_2d[y]) > 70) then
    begin // more than one char

      {$IFDEF OCRDEBUG}
      if length(chars_2d[y]) > 70 then
        mDebugLn('more than one char at y: ' + inttostr(y));
      if (bb.x2 - bb.x1 > 10) then
        mDebugLn('too wide at y: ' + inttostr(y));
      {$ENDIF}

      { TODO: Remove all the stuff below? }

      { Store the shadow of each char in helpershadow }
      helpershadow:=getshadows(shadowsbmp,chars_2d[y]);

      { Split helpershadow as well }
      chars_2d_b := splittpaex(helpershadow,2,shadowsbmp.height);

      //writeln('chars_2d_b length: ' + inttostr(length(chars_2d_b)));

      { Draw on shadowsbmp }
      shadowsbmp.DrawATPA(chars_2d_b);
      for x := 0 to high(chars_2d_b) do
      begin
        setlength(shadows,length(shadows)+1);
        shadows[high(shadows)] :=  ConvTPAArr(chars_2d_b[x]);
      end;

    end else if length(chars_2d[y]) < 70 then
    begin
      { Character fits, get the shadow and store it in shadows }
      setlength(shadows,length(shadows)+1);
      shadows[high(shadows)] := getshadows(shadowsbmp, chars_2d[y]);
    end;
  end;

  {
    Put the characters back in proper order,
    SplitTPA messes with the order of them.
    Perform some more length checks as well. (TODO: WHY?)

    Store the resulting tpa in ``finalchars''.
  }
  SortATPAFromFirstPoint(chars_2d, point(0,0));
  for y := 0 to high(chars_2d) do
  begin
    if length(chars_2d[y]) > 70 then
      continue;
    setlength(finalchars,length(finalchars)+1);
    finalchars[high(finalchars)] := chars_2d[y];
  end;

  { Sort the shadows as well because splitTPA messes with the order }
  SortATPAFromFirstPoint(shadows, point(0,0));
  for x := 0 to high(shadows) do
  begin
    pc:=0;

    { Draw some stuff? TODO WHY }
    pc := random(clWhite);
    for y := 0 to high(shadows[x]) do
      shadowsbmp.FastSetPixel(shadows[x][y].x, shadows[x][y].y, pc);
  end;
  {$IFDEF OCRDEBUG}
    DebugToBmp(shadowsbmp,7,h);
  {$ENDIF}

  {
    Return finalized characters.
    They are not yet trimmed. They will be trimmed later on.
  }
  _chars := finalchars;
  _shadows := shadows;

  bmp.Free;
  charsbmp.Free;
  shadowsbmp.Free;
  Result := true;
end;

(*
GetUpTextAtEx
~~~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.GetUpTextAtEx(atX, atY: integer; shadow: boolean): string;


GetUpTextAtEx will identify each character, and also keep track of the previous
chars' final *x* bounds. If the difference between the .x2 of the previous
character and the .x1 of the current character is bigger than 5, then there
was a space between them. (Add ' ' to result)
*)

function TMOCR.GetUpTextAtEx(atX, atY: integer; shadow: boolean): string;
var
   n:Tnormarray;
   ww, hh,i,j,nl: integer;
   font: TocrData;
   chars, shadows, thachars: T2DPointArray;
   t:Tpointarray;
   b,lb:tbox;
   lbset: boolean;

begin
  result:='';
  ww := 400;
  hh := 20;

  { Return all the character points to chars & shadow }
  getTextPointsIn(atX, atY, ww, hh, shadow, chars, shadows);

  // Get font data for analysis.

  if shadow then
  begin
    font := FFonts.GetFont('UpChars_s');
    thachars := shadows;
  end
  else
  begin
    font := FFonts.GetFont('UpChars');
    thachars := chars;
  end;

  lbset:=false;
  setlength(n, (font.width+1) * (font.height+1));
  nl := high(n);

  for j := 0 to high(thachars) do
  begin
    for i := 0 to nl do
      n[i] := 0;

    t:= thachars[j];
    b:=gettpabounds(t);

    if not lbset then
    begin
      lb:=b;
      lbset:=true;
    end else
    begin
      { This is a space }
      if b.x1 - lb.x2 > 5 then
        result:=result+' ';

      { TODO: Don't we need a continue; here ? }

      lb:=b;
    end;

    { ``Normalize'' the Character. THIS IS IMPORTANT }
    for i := 0 to high(t) do
      t[i] := t[i] - point(b.x1,b.y1);

    {
      TODO: If the TPA is too large, we can still go beyond n's bounds.
      We should check the bounds in GetTextPointsIn
    }
    for i := 0 to high(thachars[j]) do
    begin
      if (thachars[j][i].x) + ((thachars[j][i].y) * font.width) <= nl then
        n[(thachars[j][i].x) + ((thachars[j][i].y) * font.width)] := 1;
    end;

    { Analyze the final glyph }
    result := result + GuessGlyph(n, font);
  end;
end;

(*
GetUpTextAt
~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.GetUpTextAt(atX, atY: integer; shadow: boolean): string;

Retreives the (special) uptext.

*)
function TMOCR.GetUpTextAt(atX, atY: integer; shadow: boolean): string;

begin
  if shadow then
    result := GetUpTextAtEx(atX, atY, true)
  else
    result := GetUpTextAtEx(atX, atY, false);
end;

(*
GetTextATPA
~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.GetTextATPA(const ATPA : T2DPointArray;const maxvspacing : integer; font: string): string;

Returns the text defined by the ATPA. Each TPA represents one character,
approximately.
*)

function TMOCR.GetTextATPA(const ATPA : T2DPointArray;const maxvspacing : integer; font: string): string;
var
  b, lb: TBox;
  i, j, w, h: Integer;
  lbset: boolean;
  n: TNormArray;
  fD: TocrData;
  TPA: TPointArray;

begin
  Result := '';
  fD := FFonts.GetFont(font);

  lbset := false;
  SetLength(Result, 0);
  SetLength(n, (fd.width + 1) * (fd.height + 1));
  for i := 0 to high(ATPA) do
  begin
    for j := 0 to high(n) do
      n[j] := 0;
    TPA := ATPA[i];
    b := GetTPABounds(TPA);
    if not lbset then
    begin
      lb:=b;
      lbset:=true;
    end else
    begin
     { if b.x1 - lb.x2 < minvspacing then
      begin
        writeln('GetTextAt: not enough spacing between chars...');
        lb := b;
        continue;
      end;   }
      if b.x1 - lb.x2 > maxvspacing then
        result:=result+' ';

      lb:=b;
    end;

    for j := 0 to high(tpa) do
      tpa[j] := tpa[j] - point(b.x1,b.y1);

    {
      FIXME: We never check it j actually fits in n's bounds...
      This *WILL* error when wrong spaces etc are passed.
      Added a temp resolution.
    }
    for j := 0 to high(tpa) do
    begin
      if (tpa[j].x) + ((tpa[j].y) * fD.width) <= high(n) then
        n[(tpa[j].x) + ((tpa[j].y) * fD.width)] := 1
      else
        mDebugLn('The automatically split characters are too wide. Try decreasing minspacing');
    end;
    result := result + GuessGlyph(n, fD);
  end;
end;

(*
GetTextAt
~~~~~~~~~

.. code-block:: pascal

    function TMOCR.GetTextAt(xs, ys, xe,ye, minvspacing, maxvspacing, hspacing,
                               color, tol: integer; font: string): string;

General text-finding function.
*)
function TMOCR.GetTextAt(xs, ys, xe,ye, minvspacing, maxvspacing, hspacing,
                               color, tol: integer; font: string): string;
var
  TPA : TPointArray;
  STPA : T2DPointArray;
  B : TBox;
begin;
  SetLength(TPA, 0);
  TClient(Client).MFinder.FindColorsTolerance(TPA, color, xs,ys,xe,ye,tol);
  b := GetTPABounds(TPA);

  { Split the text points into something usable. }
  { +1 because splittpa will not split well if we use 0 space ;) }
  STPA := SplitTPAEx(TPA, minvspacing+1, hspacing+1);

  SortATPAFrom(STPA, Point(0, ys));
  SortATPAFromFirstPoint(STPA, Point(0, ys));
  result := gettextatpa(STPA,maxvspacing,font);
end;

(*
GetTextAt (2)
~~~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.GetTextAt(atX, atY, minvspacing, maxvspacing, hspacing,
                               color, tol, len: integer; font: string): string;

General text-finding function. Different parameters than other GetTextAt.
*)
function TMOCR.GetTextAt(atX, atY, minvspacing, maxvspacing, hspacing,
                               color, tol, len: integer; font: string): string;
var
  w,h : integer;
  fD: TocrData;

begin
  Result := '';
  fD := FFonts.GetFont(font);
  TClient(Client).IOManager.GetDimensions(w, h);
 { writeln('Dimensions: (' + inttostr(w) + ', ' + inttostr(h) + ')');    }

  { Get the text points }
  if (atY + fD.height -1) >= h then
    raise exception.createFMT('You are trying to get text that is out of is origin y-coordinate: %d',[aty]);
  result := GetTextAt(atX, atY,min(atX + fD.max_width * len, w - 1),
            atY + fD.max_height - 1, minvspacing,maxvspacing,hspacing,color,tol,font);
  if length(result) > len then
    setlength(result,len);

end;

(*
TextToFontTPA
~~~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.TextToFontTPA(Text, font: String; out w, h: integer): TPointArray;

Returns a TPA of a specific *Text* of the specified *Font*.

*)


function TMOCR.TextToFontTPA(Text, font: String; out w, h: integer): TPointArray;

var
   fontD: TOcrData;
   c, i, x, y, off: Integer;
   d: TocrGlyphMetric;
   an: integer;

begin
  fontD := FFonts.GetFont(font);
  c := 0;
  off := 0;
  setlength(result, 0);
  for i := 1 to length(text)  do
  begin
    an := Ord(text[i]);
    if not InRange(an, 0, 255) then
    begin
      mDebugLn('WARNING: Invalid character passed to TextToFontTPA');
      continue;
    end;
    d := fontD.ascii[an];
    if not d.inited then
    begin
      mDebugLn('WARNING: Character does not exist in font');
      continue;
    end;
{    writeln(format('xoff, yoff: %d, %d', [d.xoff, d.yoff]));
    writeln(format('bmp w,h: %d, %d', [d.width, d.height]));
    writeln(format('font w,h: %d, %d', [fontD.width, fontD.height]));}
    setlength(result, c+d.width*d.height);
    for y := 0 to fontD.height - 1 do
      for x := 0 to fontD.width - 1 do
      begin
        if fontD.pos[d.index][x + y * fontD.width] = 1 then
       // if fontD.pos[an][x + y * fontD.width] = 1 then
        begin
          result[c] := Point(x + off +d.xoff, y+d.yoff);
          inc(c);
        end;
      end;
    setlength(result, c);
    off := off + d.width;
  end;
  w := off;
  h := d.height;
 { writeln('C: ' + inttostr(c));      }
end;

(*
TextToFontBitmap
~~~~~~~~~~~~~~~~

.. code-block:: pascal

    function TMOCR.TextToFontBitmap(Text, font: String): TMufasaBitmap;

Returns a Bitmap of the specified *Text* of the specified *Font*.
*)

function TMOCR.TextToFontBitmap(Text, font: String): TMufasaBitmap;
var
   TPA: TPointArray;
   w,h: integer;
   bmp: TMufasaBitmap;
begin
  TPA := TextToFontTPA(text, font, w, h);
  bmp := TMufasaBitmap.Create;
  bmp.SetSize(w, h);
  bmp.DrawTPA(TPA, clWhite);
  result := bmp;
end;

function TMOCR.TextToMask(Text, font: String): TMask;
var
   TPA: TPointArray;
   w,h: integer;
   i,x,y : integer;
   dx,dy : integer;
   c : integer;
   Pixels : array of array of boolean; //White = true
begin
  TPA := TextToFontTPA(text, font, w, h);
  Result.w := w;
  Result.h := h;
  Result.WhiteHi:= High(TPA);//High(WhitePixels)
  Result.BlackHi:= w*h - Length(TPA) - 1;//High(BlackPixels) = Length(blackPixels) - 1 = (TotalLength - LenWhitePixels) - 1
  SetLength(Pixels,w,h);
  SetLength(result.White,Result.WhiteHi + 1);
  SetLength(result.Black,Result.BlackHi + 1);
  for i := Result.WhiteHi downto 0 do
  begin
    Result.White[i] := TPA[i];
    Pixels[TPA[i].x][TPA[i].y] := true;
  end;
  c := 0;
  dx := w-1;
  dy := h-1;
  for y := 0 to dY do
    for x := 0 to dX do
    if not Pixels[x][y] then
    begin
      result.Black[c].x :=x;
      result.black[c].y := y;
      inc(c);
    end;
end;

end.

(*

.. _uptext-filter:

Uptext
======

To read the UpText, the TMOCR class applies several filters on the client data
before performing the actual OCR. We will take a look at the two filters first.

Filter 1: The Colour Filter
~~~~~~~~~~~~~~~~~~~~~~~~~~~

We first filter the raw client image with a very rough and tolerant colour
comparison / check.
We first convert the colour to RGB, and if it falls into the following
defined ranges, it may be part of the uptext. We also get the possible
shadows.


We will iterate over each pixel in the bitmap, and if it matches any of the
*rules* for the colour; we will set it to a constant colour which
represents this colour (and corresponding rule). Usually the *base*
colour. If it doesn't match any of the rules, it will be painted black.
We won't just check for colours, but also for differences between specific
R, G, B values. For example, if the colour is white; R, G and B should all
lie very close to each other. (That's what makes a colour white.)

The tolerance for getting the pixels is quite large. The reasons for the
high tolerance is because the uptext colour vary quite a lot. They're also
transparent and vary thus per background.
We will store/match shadow as well; we need it later on in filter 2.

To my knowledge this algorithm doesn't remove any *valid* points. It does
not remove *all* invalid points either; but that is simply not possible
based purely on the colour. (If someone has a good idea, let me know)

In code:

.. code-block:: pascal

    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        colortorgb(bmp.fastgetpixel(x,y),r,g,b);
    
        if (r < ocr_Limit_Low) and (g < ocr_Limit_Low) and
            (b < ocr_Limit_Low) then
        begin
          bmp.FastSetPixel(x,y, ocr_Purple);
          continue;
        end;
    
        // Black if no match
        bmp.fastsetpixel(x,y,0);
      end;

Filter 2: The Characteristics Filter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This second filter is easy to understand but also very powerful:

    -   It removes *all* false shadow pixels.
    -   It removes uptext pixels that can't be uptext according to specific
        rules. These rules are specifically designed so that it will never
        throw away proper points.

It also performs another filter right at the start, but we'll disregard that
filter for now.

Removing shadow points is trivial if one understands the following insight.

If there some pixel is shadow on *x, y*, then it's neighbour *x+1, y+1*
may not be a shadow pixel. A shadow is always only one pixel *thick*.

With this in mind, we can easily define an algorithm which removes all false
shadow pixels. In code:

.. code-block:: pascal

    {
        The tricky part of the algorithm is that it starts at the bottom,
        removing shadow point x,y if x-1,y-1 is also shadow. This is
        more efficient than the obvious way. (It is also easier to implement)
    }

    for y := bmp.Height - 1 downto 1 do
      for x := bmp.Width - 1 downto 1 do
      begin
        // Is it shadow?
        if bmp.fastgetpixel(x,y) <> clPurple then
          continue;
        // Is the point at x-1,y-1 shadow? If it is
        // then x, y cannot be shadow.
        if bmp.fastgetpixel(x,y) = bmp.fastgetpixel(x-1,y-1) then
        begin
          bmp.fastsetpixel(x,y,clSilver);
          continue;
        end;
        if bmp.fastgetpixel(x-1,y-1) = 0 then
          bmp.fastsetpixel(x,y,clSilver);
      end;

We are now left with only proper shadow pixels.
Now it is time to filter out false Uptext pixels.

Realize:

    -   If *x, y* is uptext, then *x+1, y+1* must be either uptext or shadow.

In code:

.. code-block:: pascal

    for y := bmp.Height - 2 downto 0 do
      for x := bmp.Width - 2 downto 0 do
      begin
        if bmp.fastgetpixel(x,y) = clPurple then
          continue;
        if bmp.fastgetpixel(x,y) = clBlack then
          continue;

        // Is the other pixel also uptext?
        // NOTE THAT IT ALSO HAS TO BE THE SAME COLOUR
        // UPTEXT IN THIS CASE.
        // I'm still not sure if this is a good idea or not.
        // Perhaps it should match *any* uptext colour.
        if (bmp.fastgetpixel(x,y) = bmp.fastgetpixel(x+1,y+1) ) then
          continue;

        // If it isn't shadow (and not the same colour uptext, see above)
        // then it is not uptext.
        if bmp.fastgetpixel(x+1,y+1) <> clPurple then
        begin
          bmp.fastsetpixel(x,y,clOlive);
          continue;
        end;

       // If we make it to here, it means the pixel is part of the uptext.
      end;

Identifying characters
~~~~~~~~~~~~~~~~~~~~~~

.. note::
    This part of the documentation is a bit vague and incomplete.

To actually identify the text we split it up into single character and then
pass each character to the OCR engine.

In the function *getTextPointsIn* we will use both the filters mentioned above.
After these have been applied, we will make a bitmap that only contains the 
shadows as well as a bitmap that only contains the uptext chars (not the 
shadows)

Now it is a good idea to count the occurances of all colours
(on the character bitmap); we will also use this later on.
To split the characters we use the well known *splittpaex* function.

We will then sort the points for in each character TPA, as this makes
makes looping over them and comparing distances easier. We will also
calculate the bounding box of each characters TPA.

.. note::
    Some more hackery is then used to seperate the characters and find
    spaces; but isn't yet documented here.

Normal OCR
----------

.. note::
    To do :-)
    A large part is already explained above.
    Most of the other OCR functions are simply used for plain identifying
    and have no filtering tasks.
*)
