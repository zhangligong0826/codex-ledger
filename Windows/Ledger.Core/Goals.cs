using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
namespace CodexLedger;
public sealed record LedgerGoal(string ID,string Name,DateTimeOffset CreatedAt,DateTimeOffset? CompletedAt=null,CostEstimate? CompletionCost=null,TokenUsage? CompletionUsage=null,string? CompletionPriceDate=null,decimal? BudgetUSD=null) { public IReadOnlyList<CompletionRecord> Completions {get;init;}=[]; }
public sealed record GoalTarget(string Kind,string ID);
public sealed record AttributionRule(string ID,GoalTarget Target,string GoalID,string Mode,IReadOnlySet<string> TurnIDs,DateTimeOffset? Start,DateTimeOffset? End,DateTimeOffset SavedAt,bool Legacy=false) {
    public bool Matches(LedgerTurn t) {
        if(Mode=="selected")return TurnIDs.Contains(t.ID);
        bool target=Target.Kind switch {"turn"=>Target.ID==t.ID,"conversation"=>Target.ID==t.SessionID,"project"=>Target.ID==t.Project.ID,_=>false};
        return target&&(Mode=="selected"?TurnIDs.Contains(t.ID):(Start==null||t.AttributionStart>=Start)&&(End==null||t.AttributionStart<End));
    }
}
public sealed record CompletionRecord(string ID,DateTimeOffset CompletedAt,DateTimeOffset CapturedAt,IReadOnlySet<string> TurnIDs,TokenUsage Usage,CostEstimate Cost,AccountingCoverage Coverage,string PriceVersion,bool Legacy=false);
public sealed record AttributionPreview(IReadOnlyList<LedgerTurn> Turns,CostEstimate Cost,IReadOnlyDictionary<string,int> Displaced);
public sealed class GoalBook {
    public int Version {get;set;}=2;
    public List<LedgerGoal> Goals {get;set;}=[];
    public Dictionary<string,string> Bindings {get;set;}=[];
    public List<AttributionRule> Rules {get;set;}=[];
    public const string Unassigned="__unassigned__";
    public string? Owner(LedgerTurn turn) {
        foreach(var kind in new[]{"turn","conversation","project"}) {
            var rule=Rules.Select((r,index)=>(r,index)).Where(x=>(x.r.Mode=="selected"?"turn":x.r.Target.Kind)==kind&&x.r.Matches(turn)).OrderByDescending(x=>x.r.SavedAt).ThenByDescending(x=>x.index).Select(x=>x.r).FirstOrDefault();if(rule!=null)return Goals.Any(g=>g.ID==rule.GoalID)?rule.GoalID:null;
            var target=kind+":"+(kind=="turn"?turn.ID:kind=="conversation"?turn.SessionID:turn.Project.ID);
            if(Bindings.TryGetValue(target,out var id))return Goals.Any(g=>g.ID==id)?id:null;
        }return null;
    }
    public void Assign(string target,string? goalID)=>Bindings[target]=goalID??Unassigned;
    public AttributionPreview Preview(AttributionRule rule,IReadOnlyList<LedgerTurn> turns) {
        var simulated=new GoalBook{Version=Version,Goals=new(Goals),Bindings=new(Bindings),Rules=new(Rules)};simulated.Apply(rule);var desired=rule.GoalID==Unassigned?null:rule.GoalID;
        var selected=turns.Where(t=>rule.Matches(t)&&simulated.Owner(t)==desired&&Owner(t)!=desired).ToArray();return new(selected,selected.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),selected.Where(t=>Owner(t)!=null&&Owner(t)!=rule.GoalID).GroupBy(t=>Owner(t)!).ToDictionary(g=>g.Key,g=>g.Count()));
    }
    public void Apply(AttributionRule rule)=>Rules.Add(rule);
    public void Remove(string id) {Goals.RemoveAll(g=>g.ID==id);Rules.RemoveAll(r=>r.GoalID==id);foreach(var key in Bindings.Where(x=>x.Value==id).Select(x=>x.Key).ToArray())Bindings.Remove(key);}
    public void Complete(string id,IReadOnlyList<LedgerTurn> lifetime,DateTimeOffset now,DateTimeOffset? capturedAt=null,AccountingCoverage? coverage=null) {
        if(coverage!=null&&!coverage.CanComplete)return;
        int index=Goals.FindIndex(g=>g.ID==id);if(index<0)return;var selected=lifetime.Where(t=>Owner(t)==id).ToArray();
        coverage??=new AccountingCoverage("complete",[]);
        var record=new CompletionRecord(Guid.NewGuid().ToString(),now,capturedAt??now,selected.Select(t=>t.ID).ToHashSet(),selected.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage),selected.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),coverage,Pricing.Version);
        for(int i=0;i<Rules.Count;i++)if(Rules[i].GoalID==id&&!Rules[i].Legacy&&Rules[i].Mode!="selected"&&Rules[i].End==null)Rules[i]=Rules[i] with{End=now};
        Goals[index]=Goals[index] with{Completions=Goals[index].Completions.Append(record).ToArray(),CompletedAt=now,CompletionCost=selected.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),CompletionUsage=selected.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage),CompletionPriceDate=Pricing.Date};
    }
    public void Reopen(string id) {int index=Goals.FindIndex(g=>g.ID==id);if(index>=0)Goals[index]=Goals[index] with{CompletedAt=null,CompletionCost=null,CompletionUsage=null,CompletionPriceDate=null};}
    public static GoalBook Decode(string text) {var b=JsonSerializer.Deserialize<GoalBook>(text,Json.Options)??throw new InvalidDataException("Empty goal book");if(b.Version is not (1 or 2)||b.Rules==null||b.Goals==null||b.Bindings==null||b.Goals.Any(g=>g==null||string.IsNullOrWhiteSpace(g.ID)||string.IsNullOrWhiteSpace(g.Name)||g.Name.Length>160||g.BudgetUSD<0||g.CompletionCost is { } c&&(c.InputUSD<0||c.CachedUSD<0||c.OutputUSD<0||c.PricedTokens<0||c.UnpricedTokens<0||c.UnverifiedContextTokens<0)||g.CompletionUsage is {} u&&(u.Input<0||u.Output<0||u.Cached<0||u.Cached>u.Input||u.Reasoning<0||u.Reasoning>u.Output||u.Input>long.MaxValue-u.Output)||g.CompletedAt!=null&&(g.CompletionCost==null||g.CompletionUsage==null))||b.Bindings.Any(x=>x.Value==null)||b.Goals.Select(g=>g.ID).Distinct().Count()!=b.Goals.Count)throw new InvalidDataException("Unsupported goal book");if(b.Version==1){b.Version=2;for(int i=0;i<b.Goals.Count;i++){var g=b.Goals[i];if(g.CompletedAt is {} at&&g.CompletionCost is {} cost&&g.CompletionUsage is {} usage)b.Goals[i]=g with{Completions=new[]{new CompletionRecord(Guid.NewGuid().ToString(),at,at,new HashSet<string>(),usage,cost,new("complete",[]),g.CompletionPriceDate??"",true)}};}}
        if(b.Rules.Any(r=>r==null||r.Target==null||r.Target.Kind is not ("turn" or "conversation" or "project")||r.Mode is not("selected" or "fromDate" or "entire")||r.TurnIDs==null||r.ID==null||r.Target.ID.Length==0||r.GoalID!=Unassigned&&!b.Goals.Any(g=>g.ID==r.GoalID)||r.Start>r.End||r.Mode=="fromDate"&&r.Start==null)||b.Rules.Select(r=>r.ID).Distinct().Count()!=b.Rules.Count)throw new InvalidDataException("Invalid attribution rule");
        if(b.Goals.Any(g=>g.CompletedAt!=null&&g.Completions!=null&&g.Completions.Count>0&&(g.Completions.Last().Cost!=g.CompletionCost||g.Completions.Last().Usage!=g.CompletionUsage)))throw new InvalidDataException("Inconsistent frozen completion");
        if(b.Goals.Any(g=>g.Completions==null||g.Completions.Any(r=>r==null||string.IsNullOrEmpty(r.ID)||r.Cost==null||r.Coverage==null||!r.Coverage.CanComplete||r.Usage==null||r.TurnIDs==null||r.Usage.Input<0||r.Usage.Output<0||r.Usage.Cached<0||r.Usage.Cached>r.Usage.Input||r.Usage.Reasoning<0||r.Usage.Reasoning>r.Usage.Output||r.Usage.Input>long.MaxValue-r.Usage.Output||r.Cost.InputUSD<0||r.Cost.CachedUSD<0||r.Cost.OutputUSD<0||r.Cost.PricedTokens<0||r.Cost.UnpricedTokens<0)||g.Completions.Select(r=>r.ID).Distinct().Count()!=g.Completions.Count))throw new InvalidDataException("Invalid completion record");return b;}
}
public static class LocalFiles {
    public static string DataDirectory=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexLedger");
    public static string GoalFile(string source)=>GoalPath(CanonicalSource(source)).Replace(".json","-v2.json");
    public static string V1GoalFile(string source)=>GoalPath(CanonicalSource(source));
    public static string LegacyGoalFile(string source)=>GoalPath(ProjectResolver.Normalize(source));
    public static string CanonicalSource(string source){var path=ProjectResolver.Normalize(source);return OperatingSystem.IsWindows()?path.ToUpperInvariant():path;}
    private static string GoalPath(string source)=>Path.Combine(DataDirectory,"goals-"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source)))+".json");
    public static void Backup(string path){
        if(!File.Exists(path))return;var dir=Path.Combine(Path.GetDirectoryName(path)!,"Backups");Directory.CreateDirectory(dir);
        var prefix=Path.GetFileNameWithoutExtension(path);var bytes=File.ReadAllBytes(path);string suffix;string? text=null;
        try{text=GoalArchive.Encode(GoalBook.Decode(new UTF8Encoding(false,true).GetString(bytes)));suffix=".backup.json";}catch(Exception e)when(e is JsonException or InvalidDataException or DecoderFallbackException){suffix=".recovery.bin";}
        var backup=Path.Combine(dir,prefix+"-"+DateTime.UtcNow.ToString("yyyyMMddHHmmssfffffff")+"-"+Guid.NewGuid()+suffix);if(text!=null)AtomicWrite(backup,text);else File.WriteAllBytes(backup,bytes);
        foreach(var old in Directory.EnumerateFiles(dir,prefix+"-*.backup.json").OrderByDescending(File.GetCreationTimeUtc).Skip(20))File.Delete(old);
    }
    public static GoalBook Import(string path,string text){var book=GoalArchive.Decode(text);Backup(path);AtomicWrite(path,JsonSerializer.Serialize(book,Json.Options));return book;}
    public static void AtomicWrite(string path,string text) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);var staging=path+"."+Guid.NewGuid()+".tmp";
        try {File.WriteAllText(staging,text,new UTF8Encoding(false));File.Move(staging,path,true);}finally{if(File.Exists(staging))File.Delete(staging);}
    }
}
public sealed record ShareContext(string Kind,string? EntityID,string Query,string? Category,string? Model,DateTimeOffset RangeStart,DateTimeOffset RangeEnd,string Timezone,AccountingCoverage Coverage,DateTimeOffset CapturedAt,CompletionRecord? Completion);
public sealed record ShareSnapshot(string Kind,string PrivateTitle,string Range,string Timezone,TokenUsage Usage,CostEstimate Cost,int Turns,int Conversations,int Models,IReadOnlyList<DailyUsage> Days,CostEstimate? CompletionCost,DateTimeOffset? CompletionDate,string? CompletionPriceDate,bool Filtered,bool Warning,string PriceDate,DateTimeOffset CapturedAt=default,DateTimeOffset RangeStart=default,DateTimeOffset RangeEnd=default,string HeatmapMetric="tokens") {
    public ShareContext? Context {get;init;}
    public IReadOnlyList<DailyUsage> Days { get; } = Array.AsReadOnly(Days.ToArray());
    public const string DownloadURL="https://zhangligong0826.github.io/codex-ledger/";
    public CostEstimate PrimaryCost=>CompletionCost??Cost;
    public TokenUsage PrimaryUsage=>Context?.Completion?.Usage??Usage;
    public int? PrimaryTurns=>Context?.Completion is {} completion?(completion.Legacy?null:completion.TurnIDs.Count):Turns;
    public TokenUsage MonthlyUsage=>Days.Aggregate(new TokenUsage(),(a,d)=>a+d.Usage);
    public CostEstimate MonthlyCost=>Days.Aggregate(new CostEstimate(),(a,d)=>a+d.Cost);
    public string DateLabel(DateTimeOffset date,bool time=false){TimeZoneInfo zone;try{zone=TimeZoneInfo.FindSystemTimeZoneById(Timezone);}catch{zone=TimeZoneInfo.Utc;}return TimeZoneInfo.ConvertTime(date,zone).ToString(time?"yyyy-MM-dd HH:mm":"yyyy-MM-dd",System.Globalization.CultureInfo.InvariantCulture);}
    public string CalendarRange {get{if(RangeEnd==default)return Range;var end=DateLabel(RangeEnd.AddTicks(-1));if(RangeStart.Year<=1900)return "≤ "+end;var start=DateLabel(RangeStart);return start==end?start:start+" — "+end;}}
    public int ActiveDays=>Days.Count(d=>d.Usage.Total>0);
}
public static class CSV {
    public static string Field(string value)=>"\""+(value.Length>0&&!System.Text.RegularExpressions.Regex.IsMatch(value,@"^[+-]?[0-9]+(?:\.[0-9]+)?$")&&"=+-@\t\r".Contains(value[0])?"'":"")+value.Replace("\"","\"\"")+"\"";
    public static string Render(IEnumerable<IEnumerable<string>> rows)=>"\uFEFF"+string.Join("\r\n",rows.Select(r=>string.Join(",",r.Select(Field))));
    public static IEnumerable<string> Cost(CostEstimate c,string? priceDate=null)=>[c.HasEstimate?c.TotalUSD.ToString(System.Globalization.CultureInfo.InvariantCulture):"",c.PricedTokens.ToString(),c.UnpricedTokens.ToString(),c.UnverifiedContextTokens.ToString(),priceDate??Pricing.Date];
    public static readonly string[] CostHeaders=["预估API花费USD","已计价tokens","未计价tokens","上下文未确认tokens","价格核对日期"];
}

