using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using CodexLedger;
using Forms=System.Windows.Forms;

namespace CodexLedger.Windows;
public static class Program {
    [STAThread] public static int Main(string[] args) {
        if(args.Contains("--diagnose")) {var scanner=new LedgerScanner();var source=Environment.GetEnvironmentVariable("CODEX_LEDGER_SOURCE")??Environment.GetEnvironmentVariable("CODEX_HOME")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".codex");var result=scanner.Scan(source);var scope=args.FirstOrDefault(x=>x.StartsWith("--scope="))?[8..]??"today";var snap=scanner.Snapshot(result.Logs,scope switch{"yesterday"=>DateScope.Yesterday,"7d"=>DateScope.Week,"30d"=>DateScope.Month,"all"=>DateScope.All,_=>DateScope.Today},DateTimeOffset.Now,result.Warnings);var month=scanner.Snapshot(result.Logs,DateScope.Month,DateTimeOffset.Now);Console.WriteLine(JsonSerializer.Serialize(new{total=snap.Usage.Total,input=snap.Usage.Input,output=snap.Usage.Output,cached=snap.Usage.Cached,reasoning=snap.Usage.Reasoning,tasks=snap.Turns.Count,estimatedAPIUSD=snap.Cost.TotalUSD.ToString(CultureInfo.InvariantCulture),pricedTokens=snap.Cost.PricedTokens,unpricedTokens=snap.Cost.UnpricedTokens,pricingDate=Pricing.Date,dailyUsage=scanner.Daily(month.Turns,DateTimeOffset.Now),warnings=snap.Warnings},Json.Options));return 0;}
        bool smoke=args.Contains("--ui-smoke");using var mutex=new Mutex(true,"Local\\CodexLedger-"+Environment.UserName,out bool first);
        if(!first&&!smoke)return 0;
        var app=new System.Windows.Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};var state=new LedgerState(smoke);var window=new MainWindow(state);Forms.NotifyIcon? tray=null;
        app.Startup+=async(_,_)=>{
            if(smoke){try{await SmokeChecks.Run(window,state,args);app.Shutdown(0);}catch(Exception e){Console.Error.WriteLine(e);app.Shutdown(1);}return;}
            tray=new Forms.NotifyIcon{Icon=System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!)??System.Drawing.SystemIcons.Application,Text="Codex Ledger",Visible=true};
            var menu=new Forms.ContextMenuStrip();menu.Items.Add("Codex Ledger",null,(_,_)=>window.ShowOverview());menu.Items.Add(state.T("打开工作账本"),null,(_,_)=>window.ShowDashboard());menu.Items.Add(state.T("退出 Codex Ledger"),null,(_,_)=>app.Shutdown());tray.ContextMenuStrip=menu;
            tray.MouseClick+=(_,e)=>{if(e.Button==Forms.MouseButtons.Left)window.ShowOverview();};
            state.Updated+=()=>{var c=state.Today.Cost;tray.Text=("Codex Ledger · "+state.T(c.Money)+" USD")[..Math.Min(63,("Codex Ledger · "+state.T(c.Money)+" USD").Length)];};
            var timer=new DispatcherTimer{Interval=TimeSpan.FromSeconds(30)};timer.Tick+=async(_,_)=>await state.Refresh();timer.Start();
            await state.Refresh();if(args.Contains("--show-dashboard"))window.ShowDashboard();
        };
        app.Exit+=(_,_)=>{if(tray!=null){tray.Visible=false;tray.Dispose();}};return app.Run();
    }
}
public sealed class Preferences {public string Language{get;set;}="en";public string Appearance{get;set;}="system";public string Source{get;set;}=Environment.GetEnvironmentVariable("CODEX_HOME")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".codex");public bool LaunchAtLogin{get;set;}public Dictionary<string,string> Categories{get;set;}=[];}
public sealed class LedgerState {
    public Preferences Prefs=new();public GoalBook Book=new();public bool BookReadable=true,PreferencesReadable=true,Ready,Busy;
    public Snapshot Current=new([],[],0,0),Lifetime=new([],[],0,0),Month=new([],[],0,0),Today=new([],[],0,0);
    public IReadOnlyList<ParsedLog> Logs=[];public Dictionary<string,string> Titles=[];public string Error="";
    public string Page="goals",Search="";public DateScope Scope=DateScope.Today;public string? GoalID,ProjectID,ChatID,Model,Category;public bool UnassignedOnly;
    public readonly LedgerScanner Scanner=new();public event Action? Updated;
    private readonly bool isolated;private readonly Dictionary<string,string> strings;
    public LedgerState(bool isolated=false) {
        this.isolated=isolated;using var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("CodexLedger.strings.json")!;strings=JsonSerializer.Deserialize<Dictionary<string,string>>(stream)!;
        if(!isolated){try{var path=Path.Combine(LocalFiles.DataDirectory,"preferences.json");if(File.Exists(path))Prefs=JsonSerializer.Deserialize<Preferences>(File.ReadAllText(path),Json.Options)??throw new InvalidDataException();}catch(Exception e)when(e is IOException or JsonException or InvalidDataException){PreferencesReadable=false;Error="设置无法读取，原有数据已保留。";}LoadBook();}
    }
    public string T(string text)=>Prefs.Language=="zh"?text:strings.GetValueOrDefault(text)??text;
    public bool Dark=>Prefs.Appearance=="dark" || (Prefs.Appearance=="system"&&(Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize","AppsUseLightTheme",1) as int?)==0);
    public void Notify()=>Updated?.Invoke();
    public void SavePreferences(){if(isolated||!PreferencesReadable)return;try{LocalFiles.AtomicWrite(Path.Combine(LocalFiles.DataDirectory,"preferences.json"),JsonSerializer.Serialize(Prefs,Json.Options));}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error="设置保存失败，请重试。";} }
    public void LoadBook(){Book=new();BookReadable=true;try{var path=LocalFiles.GoalFile(Prefs.Source);if(File.Exists(path))Book=GoalBook.Decode(File.ReadAllText(path));}catch(Exception e)when(e is IOException or JsonException or InvalidDataException or UnauthorizedAccessException){BookReadable=false;Error="目标账本无法读取，原有数据已保留。";} }
    public void SaveBook(){if(isolated)return;if(!BookReadable){Error="目标账本无法读取，原有数据已保留。";return;}try{LocalFiles.AtomicWrite(LocalFiles.GoalFile(Prefs.Source),JsonSerializer.Serialize(Book,Json.Options));}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error="目标账本无法保存。";}Notify();}
    public async Task Refresh() {
        if(Busy)return;Busy=true;Notify();var source=Prefs.Source;var scope=Scope;var categories=new Dictionary<string,string>(Prefs.Categories);
        try {var result=await Task.Run(()=>{var scanned=Scanner.Scan(source);var now=DateTimeOffset.Now;return(scanned,all:Scanner.Snapshot(scanned.Logs,DateScope.All,now,scanned.Warnings,categories),today:Scanner.Snapshot(scanned.Logs,DateScope.Today,now,scanned.Warnings,categories),month:Scanner.Snapshot(scanned.Logs,DateScope.Month,now,scanned.Warnings,categories),current:Scanner.Snapshot(scanned.Logs,scope,now,scanned.Warnings,categories),titles:ConversationMetadata.Titles(source));});
            if(source!=Prefs.Source)return;Logs=result.scanned.Logs;Lifetime=result.all;Today=result.today;Month=result.month;Current=result.current;Titles=result.titles;foreach(var log in Logs)if(!Titles.ContainsKey(log.SessionID)&&log.FirstPrompt.Length>0)Titles[log.SessionID]=log.FirstPrompt;Ready=true;
        }catch(Exception e){Ready=false;Error=T("读取失败")+": "+e.Message;}finally{Busy=false;if(Ready&&scope!=Scope)SetScope(Scope);Notify();}
    }
    public void SetScope(DateScope scope){Scope=scope;if(Ready&&!Busy){var range=Dates.Interval(scope,DateTimeOffset.Now,Scanner.Zone);Current=new(Lifetime.Turns.Select(t=>Slice(t,range.Start,range.End)).Where(t=>t!=null).Cast<LedgerTurn>().OrderByDescending(t=>t.Usage.Total).ToArray(),Lifetime.Warnings,Lifetime.Files,Lifetime.Malformed);Notify();}}
    private static LedgerTurn? Slice(LedgerTurn turn,DateTimeOffset start,DateTimeOffset end){var s=turn.Samples.Where(s=>s.Date>=start&&s.Date<end).ToArray();return s.Length==0?null:turn with{Usage=s.Aggregate(new TokenUsage(),(a,x)=>a+x.Usage),Date=s.Min(x=>x.Date),LastActivity=s.Max(x=>x.Date),Responses=s.Length,SubagentResponses=s.Count(x=>x.SessionID!=turn.SessionID),Samples=s};}
    public void Navigate(string page){Page=page;GoalID=null;ProjectID=null;ChatID=null;Clear();}
    public void Clear(){Search="";Category=null;Model=null;UnassignedOnly=false;Notify();}
    public void Back(){if(ChatID!=null)ChatID=null;else if(ProjectID!=null)ProjectID=null;else GoalID=null;Clear();}
    public IReadOnlyList<LedgerTurn> Context(IReadOnlyList<LedgerTurn>? input=null,bool overview=false) {
        var rows=input??Current.Turns;if(overview)return rows;
        return rows.Where(t=>(GoalID==null||Book.Owner(t)==GoalID)&&(ProjectID==null||t.Project.ID==ProjectID)&&(ChatID==null||t.SessionID==ChatID)&&(!UnassignedOnly||Book.Owner(t)==null)&&(Page!="goals"||GoalID!=null||UnassignedOnly||Book.Owner(t)!=null)).ToArray();
    }
    public IReadOnlyList<LedgerTurn> Filter(IReadOnlyList<LedgerTurn> rows)=>rows.Where(t=>(Category==null||Category==t.Category)&&(Model==null||t.Models.Contains(Model))&&(Search.Length==0||new[]{t.Title,t.WorkingDirectory,t.Project.Name,t.Project.Path,t.SessionID,string.Join(" ",t.Models)}.Any(x=>x.Contains(Search,StringComparison.OrdinalIgnoreCase)))).ToArray();
    public string ChatTitle(string id)=>Titles.GetValueOrDefault(id)??Lifetime.Turns.Where(t=>t.SessionID==id).OrderBy(t=>t.Date).FirstOrDefault()?.Title??T("未记录用户请求");
    public string Kind(bool overview=false)=>overview?"用量总览":ChatID!=null?"对话用量":GoalID!=null?"目标花费":ProjectID!=null?"项目用量":Page=="goals"?"目标账本":"用量总览";
    public string Title=>ChatID!=null?ChatTitle(ChatID):GoalID!=null?Book.Goals.FirstOrDefault(g=>g.ID==GoalID)?.Name??T("目标账本"):ProjectID!=null?Lifetime.Turns.FirstOrDefault(t=>t.Project.ID==ProjectID)?.Project.Name??T("项目"):T(Page switch{"projects"=>"项目","conversations"=>"对话","tasks"=>"全部任务","models"=>"模型用量","settings"=>"设置",_=>"目标账本"});
    public string Range=>T(Scope switch{DateScope.Yesterday=>"昨天",DateScope.Week=>"近 7 天",DateScope.Month=>"近 30 天",DateScope.All=>"历史累计",_=>"今天"});
    public bool Known=>Ready&&(Current.Warnings.Count==0||Lifetime.Turns.Count>0);
    public bool CanShare=>Ready&&!Busy&&(Current.Warnings.Count==0||Lifetime.Turns.Count>0);
    public ShareSnapshot Share(bool overview=false) {
        if(!CanShare)throw new InvalidOperationException(T("正在整理日志，请稍候"));bool goalList=!overview&&Page=="goals"&&GoalID==null&&ChatID==null;
        var matchingGoals=Book.Goals.Where(g=>Search.Length==0||g.Name.Contains(Search,StringComparison.OrdinalIgnoreCase)).Select(g=>g.ID).ToHashSet();
        var turns=overview?Current.Turns:goalList?Current.Turns.Where(t=>Book.Owner(t) is string id&&matchingGoals.Contains(id)).ToArray():Filter(Context());
        var monthly=overview?Month.Turns:goalList?Month.Turns.Where(t=>Book.Owner(t) is string id&&matchingGoals.Contains(id)).ToArray():Filter(Context(Month.Turns));var goal=Book.Goals.FirstOrDefault(g=>g.ID==GoalID);
        return new(Kind(overview),overview?T("用量总览"):Title,Range,Scanner.Zone.Id,turns.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage),turns.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),turns.Count,turns.Select(t=>t.SessionID).Distinct().Count(),turns.SelectMany(t=>t.Models).Where(m=>m!="未知模型").Distinct().Count(),Scanner.Daily(monthly,DateTimeOffset.Now).ToArray(),!overview&&ChatID==null?goal?.CompletionCost:null,goal?.CompletedAt,goal?.CompletionPriceDate,!overview&&(Search.Length>0||Category!=null||Model!=null||UnassignedOnly),Current.Warnings.Count>0,Pricing.Date);
    }
}
