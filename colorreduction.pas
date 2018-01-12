unit ColorReduction;

{$mode objfpc}{$H+}

interface

uses
  Graphics, IntfGraphics;

type
  TReduceColorConfig = record
    Colors: integer;
    Dither: boolean;
    KMeans: boolean;
  end;
  TLog = procedure(Message: string);

function ReduceColor(Src: TBitmap; Config: TReduceColorConfig;
  Log: TLog): TLazIntfImage;

implementation

uses
  SysUtils, GraphType, FPimage;

type
  TIntegerTriple = packed array[0..2] of integer;
  TIntegerTripleArray = array[0..0] of TIntegerTriple;
  PIntegerTripleArray = ^TIntegerTripleArray;

  TByteTriple = packed array[0..2] of byte;
  TByteTripleArray = array[0..0] of TByteTriple;
  PByteTripleArray = ^TByteTripleArray;

  TPalette = array of TByteTriple;

function ColorDiff(C1, C2: TByteTriple): integer; inline;
begin
  Result := (C1[0] - C2[0]) * (C1[0] - C2[0]) + (C1[1] - C2[1]) *
    (C1[1] - C2[1]) + (C1[2] - C2[2]) * (C1[2] - C2[2]);
end;

function TByteTripleToTFPColor(Value: TByteTriple): TFPColor;
begin
  Result.blue := (Value[0] shl 8) + Value[0];
  Result.green := (Value[1] shl 8) + Value[1];
  Result.red := (Value[2] shl 8) + Value[2];
  Result.alpha := FPImage.alphaOpaque;
end;

function CreatePalette(Src: TBitmap; Config: TReduceColorConfig; Log: TLog): TPalette;
var
  I: integer;
  B, G, R: integer;
begin
  Log('Create palette');

  SetLength(Result, 256);
  for R := 0 to 5 do
  begin
    for G := 0 to 5 do
    begin
      for B := 0 to 5 do
      begin
        Result[R * 36 + G * 6 + B][0] := B * 51;
        Result[R * 36 + G * 6 + B][1] := G * 51;
        Result[R * 36 + G * 6 + B][2] := R * 51;
      end;
    end;
  end;
  for I := 216 to 255 do
  begin
    Result[I][0] := 0;
    Result[I][1] := 0;
    Result[I][2] := 0;
  end;
end;

function GetNearestIndex(C: TByteTriple; Palette: TPalette): integer;
var
  I: integer;
  BestError, E: integer;
begin
  BestError := High(integer);
  Result := -1;
  for I := 0 to Length(Palette) - 1 do
  begin
    E := ColorDiff(C, Palette[I]);
    if E < BestError then
    begin
      BestError := E;
      Result := I;
    end;
  end;
end;

procedure MapColor(Src: TBitmap; Dst: TLazIntfImage; Palette: TPalette; Log: TLog);
var
  Y, X: integer;
  SrcRow, DstRow: PByteTripleArray;
  N: integer;
  ErrorSum: int64;
begin
  Log('Map color');

  ErrorSum := 0;
  for Y := 0 to Src.Height - 1 do
  begin
    SrcRow := PByteTripleArray(Src.RawImage.GetLineStart(Y));
    DstRow := Dst.GetDataLineStart(Y);
    for X := 0 to Src.Width - 1 do
    begin
      N := GetNearestIndex(SrcRow^[X], Palette);
      DstRow^[X] := Palette[N];
      ErrorSum := ErrorSum + ColorDiff(SrcRow^[X], Palette[N]);
    end;
  end;

  Log(Format('Average Error: %.3f', [ErrorSum / Src.Width / Src.Height]));
end;

function Clamp(N: integer): integer; inline;
begin
  if N < 0 then
    N := 0
  else if N > 255 then
    N := 255;
  Result := N;
end;

procedure MapColorWithDither(Src: TBitmap; Dst: TLazIntfImage;
  Palette: TPalette; Log: TLog);
var
  Y, X: integer;
  SrcRow, DstRow: PByteTripleArray;
  C: TByteTriple;
  I, N: integer;
  Diffs: array[0..2] of PIntegerTripleArray;
  ErrorSum: int64;
begin
  Log('Map color with dither');

  for I := 0 to 1 do
  begin
    Diffs[I] := AllocMem((Src.Width + 2) * SizeOf(TIntegerTriple));
    FillChar(Diffs[I]^, (Src.Width + 2) * SizeOf(TIntegerTriple), 0);
  end;

  ErrorSum := 0;
  for Y := 0 to Src.Height - 1 do
  begin
    SrcRow := PByteTripleArray(Src.RawImage.GetLineStart(Y));
    DstRow := Dst.GetDataLineStart(Y);
    for X := 0 to Src.Width - 1 do
    begin
      C := SrcRow^[X];
      for I := 0 to 2 do
      begin
        N := Diffs[0]^[X][I];
        N := N + Diffs[0]^[X + 1][I] * 5;
        N := N + Diffs[0]^[X + 2][I] * 3;
        N := N + Diffs[1]^[X][I] * 7;
        C[I] := Clamp(C[I] + N div 16);
      end;
      N := GetNearestIndex(C, Palette);
      DstRow^[X] := Palette[N];
      for I := 0 to 2 do
      begin
        Diffs[1]^[X + 1][I] := C[I] - Palette[N][I];
      end;
      ErrorSum := ErrorSum + ColorDiff(SrcRow^[X], Palette[N]);
    end;
    Diffs[2] := Diffs[0];
    Diffs[0] := Diffs[1];
    Diffs[1] := Diffs[2];
  end;

  Log(Format('Average Error: %.3f', [ErrorSum / Src.Width / Src.Height]));
end;

function ReduceColor(Src: TBitmap; Config: TReduceColorConfig;
  Log: TLog): TLazIntfImage;
var
  I: integer;
  Palette: TPalette;
begin
  Result := TLazIntfImage.Create(Src.Width, Src.Height, [riqfRGB, riqfPalette]);
  Result.DataDescription.Init_BPP24_B8G8R8_M1_BIO_TTB(Result.Width, Result.Height);
  Result.CreateData();
  Result.UsePalette := True;
  Result.Palette.Count := Config.Colors;

  Palette := CreatePalette(Src, Config, Log);
  for I := 0 to Config.Colors - 1 do
    Result.Palette[I] := TByteTripleToTFPColor(Palette[I]);

  if Config.Dither then
    MapColorWithDither(Src, Result, Palette, Log)
  else
    MapColor(Src, Result, Palette, Log);
end;

end.
