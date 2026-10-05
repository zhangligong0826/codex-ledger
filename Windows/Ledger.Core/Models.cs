using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace CodexLedger;

public sealed record TokenUsage(long Input=0,long Cached=0,long Output=0,long Reasoning=0) {
    public long Total => Input + Output;
    public static TokenUsage operator +(TokenUsage a,TokenUsage b) => new(a.Input+b.Input,a.Cached+b.Cached,a.Output+b.Output,a.Reasoning+b.Reasoning);
    public TokenUsage Delta(TokenUsage? old) => old is null || Input<old.Input || Output<old.Output ? this : new(Input-old.Input,Math.Min(Input-old.Input,Math.Max(0,Cached-old.Cached)),Output-old.Output,Math.Min(Output-old.Output,Math.Max(0,Reasoning-old.Reasoning)));
    public static TokenUsage Read(JsonElement j) { long i=j.N("input_tokens"),o=j.N("output_tokens");return new(i,Math.Min(i,j.N("cached_input_tokens")),o,Math.Min(o,j.N("reasoning_output_tokens"))); }
}
public sealed record CostEstimate(decimal InputUSD=0,decimal CachedUSD=0,decimal OutputUSD=0,long PricedTokens=0,long UnpricedTokens=0,long UnverifiedContextTokens=0) {
    public decimal TotalUSD => InputUSD+CachedUSD+OutputUSD;
    public bool HasEstimate => PricedTokens>0 || UnpricedTokens==0;
    public static CostEstimate operator +(CostEstimate a,CostEstimate b) => new(a.InputUSD+b.InputUSD,a.CachedUSD+b.CachedUSD,a.OutputUSD+b.OutputUSD,a.PricedTokens+b.PricedTokens,a.UnpricedTokens+b.UnpricedTokens,a.UnverifiedContextTokens+b.UnverifiedContextTokens);
    public string Money => HasEstimate ? (TotalUSD is >0 and <0.01m ? "<$0.01" : TotalUSD.ToString("$0.00",CultureInfo.InvariantCulture))+(UnpricedTokens>0 ? " *" : "") : "单价未知";
}
public static class Pricing {
    private sealed record Rate(string Input,string Cached,string Output,bool LongContext);
    private sealed record Catalog(int Version,string VerifiedDate,string SourceURL,long LongContextThreshold,Dictionary<string,Rate> Models);
    private static readonly byte[] CatalogBytes=ReadBytes();
    private static readonly Catalog Data=Read();
    private static byte[] ReadBytes(){using var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Ledger.Core.prices.json")??throw new InvalidDataException("Missing pricing catalog");using var buffer=new MemoryStream();stream.CopyTo(buffer);return buffer.ToArray();}
    public static string Version=>"v1:"+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(CatalogBytes)).ToLowerInvariant();
    public static string Date => Data.VerifiedDate;
    private static Catalog Read() {
        var c=JsonSerializer.Deserialize<Catalog>(CatalogBytes,Json.Options) ?? throw new InvalidDataException("Invalid pricing catalog");
        if(c.Version!=1) throw new InvalidDataException("Unsupported pricing catalog");return c;
    }
    public static CostEstimate Estimate(string model,TokenUsage u,bool request=true) {
        if(!Data.Models.TryGetValue(model,out var p)) return new(UnpricedTokens:u.Total);
        bool longContext=request && p.LongContext && u.Input>Data.LongContextThreshold;
        decimal input=longContext?2:1,output=longContext?1.5m:1;
        decimal Rate(string s)=>decimal.Parse(s,CultureInfo.InvariantCulture);
        return new((u.Input-u.Cached)*Rate(p.Input)*input/1000000m,u.Cached*Rate(p.Cached)*input/1000000m,u.Output*Rate(p.Output)*output/1000000m,u.Total,0,!request&&p.LongContext?u.Total:0);
    }
}
public static class Json {
    public static readonly JsonSerializerOptions Options=new(){PropertyNameCaseInsensitive=true,WriteIndented=true,Converters={new ReadOnlyStringSetConverter()}};
    public static JsonElement J(this JsonElement e,string key)=>e.ValueKind==JsonValueKind.Object && e.TryGetProperty(key,out var v)?v:default;
    public static string S(this JsonElement e,string key,string fallback="")=>e.J(key).ValueKind==JsonValueKind.String?e.J(key).GetString()??fallback:fallback;
    public static long N(this JsonElement e,string key)=>e.J(key).TryLong();
    public static long TryLong(this JsonElement e)=>e.ValueKind==JsonValueKind.Number && e.TryGetInt64(out var n)?Math.Max(0,n):0;
    public static IEnumerable<JsonElement> Items(this JsonElement e)=>e.ValueKind==JsonValueKind.Array?e.EnumerateArray():[];
}
public sealed record UsageSample(string ID,string SessionID,string TurnID,string RootTurnID,DateTimeOffset Date,string Model,TokenUsage Usage,bool HasRequestUsage=true) { public CostEstimate Cost=>Pricing.Estimate(Model,Usage,HasRequestUsage); }
public sealed class TurnInfo {
    public string ID="",SessionID="",RootTurnID="",Prompt="",Model="未知模型",WorkingDirectory="",InheritedCategory="unknown";
    public DateTimeOffset Start;public bool Finished;public List<string> Artifacts=[];
}
public sealed class ParsedLog {
    public string Path="",SessionID="",WorkingDirectory="",FirstPrompt="";public string? ParentID;
    public List<DateTimeOffset>? IntegrityDates;public List<string> IntegrityWarnings=[];public bool InternalAgent;public int Malformed;public Dictionary<string,TurnInfo> Turns=[];public List<UsageSample> Samples=[];
}
public sealed record ProjectIdentity(string ID,string Name,string Path) { public static ProjectIdentity Unknown=new("unidentified-project","未识别项目",""); }
public sealed record LedgerTurn(string ID,string SessionID,string Title,string Category,TokenUsage Usage,DateTimeOffset Date,DateTimeOffset LastActivity,bool Finished,int Responses,int SubagentResponses,string WorkingDirectory,ProjectIdentity Project,IReadOnlyList<UsageSample> Samples,IReadOnlyList<string> Artifacts) {
    public DateTimeOffset StartedAt {get;init;}
    public DateTimeOffset AttributionStart=>StartedAt==default?Date:StartedAt;
    public CostEstimate Cost=>Samples.Aggregate(new CostEstimate(),(a,s)=>a+s.Cost);
    public IReadOnlyList<string> Models=>Samples.Select(x=>x.Model).Distinct().Order().ToArray();
}
public sealed record DailyUsage(DateOnly Date,TokenUsage Usage,int Responses,CostEstimate Cost) {
    public int CostIntensity(decimal peak)=>Cost.TotalUSD<=0||peak<=0?0:Math.Clamp((int)decimal.Ceiling(Cost.TotalUSD/peak*4),1,4);
    public int Intensity(long peak)=>Usage.Total==0?0:Math.Max(1,(int)Math.Ceiling(Math.Min(1,(double)Usage.Total/Math.Max(1,peak))*4));
}
public sealed record LogIssue(string Path,IReadOnlyList<string> Messages) {
    public string Kind {get;init;}="integrity";
    public IReadOnlyList<DateTimeOffset> Dates {get;init;}=[];
    public IReadOnlySet<string> AffectedTurnIDs {get;init;}=new HashSet<string>();
    public bool UnknownScope {get;init;}=true;
}
public sealed record AccountingCoverage(string Status,IReadOnlyList<string> Reasons) {
    public bool CanComplete=>Status=="complete";
    public static AccountingCoverage Evaluate(Snapshot snapshot,IReadOnlySet<string>? turnIDs=null,bool loaded=true,(DateTimeOffset Start,DateTimeOffset End)? interval=null) {
        if(!loaded)return new("loading",[]);
        var represented=snapshot.LogIssues.SelectMany(i=>i.Messages).ToHashSet();
        var reasons=snapshot.LogIssues.Where(i=>i.UnknownScope||((interval==null||i.Dates.Count==0||i.Dates.Any(d=>d>=interval.Value.Start&&d<interval.Value.End))&&(turnIDs==null||i.AffectedTurnIDs.Overlaps(turnIDs)))).SelectMany(i=>i.Messages).Concat(snapshot.Warnings.Where(w=>!represented.Contains(w))).Distinct().Order().ToArray();
        return new(reasons.Length==0&&snapshot.Malformed==0?"complete":snapshot.HasReadFailures&&snapshot.Turns.Count==0?"failed":"partial",reasons);
    }
}
public sealed record Snapshot(IReadOnlyList<LedgerTurn> Turns,IReadOnlyList<string> Warnings,int Files,int Malformed) {
    public IReadOnlyList<LogIssue> LogIssues {get;init;}=[];
    public bool HasReadFailures {get;init;}
    public string WarningSummary=>HasReadFailures?"部分日志无法读取，点击查看详情":"用量记录存在异常，点击查看详情";
    public bool IsComplete=>Warnings.Count==0&&Malformed==0;
    public DateTimeOffset CapturedAt {get;init;}=DateTimeOffset.Now;
    public TokenUsage Usage=>Turns.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage);
    public CostEstimate Cost=>Turns.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost);
}
public enum DateScope { Today,Yesterday,Week,Month,All }
public static class Dates {
    public static (DateTimeOffset Start,DateTimeOffset End) Interval(DateScope scope,DateTimeOffset now,TimeZoneInfo zone) {
        var day=TimeZoneInfo.ConvertTime(now,zone).Date;var start=scope switch {DateScope.Yesterday=>day.AddDays(-1),DateScope.Week=>day.AddDays(-6),DateScope.Month=>day.AddDays(-29),DateScope.All=>new DateTime(1900,1,1),_=>day};
        var end=scope==DateScope.Yesterday?day:day.AddDays(1);
        return (Boundary(start,zone),Boundary(end,zone));
    }
    public static (DateTimeOffset Start,DateTimeOffset End) DayInterval(DateOnly day,TimeZoneInfo zone)=> (Boundary(day.ToDateTime(TimeOnly.MinValue),zone),Boundary(day.AddDays(1).ToDateTime(TimeOnly.MinValue),zone));
    private static DateTimeOffset Boundary(DateTime date,TimeZoneInfo zone) { date=DateTime.SpecifyKind(date,DateTimeKind.Unspecified);while(zone.IsInvalidTime(date))date=date.AddMinutes(1);return new(date,zone.GetUtcOffset(date)); }
}

public sealed class ReadOnlyStringSetConverter : System.Text.Json.Serialization.JsonConverter<IReadOnlySet<string>> {
    public override IReadOnlySet<string> Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options) {
        var values=JsonSerializer.Deserialize<string[]>(ref reader,options)??throw new JsonException("Missing turn IDs");
        return System.Collections.Frozen.FrozenSet.ToFrozenSet(values,StringComparer.Ordinal);
    }
    public override void Write(Utf8JsonWriter writer,IReadOnlySet<string> values,JsonSerializerOptions options)=>JsonSerializer.Serialize(writer,values.Order(StringComparer.Ordinal).ToArray(),options);
}
