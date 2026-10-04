using CodexLedger;
using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;
int checks=0;
void Expect(bool value,string name){checks++;if(!value)throw new Exception("FAIL: "+name);}
string folder=Path.Combine(Path.GetTempPath(),"Ledger-tests-"+Guid.NewGuid());Directory.CreateDirectory(folder);
try {
    var scanner=new LedgerScanner(TimeZoneInfo.Utc);var parser=new LogParser();
    foreach(var file in Directory.GetFiles(Path.Combine(AppContext.BaseDirectory,"Fixtures"),"*.json")) {
        using var d=JsonDocument.Parse(File.ReadAllText(file));var data=d.RootElement;var now=DateTimeOffset.Parse(data.S("now"),CultureInfo.InvariantCulture);var logs=new List<ParsedLog>();int index=0;
        foreach(var lines in data.J("logs").Items()){var path=Path.Combine(folder,Path.GetFileName(file)+index+++".jsonl");File.WriteAllText(path,string.Join("\n",lines.Items().Select(x=>JsonSerializer.Serialize(x)))+"\n");logs.Add(parser.Parse(path));}
        foreach(var expected in data.J("expected").EnumerateObject()) {
            var scope=expected.Name switch{"today"=>DateScope.Today,"yesterday"=>DateScope.Yesterday,"30d"=>DateScope.Month,_=>DateScope.All};var snap=scanner.Snapshot(logs,scope,now);var e=expected.Value;string name=Path.GetFileName(file)+"/"+expected.Name;
            Expect(snap.Usage.Total==e.N("total")&&snap.Usage.Cached==e.N("cached")&&snap.Usage.Reasoning==e.N("reasoning"),name+" tokens actual="+snap.Usage+" expected="+e.GetRawText());
            Expect(snap.Turns.Count==e.N("turns")&&snap.Turns.Sum(t=>t.Responses)==e.N("responses"),name+" dedup/turns");
            Expect(snap.Cost.TotalUSD==decimal.Parse(e.S("usd"),CultureInfo.InvariantCulture)&&snap.Cost.PricedTokens==e.N("priced")&&snap.Cost.UnpricedTokens==e.N("unpriced"),name+" cost");
            Expect(snap.Turns.GroupBy(t=>t.Project.ID).Select(g=>g.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost)).Aggregate(new CostEstimate(),(a,c)=>a+c)==snap.Cost,name+" projects");
            Expect(snap.Turns.GroupBy(t=>t.SessionID).Select(g=>g.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost)).Aggregate(new CostEstimate(),(a,c)=>a+c)==snap.Cost,name+" chats");
        }
        var month=scanner.Snapshot(logs,DateScope.Month,now);var days=scanner.Daily(month.Turns,now);
        Expect(days.Count==30&&days.Aggregate(new CostEstimate(),(a,day)=>a+day.Cost)==month.Cost,"daily/month equality");
        foreach(var turn in month.Turns)Expect(scanner.Daily([turn],now).Aggregate(new CostEstimate(),(a,day)=>a+day.Cost)==turn.Cost,"scoped daily equality");
        var book=new GoalBook();book.Goals.Add(new("g1","Goal",now));book.Goals.Add(new("g2","Other",now));
        foreach(var turn in month.Turns)book.Assign("project:"+turn.Project.ID,"g1");
        var first=month.Turns.First();book.Assign("conversation:"+first.SessionID,"g2");Expect(book.Owner(first)=="g2","chat priority");book.Assign("turn:"+first.ID,null);Expect(book.Owner(first)==null,"explicit unassignment");book.Bindings.Remove("turn:"+first.ID);Expect(book.Owner(first)=="g2","inheritance restoration");
        book.Complete("g2",month.Turns,now);var completion=book.Goals[1].CompletionCost;book.Assign("turn:"+first.ID,"g1");Expect(book.Goals[1].CompletionCost==completion,"frozen completion");
        var restored=GoalBook.Decode(JsonSerializer.Serialize(book,Json.Options));Expect(restored.Goals[1].CompletionCost==completion,"completion persistence");book.Remove("g2");Expect(book.Owner(first)=="g1"&&book.Bindings.Values.All(v=>v!="g2"),"deletion preserves inherited assignment");
        Expect(CSV.Render([["=formula","a,\"b\"\n中文"]]).Contains("\"'=formula\""),"CSV formulas");
        var card=new ShareSnapshot("目标花费","private title","Today","UTC",month.Usage,month.Cost,month.Turns.Count,1,1,days,completion,now,Pricing.Date,false,false,Pricing.Date);
        Expect(card.MonthlyCost==month.Cost&&card.MonthlyUsage==month.Usage,"immutable card values");
    }
    var root=Path.Combine(folder,"repo");Directory.CreateDirectory(Path.Combine(root,".git","objects"));Directory.CreateDirectory(Path.Combine(root,".git","refs"));File.WriteAllText(Path.Combine(root,".git","HEAD"),"ref: refs/heads/main\n");Directory.CreateDirectory(Path.Combine(root,"sub"));
    var resolver=new ProjectResolver();Expect(resolver.Resolve(root).ID==resolver.Resolve(Path.Combine(root,"sub")).ID,"repository subdirectory");
    var wt=Path.Combine(folder,"worktree");var gd=Path.Combine(root,".git","worktrees","wt");Directory.CreateDirectory(wt);Directory.CreateDirectory(gd);File.WriteAllText(Path.Combine(wt,".git"),"gitdir: "+gd+"\n");File.WriteAllText(Path.Combine(gd,"HEAD"),"ref: refs/heads/work\n");File.WriteAllText(Path.Combine(gd,"commondir"),"../..\n");Expect(resolver.Resolve(root).ID==resolver.Resolve(wt).ID,"worktrees merged");
    Expect(resolver.Resolve("")==ProjectIdentity.Unknown,"missing cwd");
    var other=Path.Combine(folder,"other","repo");Directory.CreateDirectory(other);Expect(resolver.Resolve(root).ID!=resolver.Resolve(other).ID,"same named directories");
    if(OperatingSystem.IsWindows()){Expect(resolver.Resolve(root.ToUpperInvariant()).ID==resolver.Resolve(root).ID,"case aliases");Expect(ProjectResolver.Normalize(@"\\server\share\project").Length>0,"UNC path");}
    var corrupt=Path.Combine(folder,"corrupt");Directory.CreateDirectory(corrupt);File.WriteAllText(Path.Combine(corrupt,".git"),"not a git pointer");Expect(resolver.Resolve(corrupt).ID.StartsWith("directory:"),"corrupt Git metadata fallback");
    var dbPath=Path.Combine(folder,"state_5.sqlite");using(var db=new SqliteConnection("Data Source="+dbPath)){db.Open();using var cmd=db.CreateCommand();cmd.CommandText="CREATE TABLE threads (id TEXT,title TEXT); INSERT INTO threads VALUES ('chat-a','Metadata title')";cmd.ExecuteNonQuery();}
    var before=File.ReadAllBytes(dbPath);Expect(ConversationMetadata.Titles(folder).GetValueOrDefault("chat-a")=="Metadata title","metadata title");Expect(File.ReadAllBytes(dbPath).SequenceEqual(before),"metadata remains read-only");
    var dst=TimeZoneInfo.FindSystemTimeZoneById(OperatingSystem.IsWindows()?"Pacific Standard Time":"America/Los_Angeles");var interval=Dates.Interval(DateScope.Today,DateTimeOffset.Parse("2026-03-08T12:00:00-07:00"),dst);Expect((interval.End-interval.Start).TotalHours==23,"DST local day");
    Expect(Classifier.Category("有什么工具可以制作 ppt 和 Word？有现成的吗？",[])=="question","conceptual question");Expect(Classifier.Category("好的，帮我设计并且完成，我需要一个 mac应用",[])=="coding","coding intent");Expect(Classifier.Category("继续",[],"document")=="document","inherited category");Expect(Classifier.Category("帮我制作 PPT 和 Word",[])=="mixed","mixed outputs");
    Expect(!Classifier.AssociatedFile(@"C:\Users\demo\.codex\plugins\x\SKILL.md"),"Windows infrastructure paths");
    try{GoalBook.Decode("{\"Version\":2}");Expect(false,"unsupported book");}catch(InvalidDataException){Expect(true,"unsupported book preserved");}
    Console.WriteLine($"{checks}/{checks} Windows accounting, goals and shared fixture checks passed");
}finally{Directory.Delete(folder,true);}