public sealed record GoalArchive(string Format,int Version,DateTimeOffset ExportedAt,GoalBook Book) {
    private static readonly JsonSerializerOptions PortableOptions=new(Json.Options){PropertyNamingPolicy=JsonNamingPolicy.CamelCase,NumberHandling=JsonNumberHandling.AllowReadingFromString};
    public static string Encode(GoalBook book,DateTimeOffset? now=null) {
        GoalBook.Decode(JsonSerializer.Serialize(book,Json.Options));
        var node=JsonNode.Parse(JsonSerializer.Serialize(new GoalArchive("codex-ledger-goals",2,now??DateTimeOffset.Now,book),PortableOptions))!;
        var goals=node["book"]!["goals"]!.AsArray();
        for(int i=0;i<book.Goals.Count;i++){
            var g=book.Goals[i];if(g.BudgetUSD is decimal budget)goals[i]!["budgetUSD"]=budget.ToString(System.Globalization.CultureInfo.InvariantCulture);
            if(g.CompletionCost is { } cost){var price=goals[i]!["completionCost"]!;price["inputUSD"]=cost.InputUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);price["cachedUSD"]=cost.CachedUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);price["outputUSD"]=cost.OutputUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);}
        }
        for(int i=0;i<book.Goals.Count;i++)for(int j=0;j<book.Goals[i].Completions.Count;j++){
            var cost=book.Goals[i].Completions[j].Cost;var price=goals[i]!["completions"]![j]!["cost"]!;
            price["inputUSD"]=cost.InputUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);price["cachedUSD"]=cost.CachedUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);price["outputUSD"]=cost.OutputUSD.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        return node.ToJsonString(PortableOptions);
    }
    public static GoalBook Decode(string text) {
        if(Encoding.UTF8.GetByteCount(text)>8*1024*1024)throw new InvalidDataException("Backup too large");
        var archive=JsonSerializer.Deserialize<GoalArchive>(text,PortableOptions)??throw new InvalidDataException("Invalid backup");
        if(archive.Format!="codex-ledger-goals"||archive.Version is not (1 or 2)||archive.Book==null)throw new InvalidDataException("Unsupported backup");
        return GoalBook.Decode(JsonSerializer.Serialize(archive.Book,Json.Options));
    }
}


public static class GoalBudget {
    private static string Money(decimal value)=>value is >0 and <0.01m?"<$0.01":value.ToString("$0.00",System.Globalization.CultureInfo.InvariantCulture);
    public static decimal? Parse(string text)=>System.Text.RegularExpressions.Regex.IsMatch(text.Trim(),@"^[0-9]+(?:\.[0-9]{1,8})?$")&&decimal.TryParse(text.Trim(),System.Globalization.NumberStyles.AllowDecimalPoint,System.Globalization.CultureInfo.InvariantCulture,out var value)?value:null;
    public static string? Label(LedgerGoal goal,CostEstimate cost,Func<string,string> t,bool complete=true){
        if(goal.BudgetUSD is not decimal budget)return null;
        string prefix=t("预算")+" "+Money(budget)+" USD";
        if(!complete)return prefix+" · "+t("记录不完整");if(cost.UnpricedTokens>0)return prefix+" · "+t("含未计价用量");
        decimal difference=budget-cost.TotalUSD;return prefix+" · "+t(difference>=0?"估算剩余":"估算超出")+" "+Money(Math.Abs(difference));
    }
}
