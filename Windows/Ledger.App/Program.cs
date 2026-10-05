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
        if(args.Contains("--check-storage")){var check=new LedgerState();Console.WriteLine(JsonSerializer.Serialize(new{preferencesReadable=check.PreferencesReadable,bookReadable=check.BookReadable,language=check.Prefs.Language,goals=check.Book.Goals.Count,completed=check.Book.Goals.Count(g=>g.CompletedAt!=null),completionUSD=check.Book.Goals.FirstOrDefault(g=>g.CompletedAt!=null)?.CompletionCost?.TotalUSD,completionPriceDate=check.Book.Goals.FirstOrDefault(g=>g.CompletedAt!=null)?.CompletionPriceDate,bookVersion=check.Book.Version,completionRecords=check.Book.Goals.Sum(g=>g.Completions.Count),legacyRecords=check.Book.Goals.Sum(g=>g.Completions.Count(c=>c.Legacy))},Json.Options));return check.PreferencesReadable&&check.BookReadable?0:1;}
        bool smoke=args.Contains("--ui-smoke");using var mutex=new Mutex(true,"Local\\CodexLedger-"+Environment.UserName,out bool first);
        if(!first&&!smoke){if(!AppInstance.Send(args.Contains("--show-dashboard")?"dashboard":"overview"))MessageBox.Show("Codex Ledger is already running in the system tray.");return 0;}
        var app=new System.Windows.Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};var state=new LedgerState(smoke);var window=new MainWindow(state);Forms.NotifyIcon? tray=null;using var cancel=new CancellationTokenSource();
        app.Startup+=async(_,_)=>{
            if(smoke){try{await SmokeChecks.Run(window,state,args);app.Shutdown(0);}catch(Exception e){Console.Error.WriteLine(e);app.Shutdown(1);}return;}
            _ = AppInstance.Listen(command=>app.Dispatcher.BeginInvoke(new Action(()=>{if(command=="dashboard")window.ShowDashboard();else window.ShowOverview();})),cancel.Token);
            tray=new Forms.NotifyIcon{Icon=System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!)??System.Drawing.SystemIcons.Application,Text="Codex Ledger",Visible=true};
            var menu=new Forms.ContextMenuStrip();menu.Items.Add("Codex Ledger",null,(_,_)=>window.ShowOverview());menu.Items.Add(state.T("打开工作账本"),null,(_,_)=>window.ShowDashboard());menu.Items.Add(state.T("退出 Codex Ledger"),null,(_,_)=>app.Shutdown());tray.ContextMenuStrip=menu;
            tray.MouseClick+=(_,e)=>{if(e.Button==Forms.MouseButtons.Left)window.ShowOverview();};
            state.Updated+=()=>{menu.Items[1].Text=state.T("打开工作账本");menu.Items[2].Text=state.T("退出 Codex Ledger");var c=state.Today.Cost;tray.Text=("Codex Ledger · "+state.T(c.Money)+" USD")[..Math.Min(63,("Codex Ledger · "+state.T(c.Money)+" USD").Length)];};
            var timer=new DispatcherTimer{Interval=TimeSpan.FromSeconds(30)};timer.Tick+=async(_,_)=>await state.Refresh();timer.Start();
            await state.Refresh();if(args.Contains("--show-dashboard"))window.ShowDashboard();
        };
        app.Exit+=(_,_)=>{cancel.Cancel();if(tray!=null){tray.Visible=false;tray.Dispose();}};return app.Run();
    }
}
public sealed class Preferences {public DateScope OverviewScope{get;set;}=DateScope.Today;public DateScope DashboardScope{get;set;}=DateScope.Today;public string Language{get;set;}="en";public string Appearance{get;set;}="system";public string Source{get;set;}=Environment.GetEnvironmentVariable("CODEX_HOME")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".codex");public bool LaunchAtLogin{get;set;}public string HeatmapMetric{get;set;}="tokens";public Dictionary<string,string> Categories{get;set;}=[];
    public void Validate(){if(string.IsNullOrWhiteSpace(Source)||Language is not("en" or "zh")||Appearance is not("system" or "light" or "dark")||Categories==null||Categories.Any(x=>x.Key==null||x.Value==null)||HeatmapMetric is not("tokens" or "cost")||!Enum.IsDefined(OverviewScope)||!Enum.IsDefined(DashboardScope))throw new InvalidDataException("Invalid preferences");}}
