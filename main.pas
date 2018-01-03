unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, Forms, Controls, Dialogs, Menus, StdCtrls, ComCtrls;

type

  { TMainForm }

  TMainForm = class(TForm)
    MainMenu: TMainMenu;
    FilwMenuItem: TMenuItem;
    ClipboardMenuItem: TMenuItem;
    Memo: TMemo;
    MenuItem1: TMenuItem;
    QuitMenuItem: TMenuItem;
    ColorsMenuItem: TMenuItem;
    Colors256MenuItem: TMenuItem;
    Colors16MenuItem: TMenuItem;
    DitherMenuItem: TMenuItem;
    KMeansMenuItem: TMenuItem;
    SettingMenuItem: TMenuItem;
    StatusBar: TStatusBar;
    procedure ClipboardMenuItemClick(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure QuitMenuItemClick(Sender: TObject);
  private

  public

  end;

var
  MainForm: TMainForm;

implementation

uses SysUtils, Graphics, LCLType, LCLIntf, IntfGraphics, FPWriteBMP,
  zstream, ColorReduction;

{$R *.lfm}

procedure Log(Message: string);
begin
  if Message = '' then
    MainForm.Memo.Append('')
  else
    MainForm.Memo.Append(Format('%s %s', [FormatDateTime('hh:nn:ss.zzz', Now()),
      Message]));
end;

function AvoidCollisionName(const FileName: string): string;
var
  I: integer;
  Path, Name, Ext: string;
begin
  if not FileExists(FileName) then
    Exit(FileName);
  I := 1;
  Path := ExtractFilePath(FileName);
  Name := ChangeFileExt(ExtractFileName(FileName), '');
  Ext := ExtractFileExt(FileName);
  while FileExists(Format('%s%s[%d]%s', [Path, Name, I, Ext])) do
    Inc(I);
  Result := Format('%s%s[%d]%s', [Path, Name, I, Ext]);
end;

procedure CopyBitmap(Src, Dst: TBitmap);
begin
  Dst.SetSize(Src.Width, Src.Height);
  Dst.PixelFormat := pf24bit;
  Dst.BeginUpdate(True);
  Dst.Canvas.Draw(0, 0, Src);
  Dst.EndUpdate(False);
end;

function LoadFromFile(FileName: string): TBitmap;
var
  Image: TPicture;
begin
  Log(Format('Load From File: %s', [FileName]));
  Image := TPicture.Create();
  Image.LoadFromFile(FileName);
  Result := TBitmap.Create();
  CopyBitmap(Image.Bitmap, Result);
  FreeAndNil(Image);
end;

function LoadFromClipboard(): TBitmap;
var
  Image: TBitmap;
begin
  Log('Load From Clipboard');
  Image := TBitmap.Create();
  Image.LoadFromClipboardFormat(PredefinedClipboardFormat(pcfBitmap));
  Result := TBitmap.Create();
  CopyBitmap(Image, Result);
  FreeAndNil(Image);
end;

procedure SaveToFile(Image: TLazIntfImage; FileName: string);
var
  SaveName: string;
  PngWriter: TLazWriterPNG;
begin
  if FileName = '' then
    FileName := 'screenshot.bmp';
  SaveName := AvoidCollisionName(ChangeFileExt(FileName, '.png'));
  Log(Format('Save To File: %s', [SaveName]));

  PngWriter := TLazWriterPNG.Create();
  PngWriter.Indexed := True;
  PngWriter.CompressionLevel := clmax;

  Image.SaveToFile(SaveName, PngWriter);

  FreeAndNil(PngWriter);
end;

function GatherConfig(): TReduceColorConfig;
begin
  if MainForm.Colors256MenuItem.Checked then
    Result.Colors := 256
  else if MainForm.Colors16MenuItem.Checked then
    Result.Colors := 16;
  Result.Dither := MainForm.DitherMenuItem.Checked;
  Result.KMeans := MainForm.KMeansMenuItem.Checked;
end;

procedure ReduceColorWrapper(FileName: string);
var
  Config: TReduceColorConfig;
  Src: TBitmap;
  Dst: TLazIntfImage;
begin
  Log('*** START ***');

  Config := GatherConfig();

  if FileName = '' then
    Src := LoadFromClipboard()
  else
    Src := LoadFromFile(FileName);

  Dst := ReduceColor(Src, Config, @Log);

  SaveToFile(Dst, FileName);

  FreeAndNil(Dst);
  FreeAndNil(Src);

  Log('*** END ***');
  Log('');
end;

{ TMainForm }

procedure TMainForm.QuitMenuItemClick(Sender: TObject);
begin
  Close();
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  ReduceColorWrapper(FileNames[0]);
end;

procedure TMainForm.ClipboardMenuItemClick(Sender: TObject);
begin
  ReduceColorWrapper('');
end;

end.
