using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
namespace CodexLedger;
public sealed record LedgerGoal(string ID,string Name,DateTimeOffset CreatedAt,DateTimeOffset? CompletedAt=null,CostEstimate? CompletionCost=null,TokenUsage? CompletionUsage=null,string? CompletionPriceDate=null);
public sealed class GoalBook {
    public int Version {get;set;}=1;
    public List<LedgerGoal> Goals {get;set;}=[];
    public Dictionary<string,string> Bindings {get;set;}=[];
    public const string Unassigned="__unassigned__";
    public string? Owner(LedgerTurn turn) {
        foreach(var key in new[]{"turn:"+turn.ID,"conversation:"+turn.SessionID,"project:"+turn.Project.ID})if(Bindings.TryGetValue(key,out var id))return Goals.Any(g=>g.ID==id)?id:null;return null;
    }
    public void Assign(string target,string? goalID)=>Bindings[target]=goalID??Unassigned;
    public void Remove(string id) {Goals.RemoveAll(g=>g.ID==id);foreach(var key in Bindings.Where(x=>x.Value==id).Select(x=>x.Key).ToArray())Bindings.Remove(key);}
    public void Complete(string id,IReadOnlyList<LedgerTurn> lifetime,DateTimeOffset now) {
        int index=Goals.FindIndex(g=>g.ID==id);if(index<0)return;var selected=lifetime.Where(t=>Owner(t)==id).ToArray();
        Goals[index]=Goals[index] with{CompletedAt=now,CompletionCost=selected.Aggregate(new CostEstimate(),(a,t)=>a+t.Cost),CompletionUsage=selected.Aggregate(new TokenUsage(),(a,t)=>a+t.Usage),CompletionPriceDate=Pricing.Date};
    }
    public void Reopen(string id) {int index=Goals.FindIndex(g=>g.ID==id);if(index>=0)Goals[index]=Goals[index] with{CompletedAt=null,CompletionCost=null,CompletionUsage=null,CompletionPriceDate=null};}
    public static GoalBook Decode(string text) {var b=JsonSerializer.Deserialize<GoalBook>(text,Json.Options)??throw new InvalidDataException("Empty goal book");if(b.Version!=1||b.Goals==null||b.Bindings==null||b.Goals.Select(g=>g.ID).Distinct().Count()!=b.Goals.Count)throw new InvalidDataException("Unsupported goal book");return b;}
}
public static class LocalFiles {
    public static string DataDirectory=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexLedger");
    public static string GoalFile(string source)=>Path.Combine(DataDirectory,"goals-"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(ProjectResolver.Normalize(source))))+".json");
    public static void AtomicWrite(string path,string text) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);var staging=path+"."+Guid.NewGuid()+".tmp";
        try {File.WriteAllText(staging,text,new UTF8Encoding(false));File.Move(staging,path,true);}finally{if(File.Exists(staging))File.Delete(staging);}
    }
}
public sealed record ShareSnapshot(string Kind,string PrivateTitle,string Range,string Timezone,TokenUsage Usage,CostEstimate Cost,int Turns,int Conversations,int Models,IReadOnlyList<DailyUsage> Days,CostEstimate? CompletionCost,DateTimeOffset? CompletionDate,string? CompletionPriceDate,bool Filtered,bool Warning,string PriceDate) {
    public const string DownloadURL="https://zhangligong0826.github.io/codex-ledger/";
    public TokenUsage MonthlyUsage=>Days.Aggregate(new TokenUsage(),(a,d)=>a+d.Usage);
    public CostEstimate MonthlyCost=>Days.Aggregate(new CostEstimate(),(a,d)=>a+d.Cost);
    public int ActiveDays=>Days.Count(d=>d.Usage.Total>0);
}
public static class CSV {
    public static string Field(string value)=>"\""+(value.Length>0&&"=+-@\t\r".Contains(value[0])?"'":"")+value.Replace("\"","\"\"")+"\"";
    public static string Render(IEnumerable<IEnumerable<string>> rows)=>"\uFEFF"+string.Join("\r\n",rows.Select(r=>string.Join(",",r.Select(Field))));
    public static IEnumerable<string> Cost(CostEstimate c)=>[c.HasEstimate?c.TotalUSD.ToString(System.Globalization.CultureInfo.InvariantCulture):"",c.PricedTokens.ToString(),c.UnpricedTokens.ToString(),c.UnverifiedContextTokens.ToString(),Pricing.Date];
    public static readonly string[] CostHeaders=["预估API花费USD","已计价tokens","未计价tokens","上下文未确认tokens","价格核对日期"];
}
