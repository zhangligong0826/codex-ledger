using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CodexLedger;
using QRCoder;
namespace CodexLedger.Windows;
public static class ShareRendering {
    public static string Compact(long n)=>n>=1000000000?(n/1000000000d).ToString("0.00",CultureInfo.InvariantCulture)+"B":n>=1000000?(n/1000000d).ToString("0.00",CultureInfo.InvariantCulture)+"M":n>=1000?(n/1000d).ToString("0.0",CultureInfo.InvariantCulture)+"K":n.ToString(CultureInfo.InvariantCulture);
    public static BitmapSource Capture(FrameworkElement view){view.UpdateLayout();var bitmap=new RenderTargetBitmap(Math.Max(1,(int)Math.Ceiling(view.ActualWidth)),Math.Max(1,(int)Math.Ceiling(view.ActualHeight)),96,96,PixelFormats.Pbgra32);bitmap.Render(view);bitmap.Freeze();return bitmap;}
    public static BitmapSource Render(FrameworkElement view,int width,int height,int scale=1){view.Measure(new Size(width,height));view.Arrange(new Rect(0,0,width,height));view.UpdateLayout();var bitmap=new RenderTargetBitmap(width*scale,height*scale,96*scale,96*scale,PixelFormats.Pbgra32);bitmap.Render(view);bitmap.Freeze();return bitmap;}
    public static void Save(BitmapSource bitmap,string path){var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var stream=File.Create(path);encoder.Save(stream);}
    private static readonly string[] Colors=["#E8ECEF","#9CD2AB","#4AA86E","#267D4F","#12563B"];
    public static FrameworkElement Activity(IReadOnlyList<DailyUsage> days,Func<string,string> t,bool dark,Brush fg){
        var row=new StackPanel();row.Children.Add(new TextBlock{Text=t("近 30 天"),Foreground=fg,FontSize=12,FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,0,0,8)});var grid=new Grid();long peak=days.Select(d=>d.Usage.Total).DefaultIfEmpty().Max();
        int offset=days.Count==0?0:(int)days[0].Date.DayOfWeek;int columns=(offset+days.Count+6)/7;
        for(int n=0;n<columns;n++)grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(24)});for(int n=0;n<7;n++)grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(24)});
        for(int n=0;n<days.Count;n++){var d=days[n];int i=d.Intensity(peak);var box=new Border{Width=19,Height=19,CornerRadius=new CornerRadius(3),Background=new SolidColorBrush((Color)ColorConverter.ConvertFromString(i==0&&dark?"#37414B":Colors[i])),ToolTip=$"{d.Date:yyyy-MM-dd} · {t(d.Cost.Money)} USD · {d.Usage.Total:N0} tokens · {d.Responses} {t("调用次数")}"};Grid.SetColumn(box,(n+offset)/7);Grid.SetRow(box,(n+offset)%7);grid.Children.Add(box);}row.Children.Add(grid);
        var cost=days.Aggregate(new CostEstimate(),(a,d)=>a+d.Cost);row.Children.Add(new TextBlock{Text=t(cost.Money)+" USD · "+Compact(days.Sum(d=>d.Usage.Total))+" tokens",FontSize=12,Foreground=fg,Margin=new Thickness(0,8,0,0)});row.Children.Add(new TextBlock{Text=$"{days.Count(d=>d.Usage.Total>0)}/30 {t("活跃天数")}"+(days.Count>0?$" · {days[0].Date:MM/dd} — {days[^1].Date:MM/dd}":""),FontSize=9,Foreground=fg,Margin=new Thickness(0,4,0,0)});return row;
    }
    public static FrameworkElement Card(ShareSnapshot s,string title,bool showName,bool dark,Func<string,string> t){
        var fg=new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark?"#E8EEF5":"#17212B"));var muted=new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark?"#A6B2BF":"#687681"));
        var panel=new Canvas{Background=new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark?"#151B22":"#FFFFFF")),Width=360,Height=480,ClipToBounds=true};
        void Add(UIElement element,double x,double y){Canvas.SetLeft(element,x);Canvas.SetTop(element,y);panel.Children.Add(element);}
        TextBlock Text(string v,double size,bool bold=false,double width=316)=>new(){Text=v,Foreground=fg,FontSize=size,Width=width,FontWeight=bold?FontWeights.SemiBold:FontWeights.Normal,TextWrapping=TextWrapping.Wrap};
        Add(Text("▥  Codex Ledger",12,true),22,22);Add(Text("LOCAL",8,true,40),298,24);
        string name=title.Trim();if(name.Length==0)name=showName?s.PrivateTitle:t(s.Kind);name=name[..Math.Min(120,name.Length)];var heading=Text(name,23,true);heading.Height=57;heading.TextTrimming=TextTrimming.CharacterEllipsis;heading.ClipToBounds=true;Add(heading,22,48);
        Add(Text(t("预估 API 花费")+" · USD",10),22,112);
        var amount=new Viewbox{Width=316,Height=47,Stretch=Stretch.Uniform,StretchDirection=StretchDirection.DownOnly,HorizontalAlignment=HorizontalAlignment.Left,Child=new TextBlock{Text=t(s.Cost.Money),FontSize=38,FontWeight=FontWeights.SemiBold,Foreground=fg}};Add(amount,22,128);
        Add(Text(s.Range+(s.Filtered?" · "+t("已筛选"):""),10),22,181);Add(Text($"{Compact(s.Usage.Total)} tokens · {s.Turns} {t("任务轮次")} · {s.Models} {t("模型")}",10),22,201);
        if(s.CompletionCost!=null)Add(Text(t("完成时")+": "+t(s.CompletionCost.Money)+" USD",10),22,221);
        double y=s.CompletionCost==null?232:250;
        var board=new Canvas{Width=316,Height=136,Background=new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark?"#232C35":"#F2F5F8"))};
        void Board(UIElement e,double x,double top){Canvas.SetLeft(e,x);Canvas.SetTop(e,top);board.Children.Add(e);}
        Board(Text(t("近 30 天"),10,true,130),12,9);int offset=s.Days.Count==0?0:(int)s.Days[0].Date.DayOfWeek;long peak=s.Days.Select(d=>d.Usage.Total).DefaultIfEmpty().Max();
        for(int n=0;n<s.Days.Count;n++){int i=s.Days[n].Intensity(peak);Board(new Border{Width=11,Height=11,CornerRadius=new CornerRadius(2),Background=new SolidColorBrush((Color)ColorConverter.ConvertFromString(i==0&&dark?"#37414B":Colors[i]))},12+(n+offset)/7*13,27+(n+offset)%7*13);}
        var month=Text(t(s.MonthlyCost.Money)+" USD",15,true,185);month.TextAlignment=TextAlignment.Right;Board(month,119,48);var tokens=Text(Compact(s.MonthlyUsage.Total)+" tokens",9,false,185);tokens.TextAlignment=TextAlignment.Right;Board(tokens,119,70);var active=Text($"{s.ActiveDays}/30 {t("活跃天数")}",9,false,185);active.TextAlignment=TextAlignment.Right;Board(active,119,91);
        if(s.Days.Count>0)Board(Text($"{s.Days[0].Date:MM/dd} — {s.Days[^1].Date:MM/dd} · {s.Timezone}",7,false,292),12,123);Add(new Border{Child=board,CornerRadius=new CornerRadius(12),ClipToBounds=true},22,y);
        using var qr=new QRCodeGenerator();using var data=qr.CreateQrCode(ShareSnapshot.DownloadURL,QRCodeGenerator.ECCLevel.M);using var png=new PngByteQRCode(data);var bytes=png.GetGraphic(8);var image=new BitmapImage();using(var stream=new MemoryStream(bytes)){image.BeginInit();image.CacheOption=BitmapCacheOption.OnLoad;image.StreamSource=stream;image.EndInit();image.Freeze();}
        Add(new Image{Source=image,Width=59,Height=59},22,397);Add(Text(t("扫码下载 · Mac / Windows"),10,true,240),91,405);Add(Text("zhangligong0826.github.io/codex-ledger",7,false,240),91,423);Add(Text(t("本地统计 · MIT 开源"),8,false,240),91,439);
        var note=Text(t("API 成本估算，非实际账单")+" · "+s.PriceDate+(s.Warning?" · "+t("部分日志不可读"):"")+(s.Cost.UnpricedTokens>0||s.MonthlyCost.UnpricedTokens>0?" · "+t("含未计价用量"):""),7);note.Foreground=muted;Add(note,22,460);return panel;
    }
}
public sealed class ShareWindow : Window {
    private readonly LedgerState state;private readonly ShareSnapshot? snapshot;private readonly BitmapSource? capture;
    private readonly Image image=new(){Width=315,Height=420,Stretch=Stretch.Uniform};private readonly TextBox title=new(){MaxLength=120,Margin=new Thickness(0,8,0,8)};private readonly CheckBox showName=new(),dark=new();private readonly TextBlock status=new(){Margin=new Thickness(0,6,0,0)};private BitmapSource? bitmap;
    public ShareWindow(LedgerState state,ShareSnapshot? snapshot,BitmapSource? capture){this.state=state;this.snapshot=snapshot;this.capture=capture;Title=state.T(snapshot==null?"当前界面截图":"分享卡片");Width=430;Height=650;ResizeMode=ResizeMode.NoResize;WindowStartupLocation=WindowStartupLocation.CenterOwner;var p=new StackPanel{Margin=new Thickness(18)};p.Children.Add(image);
        if(snapshot!=null){title.ToolTip=state.T("公开标题（可选）");p.Children.Add(title);showName.Content=state.T("显示原始名称");dark.Content=state.T("深色卡片");dark.IsChecked=state.Dark;p.Children.Add(showName);p.Children.Add(dark);p.Children.Add(new TextBlock{Text=state.T("默认隐藏名称、路径和对话标题。请确认预览后分享。"),TextWrapping=TextWrapping.Wrap,FontSize=11,Margin=new Thickness(0,8,0,4)});title.TextChanged+=(_,_)=>Update();showName.Click+=(_,_)=>Update();dark.Click+=(_,_)=>Update();}
        else p.Children.Add(new TextBlock{Text=state.T("截图包含当前可见的名称和标题，请确认预览后分享。"),TextWrapping=TextWrapping.Wrap,FontSize=11,Margin=new Thickness(0,10,0,10)});
        var actions=new StackPanel{Orientation=Orientation.Horizontal};var copy=new Button{Content=state.T("复制图片"),Padding=new Thickness(10,6,10,6),Margin=new Thickness(3)};copy.Click+=(_,_)=>{try{Clipboard.SetImage(bitmap!);status.Text=state.T("已复制");}catch(Exception){status.Text=state.T("复制失败，请重试");}};actions.Children.Add(copy);var save=new Button{Content=state.T("保存 PNG…"),Padding=new Thickness(10,6,10,6),Margin=new Thickness(3)};save.Click+=(_,_)=>{var dialog=new Microsoft.Win32.SaveFileDialog{Filter="PNG (*.png)|*.png",FileName="Codex-Ledger-Share.png"};if(dialog.ShowDialog(this)==true)try{ShareRendering.Save(bitmap!,dialog.FileName);status.Text=state.T("已保存");}catch(Exception){status.Text=state.T("保存失败，请重试");}};actions.Children.Add(save);p.Children.Add(actions);p.Children.Add(status);Content=new ScrollViewer{Content=p,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};Update();}
    private void Update(){bitmap=capture??(snapshot!=null?ShareRendering.Render(ShareRendering.Card(snapshot,title.Text,showName.IsChecked==true,dark.IsChecked==true,state.T),360,480,3):null);image.Source=bitmap;}
}