public sealed record ViewContext(string Page,string? Goal,string? Project,string? Chat,DateScope Scope,string Search,string? Category,string? Model,bool Unassigned,DateOnly? Day,string Sort="cost",double Scroll=0);
public sealed class LedgerState {
    public Preferences Prefs=new();public GoalBook Book=new();public bool BookReadable=true,PreferencesReadable=true,Ready,Busy;
    public Snapshot Current=new([],[],0,0),Lifetime=new([],[],0,0),Month=new([],[],0,0),Today=new([],[],0,0);
    public IReadOnlyList<ParsedLog> Logs=[];public Dictionary<string,string> Titles=[];public string Error="";
    public string Page="goals",Search="";public DateScope Scope=DateScope.Today;public string? GoalID,ProjectID,ChatID,Model,Category;public bool UnassignedOnly;
    public DateOnly? Day;public double Scroll;public string Sort="cost";
    public DateScope OverviewScope=DateScope.Today,DashboardScope=DateScope.Today,PublishedScope=DateScope.Today;
    private readonly Stack<ViewContext> history=new();private readonly Dictionary<string,ViewContext> pages=[];
    private readonly Stack<string> undoBooks=new();
    public ViewContext View=>new(Page,GoalID,ProjectID,ChatID,Scope,Search,Category,Model,UnassignedOnly,Day,Sort,Scroll);
    private void Restore(ViewContext c){Page=c.Page;GoalID=c.Goal;ProjectID=c.Project;ChatID=c.Chat;Search=c.Search;Category=c.Category;Model=c.Model;UnassignedOnly=c.Unassigned;Day=c.Day;Sort=c.Sort;Scroll=c.Scroll;SetScope(c.Scope);}
    public void Enter(string? goal=null,string? project=null,string? chat=null){history.Push(View);if(goal!=null)GoalID=goal;if(project!=null)ProjectID=project;if(chat!=null)ChatID=chat;Scroll=0;Clear();}
    public void Apply(AttributionRule rule){undoBooks.Push(JsonSerializer.Serialize(Book,Json.Options));Book.Apply(rule);SaveBook();Notify();}
    public void Undo(){if(undoBooks.TryPop(out var data)){var old=GoalBook.Decode(data);Book.Rules=old.Rules;Book.Bindings=old.Bindings;
        for(int i=0;i<Book.Rules.Count;i++)if(!Book.Rules[i].Legacy&&Book.Rules[i].Mode!="selected"&&Book.Rules[i].End==null&&Book.Goals.FirstOrDefault(g=>g.ID==Book.Rules[i].GoalID)?.CompletedAt is {} at)Book.Rules[i]=Book.Rules[i] with{End=at};SaveBook();Notify();}}
    public bool CanUndo=>undoBooks.Count>0;
    public readonly LedgerScanner Scanner=new();public event Action? Updated;
    private readonly bool isolated;private readonly Dictionary<string,string> strings;
    public LedgerState(bool isolated=false) {
        this.isolated=isolated;using var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("CodexLedger.strings.json")!;strings=JsonSerializer.Deserialize<Dictionary<string,string>>(stream)!;
        if(!isolated){try{var path=Path.Combine(LocalFiles.DataDirectory,"preferences.json");if(File.Exists(path))Prefs=JsonSerializer.Deserialize<Preferences>(File.ReadAllText(path),Json.Options)??throw new InvalidDataException();Prefs.Validate();}catch(Exception e)when(e is IOException or JsonException or InvalidDataException or UnauthorizedAccessException){Prefs=new();PreferencesReadable=false;Error="设置无法读取，原有数据已保留。";}OverviewScope=Prefs.OverviewScope;DashboardScope=Prefs.DashboardScope;Scope=DashboardScope;LoadBook();}
    }
    public string T(string text)=>Prefs.Language=="zh"?text:strings.GetValueOrDefault(text)??text;
    public bool Dark=>Prefs.Appearance=="dark" || (Prefs.Appearance=="system"&&(Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize","AppsUseLightTheme",1) as int?)==0);
    public void Notify()=>Updated?.Invoke();
    public void SavePreferences(){Prefs.OverviewScope=OverviewScope;Prefs.DashboardScope=DashboardScope;if(isolated||!PreferencesReadable)return;try{LocalFiles.AtomicWrite(Path.Combine(LocalFiles.DataDirectory,"preferences.json"),JsonSerializer.Serialize(Prefs,Json.Options));}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error="设置保存失败，请重试。";} }
    public void LoadBook(){Book=new();BookReadable=true;try{var path=LocalFiles.GoalFile(Prefs.Source);var legacy=File.Exists(LocalFiles.V1GoalFile(Prefs.Source))?LocalFiles.V1GoalFile(Prefs.Source):LocalFiles.LegacyGoalFile(Prefs.Source);if(!File.Exists(path)&&File.Exists(legacy)){var old=File.ReadAllText(legacy);var migrated=GoalBook.Decode(old);LocalFiles.Backup(legacy);LocalFiles.AtomicWrite(legacy+".v1-original",old);LocalFiles.AtomicWrite(path,JsonSerializer.Serialize(migrated,Json.Options));}if(File.Exists(path))Book=GoalBook.Decode(File.ReadAllText(path));}catch(Exception e)when(e is IOException or JsonException or InvalidDataException or UnauthorizedAccessException){BookReadable=false;Error="目标账本无法读取，原有数据已保留。";} }
    public void SaveBook(){if(isolated)return;if(!BookReadable){Error="目标账本无法读取，原有数据已保留。";return;}try{var path=LocalFiles.GoalFile(Prefs.Source);LocalFiles.Backup(path);LocalFiles.AtomicWrite(path,JsonSerializer.Serialize(Book,Json.Options));}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error="账本备份或保存失败，原有数据未覆盖。";try{Book=GoalBook.Decode(File.ReadAllText(LocalFiles.GoalFile(Prefs.Source)));}catch{BookReadable=false;}}Notify();}
    public async Task Refresh() {
        if(Busy)return;Busy=true;Notify();var source=Prefs.Source;var scope=Scope;
        try {var categories=new Dictionary<string,string>(Prefs.Categories);var result=await Task.Run(()=>{var scanned=Scanner.Scan(source);var now=DateTimeOffset.Now;return(scanned,all:Scanner.Snapshot(scanned.Logs,DateScope.All,now,scanned.Warnings,categories),today:Scanner.Snapshot(scanned.Logs,DateScope.Today,now,scanned.Warnings,categories),month:Scanner.Snapshot(scanned.Logs,DateScope.Month,now,scanned.Warnings,categories),current:Scanner.Snapshot(scanned.Logs,scope,now,scanned.Warnings,categories),titles:ConversationMetadata.Titles(source));});
            if(source!=Prefs.Source)return;Logs=result.scanned.Logs;Lifetime=result.all;Today=result.today;Month=result.month;Current=result.current;PublishedScope=scope;Titles=result.titles;foreach(var log in Logs)if(!Titles.ContainsKey(log.SessionID)&&log.FirstPrompt.Length>0)Titles[log.SessionID]=log.FirstPrompt;Ready=true;
        }catch(Exception e){Ready=false;Error=T("读取失败")+": "+e.Message;}finally{Busy=false;if(Ready&&scope!=Scope)SetScope(Scope);Notify();}
    }
    public void SetScope(DateScope scope){if(scope==Scope&&PublishedScope==scope&&Ready){Notify();return;}Scope=scope;if(Ready&&!Busy){Current=Scanner.Snapshot(Logs,scope,Lifetime.CapturedAt,Lifetime.HasReadFailures?Lifetime.Warnings.Except(Lifetime.LogIssues.SelectMany(i=>i.Messages)).ToArray():[],Prefs.Categories);PublishedScope=scope;Notify();}}
    private static LedgerTurn? Slice(LedgerTurn turn,DateTimeOffset start,DateTimeOffset end){var s=turn.Samples.Where(s=>s.Date>=start&&s.Date<end).ToArray();return s.Length==0?null:turn with{Usage=s.Aggregate(new TokenUsage(),(a,x)=>a+x.Usage),Date=s.Min(x=>x.Date),LastActivity=s.Max(x=>x.Date),Responses=s.Length,SubagentResponses=s.Count(x=>x.SessionID!=turn.SessionID),Samples=s};}
    public void ResetNavigation(){history.Clear();pages.Clear();Scroll=0;}
    public void Navigate(string page){pages[Page]=View;history.Clear();if(pages.TryGetValue(page,out var c)){Restore(c);return;}Page=page;GoalID=null;ProjectID=null;ChatID=null;Scroll=0;Clear();}
    public void Clear(){Search="";Category=null;Model=null;Day=null;UnassignedOnly=false;Notify();}
    public void Back(){if(history.TryPop(out var c)){Restore(c);return;}if(ChatID!=null)ChatID=null;else if(ProjectID!=null)ProjectID=null;else GoalID=null;Clear();}
    public IReadOnlyList<LedgerTurn> Context(IReadOnlyList<LedgerTurn>? input=null,bool overview=false) {
        var rows=input??Current.Turns;if(overview)return rows;
        return rows.Where(t=>(GoalID==null||Book.Owner(t)==GoalID)&&(ProjectID==null||t.Project.ID==ProjectID)&&(ChatID==null||t.SessionID==ChatID)&&(!UnassignedOnly||Book.Owner(t)==null)&&(Page!="goals"||GoalID!=null||UnassignedOnly||Book.Owner(t)!=null)).ToArray();
    }
    public IReadOnlyList<LedgerGoal> MatchingGoals()=>Book.Goals.Where(g=>Search.Length==0||g.Name.Contains(Search,StringComparison.OrdinalIgnoreCase)||Lifetime.Turns.Where(t=>Book.Owner(t)==g.ID).Any(t=>new[]{t.Title,t.Project.Path,t.WorkingDirectory}.Any(v=>v.Contains(Search,StringComparison.OrdinalIgnoreCase)))).ToArray();
    public IReadOnlyList<LedgerTurn> Selected(bool overview=false) {
        var rows=overview?Current.Turns:Filter(Context());if(Day is not {} day||overview)return rows;
        return rows.Select(t=> {var samples=t.Samples.Where(s=>DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(s.Date,Scanner.Zone).Date)==day).ToArray();return t with{Samples=samples,Usage=samples.Aggregate(new TokenUsage(),(a,s)=>a+s.Usage),Responses=samples.Length};}).Where(t=>t.Samples.Count>0).ToArray();
    }
    public IReadOnlyList<LedgerTurn> Filter(IReadOnlyList<LedgerTurn> rows) {
        bool Match(string value)=>Search.Length==0||value.Contains(Search,StringComparison.OrdinalIgnoreCase);
        IEnumerable<LedgerTurn> result=rows;
        if(Page=="models"&&ChatID==null) {
            return rows.Where(t=>Category==null||Category==t.Category).Select(t=>{
                var samples=t.Samples.Where(s=>(Model==null||s.Model==Model)&&Match(s.Model)).ToArray();
                return t with{Samples=samples,Usage=samples.Aggregate(new TokenUsage(),(u,s)=>u+s.Usage),Responses=samples.Length};
            }).Where(t=>t.Samples.Count>0).ToArray();
        }
        if(Page=="goals"&&GoalID==null&&ChatID==null){var ids=MatchingGoals().Select(g=>g.ID).ToHashSet();result=result.Where(t=>Book.Owner(t) is string id&&ids.Contains(id));}
        else if(Page=="projects"&&ProjectID==null&&ChatID==null){var ids=rows.Where(t=>Match(T(t.Project.Name))||Match(t.Project.Path)).Select(t=>t.Project.ID).ToHashSet();result=result.Where(t=>ids.Contains(t.Project.ID));}
        else if(ChatID==null&&(Page=="conversations"||ProjectID!=null||GoalID!=null)){
            var ids=rows.Where(t=>new[]{ChatTitle(t.SessionID),t.SessionID,t.Project.Path,string.Join(" ",t.Models)}.Any(Match)).Select(t=>t.SessionID).ToHashSet();result=result.Where(t=>ids.Contains(t.SessionID));
        }
        else result=result.Where(t=>new[]{t.Title,t.WorkingDirectory,t.Project.Name,t.Project.Path,t.SessionID,ChatTitle(t.SessionID),string.Join(" ",t.Models)}.Any(Match));
        return result.Where(t=>Category==null||Category==t.Category).Select(t=>{
            if(Model==null)return t;var samples=t.Samples.Where(s=>s.Model==Model).ToArray();return t with{Samples=samples,Usage=samples.Aggregate(new TokenUsage(),(a,s)=>a+s.Usage),Responses=samples.Length};
        }).Where(t=>t.Samples.Count>0).ToArray();
    }
    public string ChatTitle(string id)=>Titles.GetValueOrDefault(id)??Lifetime.Turns.Where(t=>t.SessionID==id).OrderBy(t=>t.Date).FirstOrDefault()?.Title??T("未记录用户请求");
    public string Kind(bool overview=false)=>overview?"用量总览":ChatID!=null?"对话用量":GoalID!=null?"目标花费":ProjectID!=null?"项目用量":Page=="goals"?"目标账本":"用量总览";
    public string Title=>ChatID!=null?ChatTitle(ChatID):GoalID!=null?Book.Goals.FirstOrDefault(g=>g.ID==GoalID)?.Name??T("目标账本"):ProjectID!=null?Lifetime.Turns.FirstOrDefault(t=>t.Project.ID==ProjectID)?.Project.Name??T("项目"):T(Page switch{"projects"=>"项目","conversations"=>"对话","tasks"=>"全部任务","models"=>"模型用量","settings"=>"设置",_=>"目标账本"});
    public string Range=>T(Scope switch{DateScope.Yesterday=>"昨天",DateScope.Week=>"近 7 天",DateScope.Month=>"近 30 天",DateScope.All=>"历史累计",_=>"今天"});
    public AccountingCoverage ContextCoverage=>AccountingCoverage.Evaluate(Current,Selected().Select(t=>t.ID).ToHashSet(),Ready,Day is {} day?Dates.DayInterval(day,Scanner.Zone):null);
    public bool Known=>Ready&&PublishedScope==Scope&&(Current.Warnings.Count==0||Lifetime.Turns.Count>0);
    public bool RequiresGoalBook=>Page=="goals"||GoalID!=null||UnassignedOnly;
    public bool ContextKnown=>Known&&(!RequiresGoalBook||BookReadable);
    public bool CanShareOverview=>Ready&&Known&&PublishedScope==Scope;
    public AccountingCoverage GoalCoverage(string id)=>AccountingCoverage.Evaluate(Lifetime,Lifetime.Turns.Where(t=>Book.Owner(t)==id).Select(t=>t.ID).ToHashSet(),Ready);
    public bool CanComplete=>Ready&&!Busy&&BookReadable&&GoalID!=null&&GoalCoverage(GoalID).CanComplete;
    public bool CanShare=>CanShareOverview&&(!RequiresGoalBook||BookReadable);
    public ShareSnapshot Share(bool overview=false) {
        if(!(overview?CanShareOverview:CanShare))throw new InvalidOperationException(T("正在整理日志，请稍候"));
        var turns=Selected(overview);
        var monthly=overview?Month.Turns:Filter(Context(Month.Turns));var goal=Book.Goals.FirstOrDefault(g=>g.ID==GoalID);
        var snapshot = new ShareSnapshot(Kind(overview),overview?T("用量总览"):Title,Range,Scanner.Zone.Id,turns.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage),turns.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),turns.Count,turns.Select(t=>t.SessionID).Distinct().Count(),turns.SelectMany(t=>t.Models).Where(m=>m!="未知模型").Distinct().Count(),Scanner.Daily(monthly,Current.CapturedAt).ToArray(),!overview&&ChatID==null?goal?.CompletionCost:null,goal?.CompletedAt,goal?.CompletionPriceDate,!overview&&(Search.Length>0||Category!=null||Model!=null||UnassignedOnly),Current.Warnings.Count>0,Pricing.Date,Current.CapturedAt,Dates.Interval(Scope,Current.CapturedAt,Scanner.Zone).Start,Dates.Interval(Scope,Current.CapturedAt,Scanner.Zone).End,Prefs.HeatmapMetric);
        var interval=!overview&&Day is {} day?Dates.DayInterval(day,Scanner.Zone):Dates.Interval(Scope,Current.CapturedAt,Scanner.Zone);
        return snapshot with{RangeStart=interval.Start,RangeEnd=interval.End,Range=!overview&&Day!=null?T("仅此日"):Range,Context=new(Kind(overview),overview?null:ChatID??ProjectID??GoalID,overview?"":Search,overview?null:Category,overview?null:Model,interval.Start,interval.End,Scanner.Zone.Id,overview?AccountingCoverage.Evaluate(Current):ContextCoverage,Current.CapturedAt,overview||ChatID!=null||goal?.CompletedAt==null?null:goal?.Completions.LastOrDefault())};
    }
}
