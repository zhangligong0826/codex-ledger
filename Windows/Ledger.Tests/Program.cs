using CodexLedger;
using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;
if(args.Length==2&&args[0]=="--verify-backup") {var b=GoalArchive.Decode(File.ReadAllText(args[1]));if(b.Goals[0].CompletionCost!.TotalUSD!=0.151456789m||b.Goals[0].CompletionPriceDate!="2026-10-01"||b.Goals[0].BudgetUSD!=10.25m||b.Rules.Count!=1||b.Goals[0].Completions[0].ID!="portable-completion"||!b.Goals[0].Completions[0].TurnIDs.SetEquals(new[]{"portable-chat:first"}))throw new Exception("Cross-language backup mismatch");Console.WriteLine("Swift -> C# precise backup accepted");return;}
int checks=0;
void Expect(bool value,string name){checks++;if(!value)throw new Exception("FAIL: "+name);}
string folder=Path.Combine(Path.GetTempPath(),"Ledger-tests-"+Guid.NewGuid());Directory.CreateDirectory(folder);
try {
    var scanner=new LedgerScanner(TimeZoneInfo.Utc);var parser=new LogParser();
    foreach(var file in Directory.GetFiles(Path.Combine(AppContext.BaseDirectory,"Fixtures"),"*.json")) {
        using var d=JsonDocument.Parse(File.ReadAllText(file));var data=d.RootElement;var now=DateTimeOffset.Parse(data.S("now"),CultureInfo.InvariantCulture);var logs=new List<ParsedLog>();int index=0;
        foreach(var lines in data.J("logs").Items()){var path=Path.Combine(folder,Path.GetFileName(file)+index+++".jsonl");File.WriteAllText(path,string.Join("\n",lines.Items().Select(x=>JsonSerializer.Serialize(x)))+"\n");logs.Add(parser.Parse(path));}
        foreach(var expected in data.J("expected").EnumerateObject()) {
            var scope=expected.Name switch{"today"=>DateScope.Today,"yesterday"=>DateScope.Yesterday,"30d"=>DateScope.Month,_=>DateScope.All};var snap=scanner.Snapshot(logs,scope,now);var e=expected.Value;if(data.J("complete").ValueKind is JsonValueKind.True or JsonValueKind.False)Expect(snap.IsComplete==data.J("complete").GetBoolean(),"mixed integrity");string name=Path.GetFileName(file)+"/"+expected.Name;
            Expect(snap.Usage.Total==e.N("total")&&snap.Usage.Cached==e.N("cached")&&snap.Usage.Reasoning==e.N("reasoning"),name+" tokens actual="+snap.Usage+" expected="+e.GetRawText());
            Expect(snap.Turns.Count==e.N("turns")&&snap.Turns.Sum(t=>t.Responses)==e.N("responses"),name+" dedup/turns");
            Expect(snap.Cost.TotalUSD==decimal.Parse(e.S("usd"),CultureInfo.InvariantCulture)&&snap.Cost.PricedTokens==e.N("priced")&&snap.Cost.UnpricedTokens==e.N("unpriced"),name+" cost");
            Expect(snap.Turns.GroupBy(t=>t.Project.ID).Select(g=>g.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost)).Aggregate(new CostEstimate(),(a,c)=>a+c)==snap.Cost,name+" projects");
            Expect(snap.Turns.GroupBy(t=>t.SessionID).Select(g=>g.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost)).Aggregate(new CostEstimate(),(a,c)=>a+c)==snap.Cost,name+" chats");
        }
        if(data.J("complete").ValueKind==JsonValueKind.False){var unaffected=scanner.Snapshot(logs,DateScope.Today,now.AddDays(1));var lifetime=scanner.Snapshot(logs,DateScope.All,now.AddDays(1));Expect(unaffected.IsComplete&&unaffected.LogIssues.Count==0,"historical conflicts exclude unrelated days");Expect(!lifetime.IsComplete&&lifetime.LogIssues.Count>0&&!lifetime.HasReadFailures,"historical accounting conflicts stay disclosed");}
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
    var dbPath=Path.Combine(folder,"state_5.sqlite");using(var db=new SqliteConnection("Data Source="+dbPath+";Pooling=False")){db.Open();using var cmd=db.CreateCommand();cmd.CommandText="CREATE TABLE threads (id TEXT,title TEXT); INSERT INTO threads VALUES ('chat-a','Metadata title')";cmd.ExecuteNonQuery();}
    var before=File.ReadAllBytes(dbPath);Expect(ConversationMetadata.Titles(folder).GetValueOrDefault("chat-a")=="Metadata title","metadata title");Expect(File.ReadAllBytes(dbPath).SequenceEqual(before),"metadata remains read-only");
    var dst=TimeZoneInfo.FindSystemTimeZoneById(OperatingSystem.IsWindows()?"Pacific Standard Time":"America/Los_Angeles");var interval=Dates.Interval(DateScope.Today,DateTimeOffset.Parse("2026-03-08T12:00:00-07:00"),dst);Expect((interval.End-interval.Start).TotalHours==23,"DST local day");
    Expect(Classifier.Category("有什么工具可以制作 ppt 和 Word？有现成的吗？",[])=="question","conceptual question");Expect(Classifier.Category("好的，帮我设计并且完成，我需要一个 mac应用",[])=="coding","coding intent");Expect(Classifier.Category("继续",[],"document")=="document","inherited category");Expect(Classifier.Category("帮我制作 PPT 和 Word",[])=="mixed","mixed outputs");
    Expect(!Classifier.AssociatedFile(@"C:\Users\demo\.codex\plugins\x\SKILL.md"),"Windows infrastructure paths");
    try{GoalBook.Decode("{\"Version\":3}");Expect(false,"unsupported book");}catch(InvalidDataException){Expect(true,"unsupported book preserved");}
    var portable=GoalArchive.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"goal-backup-fixture.json")));
    Expect(portable.Goals[0].CompletionCost!.TotalUSD==0.151456789m&&portable.Goals[0].BudgetUSD==10.25m&&portable.Goals[0].CompletionPriceDate=="2026-10-01","portable exact money/budget/provenance");
    var v2=GoalArchive.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"goal-v2-fixture.json")));
    Expect(v2.Version==2&&v2.Rules.Count==1&&v2.Goals[0].Completions[0].TurnIDs.SetEquals(new[]{"portable-chat:first"}),"v2 membership and rule fixture");
    Expect(portable.Goals[0].Completions[0].Legacy&&portable.Goals[0].Completions[0].TurnIDs.Count==0,"v1 migration does not invent membership");
    Expect(GoalArchive.Decode(GoalArchive.Encode(v2)).Rules[0].Start==v2.Rules[0].Start,"v2 UTC date boundaries roundtrip");
    if(Environment.GetEnvironmentVariable("CODEX_LEDGER_INTEROP_OUTPUT") is string output)File.WriteAllText(output,GoalArchive.Encode(v2));
    var portableRoundtrip=GoalArchive.Decode(GoalArchive.Encode(portable));Expect(JsonSerializer.Serialize(portableRoundtrip.Goals[0],Json.Options)==JsonSerializer.Serialize(portable.Goals[0],Json.Options)&&portableRoundtrip.Bindings.SequenceEqual(portable.Bindings),"portable roundtrip");
    var archivePath=Path.Combine(folder,"book.json");File.WriteAllText(archivePath,JsonSerializer.Serialize(portable,Json.Options));
    LocalFiles.Import(archivePath,GoalArchive.Encode(portable));Expect(Directory.GetFiles(Path.Combine(folder,"Backups"),"*.backup.json").Length==1,"import preserves recovery copy");
    var unchanged=File.ReadAllBytes(archivePath);try{LocalFiles.Import(archivePath,"{}");Expect(false,"invalid import");}catch(Exception e)when(e is InvalidDataException or JsonException){Expect(File.ReadAllBytes(archivePath).SequenceEqual(unchanged),"invalid backup cannot overwrite");}
    File.WriteAllBytes(archivePath,[0xff,0xfe,0x00]);LocalFiles.Backup(archivePath);Expect(Directory.GetFiles(Path.Combine(folder,"Backups"),"*.recovery.bin").Any(f=>File.ReadAllBytes(f).SequenceEqual(new byte[]{0xff,0xfe,0x00})),"corrupt recovery is byte exact");
    try{GoalBook.Decode("{\"Version\":1,\"Goals\":[null],\"Bindings\":{}}");Expect(false,"null goal");}catch(InvalidDataException){Expect(true,"null goal rejected");}
    Expect(GoalBudget.Parse("0.001")==0.001m&&GoalBudget.Parse("-1")==null&&GoalBudget.Parse("NaN")==null,"budget validation");
    Expect(GoalBudget.Label(portable.Goals[0] with { BudgetUSD=0.001m },new CostEstimate(),x=>x)!.Contains("<$0.01"),"sub-cent budget is not zero");
    Expect(CSV.Cost(portable.Goals[0].CompletionCost!,portable.Goals[0].CompletionPriceDate).Last()=="2026-10-01","CSV historical price date");
    if(OperatingSystem.IsWindows())Expect(LocalFiles.GoalFile(root.ToUpperInvariant())==LocalFiles.GoalFile(root.ToLowerInvariant()),"source casing preserves book identity");
    var malformedPath=Path.Combine(folder,"malformed.jsonl");File.WriteAllText(malformedPath,"{bad}\n");Expect(parser.Parse(malformedPath).Malformed==1,"malformed final complete line is not pending write");
    File.WriteAllText(malformedPath,"{bad");Expect(parser.Parse(malformedPath).Malformed==0,"unfinished trailing line is retryable");
    Expect(CSV.Field("-25.00")=="\"-25.00\"","negative budget values are numeric");

    var scopedIssue=new LogIssue("synthetic",new[]{"conflict"}){Dates=new[]{DateTimeOffset.UtcNow},AffectedTurnIDs=new HashSet<string>{"main:turn"},UnknownScope=false};
    var partial=new Snapshot([],new[]{"conflict"},1,0){LogIssues=new[]{scopedIssue}};
    Expect(AccountingCoverage.Evaluate(partial,new HashSet<string>{"other:turn"}).CanComplete,"unrelated issue does not block goal");
    Expect(!AccountingCoverage.Evaluate(partial,new HashSet<string>{"main:turn"}).CanComplete,"related issue blocks goal");
    Expect(!AccountingCoverage.Evaluate(new Snapshot([],new[]{"missing"},0,0){HasReadFailures=true},new HashSet<string>()).CanComplete,"empty context cannot hide unknown failure");
    var g2=v2.Goals[0];v2.Reopen(g2.ID);Expect(v2.Goals[0].Completions.Count==1&&v2.Goals[0].Completions[0].ID==g2.Completions[0].ID,"reopen retains completion history");
    V2Checks.Run(Expect);
    Console.WriteLine($"{checks}/{checks} Windows accounting, goals and shared fixture checks passed");
}finally{Directory.Delete(folder,true);}
