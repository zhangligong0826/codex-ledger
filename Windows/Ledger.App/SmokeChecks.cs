using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using CodexLedger;
namespace CodexLedger.Windows;
public static class SmokeChecks {
    private static System.Collections.Generic.IEnumerable<string> Texts(System.Windows.DependencyObject root){
        if(root is System.Windows.Controls.TextBlock text)yield return text.Text;
        for(int i=0;i<System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);i++)foreach(var value in Texts(System.Windows.Media.VisualTreeHelper.GetChild(root,i)))yield return value;
    }
    public static async Task Run(MainWindow window,LedgerState state,string[] args){
        string output=args.FirstOrDefault(a=>a.StartsWith("--output="))?[9..]??Path.Combine(Path.GetTempPath(),"Ledger-ui-checks");Directory.CreateDirectory(output);
        string root=Path.Combine(Path.GetTempPath(),"Ledger-smoke-"+Guid.NewGuid());Directory.CreateDirectory(Path.Combine(root,"sessions"));
        try{var parser=new LogParser();var now=DateTimeOffset.Now;string Line(string type,object payload)=>JsonSerializer.Serialize(new{type,payload,timestamp=now.ToString("O")});
            File.WriteAllText(Path.Combine(root,"sessions","demo.jsonl"),string.Join("\n",new[]{Line("session_meta",new{id="f0000000-0000-0000-0000-000000000001",cwd=root}),Line("event_msg",new{type="task_started",turn_id="turn"}),Line("turn_context",new{turn_id="turn",model="gpt-5.4"}),Line("event_msg",new{type="user_message",message="Private title should not appear on public card"}),Line("token_usage_record",new{thread_id="f0000000-0000-0000-0000-000000000001",response_id="response",turn_id="turn",model="gpt-5.4",usage=new{input_tokens=100000,cached_input_tokens=50000,output_tokens=1000}})})+"\n");
            state.Prefs.Source=root;await state.Refresh();if(!state.Ready||state.Lifetime.Usage.Total!=101000)throw new Exception("UI source scan failed");var goal=new LedgerGoal("goal","Private goal",now);state.Book.Goals.Add(goal);state.Book.Assign("conversation:f0000000-0000-0000-0000-000000000001",goal.ID);
            window.ShowDashboard();await window.Dispatcher.InvokeAsync(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            Console.WriteLine("UI phase: source scan ready");int count=0;
            foreach(var language in new[]{"en","zh"})foreach(var theme in new[]{"light","dark","system"})foreach(var page in new[]{"goals","projects","conversations","tasks","models","settings"}){state.Prefs.Language=language;state.Prefs.Appearance=theme;state.Navigate(page);window.Width=760;window.Height=560;window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((System.Windows.FrameworkElement)window.Content),Path.Combine(output,$"{language}-{theme}-{page}.png"));count++;Console.WriteLine($"UI render: {language}/{theme}/{page}");}
            foreach(var text in new[]{"{\"Categories\":null}","{\"Source\":null}","{\"Appearance\":\"invalid\"}"}){
                try{JsonSerializer.Deserialize<Preferences>(text,Json.Options)!.Validate();throw new Exception("Invalid preferences accepted");}catch(InvalidDataException){}
            }
            Console.WriteLine("UI phase: page renders complete");state.Prefs.Language="en";state.Prefs.Appearance="light";state.Navigate("projects");state.ProjectID=state.Current.Turns[0].Project.ID;state.Notify();if(state.Context().Count!=1)throw new Exception("project scope");state.ChatID=state.Current.Turns[0].SessionID;state.Notify();if(state.Context().Count!=1)throw new Exception("chat scope");state.Back();if(state.ChatID!=null||state.ProjectID==null)throw new Exception("back scope");state.Back();if(state.ProjectID!=null)throw new Exception("back project");
            state.Navigate("conversations");state.Titles[state.Current.Turns[0].SessionID]="Metadata-only conversation title";state.Search="Metadata-only";if(state.Filter(state.Context()).Count!=1)throw new Exception("metadata title search");state.Search="nonmatching";state.Notify();if(state.Filter(state.Context()).Count!=0)throw new Exception("search");state.Clear();
            state.Navigate("goals");state.GoalID="goal";state.SetScope(DateScope.All);state.Book.Complete("goal",state.Lifetime.Turns,now);state.Notify();var frozen=state.Share();var original=state.Current;state.Current=new([],[],0,0);var card=ShareRendering.Render(ShareRendering.Card(frozen,"",false,false,state.T),360,480,3);if(card.PixelWidth!=1080||card.PixelHeight!=1440||frozen.Cost.TotalUSD!=0.1525m)throw new Exception("frozen share dimensions/cost");ShareRendering.Save(card,Path.Combine(output,"share-card.png"));System.Windows.Clipboard.SetImage(card);if(System.Windows.Clipboard.GetImage()?.PixelWidth!=1080)throw new Exception("clipboard image roundtrip");
            foreach(var language in new[]{"en","zh"})foreach(var dark in new[]{false,true}){state.Prefs.Language=language;var variant=ShareRendering.Render(ShareRendering.Card(frozen,"",false,dark,state.T),360,480,3);ShareRendering.Save(variant,Path.Combine(output,$"share-{language}-{(dark?"dark":"light")}.png"));}
            state.Prefs.Language="en";
            foreach(var pair in new[]{("large",new CostEstimate(InputUSD:9876543210987.99m,PricedTokens:1)),("unpriced",new CostEstimate(UnpricedTokens:100))}){var edge=frozen with{Cost=pair.Item2,CompletionCost=pair.Item2,Warning=true,Filtered=true};var variant=ShareRendering.Render(ShareRendering.Card(edge,new string('目',120),false,false,state.T),360,480,3);ShareRendering.Save(variant,Path.Combine(output,$"edge-{pair.Item1}.png"));if(variant.PixelHeight!=1440)throw new Exception("edge dimensions");}
            try{ShareRendering.Save(card,Path.Combine(output,"missing-folder","failure.png"));throw new Exception("Expected save failure");}catch(DirectoryNotFoundException){}

            if(!window.ExportContents().Contains("Private goal"))throw new Exception("CSV goal summary");state.Current=original;window.ShowOverview();window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((System.Windows.FrameworkElement)window.Content),Path.Combine(output,"overview.png"));
            state.Busy=true;var duringRefresh=state.Share(true);if(duringRefresh.Usage!=state.Current.Usage)throw new Exception("Refresh must allow published snapshot sharing");state.Busy=false;
            Console.WriteLine("UI phase: baseline sharing complete");window.ShowDashboard();var savedCurrent=state.Current;var savedLifetime=state.Lifetime;var savedMonth=state.Month;
            var seed=savedCurrent.Turns[0];var sample=seed.Samples[0];var other=sample with{ID="second-model",Model="gpt-5.4-mini",Usage=new TokenUsage(2000,0,200,0)};
            var mixed=seed with{ID="mixed-turn",Samples=new[]{sample,other},Usage=sample.Usage+other.Usage,Responses=2};
            state.Current=new(new[]{mixed},Array.Empty<string>(),1,0){CapturedAt=savedCurrent.CapturedAt};state.Lifetime=state.Current;state.Month=state.Current;state.PublishedScope=state.Scope;state.ResetNavigation();
            state.Navigate("models");state.Search="gpt-5.4-mini";state.Notify();var modelShare=state.Share();var modelCsv=window.ExportContents();
            if(modelShare.Usage!=other.Usage||modelShare.Cost!=other.Cost||modelCsv.Contains("\"gpt-5.4\""))throw new Exception("Model UI/share/CSV scope mismatch");
            state.Navigate("projects");state.Search=seed.Project.Name;state.Notify();if(state.Share().Usage.Total!=mixed.Usage.Total)throw new Exception("Project entity search must retain whole amount");
            state.Navigate("goals");state.GoalID="goal";state.Search="Metadata-only";state.Notify();if(state.Share().Usage.Total!=mixed.Usage.Total||!window.ExportContents().Contains("Private goal"))throw new Exception("Goal detail CSV ignores chat search");
            state.Lifetime=state.Lifetime with{Warnings=new[]{"Missing synthetic log"}};if(state.CanComplete)throw new Exception("Incomplete lifetime must block completion");
            state.Current=savedCurrent;state.Lifetime=savedLifetime;state.Month=savedMonth;state.Clear();
            state.Book.Goals[0]=state.Book.Goals[0] with{BudgetUSD=1m,CompletionPriceDate="2026-10-01"};state.Notify();if(!window.ExportContents().Contains("2026-10-01"))throw new Exception("Frozen completion price provenance");
            state.Prefs.HeatmapMetric="cost";window.ShowOverview();window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((FrameworkElement)window.Content),Path.Combine(output,"cost-heatmap.png"));
            Console.WriteLine("UI phase: scope and budget complete");var oldBook=state.Book;state.Book=new();state.BookReadable=false;state.Error="目标账本无法读取，原有数据已保留。";state.Navigate("goals");window.ShowDashboard();window.UpdateLayout();
            if(state.ContextKnown||state.CanShare)throw new Exception("Unreadable attribution must not be known zero");
            try{state.Share();throw new Exception("Unreadable goal share must fail");}catch(InvalidOperationException){}
            if(state.Share(true).Usage.Total!=state.Current.Usage.Total)throw new Exception("Independent overview should remain available");
            ShareRendering.Save(ShareRendering.Capture((FrameworkElement)window.Content),Path.Combine(output,"book-error.png"));
            state.Book=oldBook;state.BookReadable=true;state.Error="";state.Navigate("goals");window.ShowOverview();
            var good=state.Current;state.Current=new([],[],0,0);state.Month=state.Current;state.Lifetime=state.Current;state.Ready=true;window.ShowOverview();window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((FrameworkElement)window.Content),Path.Combine(output,"empty.png"));if(!state.Known)throw new Exception("valid empty is known");
            state.Ready=false;state.Notify();if(state.CanShare)throw new Exception("loading export gate");if(Texts((FrameworkElement)window.Content).Any(t=>t.Contains("$0.00")))throw new Exception("Loading must not claim zero spend");window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((FrameworkElement)window.Content),Path.Combine(output,"loading.png"));
            state.Ready=true;state.Current=new([],new[]{"Unreadable fixture source"},0,0);state.Notify();if(state.Known||state.CanShare)throw new Exception("error must not be known zero");if(Texts((FrameworkElement)window.Content).Any(t=>t.Contains("$0.00")))throw new Exception("Error must not claim zero monthly spend");window.UpdateLayout();ShareRendering.Save(ShareRendering.Capture((FrameworkElement)window.Content),Path.Combine(output,"error.png"));
            Console.WriteLine("UI phase: loading/error complete");var pipe="CodexLedger-test-"+Guid.NewGuid();using var cancellation=new System.Threading.CancellationTokenSource();var received=new TaskCompletionSource<string>();var listening=AppInstance.Listen(command=>received.TrySetResult(command),cancellation.Token,pipe);
            if(!await Task.Run(()=>AppInstance.Send("dashboard",pipe))||await received.Task.WaitAsync(TimeSpan.FromSeconds(5))!="dashboard")throw new Exception("Second-launch IPC command failed");cancellation.Cancel();try{await listening;}catch(OperationCanceledException){}
            Console.WriteLine($"Windows UI smoke: {count} localized/theme/page renders, navigation/search, CSV, frozen 1080x1440 share, clipboard roundtrip, save failure and loading/empty/error passed; not physical-device acceptance.");
        }finally{window.Hide();Directory.Delete(root,true);}
    }
}
